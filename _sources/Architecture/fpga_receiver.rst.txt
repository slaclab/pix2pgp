.. _architecture_fpga_receiver:

======================
FPGA Receiver Architecture
======================

The Pix2PGP FPGA receiver takes the per-lane frames coming off the
ASIC's serial links, checks each of them for integrity, and merges
them into one consolidated frame per trigger. Its internal structure
deliberately mirrors the ASIC core:

* Per-lane receivers (``LaneRx``) sit where the Column Managers sat on
  the ASIC side
* A Lane Supervisor sits where the Column Supervisor sat
* A Lane Merger sits where the Arbiter sat

Unlike the ASIC core, the FPGA receiver is **not trigger-agnostic**:
it also buffers the ``SRO`` triggers forwarded to the front-end, so it
can maintain the one-to-one trigger-to-frame mapping that the LCLS-II
DAQ infrastructure expects. The receiver additionally exposes an
**AXI-Lite** interface for configuration and status read-back.

The main source files live under ``firmware/fpga/rtl/``:

* ``Pix2PgpAsicStreamRx.vhd``    — top level of the FPGA receiver for
  one ASIC
* ``Pix2PgpLaneRxWrapper.vhd``,
  ``Pix2PgpLaneRx.vhd``          — see :ref:`architecture_fpga_lane_rx`
* ``Pix2PgpLaneMon.vhd``         — per-lane statistics for online
  monitoring / calibration
* ``Pix2PgpLaneSupervisor.vhd``  — cross-lane orchestration
* ``Pix2PgpLaneMerger.vhd``      — final frame assembly
* ``Pix2PgpTriggerManager.vhd``  — SRO / DAQ trigger buffering
* ``Pix2PgpAxiLiteManager.vhd``  — AXI-Lite register access

.. _architecture_fpga_lane_rx:

Lane Receiver (LaneRx)
======================

Each ``LaneRx`` instance is tied to one PGP4 receiver core. It parses
the AXI-Stream from the decoder, buffers the frame, and checks its
integrity.

Like the Column Manager on the ASIC side, ``LaneRx`` uses a **dual-FIFO
architecture** plus a small FSM that inspects every field of the
inbound frame:

* The **header** is registered first. The header carries:

  * ``OverOcc``, ``Pause``, ``Pause-Error``, ``Timeout``, ``Column
    FIFO Error``, ``Dummy Header`` flags
  * ``Column Hitmask`` — one bit per Column Manager in the source ASIC
    core; high if that Column recorded hits
  * ``Trigger Counter`` — for the current event

* The **payload** is then streamed into the ``LaneRx`` Data FIFO
* On successful decoding, the header metadata plus the
  internally-computed frame length are written into the ``LaneRx``
  Status FIFO, indicating event close-out for that lane

.. note::

   Each ``LaneRx`` instance is tied to a **GT (GigaBit Transceiver)**
   receiver, which is a hard block physically fixed to a specific area
   of the FPGA die. It is therefore important to **pipeline** the
   AXI-Stream output of each ``LaneRx`` as it is driven to the shared
   Lane Merger. Relevant generics: ``PIPELINE_DATA_G``,
   ``PIPELINE_STATUS_G``, ``ARB_DOUT_PIPE_G``, ``DATAFIFO_PIPE_G``,
   ``STATUSFIFO_PIPE_G``.

Lane Monitoring
===============

Each ``LaneRx`` is accompanied by a ``Pix2PgpLaneMon`` instance that
gathers per-lane statistics based on the received frame metadata.
These statistics are exposed via AXI-Lite and serve two main
use-cases:

* **Fast pixel calibration (trimming)** — the user can activate a
  single pixel per column and read back the per-column hit counts
  (accumulated from the Column Hitmask) directly from registers,
  avoiding a full frame decode round-trip through the back-end
  software. Register-based read-back is much faster than routing
  every frame through the decoder just for calibration
* **Real-time data-flow management** — an external logic monitors
  occupancy trends and implements **trigger throttling** if excessive
  per-event hit volumes are detected, so as to prevent Pause-Error
  conditions before they happen

Trigger Buffering
=================

``Pix2PgpTriggerManager`` maintains a buffer of trigger information
tied to each event. Two trigger types are tracked, following the
established LCLS data-management scheme:

* **Run trigger** — translates into ``SRO`` mediated to the
  front-end, initiating pixel readout
* **DAQ trigger** — indicates that the LCLS back-end expects a data
  frame for that event. If absent, frames are discarded at the FPGA
  receiver level and not transmitted downstream

For flexibility, the receiver can also be configured to run
**trigger-less**, initiating readout solely on lane activity — useful
for standalone testing and calibration.

Lane Supervision
================

``Pix2PgpLaneSupervisor`` monitors metadata from every ``LaneRx``. Its
job is to keep exactly one consolidated Pix2PGP frame going out per
trigger under all conditions:

* **Nominal operation** — merges one frame from each lane into the
  final Pix2PGP frame, one event per merger cycle
* **Pause fragments** — when a lane frame arrives with the ``Pause``
  bit set, the Supervisor knows more fragments from that lane are
  still to come and keeps the event open until a frame with the
  ``Pause`` bit cleared arrives, then closes and transmits the
  consolidated event
* **Error conditions** — on ASIC frame decoding failures, ``LaneRx``
  FIFO overflow, or unstable physical links, the Supervisor takes
  protective actions:

  * Disabling individual lanes
  * Resetting the entire receiver core
  * Transmitting **drop-frames** to the back-end until the receiver
    returns to an idle state (see :ref:`architecture_frame_format`)

Lane Merger
===========

``Pix2PgpLaneMerger`` performs the final frame assembly. Driven by
the Lane Supervisor, it emits the outbound Pix2PGP frame (preamble,
header, per-lane lengths, lane data, trailer — see
:ref:`architecture_frame_format`) over AXI-Stream to the back-end.
