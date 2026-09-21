.. _architecture_asic_core:

===================
ASIC Core Architecture
===================

The Pix2PGP ASIC core is comprised of three main module types:

* :ref:`architecture_column_manager` — one instance per data source
  (typically per pixel column); accepts data words and event delimiters
  from the ASIC User Logic and buffers them until the event closes
* :ref:`architecture_column_supervisor` — one instance per core;
  orchestrates readout by monitoring the Status Bus of every Column
  Manager
* :ref:`architecture_arbiter` — one instance per core; drains the Data
  FIFOs and assembles the outbound AXI-Stream frame

The core operates across two clock domains (see
:ref:`architecture_top_level`). Most logic lives on the PGP / Serializer
clock; only the write-side of each Column Manager FIFO runs on the User
Logic clock.

Handshaking Interface
=====================

Between the User Logic (data source) and each Column Manager, four
groups of signals are exchanged:

* **Data Bus / wrEn** — data flow into Pix2PGP. ``wrEn`` is the
  write-enable strobe issued alongside a valid data word on the Data
  Bus. Data widths are ASIC-specific; see
  :ref:`architecture_asic_implementations`
* **SoF / EoF / OverOcc** — event delimiters driven by the User Logic:

  * ``SoF`` (Start-of-Frame) opens a new event
  * ``EoF`` (End-of-Frame) closes the current event nominally
  * ``OverOcc`` (Over-Occupancy) closes the current event and opens the
    next one on the same cycle. See :ref:`flow_over_occupancy`

* **Pause** — back-pressure driven from Pix2PGP to the User Logic.
  Asserted when either the Data FIFO or the Status FIFO of the Column
  Manager reaches its almost-full capacity threshold. See :ref:`flow_pause`
* **busy** — output from Pix2PGP indicating that the Column Manager is
  currently mid-event

.. _architecture_column_manager:

Column Manager
==============

Each Column Manager interfaces one data-generating User Logic instance
with the rest of the Pix2PGP core. It contains:

* A **Data FIFO** (dual-clock) that buffers the ``wrEn``-strobed data
  words. Its output drives the Column's Data Bus
* A **Status FIFO** (dual-clock) that buffers a single per-event
  metadata word. Its output drives the Column's Status Bus
* A **monitoring FSM** on the User Logic clock domain that reacts to
  ``SoF`` / ``EoF`` / ``OverOcc`` and maintains two counters:

  * ``Trigger Counter`` — incremented on every ``SoF``
  * ``Data-Length Counter`` — incremented on every ``wrEn``

On ``SoF``, the monitoring FSM enters a **busy** state (also exposed as
an output) and the Data FIFO becomes writable. Any of ``EoF``,
``OverOcc``, or an internal Pause assertion closes the event within the
Column Manager's local scope. Event closure means: one **Status Word**
is written into the Status FIFO, made up of:

* ``OverOcc`` flag — high if the event closed because of an OverOcc
  reception
* ``Pause`` flag — high if the event closed because a FIFO reached its
  almost-full threshold
* ``Data-Length Counter`` value — how many hits were recorded for this
  event
* ``Trigger Counter`` value — which trigger this event belongs to

The Data-Length Counter's role in the drain sequence is described under
:ref:`architecture_arbiter`.

The Column Manager exposes two outputs:

* **Data Bus** — the Data FIFO output
* **Status Bus** — the Status FIFO output, plus its empty / dataValid
  flag and an overflow / underflow error signal

These buses are bundled together across every Column Manager and driven
into the Arbiter and the Column Supervisor.

.. _architecture_column_supervisor:

Column Supervisor
=================

The Column Supervisor is a single-instance FSM. It ignores ``SoF`` /
``EoF`` timing entirely and reacts only to the Status Buses. While
``IDLE``, it monitors the empty / dataValid flag of every Column
Manager's Status FIFO. Depending on the observed pattern, one of the
following **Readout Sequences** is initiated:

* **Nominal** — every Status FIFO yields a word, and no lane reports
  Pause. The Column Hitmask is assembled: one bit per Column Manager,
  high if that Column recorded at least one hit for this event (i.e. if
  its Data-Length Counter is non-zero). The Arbiter then drains the
  Data FIFOs of the columns whose bit is high
* **Pause** — every Status FIFO yields a word, and some/all report
  Pause. Only the paused columns have their bit set in the Column
  Hitmask; the Arbiter drains only their Data FIFOs. The remaining
  columns will be read on a subsequent cycle when the event closes
  normally

  * For ASICs featuring an ERO signal (see
    :ref:`architecture_asic_impl_timing`), the Supervisor cannot wait
    for every Status FIFO to be non-empty before starting a Pause
    sequence, because event closure is externally triggered. Instead,
    it enters a short configurable **pause-timeout** on the first
    Pause, to group any other paused columns from the same event, and
    then reads them out

* **Pause-Error / Digital Over-Occupancy** — one or more Status FIFOs
  report both Pause and OverOcc high (a new ``SoF`` arrived while the
  column was still paused). The Supervisor starts the Arbiter
  immediately without waiting for the other columns to close, so as to
  drain FIFOs as fast as possible. The ``Pause-Error`` bit is set in
  the outbound frame's header. See :ref:`flow_pause_error`
* **Timeout** — a subset (but not all) of the Status FIFOs are
  non-empty. A watchdog counter is armed, and if the state persists
  for a configurable number of PGP-clock cycles, the event is closed
  with the Timeout flag raised, and only the non-empty columns are
  drained. If all Status FIFOs go non-empty before the watchdog
  expires, one of the other three sequences is initiated instead.
  This feature is **not** activated on ASICs that rely on an ERO
  signal to close events

Once a sequence is chosen, the Supervisor registers the aggregate
metadata (Column Hitmask, Trigger Counter, status flags) and signals
the Arbiter to begin.

.. _architecture_arbiter:

Arbiter
=======

The Arbiter is a single-instance FSM that produces the outbound
AXI-Stream forwarded to the PGP4 encoder. Its data-output width equals
the internal Pix2PGP bus width
(``PIX2PGP_DATABUS_DWIDTH_C = ASIC_DATABUS_DWIDTH_C * 2``), which is
application-specific. A **Gearbox** between the Arbiter's AXI-Stream
output and the 64-bit AXI-Stream input of the PGP4 transmitter adapts
the width.

Once the Column Supervisor issues its ``Start`` signal, the Arbiter:

1. **Opens the outbound frame** and transmits the header (see
   :ref:`architecture_frame_format`). The header carries the Column
   Hitmask, the Trigger Counter, and the aggregate status flags
2. **Scans the Column Hitmask** for high bits:

   * A low bit means the Column has no data for this event — skip it
   * A high bit means the Column has data for this event. The Arbiter:

     a. Switches a **Column Metadata Multiplexer** onto the Status
        FIFO output of the current Column, and transmits the Column
        Metadata word (per-column Pause / OverOcc / Timeout / Trigger
        Counter / Data-Length values)
     b. Switches a **Data Bus Multiplexer** onto the Data FIFO output
        of the current Column
     c. **Reads exactly** ``Data-Length Counter`` **words** from that
        Data FIFO and transmits them. Not one more, not one less

3. **Closes the frame** after every Hitmask bit has been evaluated

The precise draining in step 2c is why each Column Manager needs its
Status FIFO. Without an exact hit count, the Arbiter would either have
to drain until the FIFO went empty (risking picking up hits from a
later event that was already being written) or transmit padding — both
options ruin per-event ordering. Keeping the exact count decouples the
User Logic side from the drain side: the User Logic can keep writing
into the next event while the Arbiter is still shipping out the
previous one.

If no Columns recorded hits (Column Hitmask == 0), only the header is
transmitted and the frame closes immediately. This preserves the
one-frame-per-trigger invariant even for zero-hit events.
