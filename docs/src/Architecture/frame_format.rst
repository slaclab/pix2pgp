.. _architecture_frame_format:

===============
Data Frame Format
===============

Pix2PGP defines two nested frame formats:

* :ref:`frame_lane_frame`  — the per-lane frame transmitted by each Pix2PGP
  ASIC core over its PGP4 physical link, and consumed by one ``LaneRx``
  instance in the FPGA receiver
* :ref:`frame_pix2pgp_frame` — the consolidated event frame produced by the
  FPGA receiver by merging every lane's frame together, and transmitted to
  the back-end

.. _frame_lane_frame:

Pix2PGP Lane Frame
==================

Every Pix2PGP ASIC core transmits **one PGP frame per event** for the group
of Columns it serves. Under back-pressure conditions (see
:ref:`flow_pause`), a single trigger may produce more than one such frame:
each Pause fragment is a self-contained Lane Frame with the ``Pause`` bit
set in its header, and the FPGA receiver reassembles the fragments into
one consolidated event.

The Lane Frame is comprised of:

* **Header** (always present)

  * Status flags: lane-wide ``Pause``, ``Over-Occupancy``, ``Pause-Error``,
    ``Timeout``, ``Column FIFO Error``, ``Dummy Header``
  * ``Column Hitmask`` — one bit per Column Manager. If a bit is high,
    that Column recorded at least one hit for this event
  * ``Trigger Counter`` — the event's trigger identifier

* **Column Metadata + Column Data** — repeated per Column with a high bit
  in the Hitmask:

  * Column Metadata word: per-column ``Pause``, ``Over-Occupancy``,
    ``Timeout`` flags; the Column's ``Data-Length Counter`` value; and
    the Column's ``Trigger Counter`` value (should match the header's)
  * ``Data-Length Counter`` data words (i.e. the hits)

The width of each field is application-specific: it depends on
``ASIC_DATABUS_DWIDTH_C`` (defined in each ASIC's ``Pix2PgpAsicPkg.vhd``)
and its associated internal doubled bus width
(``PIX2PGP_DATABUS_DWIDTH_C = ASIC_DATABUS_DWIDTH_C * 2``).

Header Sizing and Scaling
-------------------------

The Header must fit in a single ``PIX2PGP_DATABUS_DWIDTH_C``-wide word. If
the number of Column Managers is large enough that the Column Hitmask +
status flags + Trigger Counter exceed the native internal data-bus width,
the header can be scaled up via the ``HEADER_WIDTH_MULT_C`` constant in
``Pix2PgpAsicPkg.vhd``, which doubles/triples/etc. the header size.

For example, for a core managing 24 Column Managers on a 20-bit data bus
(40-bit internal), the header fits natively: 6-bit flags + 24-bit Hitmask
+ 8-bit Trigger Counter = 38 bits ≤ 40. For a core managing 64 Column
Managers on the same data bus, the header requires at least 78 bits, so
``HEADER_WIDTH_MULT_C = 2`` is set (yielding a doubled 80-bit header).

The **Column Metadata word does not have a scaling factor** — it must fit
in the native ``PIX2PGP_DATABUS_DWIDTH_C``.

Supported Data-Bus Widths
-------------------------

Pix2PGP supports the following ``ASIC_DATABUS_DWIDTH_C`` values:

* 4, 8, 12, 16, 20, 24, 28, 32 bits

It is strongly advised to use 16 bits or more. Padding can be added to the
input if the data width is smaller than 16 bits, at the expense of
bandwidth. If wider than 32 bits, the data must be driven in multiple
cycles at one of the supported widths.

.. _frame_pix2pgp_frame:

Consolidated Pix2PGP Frame
==========================

Upon receiving valid frames from every enabled lane for a given trigger,
the FPGA receiver's Lane Merger produces the consolidated Pix2PGP Frame.
It consists of:

* **Preamble** (fixed 128-bit)

  * 48-bit identifier — ``'PixPGP'`` in ASCII =
    ``0x00706978706770``
  * 16-bit ``Frame Type ID`` — 0 = Nominal, 1 = Drop-Frame, ... to-be-extended
  * 16-bit ``ASIC Type`` — 1 = SparkPix-S, 2 = SparkPix-T, 3 = Thriglav,
    etc. (0 = Reserved)
  * 16-bit ``ASIC ID`` — for systems hosting multiple ASICs per FPGA
  * 16-bit ``FPGA ID`` — for multi-FPGA DAQ systems
  * 16-bit ``FPGA Trigger Counter`` — should match every lane's Trigger
    Counter

* **Header** (variable, per-lane bitmasks). Each bitmask is ``NUM_OF_
  SERIALIZERS_C`` bits wide (8 for SparkPix-S/T, 2 for Thriglav):

  * ``Lane Decoding Error``, ``Lane Over-Occupancy``, ``Lane Pause``,
    ``Lane Pause-Error``, ``Lane Full``, ``Lane Timeout``, ``Lane Down``
  * ``Lane Valid`` — a frame was received for that lane for that trigger.
    Nominal readout has every bit high. If a lane is in Decoding Error,
    Full, Timed-Out, or Down, its Valid bit is never set

* **Lane-Frame-Length field** — one 16-bit length subfield per lane whose
  ``Lane Valid`` bit was high. The value is the number of data words for
  that lane for that trigger
* **Lane Frames** — the concatenation of every valid lane's frame
* **Trailer** — fixed 48-bit identifier (``'PixPGP'`` in ASCII =
  ``0x00706978706770``)

Drop Frames
-----------

If the receiver drops a frame (e.g. lane down, decoding failure, receiver
overflow), a **drop-frame** is transmitted in place of the actual frame,
carrying a distinct ``Frame Type Type`` code so the back-end can detect the
miss and take corrective action.
