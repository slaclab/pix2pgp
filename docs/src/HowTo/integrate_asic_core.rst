.. _how_to_integrate_asic_core:

===============================================
How to Integrate the Pix2PGP Core in Your ASIC
===============================================

This page describes how to drop the Pix2PGP core into an ASIC design.
The core is a **VHDL** design that is expected to be instantiated inside
the digital section of the ASIC, one instance per data lane (typically
one per PGP4 transmitter / serializer).

The top-level entity is ``Pix2PgpTop``, defined in
``gateware/shared/rtl/Pix2PgpTop.vhd``. It is intentionally kept
**simple-port** (``std_logic`` / ``std_logic_vector`` only on the
data-facing side) so it can be instantiated from a SystemVerilog /
Verilog wrapper without record-type friction. The only VHDL records
appearing on its interface are the small ``config`` / ``readback`` and
``AxiStreamMaster`` / ``Slave`` records — see the port table below.

Prerequisites
=============

* A per-ASIC package file (``Pix2PgpAsicPkg.vhd``) that defines the
  ASIC-scoped constants Pix2PGP reads (see :ref:`architecture_asic_core`
  and :ref:`how_to_add_new_asic`). The main knobs are:

  * ``NUM_OF_COL_MANAGERS_C`` — how many columns each Pix2PGP instance
    serves
  * ``NUM_OF_SERIALIZERS_C``  — how many Pix2PGP instances / lanes exist
    on the whole ASIC (used by the FPGA receiver — the ASIC core itself
    only cares about ``NUM_OF_COL_MANAGERS_C``)
  * ``ASIC_DATABUS_DWIDTH_C`` — the width of the data bus driven **into**
    Pix2PGP. Supported: 4, 8, 12, 16, 20, 24, 28, 32 bits
  * ``ASIC_TYPE_C``           — a numeric identifier, propagated into the
    consolidated FPGA-side frame preamble
  * ``INCR_TRGCNT_OVEROCC_C`` — whether the Trigger Counter should be
    incremented on an Over-Occupancy event
  * ``DATALEN_WIDTH_C`` / ``TRGCNT_WIDTH_C`` / ``TIMEOUT_LIMIT_WIDTH_C``
    — bit widths of the counters
  * ``EVAL_SOF_C`` / ``EVAL_EOFE_C`` — enable strict SoF / EoFE checking
    on the outbound AXI-Stream
  * ``HEADER_WIDTH_MULT_C`` — header scaling factor if the natural
    doubled-bus width cannot fit the header bitfields
  * The **header and column-metadata bitfield** definitions

* Two clocks: ``sparseClk`` (User Logic domain) and ``pgpClk``
  (Serializer / PGP domain) with their matching active-high resets
* An AXI-Stream slave downstream (a PGP4 transmitter for the standard
  use-case, or any other consumer if you want to wire Pix2PGP into a
  non-PGP transport)

Generics
========

.. list-table:: ``Pix2PgpTop`` generics
   :header-rows: 1
   :widths: 30 15 15 40

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
     - ``true``
     - ``true`` → use asynchronous reset; ``false`` → synchronous reset
   * - ``RST_POLARITY_G``
     - ``std_logic``
     - ``'1'``
     - Reset active-high (``'1'``) or active-low (``'0'``)
   * - ``PIPELINE_DATA_G``
     - ``boolean``
     - ``false``
     - Insert an extra pipeline stage on the Arbiter → PGP TX data path.
       Enable when timing on the AXI-Stream to the PGP4 transmitter is
       tight
   * - ``PIPELINE_STATUS_G``
     - ``boolean``
     - ``true``
     - Insert an extra pipeline stage on the Column Supervisor /
       Arbiter status buses. Usually leave enabled
   * - ``COLMANAGER_DATA_DEPTH_G``
     - ``integer``
     - ``7``
     - Data FIFO depth per Column Manager, as ``log2``. E.g. ``7`` → 128
       entries. Bounded by the silicon area budget of the digital core
       (see :ref:`flow_pause` for the buffer-sizing trade-off)
   * - ``COLMANAGER_STATUS_DEPTH_G``
     - ``integer``
     - ``6``
     - Status FIFO depth per Column Manager, as ``log2``. E.g. ``6`` → 64
       entries. Typically smaller than the Data FIFO
   * - ``DATAFIFO_PIPE_G``
     - ``natural``
     - ``1``
     - Number of pipeline registers on the Data FIFO output. Zero-latency
       reads are supported, but adding a pipeline stage helps timing
       closure inside the core
   * - ``STATUSFIFO_PIPE_G``
     - ``natural``
     - ``1``
     - Number of pipeline registers on the Status FIFO output

Ports
=====

General Interface
-----------------

.. list-table::
   :header-rows: 1
   :widths: 20 15 65

   * - Name
     - Direction
     - Description
   * - ``sparseClk``
     - ``in``
     - User Logic clock (matrix / sparse-logic domain). Drives the
       write-side of each Column Manager FIFO
   * - ``pgpClk``
     - ``in``
     - PGP / Serializer clock. Drives the Column Supervisor, the
       Arbiter, and the read-side of every FIFO
   * - ``sparseRst``
     - ``in``
     - Reset on the ``sparseClk`` domain, polarity per
       ``RST_POLARITY_G``
   * - ``pgpRst``
     - ``in``
     - Reset on the ``pgpClk`` domain, polarity per
       ``RST_POLARITY_G``
   * - ``config``
     - ``in``
     - ``Pix2PgpCfgConfigType`` record. Carries the run-time configurable
       fields (see the *Config record* subsection below)
   * - ``readback``
     - ``out``
     - ``Pix2PgpCfgReadbackType`` record. Aggregated status flags used
       for register read-back (see *Readback record* below)

Column Manager Interface
------------------------

All of these ports are ``NUM_OF_COL_MANAGERS_C`` bits wide and share the
User Logic clock domain. They are the interface between Pix2PGP and the
per-column User Logic instances.

.. list-table::
   :header-rows: 1
   :widths: 15 12 15 58

   * - Name
     - Direction
     - Type
     - Description
   * - ``din``
     - ``in``
     - ``Pix2PgpSparseDinArray``
     - Data bus. One
       ``std_logic_vector(ASIC_DATABUS_DWIDTH_C-1 downto 0)`` per Column
       Manager. Values latched into the Column Manager Data FIFO on
       every high ``wrEn`` strobe
   * - ``wrEn``
     - ``in``
     - ``slv``
     - Per-column write-enable. Strobes a valid data word on ``din``
       into the corresponding Column Manager Data FIFO
   * - ``sof``
     - ``in``
     - ``slv``
     - Per-column Start-of-Frame. Opens a new event in that Column
       Manager and increments its Trigger Counter
   * - ``eof``
     - ``in``
     - ``slv``
     - Per-column End-of-Frame. Closes the event nominally
   * - ``overOcc``
     - ``in``
     - ``slv``
     - Per-column Over-Occupancy. Closes the current event and (for
       self-closure ASICs) opens the next one on the same cycle. See
       :ref:`flow_over_occupancy`
   * - ``pauseAck``
     - ``in``
     - ``slv``
     - Per-column Pause acknowledgement from the User Logic. Confirms
       to the Column Manager that the User Logic has seen the ``pause``
       assertion and stopped forwarding new hits
   * - ``busy``
     - ``out``
     - ``slv``
     - Per-column busy status. High while the Column Manager is
       actively processing an event
   * - ``pause``
     - ``out``
     - ``slv``
     - Per-column Pause request driven back to the User Logic. Asserted
       when the Column Manager's Data FIFO or Status FIFO reaches its
       almost-full threshold. See :ref:`flow_pause`

PGP4 TX Interface
-----------------

.. list-table::
   :header-rows: 1
   :widths: 20 15 65

   * - Name
     - Direction
     - Description
   * - ``pgpTxMaster``
     - ``out``
     - AXI-Stream master carrying the outbound Pix2PGP Lane Frame. Its
       width is ``PIX2PGP_DATABUS_DWIDTH_C = ASIC_DATABUS_DWIDTH_C * 2``.
       Wire this directly to the ``pgpTxMaster`` input of the PGP4
       transmitter (a Gearbox inside the core adapts the width to 64-bit
       PGP4 before this port). See :ref:`architecture_frame_format`
   * - ``pgpTxSlave``
     - ``in``
     - AXI-Stream slave handshake from the PGP4 transmitter

Config record
=============

``Pix2PgpCfgConfigType`` (defined in
``gateware/shared/rtl/Pix2PgpPkg.vhd``) is the run-time configuration
record driven into ``Pix2PgpTop.config``:

.. list-table::
   :header-rows: 1
   :widths: 25 15 60

   * - Field
     - Width
     - Description
   * - ``colEnaSparse``
     - ``NUM_OF_COL_MANAGERS_C``
     - Per-column enable on the sparse / User-Logic side. Low disables
       writes into that Column Manager's Data FIFO
   * - ``colEnaPgp``
     - ``NUM_OF_COL_MANAGERS_C``
     - Per-column enable on the PGP / drain side. Low keeps the
       Arbiter from draining that Column Manager
   * - ``timeoutLimit``
     - ``TIMEOUT_LIMIT_WIDTH_C``
     - Watchdog limit (in PGP-clock cycles) used by the Column
       Supervisor in the Timeout Readout Sequence
   * - ``pauseLimit``
     - ``TIMEOUT_LIMIT_WIDTH_C``
     - Pause-timeout limit (in PGP-clock cycles) used by the Column
       Supervisor to group paused columns together on ERO-closure
       ASICs

A ready-made default value, ``DEFAULT_PIX2PGP_CONFIG_C``, is exported
by the package. If you have no register-file infrastructure yet, wire
``config <= DEFAULT_PIX2PGP_CONFIG_C`` to bring the core up.

Readback record
===============

``Pix2PgpCfgReadbackType`` — aggregated status returned on
``Pix2PgpTop.readback``:

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - Field
     - Description
   * - ``cfgColBusy``
     - Logical-OR of the per-column ``busy`` signals
   * - ``cfgColDataEmpty``
     - Logical-AND of the empty flags of every Column Manager Data FIFO
   * - ``cfgColStatusEmpty``
     - Logical-AND of the empty flags of every Column Manager Status
       FIFO
   * - ``cfgSuperBusy``
     - Column Supervisor busy flag
   * - ``cfgArbBusy``
     - Arbiter busy flag

Wire these up to your ASIC's slow-control read-back path if you want the
core's live state to be observable off-chip.

Instantiation Template
======================

For an ASIC with 24 columns per Pix2PGP instance, 20-bit data words,
and 8 lanes (SparkPix-S-style):

.. code-block:: vhdl

   library ieee;
   use ieee.std_logic_1164.all;

   library surf;
   use surf.StdRtlPkg.all;
   use surf.AxiStreamPkg.all;

   library pix2pgp;
   use pix2pgp.Pix2PgpAsicPkg.all;
   use pix2pgp.Pix2PgpPkg.all;

   -- ...

   U_Pix2PgpLane : entity pix2pgp.Pix2PgpTop
      generic map (
         TPD_G                     => 1 ns,
         RST_ASYNC_G               => true,
         RST_POLARITY_G            => '1',
         PIPELINE_DATA_G           => false,
         PIPELINE_STATUS_G         => true,
         COLMANAGER_DATA_DEPTH_G   => 7,   -- 128 entries per column
         COLMANAGER_STATUS_DEPTH_G => 6,   -- 64 entries per column
         DATAFIFO_PIPE_G           => 1,
         STATUSFIFO_PIPE_G         => 1)
      port map (
         -- Clocks / resets
         sparseClk   => sparseClk,
         pgpClk      => pgpClk,
         sparseRst   => sparseRst,
         pgpRst      => pgpRst,
         -- Config / readback
         config      => pix2pgpConfig,
         readback    => pix2pgpReadback,
         -- Column Manager Interface (all NUM_OF_COL_MANAGERS_C-wide)
         din         => colDin,
         wrEn        => colWrEn,
         sof         => colSof,
         eof         => colEof,
         overOcc     => colOverOcc,
         pauseAck    => colPauseAck,
         busy        => colBusy,
         pause       => colPause,
         -- PGP4 TX
         pgpTxMaster => pgpTxMaster,
         pgpTxSlave  => pgpTxSlave);

Replicate this instantiation ``NUM_OF_SERIALIZERS_C`` times inside your
ASIC top-level, each connected to a distinct group of columns and to a
distinct PGP4 transmitter / serializer pair.

Instantiation Checklist
=======================

* Both ``sparseClk`` and ``pgpClk`` are physically driven and their
  frequencies match those declared in ``Pix2PgpAsicPkg.vhd``
* ``RST_POLARITY_G`` matches the polarity of the resets you feed in
* Every element of ``din(i)`` is exactly ``ASIC_DATABUS_DWIDTH_C`` bits
  wide (VHDL synthesis will error out otherwise, but Verilog wrappers
  often silently truncate)
* The User Logic honours ``pause`` — no ``wrEn`` may be issued while
  ``pause`` is high; ``pauseAck`` should mirror this. Failure to honour
  Pause causes Data / Status FIFO overflows and undefined behaviour
* The AXI-Stream between ``pgpTxMaster``/``pgpTxSlave`` and the PGP4
  transmitter carries the correct ``tKeep`` / ``tLast`` conventions.
  If you use SURF's ``Pgp4TxLite``, wire directly; if you use a
  proprietary PGP transmitter, verify the AXI-Stream config record
  matches
* ``config`` is stable during operation. If register writes are allowed
  at runtime, ensure the ``config`` fields are captured on ``pgpClk``
  before being applied
