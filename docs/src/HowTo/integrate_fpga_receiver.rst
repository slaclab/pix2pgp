.. _how_to_integrate_fpga_receiver:

=====================================================
How to Integrate the Pix2PGP FPGA Receiver in Your FPGA
=====================================================

This page describes how to drop the Pix2PGP FPGA receiver into an FPGA
design. The receiver is a **VHDL** design that expects one PGP4
receiver core per data lane on its input side, and delivers a single
consolidated AXI-Stream per trigger on its output side.

The top-level entity is ``Pix2PgpAsicStreamRx``, defined in
``firmware/fpga/rtl/Pix2PgpAsicStreamRx.vhd``. Unlike the ASIC-side
``Pix2PgpTop``, the FPGA receiver is a full-featured module — it
carries an integrated AXI-Lite crossbar, a trigger-buffer for the
ASIC's ``SRO`` signal, per-lane monitoring, and clock-domain-crossing
logic between the ASIC-facing clock and the PGP RX clock. Instantiate
**one ``Pix2PgpAsicStreamRx`` per ASIC** in your FPGA design.

Prerequisites
=============

* The **same** ``Pix2PgpAsicPkg.vhd`` package used by the ASIC (or an
  identical copy — the receiver depends on
  ``NUM_OF_COL_MANAGERS_C``, ``NUM_OF_SERIALIZERS_C``,
  ``ASIC_DATABUS_DWIDTH_C``, header/metadata bitfield positions, etc.)
* One PGP4 receiver core per lane (``NUM_OF_SERIALIZERS_C`` cores).
  Their AXI-Stream masters and ``linkUp`` signals are wired to the
  receiver
* Three clock domains:

  * ``pgpRxClk``  — the PGP4 receivers' recovered clock. The receiver
    logic runs here
  * ``asicClk``   — the clock associated with the ``SRO`` trigger
    forwarded to the ASIC. The Trigger Manager crosses this into
    ``pgpRxClk`` internally
  * ``axilClk``   — the AXI-Lite bus clock. The receiver crosses this
    into ``pgpRxClk`` internally via an ``AxiLiteAsync``

* An AXI-Lite master (a register file, an embedded processor, etc.)
  that can address the receiver's ``AXIL_BASE_ADDR_G`` region

Generics
========

.. list-table:: ``Pix2PgpAsicStreamRx`` generics
   :header-rows: 1
   :widths: 28 15 12 45

   * - Name
     - Type
     - Default
     - Description
   * - ``TPD_G``
     - ``time``
     - ``1 ns``
     - Simulation-only propagation delay applied to registers. Ignored
       by synthesis
   * - ``RST_ASYNC_G``
     - ``boolean``
     - ``false``
     - ``true`` → asynchronous reset; ``false`` → synchronous reset for
       the receiver logic
   * - ``RST_POLARITY_G``
     - ``sl``
     - ``'1'``
     - Reset active-high (``'1'``) or active-low (``'0'``) for the
       receiver logic
   * - ``ASIC_RST_POLARITY_G``
     - ``sl``
     - ``'0'``
     - Reset polarity for the ASIC-facing ``asicRst`` input. Independent
       of ``RST_POLARITY_G`` because the ASIC and the FPGA logic often
       use different conventions
   * - ``ASIC_ID_G``
     - ``natural``
     - ``0``
     - Numeric identifier for this ASIC, written into the consolidated
       Pix2PGP frame preamble. Unique per receiver instance if the FPGA
       services multiple ASICs
   * - ``LANE_MON_GEN_G``
     - ``boolean``
     - ``false``
     - Generate the ``Pix2PgpLaneMon`` per-lane monitoring module. Set
       ``true`` to enable AXI-Lite readback of per-lane statistics
       (occupancy trends, hit counts, etc.). Costs additional
       resources; disable if AXI-Lite budget is tight
   * - ``LANE_MON_CNT_WIDTH_G``
     - ``positive``
     - ``20``
     - Bit width of the per-lane monitoring counters
   * - ``TRG_FIFO_ADDR_WIDTH_G``
     - ``positive``
     - ``6``
     - Trigger-buffer FIFO depth, as ``log2``. ``6`` → 64 pending
       triggers. Size it against the maximum in-flight event count
       between an ``SRO`` issued to the ASIC and the corresponding
       frame arriving on ``pgp4RxMaster``
   * - ``META_FIFO_ADDR_WIDTH_G``
     - ``positive``
     - ``6``
     - Depth of each ``LaneRx`` Status FIFO (metadata), as ``log2``
   * - ``LANE_FIFO_ADDR_WIDTH_G``
     - ``positive``
     - ``9``
     - Depth of each ``LaneRx`` Data FIFO, as ``log2``. ``9`` → 512
       entries. Increase for very large per-event frames (e.g. long
       Pause-fragmented events during full-matrix calibration)
   * - ``AXIL_BASE_ADDR_G``
     - ``slv(31 downto 0)``
     - (no default)
     - Base address of this receiver's AXI-Lite region. **Required**
       — the internal crossbar sizes its address windows by taking the
       base and stepping through in 16-bit strides
       (``NUM_OF_SERIALIZERS_C + 1`` master ports total: one for the
       receiver's global registers, one for each ``LaneRx`` monitor)

Ports
=====

General Interface
-----------------

.. list-table::
   :header-rows: 1
   :widths: 20 12 68

   * - Name
     - Direction
     - Description
   * - ``pgpRxClk``
     - ``in``
     - PGP4 receiver's recovered clock. Every ``LaneRx``, the Lane
       Supervisor, the Lane Merger, and the internal AXI-Lite crossbar
       run on this clock
   * - ``pgpRxRst``
     - ``in``
     - Reset on ``pgpRxClk``, polarity per ``RST_POLARITY_G``.
       Defaults to ``not(RST_POLARITY_G)`` (i.e. inactive) if left
       open

ASIC Domain Interface
---------------------

.. list-table::
   :header-rows: 1
   :widths: 20 12 68

   * - Name
     - Direction
     - Description
   * - ``asicClk``
     - ``in``
     - Clock of the ASIC-facing side (the clock the ``SRO`` trigger is
       synchronous to)
   * - ``asicRst``
     - ``in``
     - ASIC-side reset. Polarity governed by ``ASIC_RST_POLARITY_G``
       (documented as active-low in the source header)
   * - ``asicSro``
     - ``in``
     - Start-of-Readout trigger issued to the ASIC. On every ``SRO``
       assertion, the Trigger Manager pushes an entry into the trigger
       buffer
   * - ``asicSroEn``
     - ``in``
     - Enable for ``asicSro``. Low disables trigger buffering (useful
       during ASIC reset / configuration)
   * - ``sysDaq``
     - ``in``
     - System-level DAQ enable. When high, every buffered trigger
       forwards the merged frame to the back-end; when low, frames are
       either discarded or handled per ``config`` — see
       :ref:`architecture_fpga_receiver` for the LCLS Run / DAQ trigger
       model

PGP4 RX Input Interface (``pgpRxClk`` domain)
--------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 20 12 68

   * - Name
     - Direction
     - Description
   * - ``pgp4RxMaster``
     - ``in``
     - Array of ``NUM_OF_SERIALIZERS_C`` AXI-Stream masters from the
       PGP4 receiver cores — one per lane. Each carries the decoded
       Pix2PGP Lane Frame from its associated ASIC-side Pix2PGP core
   * - ``pgp4RxSlave``
     - ``out``
     - Matching array of AXI-Stream slaves (handshake back to each
       PGP4 receiver)
   * - ``pgp4RxLinkUp``
     - ``in``
     - Per-lane link-up flag from each PGP4 receiver. When a lane goes
       down mid-run, the Lane Supervisor emits drop-frames until the
       receiver returns to idle

AXI-Stream Output Interface (``pgpRxClk`` domain)
------------------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 20 12 68

   * - Name
     - Direction
     - Description
   * - ``asicRxMaster``
     - ``out``
     - Consolidated Pix2PGP frame, as a single AXI-Stream per trigger.
       This is the output that goes on to the back-end (a second-tier
       PGP4 transmitter, a DMA channel to a rogue-managed CPU, etc.).
       See :ref:`architecture_frame_format` for the byte-level layout
   * - ``asicRxSlave``
     - ``in``
     - AXI-Stream slave handshake from the downstream consumer

ASIC Monitoring Status Output
-----------------------------

.. list-table::
   :header-rows: 1
   :widths: 20 12 68

   * - Name
     - Direction
     - Description
   * - ``asicMonStatus``
     - ``out``
     - Array of ``Pix2PgpLaneStatusType`` records — the live per-lane
       monitoring snapshot (last-seen header flags, Column Hitmask,
       Trigger Counter, etc.), one entry per lane. Wire into your
       system-level monitoring path if you want fast, register-free
       access to lane state (e.g. for embedded trigger throttling)

AXI-Lite Interface
------------------

.. list-table::
   :header-rows: 1
   :widths: 22 12 66

   * - Name
     - Direction
     - Description
   * - ``axilClk``
     - ``in``
     - AXI-Lite bus clock
   * - ``axilRst``
     - ``in``
     - AXI-Lite bus reset
   * - ``axilReadMaster``
     - ``in``
     - AXI-Lite read master, initialized to
       ``AXI_LITE_READ_MASTER_INIT_C`` if left open
   * - ``axilReadSlave``
     - ``out``
     - AXI-Lite read slave response
   * - ``axilWriteMaster``
     - ``in``
     - AXI-Lite write master, initialized to
       ``AXI_LITE_WRITE_MASTER_INIT_C`` if left open
   * - ``axilWriteSlave``
     - ``out``
     - AXI-Lite write slave response

Internally, ``Pix2PgpAsicStreamRx`` places an ``AxiLiteAsync`` on this
port (so ``axilClk`` can differ from ``pgpRxClk``) followed by a
``NUM_OF_SERIALIZERS_C + 1``-port AXI-Lite crossbar. Index 0 of the
crossbar addresses the receiver's global registers
(``Pix2PgpAxiLiteManager``); indices 1 … ``NUM_OF_SERIALIZERS_C`` each
address one ``LaneRx`` monitor. The 16-bit stride is fixed by the
crossbar generator inside the entity.

Instantiation Template
======================

For an ASIC with 8 lanes (SparkPix-S-style):

.. code-block:: vhdl

   library ieee;
   use ieee.std_logic_1164.all;

   library surf;
   use surf.StdRtlPkg.all;
   use surf.AxiLitePkg.all;
   use surf.AxiStreamPkg.all;

   library pix2pgp;
   use pix2pgp.Pix2PgpAsicPkg.all;
   use pix2pgp.Pix2PgpPkg.all;

   -- ...

   U_Pix2PgpAsicRx : entity pix2pgp.Pix2PgpAsicStreamRx
      generic map (
         TPD_G                  => 1 ns,
         RST_ASYNC_G            => false,
         RST_POLARITY_G         => '1',
         ASIC_RST_POLARITY_G    => '0',
         ASIC_ID_G              => 0,       -- unique per ASIC in the system
         LANE_MON_GEN_G         => true,    -- enable per-lane monitoring
         LANE_MON_CNT_WIDTH_G   => 20,
         TRG_FIFO_ADDR_WIDTH_G  => 6,       -- 64 in-flight triggers
         META_FIFO_ADDR_WIDTH_G => 6,
         LANE_FIFO_ADDR_WIDTH_G => 9,       -- 512 words per lane
         AXIL_BASE_ADDR_G       => x"A000_0000")
      port map (
         -- Clocks / resets
         pgpRxClk        => pgpRxClk,
         pgpRxRst        => pgpRxRst,
         asicClk         => asicClk,
         asicRst         => asicRst,
         -- ASIC control
         asicSro         => asicSro,
         asicSroEn       => asicSroEn,
         sysDaq          => sysDaq,
         -- PGP4 RX inputs (from your 8 PGP4 receiver cores)
         pgp4RxMaster    => pgp4RxMasters,
         pgp4RxSlave     => pgp4RxSlaves,
         pgp4RxLinkUp    => pgp4RxLinkUps,
         -- Consolidated AXI-Stream output to the back-end
         asicRxMaster    => asicRxMaster,
         asicRxSlave     => asicRxSlave,
         -- Per-lane monitoring snapshot
         asicMonStatus   => asicMonStatus,
         -- AXI-Lite
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMaster,
         axilReadSlave   => axilReadSlave,
         axilWriteMaster => axilWriteMaster,
         axilWriteSlave  => axilWriteSlave);

If the FPGA services multiple ASICs, replicate the instantiation with
distinct ``ASIC_ID_G`` and ``AXIL_BASE_ADDR_G`` values.

Instantiation Checklist
=======================

* The ``Pix2PgpAsicPkg.vhd`` compiled into the FPGA design is **the
  same** as the one used by the ASIC. A mismatch (e.g. different
  ``NUM_OF_COL_MANAGERS_C``, or a shifted header bitfield) causes
  silent decoding failures manifested as ``Lane Decoding Error`` flags
* The PGP4 receiver instances driving ``pgp4RxMaster`` deliver 64-bit
  AXI-Stream with the SURF PGP4 conventions. If you roll your own PGP4
  RX, verify the AXI-Stream config record matches SURF's
  ``PIX2PGP_FPGA_AXI_CONFIG_C``
* ``pgp4RxLinkUp`` is driven per lane. Tying it high defeats the
  Lane Supervisor's link-down handling
* ``AXIL_BASE_ADDR_G`` is set to a legal region of your system's
  AXI-Lite map. The receiver's internal crossbar consumes
  ``NUM_OF_SERIALIZERS_C + 1`` × 16 bits of address space starting from
  this base
* ``asicSro`` and ``asicSroEn`` are on the ``asicClk`` domain — do not
  drive them from ``pgpRxClk``-domain logic; the Trigger Manager
  handles the crossing internally
* If ``LANE_MON_GEN_G`` is ``false``, the ``LaneRx`` monitor AXI-Lite
  ports still exist in the crossbar but return
  ``AXI_LITE_READ_SLAVE_EMPTY_SLVERR_C``. Software register reads to
  those regions will get a SLVERR response
* Pipeline the AXI-Stream output of every ``LaneRx`` if you cannot
  place the receiver near the GT hard blocks. This is handled with the
  ``PIPELINE_*`` / ``*_PIPE_G`` generics on lower-level modules; the
  ``Pix2PgpAsicStreamRx`` wrapper itself has no such generic (the
  wrapper defaults are used)
