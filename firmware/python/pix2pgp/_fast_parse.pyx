# cython: boundscheck=False, wraparound=False, cdivision=True
"""
Cython-accelerated event parser for pix2pgp.

Replaces the Python FSM chain (AsicData.eventParseFsm → LaneData.eventParseFsm
→ extractLaneData → all format decoders) with a single compiled function.
"""
from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t, int32_t
from libc.stdlib cimport malloc, realloc, free
from libc.string cimport memset

import numpy as np
cimport numpy as cnp

cnp.import_array()

# ── Inline helpers ──────────────────────────────────────────────────

cdef inline uint64_t read_le(const uint8_t* buf, int n) noexcept nogil:
    """Read *n* bytes (1-8) from *buf* as a little-endian integer."""
    cdef uint64_t val = 0
    cdef int i
    for i in range(n):
        val |= (<uint64_t>buf[i]) << (8 * i)
    return val


# ── Hit buffer (malloc-backed, growable) ────────────────────────────

cdef struct Hit:
    int32_t col
    int32_t row
    int32_t adc

cdef struct HitBuf:
    Hit* data
    int32_t size
    int32_t cap

cdef inline void hitbuf_init(HitBuf* hb) noexcept nogil:
    hb.cap = 256
    hb.size = 0
    hb.data = <Hit*>malloc(hb.cap * sizeof(Hit))

cdef inline void hitbuf_push(HitBuf* hb, int32_t col, int32_t row, int32_t adc) noexcept nogil:
    if hb.size == hb.cap:
        hb.cap *= 2
        hb.data = <Hit*>realloc(hb.data, hb.cap * sizeof(Hit))
    hb.data[hb.size].col = col
    hb.data[hb.size].row = row
    hb.data[hb.size].adc = adc
    hb.size += 1

cdef inline void hitbuf_free(HitBuf* hb) noexcept nogil:
    if hb.data != NULL:
        free(hb.data)
        hb.data = NULL


# ── Config object (created once, reused for all events) ─────────────

cdef class AsicConfig:
    cdef public int32_t num_lanes
    cdef public int32_t num_cols
    cdef public int32_t word_len
    cdef public int32_t preamble_len
    cdef public int32_t header_len
    cdef public int32_t frame_size_len
    cdef public int32_t trailer_len
    cdef public int32_t asic_type_id
    cdef public bint old_format
    # Lane-header bit positions
    cdef public int32_t hdr_overOcc_bit
    cdef public int32_t hdr_pause_bit
    cdef public int32_t hdr_colErr_bit
    cdef public int32_t hdr_pauseErr_bit
    cdef public int32_t hdr_dummy_bit
    cdef public int32_t hdr_timeout_bit
    cdef public int32_t hdr_colHitmask_shift
    cdef public uint32_t hdr_colHitmask_mask
    cdef public uint32_t hdr_trgCnt_mask
    # ColMetadata bit positions
    cdef public int32_t meta_colTimeout_bit
    cdef public int32_t meta_colOverOcc_bit
    cdef public int32_t meta_colPause_bit
    cdef public int32_t meta_colId_shift
    cdef public uint32_t meta_colId_mask
    cdef public int32_t meta_colTrgCnt_shift
    cdef public uint32_t meta_colTrgCnt_mask
    cdef public uint32_t meta_colLen_mask
    # Hit decode
    cdef public int32_t hit_upper_shift
    cdef public uint32_t hit_mask
    cdef public int32_t hit_lr_bit
    cdef public int32_t hit_row_shift
    cdef public uint32_t hit_row_mask
    cdef public uint32_t hit_adc_mask
    # FPGA header layout (8 bitmask fields × numLanes bits)
    cdef public int32_t fpga_hdr_num_fields


def make_config(str asic_type, bint old_format=False):
    """Create an AsicConfig for the given ASIC type string."""
    cdef AsicConfig cfg = AsicConfig()
    cfg.old_format = old_format
    cfg.preamble_len = 16
    cfg.frame_size_len = 2
    cfg.trailer_len = 6
    cfg.fpga_hdr_num_fields = 8

    if asic_type in ("SparkPixS", "SparkPixSv2"):
        cfg.num_lanes = 8
        cfg.num_cols = 24
        cfg.word_len = 5
        cfg.asic_type_id = 1 if asic_type == "SparkPixS" else 4
        cfg.header_len = 8
        # Lane header (40-bit word)
        cfg.hdr_overOcc_bit = 39
        cfg.hdr_pause_bit = 38
        cfg.hdr_colErr_bit = 37
        cfg.hdr_pauseErr_bit = 36
        cfg.hdr_dummy_bit = 35
        cfg.hdr_timeout_bit = 34
        cfg.hdr_colHitmask_shift = 8
        cfg.hdr_colHitmask_mask = 0xFFFFFF
        cfg.hdr_trgCnt_mask = 0xFF
        # ColMetadata
        cfg.meta_colTimeout_bit = 26
        cfg.meta_colOverOcc_bit = 25
        cfg.meta_colPause_bit = 24
        cfg.meta_colId_shift = 16
        cfg.meta_colId_mask = 0xFF
        cfg.meta_colTrgCnt_shift = 8
        cfg.meta_colTrgCnt_mask = 0xFF
        cfg.meta_colLen_mask = 0xFF
        # Hit (two 20-bit halves in a 40-bit word)
        cfg.hit_upper_shift = 20
        cfg.hit_mask = 0xFFFFF
        cfg.hit_lr_bit = 19
        cfg.hit_row_shift = 10
        cfg.hit_row_mask = 0x1FF
        cfg.hit_adc_mask = 0x3FF
    elif asic_type == "SparkPixT":
        cfg.num_lanes = 8
        cfg.num_cols = 24
        cfg.word_len = 8
        cfg.asic_type_id = 2
        cfg.header_len = 8
        cfg.hdr_overOcc_bit = 63
        cfg.hdr_pause_bit = 62
        cfg.hdr_colErr_bit = 61
        cfg.hdr_pauseErr_bit = 60
        cfg.hdr_dummy_bit = 59
        cfg.hdr_timeout_bit = 58
        cfg.hdr_colHitmask_shift = 8
        cfg.hdr_colHitmask_mask = 0xFFFFFF
        cfg.hdr_trgCnt_mask = 0xFF
        cfg.meta_colTimeout_bit = 26
        cfg.meta_colOverOcc_bit = 25
        cfg.meta_colPause_bit = 24
        cfg.meta_colId_shift = 16
        cfg.meta_colId_mask = 0xFF
        cfg.meta_colTrgCnt_shift = 8
        cfg.meta_colTrgCnt_mask = 0xFF
        cfg.meta_colLen_mask = 0xFF
        cfg.hit_upper_shift = 32
        cfg.hit_mask = 0xFFFFFFFF
        cfg.hit_lr_bit = 0  # not used for SparkPixT (no LR)
        cfg.hit_row_shift = 24
        cfg.hit_row_mask = 0xFF
        cfg.hit_adc_mask = 0  # SparkPixT uses TOA/TOT, not ADC
    elif asic_type == "Thriglav":
        cfg.num_lanes = 2
        cfg.num_cols = 50
        cfg.word_len = 8
        cfg.asic_type_id = 3
        cfg.header_len = 2
        cfg.hdr_overOcc_bit = 63
        cfg.hdr_pause_bit = 62
        cfg.hdr_colErr_bit = 61
        cfg.hdr_pauseErr_bit = 60
        cfg.hdr_dummy_bit = 59
        cfg.hdr_timeout_bit = 58
        cfg.hdr_colHitmask_shift = 7
        cfg.hdr_colHitmask_mask = 0x3FFFFFFFFFFFF
        cfg.hdr_trgCnt_mask = 0x7F
        cfg.meta_colTimeout_bit = 26
        cfg.meta_colOverOcc_bit = 25
        cfg.meta_colPause_bit = 24
        cfg.meta_colId_shift = 16
        cfg.meta_colId_mask = 0xFF
        cfg.meta_colTrgCnt_shift = 8
        cfg.meta_colTrgCnt_mask = 0xFF
        cfg.meta_colLen_mask = 0xFF
        cfg.hit_upper_shift = 32
        cfg.hit_mask = 0xFFFFFFFF
        cfg.hit_lr_bit = 0
        cfg.hit_row_shift = 8
        cfg.hit_row_mask = 0xFF
        cfg.hit_adc_mask = 0
    else:
        raise ValueError(f"Unknown asic_type: {asic_type}")

    return cfg


# ── Main parse function ─────────────────────────────────────────────

cpdef tuple parse_event(const uint8_t[::1] frame,
                        int32_t data_len,
                        int32_t start_index,
                        AsicConfig cfg):
    """Parse a single event from *frame* starting at *start_index*.

    Returns
    -------
    (asic_id, lane_valid, hits_list, trg_cnt_list, current_index, preamble_err)
    """
    # All cdef declarations must be at function top in Cython
    cdef int32_t index = start_index
    cdef int32_t num_lanes = cfg.num_lanes
    cdef int32_t num_cols = cfg.num_cols
    cdef int32_t word_len = cfg.word_len
    cdef const uint8_t* buf = &frame[0]
    cdef uint64_t pre_lo, pre_hi, pix2pgp_id, fpga_hdr, lane_bitmask
    cdef uint64_t lane_hdr, col_meta, hit_word, trailer_val
    cdef uint16_t fpga_trg_cnt, fpga_id, asic_id, asic_type_v, pix2pgp_type
    cdef bint preamble_err, stream_rx_frame, drop_frame, type_mismatch
    cdef bint header_err, in_pause, lane_pause, trailer_err
    cdef bint l_overOcc, l_colErr, l_pauseErr, l_dummy, l_timeout
    cdef uint8_t lane_valid_bits, lane_down_bits, lane_timeout_bits
    cdef uint8_t lane_full_bits, lane_dec_err_bits
    cdef uint32_t col_hitmask, hit_upper, hit_lower, trg_cnt
    cdef int32_t lane_i, col_sel, sub_len, lane_offset, lane_end
    cdef int32_t lr, row_v, adc_v, col_v, col_id
    cdef HitBuf hb
    cdef int32_t trg_cnts[16]
    cdef uint16_t frame_sizes[16]

    memset(trg_cnts, 0, sizeof(trg_cnts))
    memset(frame_sizes, 0, sizeof(frame_sizes))

    # ── Preamble (16 bytes, little-endian) ──
    pre_lo = read_le(buf + index, 8)
    pre_hi = read_le(buf + index + 8, 8)
    index += cfg.preamble_len

    fpga_trg_cnt = <uint16_t>(pre_lo & 0xFFFF)
    fpga_id      = <uint16_t>((pre_lo >> 16) & 0xFFFF)
    asic_id      = <uint16_t>((pre_lo >> 32) & 0xFFFF)
    asic_type_v  = <uint16_t>((pre_lo >> 48) & 0xFFFF)
    pix2pgp_type = <uint16_t>(pre_hi & 0xFFFF)
    pix2pgp_id   = (pre_hi >> 16) & 0xFFFFFFFFFFFF

    # "pixpgp" = 0x706978706770
    preamble_err = (pix2pgp_id != 0x706978706770)
    stream_rx_frame = (pix2pgp_type == 0)
    drop_frame = False
    type_mismatch = False

    if not stream_rx_frame:
        return (int(asic_id), [False] * num_lanes, [], [0] * num_lanes,
                index, preamble_err)

    if asic_type_v == 0:
        drop_frame = True
    elif asic_type_v != cfg.asic_type_id:
        type_mismatch = True

    if drop_frame:
        index += cfg.trailer_len
        return (int(asic_id), [False] * num_lanes, [], [0] * num_lanes,
                index, preamble_err)

    # ── Hit buffer for all lanes ──
    hitbuf_init(&hb)

    lane_valid_bits = 0
    header_err = False
    in_pause = False

    # ── Pause-frame outer loop ──
    while True:
        in_pause = False

        # ── FPGA Header (headerLen bytes, little-endian) ──
        fpga_hdr = read_le(buf + index, cfg.header_len)
        index += cfg.header_len

        lane_bitmask = (<uint64_t>1 << num_lanes) - 1
        lane_valid_bits = <uint8_t>(fpga_hdr & lane_bitmask)
        lane_down_bits    = <uint8_t>((fpga_hdr >> (num_lanes * 1)) & lane_bitmask)
        lane_timeout_bits = <uint8_t>((fpga_hdr >> (num_lanes * 2)) & lane_bitmask)
        lane_full_bits    = <uint8_t>((fpga_hdr >> (num_lanes * 3)) & lane_bitmask)
        lane_dec_err_bits = <uint8_t>((fpga_hdr >> (num_lanes * 7)) & lane_bitmask)

        header_err = (lane_dec_err_bits > 0 or lane_full_bits > 0)

        # ── Frame sizes (2 bytes × numLanes, little-endian) ──
        for lane_i in range(num_lanes):
            frame_sizes[lane_i] = <uint16_t>read_le(buf + index, cfg.frame_size_len)
            index += cfg.frame_size_len

        # ── activeColCnt (oldFormat only) ──
        if cfg.old_format:
            index += cfg.frame_size_len * num_lanes

        # ── Per-lane parsing ──
        for lane_i in range(num_lanes):
            if not ((lane_valid_bits >> lane_i) & 1):
                continue

            lane_offset = index
            lane_end = index + frame_sizes[lane_i] * word_len

            # ── Lane Header (wordLen bytes, LE = original bytes before wordSwap) ──
            lane_hdr = read_le(buf + lane_offset, word_len)
            lane_offset += word_len

            l_overOcc  = (lane_hdr >> cfg.hdr_overOcc_bit) & 1
            lane_pause = (lane_hdr >> cfg.hdr_pause_bit) & 1
            l_colErr   = (lane_hdr >> cfg.hdr_colErr_bit) & 1
            l_pauseErr = (lane_hdr >> cfg.hdr_pauseErr_bit) & 1
            l_dummy    = (lane_hdr >> cfg.hdr_dummy_bit) & 1
            l_timeout  = (lane_hdr >> cfg.hdr_timeout_bit) & 1
            col_hitmask = <uint32_t>((lane_hdr >> cfg.hdr_colHitmask_shift) & cfg.hdr_colHitmask_mask)
            trg_cnt = <uint32_t>(lane_hdr & cfg.hdr_trgCnt_mask)

            trg_cnts[lane_i] = <int32_t>trg_cnt
            in_pause = in_pause or lane_pause

            # If no data or dummy, skip column parsing
            if col_hitmask == 0 or l_dummy:
                index = lane_offset
                continue

            # ── Iterate columns with hits ──
            for col_sel in range(num_cols):
                if not ((col_hitmask >> col_sel) & 1):
                    continue

                # Column metadata
                col_meta = read_le(buf + lane_offset, word_len)
                lane_offset += word_len

                sub_len = <int32_t>(col_meta & cfg.meta_colLen_mask)

                col_id = lane_i * num_cols + col_sel

                # Parse hit words
                while sub_len > 0:
                    hit_word = read_le(buf + lane_offset, word_len)
                    lane_offset += word_len

                    # Upper hit (always emitted)
                    hit_upper = <uint32_t>((hit_word >> cfg.hit_upper_shift) & cfg.hit_mask)
                    lr    = (hit_upper >> cfg.hit_lr_bit) & 1
                    row_v = (hit_upper >> cfg.hit_row_shift) & cfg.hit_row_mask
                    adc_v = hit_upper & cfg.hit_adc_mask
                    col_v = 2 * col_id + lr
                    hitbuf_push(&hb, col_v, row_v, adc_v)

                    # Lower hit (only if subLen > 1)
                    if sub_len > 1:
                        hit_lower = <uint32_t>(hit_word & cfg.hit_mask)
                        lr    = (hit_lower >> cfg.hit_lr_bit) & 1
                        row_v = (hit_lower >> cfg.hit_row_shift) & cfg.hit_row_mask
                        adc_v = hit_lower & cfg.hit_adc_mask
                        col_v = 2 * col_id + lr
                        hitbuf_push(&hb, col_v, row_v, adc_v)

                    sub_len -= 2

            index = lane_offset

        # ── Trailer or pause-loop ──
        if not in_pause or header_err:
            trailer_val = read_le(buf + index, cfg.trailer_len)
            trailer_err = ((trailer_val & 0xFFFFFFFFFFFF) != 0x706978706770)
            index += cfg.trailer_len
            break
        # else: pause — loop back to parse another header + frame sizes + lanes

    # ── Build Python return values ──
    cdef list lane_valid_list = [bool((lane_valid_bits >> i) & 1) for i in range(num_lanes)]
    cdef list trg_cnt_list = [int(trg_cnts[i]) for i in range(num_lanes)]

    # Convert hit buffer to list of dicts (for backward compat)
    cdef list hits_list = []
    cdef int32_t hi
    for hi in range(hb.size):
        hits_list.append({
            'col': int(hb.data[hi].col),
            'row': int(hb.data[hi].row),
            'adc': int(hb.data[hi].adc),
        })

    hitbuf_free(&hb)

    return (int(asic_id), lane_valid_list, hits_list, trg_cnt_list,
            int(index), bool(preamble_err))
