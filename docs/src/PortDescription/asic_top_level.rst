.. _port_description_asic:

======================
ASIC Top-Level Wrapper
======================

Every supported ASIC has a wrapper ``Pix2Pgp<AsicName>Top`` under
``gateware/asics/<AsicName>/rtl/``. It instantiates, for **one** lane:

* the shared ``Pix2PgpTop`` core (Column Managers, Column Supervisor,
  Arbiter)
* the ``Pix2Pgp4TxLiteWrapper`` (PGP4 transmitter)
* a 66-bit → 32-bit ``Gearbox`` toward the serializer
* the clock-domain synchronizers and capture registers for the
  configuration inputs

The wrapper exposes **only** ``std_logic`` / ``std_logic_vector`` ports,
with hardcoded widths, so it can be instantiated from a SystemVerilog /
Verilog ASIC top. Asserts inside the wrapper check every port width
against the constants of ``Pix2PgpAsicPkg.vhd`` at elaboration time.
Instantiate the wrapper ``NUM_OF_SERIALIZERS_C`` times per ASIC.

In the tables below, ``N`` = ``NUM_OF_COL_MANAGERS_C`` and
``W`` = ``ASIC_DATABUS_DWIDTH_C``:

.. list-table:: Per-ASIC widths
   :header-rows: 1
   :widths: 25 15 15 15 15

   * - ASIC
     - ``N``
     - ``W``
     - ``cfgPauseLimit``
     - ``cfgMaskEofPause``
   * - SparkPix-S
     - 24
     - 20
     - no
     - no
   * - SparkPix-Sv2
     - 24
     - 20
     - no
     - no
   * - SparkPix-T
     - 24
     - 32
     - yes
     - no
   * - Thriglav
     - 50
     - 32
     - yes
     - no
   * - New ASICs (``EN_EOF_FLAG_C = True``)
     - —
     - —
     - if ``EN_ERO_C``
     - yes (see :ref:`port_description_asic_eof`)

Generics
========

.. list-table::
   :header-rows: 1
   :widths: 28 12 10 50

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
     - ``true``
     - ``true`` → asynchronous reset; ``false`` → synchronous reset
   * - ``RST_POLARITY_G``
     - ``std_logic``
     - ``'0'``
     - Reset polarity of ``sparseRst`` / ``pgpRst`` / ``pgpHardRst``.
       ``'0'`` = active-low (the wrapper default; the shared
       ``Pix2PgpTop`` defaults to ``'1'``)
   * - ``PIPELINE_DATA_G``
     - ``boolean``
     - ``false``
     - Register the Data Bus inside the Arbiter before it is
       multiplexed onto the AXI-Stream. Use for timing closure
   * - ``PIPELINE_STATUS_G``
     - ``boolean``
     - ``true``
     - Register the Status Bus inside the Column Supervisor and the
       Arbiter. Usually left enabled
   * - ``COLMANAGER_DATA_DEPTH_G``
     - ``integer``
     - ``8``
     - Data FIFO depth per Column Manager, as a number of DesignWare
       FIFO entries (not ``log2``). The FIFO is read through the
       double-width internal bus (``2*W``), so each entry holds two
       hits, i.e. the FIFO holds ``COLMANAGER_DATA_DEPTH_G * 2`` hits.
       The ``surfFifo`` variant (GHDL / FPGA emulation) ignores it and
       uses a fixed internal address width
   * - ``COLMANAGER_STATUS_DEPTH_G``
     - ``integer``
     - ``8``
     - Status FIFO depth per Column Manager, as a number of DesignWare
       FIFO entries (one per closed event / Pause fragment). Same
       ``surfFifo`` caveat as above
   * - ``DATAFIFO_PIPE_G``
     - ``natural``
     - ``1``
     - Pipeline stages on the Data FIFO write-side inputs and on its
       read-error flag
   * - ``STATUSFIFO_PIPE_G``
     - ``natural``
     - ``1``
     - Pipeline stages on the Status FIFO write-side inputs and on its
       read-error flag

Ports
=====

General Interface
-----------------

.. list-table::
   :header-rows: 1
   :widths: 20 8 12 60

   * - Name
     - Dir
     - Width
     - Description
   * - ``sparseClk``
     - in
     - 1
     - User Logic (matrix / sparse) clock. Write side of every Column
       Manager FIFO, the Column Manager FSMs and the watchdogs
   * - ``pgpClk``
     - in
     - 1
     - PGP / serializer clock. Column Supervisor, Arbiter, PGP4
       transmitter, serializer gearbox, and the read side of every
       FIFO
   * - ``sparseRst``
     - in
     - 1
     - Reset on ``sparseClk``, polarity per ``RST_POLARITY_G``. Also
       resets the FIFOs
   * - ``pgpRst``
     - in
     - 1
     - Reset of the Pix2PGP core logic on ``pgpClk``, and of the
       ``pgpClk``-domain configuration registers
   * - ``pgpHardRst``
     - in
     - 1
     - Reset of the PGP4 transmitter and the serializer gearbox only.
       Kept separate so that the core can be reset without dropping
       the PGP link

Configuration Interface
-----------------------

The ``cfg*`` inputs come from the ASIC's slow-control register file and
are treated as asynchronous. The wrapper synchronizes each one to the
clock domain where it is used, then captures it into the internal
``config`` record while ``cfgSel`` is high.

.. list-table::
   :header-rows: 1
   :widths: 20 8 12 60

   * - Name
     - Dir
     - Width
     - Description
   * - ``cfgSel``
     - in
     - 1
     - Configuration capture enable. While high, the internal
       ``config`` record tracks the synchronized ``cfg*`` inputs; while
       low, it holds its last value. Tie high if the register file
       does not need a commit strobe
   * - ``cfgTimeoutLimit``
     - in
     - 12 (``TIMEOUT_LIMIT_WIDTH_C``)
     - Column Supervisor watchdog limit for the Timeout Readout
       Sequence. The watchdog counts on **sparseClk**. Not used on
       ERO ASICs
   * - ``cfgPauseLimit``
     - in
     - 12
     - **ERO ASICs only.** Pause-timeout window (``sparseClk``
       cycles) during which the Column Supervisor groups paused
       columns before draining them. On SparkPix-S/Sv2, the port does
       not exist and ``config.pauseLimit`` is tied to zero
   * - ``cfgColumnEnable``
     - in
     - ``N``
     - Per-column enable. Synchronized to both domains:

       * ``pgpClk`` → ``config.colEnaPgp``: the Column Supervisor only
         waits for, evaluates and drains enabled columns
       * ``sparseClk`` → ``config.colEnaSparse``: masks the column's
         ``busy`` output
   * - ``cfgMaskEofPause``
     - in
     - 1
     - **New ASICs only.** See :ref:`port_description_asic_eof`
   * - ``cfgColBusy``
     - out
     - 1
     - OR of the per-column busy signals
   * - ``cfgColDataEmpty``
     - out
     - 1
     - AND of every Column Manager Data FIFO empty flag
   * - ``cfgColStatusEmpty``
     - out
     - 1
     - AND of every Column Manager Status FIFO empty flag
   * - ``cfgSuperBusy``
     - out
     - 1
     - Column Supervisor busy (not in ``IDLE``)
   * - ``cfgArbBusy``
     - out
     - 1
     - Arbiter busy (frame transmission in progress)

The five read-back outputs come from both clock domains and are **not**
synchronized. They are meant for slow-control polling.

Column Manager Interface
------------------------

Every port in this group is on the ``sparseClk`` domain and is driven
by, or drives, the per-column User Logic. Bit ``i`` of each vector
belongs to Column Manager ``i``.

.. list-table::
   :header-rows: 1
   :widths: 20 8 12 60

   * - Name
     - Dir
     - Width
     - Description
   * - ``din0`` … ``din<N-1>``
     - in
     - ``W`` each
     - Per-column data word. Written into the Data FIFO on ``wrEn``.
       One port per column, because ``W``-wide arrays cannot cross the
       VHDL/SystemVerilog boundary cleanly
   * - ``wrEn``
     - in
     - ``N``
     - Write-enable. Only accepted while the column is in-frame
       (between ``sof`` and the event closure)
   * - ``sof``
     - in
     - ``N``
     - Start-of-Frame. On a rising edge, opens an event and increments
       the column's Trigger Counter
   * - ``eof``
     - in
     - ``N``
     - End-of-Frame. Closes the event nominally and releases ``busy``.
       On ASICs with ``EN_EOF_FLAG_C = True``, also sets the EoF bit
       in the column's Status Word
   * - ``overOcc``
     - in
     - ``N``
     - Over-Occupancy, a single-cycle strobe. Closes the current event
       with the Over-Occupancy flag set; ``busy`` stays high. With
       ``INCR_TRGCNT_OVEROCC_C = True`` (SparkPix-S), it also opens the
       next event and increments the Trigger Counter. See
       :ref:`flow_over_occupancy`
   * - ``pauseAck``
     - in
     - ``N``
     - Pause acknowledge from the User Logic. A rising edge while
       in-frame closes the current fragment with the Pause flag set
   * - ``busy``
     - out
     - ``N``
     - High from ``sof`` until the ``eof``-closure Status Word is
       written. Masked by ``config.colEnaSparse``
   * - ``pause``
     - out
     - ``N``
     - Back-pressure toward the User Logic. High while either the Data
       FIFO or the Status FIFO is almost-full. See :ref:`flow_pause`

Serializer Interface
--------------------

.. list-table::
   :header-rows: 1
   :widths: 20 8 12 60

   * - Name
     - Dir
     - Width
     - Description
   * - ``pgpDout``
     - out
     - 32
     - PGP4-encoded 64b/66b stream, geared down to 32 bits
       (``SER_DWIDTH_C``) for the serializer. ``pgpClk`` domain
   * - ``pgpDoutValid``
     - out
     - 1
     - ``pgpDout`` is valid
   * - ``pgpDoutReady``
     - in
     - 1
     - Serializer is ready to accept ``pgpDout``
