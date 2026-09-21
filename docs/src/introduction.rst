.. _introduction:

============
Introduction
============

Pix2PGP is a configurable readout framework for detector front-end ASICs
that operate with a sparse readout scheme. It stitches together three
layers that would otherwise have to be re-implemented for each new ASIC:
the in-ASIC digital core that groups sparse hits into per-trigger event
frames, the FPGA logic that receives frames from every serial link of the
ASIC and merges them into one consolidated frame, and the Python library
that unpacks the aggregated frame for offline analysis.

Application Scope
-----------------

At high trigger rates, transmitting the full pixel matrix on every trigger
is not always practical. A sparse readout scheme instead forwards only the
pixels/channels that recorded a signal above threshold, which drops the
per-trigger bandwidth significantly and allows the detector to operate at
higher repetition rates without a corresponding blow-up in the amount of
data pushed off-chip.

Pix2PGP was written with the LCLS-II readout model in mind: one data frame
per accelerator pulse, per detection device. That constraint drove the
choice to place event building **inside the ASIC** rather than delegating
it to the back-end — the ASIC waits until every data source it manages has
closed the current event, then emits a single AXI-Stream frame for that
trigger [#one-frame-per-trigger]_.

.. [#one-frame-per-trigger] This is the nominal readout case. Under
   back-pressure situations (see :ref:`architecture_flow_control`), the
   ASIC emits multiple AXI-Stream frames for a single trigger — i.e.
   the event data are transmitted in fragments — and the FPGA receiver
   reassembles them before finally transmitting a single AXI-Stream frame
   to the back-end.

Framework Components
--------------------

The framework is comprised of:

* An **ASIC digital core** (VHDL) that receives sparse data words and
  externally-driven event delimiters from a configurable number of data
  sources, buffers them, and assembles the per-trigger AXI-Stream frame
  (or frames, under back-pressure — see the footnote above)
* An **FPGA data aggregation firmware** (VHDL) that takes the frames from
  each of the ASIC's serial links, checks them for integrity, and merges
  them into a single consolidated frame that is forwarded to the back-end
* A **Python decoding library** that turns the aggregated frame into a
  dictionary of hits and per-event metadata, suitable for offline
  analysis or for wrapping into a live rogue stream processor

The AXI-Stream protocol is used throughout for data transport; AXI-Lite is
used for configuring and monitoring the FPGA receiver at runtime. Data
between the ASIC and the FPGA travels over the SLAC-developed PGP4
protocol on a per-link basis, though the framework's event-building layer
is independent of the physical protocol.

System Overview
---------------

Pix2PGP builds on `SURF <https://github.com/slaclab/surf>`_ (the SLAC RTL
building-block library) and integrates with the
`ROGUE <https://github.com/slaclab/rogue>`_ software framework on the
software side.

A typical detector ASIC deploys several Pix2PGP core instances (also referred
to as **lanes**), each responsible for a distinct slice of the pixel
matrix. Each lane implements its own PGP4 transmitter and serial link, so the
ASIC ships multiple parallel streams off-chip. On the FPGA side, one PGP4
receiver per lane feeds the Pix2PGP receiver logic, which reassembles the
per-lane frames from the detector ASIC into a single consolidated
per-trigger frame associated with that event.

Supported ASICs
---------------

At the time of writing, Pix2PGP has been integrated into:

* **SparkPix-S**   — X-Ray detection, 130 nm, 119808 pixels, 8 lanes
* **SparkPix-T**   — timing detector, 130 nm, 32256 pixels, 8 lanes
* **Thriglav**     — timing detector, 28 nm, 10000 pixels, 2 lanes
* **SparkPix-Sv2** — X-Ray detection, second-generation SparkPix-S

See :ref:`architecture_asic_implementations` for a per-ASIC description
and configuration summary.

Repository Layout
-----------------

The pix2pgp repository is structured as follows::

   pix2pgp/
   ├── gateware/            # ASIC-side source code
   │   ├── shared/          #   Reusable RTL core (Column Manager, Supervisor,
   │   │                    #   Arbiter, ASIC Pkg, top-level, watchdog, FIFOs)
   │   └── asics/           #   Per-ASIC top-levels and package files
   │       ├── SparkPixS/
   │       ├── SparkPixSv2/
   │       ├── SparkPixT/
   │       └── Thriglav/
   ├── firmware/            # FPGA receiver + Python decoding
   │   ├── fpga/            #   FPGA receiver RTL (LaneRx, Merger, Supervisor,
   │   │                    #   AxiLite Manager, Trigger Manager)
   │   ├── python/pix2pgp/  #   Python data decoding library
   │   ├── targets/         #   VCS behavioral-simulation targets per ASIC
   │   └── submodules/      #   surf, ruckus
   ├── ghdl/                # GHDL-based syntax check + behavioral simulation
   ├── software/            # Auxiliary scripts (data parser, hits generator,
   │                        #   benchmarking suite)
   └── docs/                # This documentation

See :ref:`architecture_top_level` for a block-level view of the framework.
