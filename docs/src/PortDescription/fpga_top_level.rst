.. _port_description_fpga:

====================================
FPGA Top-Level (Pix2PgpAsicStreamRx)
====================================

``Pix2PgpAsicStreamRx`` (``firmware/fpga/rtl/Pix2PgpAsicStreamRx.vhd``)
is the FPGA receiver for **one** ASIC. It contains:

* one ``LaneRxWrapper`` per lane (``LaneRx`` plus optional
  ``LaneMon``)
* the Lane Supervisor and the Lane Merger
* the Trigger Manager (SRO / ERO / DAQ buffering)
* the AXI-Lite register manager, behind an ``AxiLiteAsync`` and an
  ``AxiLiteCrossbar``
* an output ``AxiStreamFifoV2`` + ``AxiStreamGearbox`` stage that
  re-packs ``tKeep`` on the consolidated stream

It must be compiled against the **same** ``Pix2PgpAsicPkg.vhd`` as the
ASIC, since every header bit position comes from that package.
Instantiate one ``Pix2PgpAsicStreamRx`` per ASIC.

``L`` = ``NUM_OF_SERIALIZERS_C`` below.

Generics
========

.. list-table::
   :header-rows: 1
   :widths: 28 14 10 48

   * - Name
     - Type
     - Default
     - Description
   * - ``TPD_G``
     - ``time``
     - ``1 ns``
     - Simulation-only register delay. Ignored by synthesis
   * - ``RST_ASYNC_G``
     - ``boolean``
     - ``false``
     - ``true`` → asynchronous reset; ``false`` → synchronous reset
   * - ``RST_POLARITY_G``
     - ``sl``
     - ``'1'``
     - Polarity of ``pgpRxRst`` and of the internal receiver resets
   * - ``ASIC_RST_POLARITY_G``
     - ``sl``
     - ``'0'``
     - Polarity of ``asicRst`` (Trigger Manager only). Independent of
       ``RST_POLARITY_G``, because the ASIC-facing reset often follows
       the ASIC's own convention
   * - ``ASIC_ID_G``
     - ``natural``
     - ``0``
     - Written into the ``ASIC ID`` field of the consolidated frame
       preamble. Must be unique per receiver if the FPGA serves several
       ASICs
   * - ``LANE_MON_GEN_G``
     - ``boolean``
     - ``false``
     - Generate one ``Pix2PgpLaneMon`` per lane (per-lane statistics
       over AXI-Lite, and the ``asicMonStatus`` output). If ``false``,
       the monitor crossbar slots return SLVERR and ``asicMonStatus``
       stays at its default
   * - ``LANE_MON_CNT_WIDTH_G``
     - ``positive``
     - ``20``
     - Width of the per-lane monitoring counters
   * - ``TRG_FIFO_ADDR_WIDTH_G``
     - ``positive``
     - ``6``
     - Trigger-buffer depth (SRO buffer, and ERO buffer if
       ``EN_ERO_C``), as ``log2``. Size it for the maximum number of
       triggers in flight between ``asicSro`` and the frame arriving
       on ``pgp4RxMaster``
   * - ``META_FIFO_ADDR_WIDTH_G``
     - ``positive``
     - ``6``
     - Depth of each ``LaneRx`` metadata (frame status) FIFO, as
       ``log2``
   * - ``LANE_FIFO_ADDR_WIDTH_G``
     - ``positive``
     - ``9``
     - Depth of each ``LaneRx`` data FIFO, as ``log2``. The first-level
       input FIFO in front of it uses ``LANE_FIFO_ADDR_WIDTH_G - 2``.
       Increase for large Pause-fragmented events
   * - ``AXIL_BASE_ADDR_G``
     - ``slv(31 downto 0)``
     - (none)
     - Base address of the receiver's AXI-Lite region. The crossbar has
       ``L + 1`` slots of 64 KiB (``addrBits = 16``): slot 0 holds the
       receiver's global registers (``Pix2PgpAxiLiteManager``), and
       slot ``1 + i`` holds the ``LaneMon`` of lane ``i``. The slot
       index is decoded from the bits between bit 16 and the lowest set
       bit of the base (bit 26 if the base is zero). So the base must
       be aligned so that ``2**(lowestSetBit - 16) >= L + 1``

Ports
=====

General Interface
-----------------

.. list-table::
   :header-rows: 1
   :widths: 20 8 14 58

   * - Name
     - Dir
     - Type
     - Description
   * - ``pgpRxClk``
     - in
     - ``sl``
     - Receiver clock. Every ``LaneRx`` (its ``laneClk`` is tied to
       this), the Lane Supervisor, the Lane Merger, the AXI-Lite
       manager and the output stream run on it. The ``pgp4Rx*`` and
       ``asicRx*`` interfaces must be synchronous to it
   * - ``pgpRxRst``
     - in
     - ``sl``
     - Receiver reset, polarity per ``RST_POLARITY_G``. Defaults to
       inactive if left open. Internally OR-ed with the AXI-Lite
       user-reset register to form the global receiver reset

ASIC Domain Interface
---------------------

Every port in this group is on the ``asicClk`` domain. The Trigger
Manager handles the crossing into ``pgpRxClk``.

.. list-table::
   :header-rows: 1
   :widths: 20 8 14 58

   * - Name
     - Dir
     - Type
     - Description
   * - ``asicClk``
     - in
     - ``sl``
     - Clock the trigger signals are synchronous to
   * - ``asicRst``
     - in
     - ``sl``
     - Trigger Manager reset. Polarity per ``ASIC_RST_POLARITY_G``
       (default active-low)
   * - ``asicSro``
     - in
     - ``sl``
     - Start-of-Readout, as forwarded to the ASIC. A rising edge
       increments the FPGA Trigger Counter (if ``asicSroEn`` is high,
       or if the ``incrSroEnLow`` register is set). A falling edge
       pushes ``{trgCnt, asicSroEn, sysDaq}`` into the SRO buffer
   * - ``asicSroEn``
     - in
     - ``sl``
     - High if the SRO actually reached the ASIC. When low, the SRO is
       still buffered, but the Lane Supervisor sends a drop-frame for
       it instead of waiting for lane data
   * - ``asicEro``
     - in
     - ``sl``
     - End-of-Readout. **Only used when** ``EN_ERO_C = True``; otherwise
       it may be left open (default ``'0'``). A falling edge pushes the
       Trigger Counter of the SRO it closes into the ERO buffer, which
       the Lane Supervisor uses to close the event. The trigger logic
       must keep the SRO → ERO → SRO … sequence intact
   * - ``sysDaq``
     - in
     - ``sl``
     - DAQ flag, sampled on the SRO falling edge (LCLS DAQ trigger).
       If it was low, the consolidated frame for that trigger is
       dumped and not forwarded downstream. Tie high to always
       forward

PGP4 RX Input Interface (``pgpRxClk`` domain)
---------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 20 8 22 50

   * - Name
     - Dir
     - Type
     - Description
   * - ``pgp4RxMaster``
     - in
     - ``AxiStreamMasterArray(L)``
     - Decoded Lane Frames, one per PGP4 receiver. Expected in
       ``ASIC_DATA_AXI_CONFIG_C`` format
       (``PIX2PGP_DATABUS_DWIDTH_C``-wide). If ``EVAL_SOF_C`` /
       ``EVAL_EOFE_C`` are set, the SSI SOF / EOFE ``tUser`` bits are
       checked
   * - ``pgp4RxSlave``
     - out
     - ``AxiStreamSlaveArray(L)``
     - Handshake back to each PGP4 receiver
   * - ``pgp4RxLinkUp``
     - in
     - ``slv(L-1 downto 0)``
     - Per-lane link-up. A lane that is down is reported as
       ``Lane Down``; if no enabled lane is up, triggers produce
       drop-frames. Do not tie high

AXI-Stream Output Interface (``pgpRxClk`` domain)
-------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 20 8 22 50

   * - Name
     - Dir
     - Type
     - Description
   * - ``asicRxMaster``
     - out
     - ``AxiStreamMasterType``
     - Consolidated Pix2PGP frame (one per trigger, or a drop-frame),
       in ``PIX2PGP_FPGA_AXI_CONFIG_C`` format
       (``FPGA_DATABUS_DWIDTH_C``-wide). See :ref:`frame_pix2pgp_frame`
   * - ``asicRxSlave``
     - in
     - ``AxiStreamSlaveType``
     - Handshake from the downstream consumer

ASIC Monitoring Status Output
-----------------------------

.. list-table::
   :header-rows: 1
   :widths: 20 8 22 50

   * - Name
     - Dir
     - Type
     - Description
   * - ``asicMonStatus``
     - out
     - ``Pix2PgpLaneStatusArray``
     - Per-lane snapshot from ``LaneMon``: ``valid`` (one-shot per
       received frame), last-seen ``overOcc`` / ``pause`` /
       ``pauseError``, ``trgCnt``, ``eventHitmask`` and ``frameSize``.
       Only driven if ``LANE_MON_GEN_G = true``. Intended for
       register-free fabric logic such as trigger throttling or
       embedded calibration

AXI-Lite Interface (``axilClk`` domain)
---------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 20 8 22 50

   * - Name
     - Dir
     - Type
     - Description
   * - ``axilClk``
     - in
     - ``sl``
     - AXI-Lite clock. Crossed into ``pgpRxClk`` by an internal
       ``AxiLiteAsync``
   * - ``axilRst``
     - in
     - ``sl``
     - AXI-Lite reset (active-high, SURF convention)
   * - ``axilReadMaster``
     - in
     - ``AxiLiteReadMasterType``
     - Read request. Defaults to ``AXI_LITE_READ_MASTER_INIT_C``
   * - ``axilReadSlave``
     - out
     - ``AxiLiteReadSlaveType``
     - Read response
   * - ``axilWriteMaster``
     - in
     - ``AxiLiteWriteMasterType``
     - Write request. Defaults to ``AXI_LITE_WRITE_MASTER_INIT_C``
   * - ``axilWriteSlave``
     - out
     - ``AxiLiteWriteSlaveType``
     - Write response
