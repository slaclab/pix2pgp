.. _architecture_top_level:

=================
Top-Level Overview
=================

A Pix2PGP-based readout chain has three tiers. Inside the ASIC, one or
more Pix2PGP cores take sparse data from their assigned slice of the
pixel matrix and hand off a per-trigger event frame to a dedicated PGP4
transmitter. Off-chip, one FPGA hosts one PGP4 receiver per link plus
the Pix2PGP receiver logic; the receiver merges the per-lane frames into
a single per-trigger frame that goes on to the back-end.

Design Philosophy
-----------------

Pix2PGP is an **event builder**: it waits for every source it manages to
close the current event, then transmits a single AXI-Stream frame per
trigger under nominal operation. Under back-pressure
(also referred to as ``Pause``) conditions (see :ref:`architecture_flow_control`),
the ASIC transmits the event data in multiple fragment frames per
trigger, and the FPGA receiver reassembles them into one
consolidated frame downstream. Either way, the back-end
sees a single frame per trigger.

This is different from a streaming design where individual hits are
pushed out as they arrive on a per-trigger basis; the streaming
approach shifts event assembly onto the back-end and becomes hard to
scale at high trigger rates with variable per-event occupancy.

Two design ideas underpin the framework:

* **Segmentation** — each Pix2PGP core owns a fixed set of data sources
  (typically pixel columns - also referred to as macro-pixels).
  Multiple cores are instantiated per ASIC to
  spread the data load. Cores are independent of each other, and each
  emits one AXI-Stream frame per trigger under nominal operation (or a
  sequence of fragment frames under back-pressure/``Pause`` conditions)
* **Handshaking** — the interface between the data-generating logic
  (referred to in this documentation as **User Logic**) and Pix2PGP is
  intentionally minimal: a data bus with a write-enable strobe, two
  event delimiters (Start-of-Frame / End-of-Frame), an Over-Occupancy
  flag, and a bidirectional back-pressure signal (Pause). See
  :ref:`architecture_flow_control` for the details

Clock Domains
-------------

Pix2PGP is a dual-clock-domain design:

* **PGP / Serializer clock** (~185.714 MHz on current deployments — the
  LCLS clock). Most of the core operates here, including the AXI-Stream
  output toward the PGP4 transmitter
* **User Logic / Matrix / Sparse clock** (application-specific — see
  :ref:`architecture_asic_implementations`). This is the domain of the
  data-generating logic that feeds Pix2PGP. Only the write-side of each
  Column Manager's FIFO lives in this domain

The Column Manager uses dual-clock FIFOs to bridge the two domains.

Repository Mapping
------------------

The RTL source is organized as follows:

* ``gateware/shared/rtl/``      — the ASIC-side core, common across every
  supported ASIC:

  * ``Pix2PgpTop.vhd``          — top-level of the shared core
  * ``Pix2PgpColumnManager.vhd`` — see :ref:`architecture_asic_core`
  * ``Pix2PgpColumnSupervisor.vhd``
  * ``Pix2PgpArbiter.vhd``
  * ``Pix2PgpWatchdog.vhd``
  * ``Pix2PgpPkg.vhd``          — global constants and types
  * ``Pix2Pgp4TxLiteWrapper.vhd`` — SURF PGP4 TX wrapper
  * ``surfFifo/`` and ``synopsysFifo/`` — dual-clock FIFO variants

* ``gateware/asics/<AsicName>/`` — per-ASIC top-level and package. Every
  ASIC integrates the shared core through:

  * ``rtl/Pix2PgpAsicPkg.vhd``  — ASIC-specific constants
    (``NUM_OF_COL_MANAGERS_C``, ``NUM_OF_SERIALIZERS_C``,
    ``ASIC_DATABUS_DWIDTH_C``, header/metadata bit-mapping)
  * ``rtl/Pix2Pgp<AsicName>Top.vhd`` — ASIC-specific top wrapper
  * ``tb/`` — behavioral models of the ASIC's pixel and per-column
    User-Logic, plus a standalone RTL testbench

* ``firmware/fpga/rtl/``        — the FPGA receiver, common across ASICs:

  * ``Pix2PgpAsicStreamRx.vhd`` — top of the FPGA receiver for one ASIC
  * ``Pix2PgpLaneRxWrapper.vhd`` / ``Pix2PgpLaneRx.vhd`` — per-lane
    receiver + integrity checker
  * ``Pix2PgpLaneMon.vhd``      — per-lane statistics for calibration /
    monitoring
  * ``Pix2PgpLaneSupervisor.vhd`` — cross-lane orchestration
  * ``Pix2PgpLaneMerger.vhd``   — final frame assembler
  * ``Pix2PgpTriggerManager.vhd`` — SRO/DAQ trigger buffering
  * ``Pix2PgpAxiLiteManager.vhd`` — AXI-Lite register interface
