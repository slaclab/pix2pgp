.. _architecture_flow_control:

=======================
Data-Flow and Corner Cases
=======================

This section describes the three special conditions Pix2PGP handles
explicitly at the ASIC-core level: **Over-Occupancy**, **Pause**, and
**Pause-Error**. Every event transmitted by a Pix2PGP lane carries the
corresponding flags in its header, so the downstream logic can reason
about the state of the acquisition.

Nominal Readout
===============

In nominal operating conditions:

1. An external trigger — Start-Of-Readout (``SRO``) — is issued to the
   detector. The User Logic translates the ``SRO`` into an ``SoF`` on
   each affected Column Manager
2. The pixel/analog logic yields data words which are digitized and
   forwarded to the Column Manager via the ``wrEn`` strobe
3. The event closes on either:

   * ``EoF`` (self-closure — the User Logic determines the event is
     done), or
   * ``ERO`` (End-Of-Readout — an external trigger that closes the
     event; only applies to ASICs featuring an ERO signal, see
     :ref:`architecture_asic_impl_timing`)

4. Once every Column Manager has closed its event, the Column
   Supervisor initiates a **Nominal Readout Sequence** and the Arbiter
   drains the Data FIFOs

Each column served by a Pix2PGP core operates independently — one
column's event closure does not affect any other column's readout.

.. _flow_over_occupancy:

Over-Occupancy
==============

**Over-Occupancy** occurs when a new ``SRO`` (and, consequently, a new
``SoF``) arrives while the User Logic of a column is still processing
the previous event.

The Column Manager treats this condition as **both an EoF and an SoF
at the same time**: the previous event is closed and flagged with
``OverOcc``, and a new event is immediately opened. The event's Status
Word carries the ``OverOcc`` bit high, and that bit propagates into
the outbound frame's header metadata.

Over-Occupancy is an expected — if undesirable — condition during
high-occupancy runs. It flags a data-integrity concern rather than a
failure mode: some hits from the previous event may have been dropped
by the analog side, but the digital core itself stays stable.

For ASICs featuring an ERO trigger (e.g. SparkPix-T and Thriglav), the
Over-Occupancy signal only **closes** the current event; a subsequent
conventional ``SRO`` (with its associated ``SoF``) opens the next one.
This occurs because Over-Occupancy is triggered upon the reception of
an ``ERO`` signal.

.. _flow_pause:

Pause (Back-Pressure)
=====================

Every Column Manager instantiates a Data FIFO and a Status FIFO of
finite depth. When either FIFO reaches its almost-full threshold
(typically set one entry below the true full threshold, to accommodate
handshaking latency between the User Logic and Pix2PGP), the Column
Manager asserts the **Pause** signal to its User Logic.

While Pause is asserted:

* The User Logic must halt data forwarding — no new ``wrEn`` strobes
  are accepted
* Within Pix2PGP, Pause is treated as an **internally-generated EoF**:
  the Column Manager writes a Status Word into its Status FIFO with
  the ``Pause`` flag high, and the Column Supervisor prioritizes
  draining the paused columns
* Once the Data FIFO and Status FIFO of a paused column have been
  drained by the Arbiter, Pause is released and the User Logic resumes
  writing

Pause serves two purposes:

* **Overflow prevention** — the finite-depth Data/Status FIFOs cannot
  lose hits from a single event even during transient occupancy bursts
* **High-occupancy readout** — a single event may be fragmented across
  multiple transmission cycles. Each fragment is flagged in its header
  metadata so the FPGA receiver can recognize and reassemble the
  pieces into one event frame downstream

**Independent operation.** The Pause mechanism is per-Column-Manager.
While one column is paused, the rest continue writing normally.

Practical example: a full-matrix calibration scan intentionally
activates thousands of pixels. Data FIFO depth is bounded by the
silicon area budget of the digital core, so a single event cannot be
buffered in one shot. Pause allows the same event to be transmitted in
several fragments, and the FPGA receiver reassembles them at the end.

.. _flow_pause_error:

Pause-Error (Digital Over-Occupancy)
====================================

**Pause-Error** occurs when a new ``SoF`` arrives while one or more
Column Managers are already in **Pause** state. This is the
"Pause + Over-Occupancy" case, also referred to as **Digital
Over-Occupancy**.

Unlike Over-Occupancy — which reflects a limit on the analog / User
Logic side — Pause-Error indicates that the **digital readout chain
itself** cannot keep up with the incoming data volume for the given
trigger rate.

When the Column Supervisor detects a Pause-Error, it does not wait for
all columns to close their event before starting the Arbiter — it
drains whatever is available immediately, and raises the
``Pause-Error`` flag in the outbound frame's header. Under sustained
Pause-Error conditions:

* Event coherence cannot be guaranteed
* Entire events may be missed by some Column Managers
* Data shuffling may occur within a single frame

**Recovery.** Once the data volume returns to nominal levels, the
system self-recovers. This is handled primarily by the FPGA receiver
logic (see :ref:`architecture_fpga_receiver`), which tracks issued
triggers and per-frame event identifiers. Once the ASIC exits
Pause-Error, the aggregator re-sorts the trigger / frame queues.

**User responsibility.** The Pause-Error flag is a diagnostic signal.
Downstream logic (or the user) should react by:

* Reducing the trigger rate, or
* Modifying the detector configuration so that fewer hits are
  generated per trigger, or
* Halting acquisition

In controlled environments (calibration runs with well-defined
per-event data volumes), Pause-Error can be avoided.
In the field, it is a realistic condition and must be planned for.

Buffer Sizing Trade-Off
=======================

Data FIFO depth is a critical parameter and is generally dominated by
the silicon area budget of the digital readout core. Given a fixed
budget, depth is validated against the target requirements — expressed
as maximum trigger rate versus hit occupancy pairs (see
:ref:`architecture_asic_implementations`).

Larger FIFOs let the core absorb higher-than-nominal occupancy bursts
before falling into Pause-Error, at the cost of area. See
:ref:`how_to_run_benchmarking` for how to evaluate this trade-off with
the provided VCS testbenches.
