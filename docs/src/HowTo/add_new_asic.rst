.. _how_to_add_new_asic:

===============================
How to Add Support for a New ASIC
===============================

Pix2PGP is designed to be adapted to a new detection ASIC through
**parameterization only** — no changes to the shared RTL core
(``gateware/shared/rtl``) or the FPGA receiver
(``firmware/fpga/rtl``) are required.

Throughout this guide, ``NewAsic`` refers to the ASIC being added. Rename
it accordingly in every step.

Pick a Template
===============

Two event-closure families are supported:

* **Self-Closure** — the ASIC User Logic determines when to issue ``EoF``
  internally (no external ERO signal). Template: **SparkPixS**
* **External-Trigger-Closure (ERO)** — an external End-Of-Readout trigger
  closes the event. Template: **SparkPixT**

Copy the closest template as the starting point for ``NewAsic``:

.. code-block:: bash

   $ cd pix2pgp/gateware/asics
   $ cp -r SparkPixT NewAsic          # or SparkPixS

Edit the RTL Package
====================

Inside ``NewAsic/rtl/Pix2PgpAsicPkg.vhd``, adjust the following constants:

* ``NUM_OF_COL_MANAGERS_C``  — how many columns each Pix2PGP instance serves
* ``NUM_OF_SERIALIZERS_C``   — how many serializers / Pix2PGP instances /
  lanes exist on the whole ASIC
* ``ASIC_DATABUS_DWIDTH_C``  — the width of the data bus driven **into**
  Pix2PGP (see the widths supported below)
* ``HEADER_WIDTH_MULT_C``    — if the doubled internal bus width
  (``PIX2PGP_DATABUS_DWIDTH_C = 2 * ASIC_DATABUS_DWIDTH_C``) is not large
  enough to fit the header bitfield, scale it up here. See
  :ref:`architecture_frame_format`
* The **header bitfield** and **column metadata bitfield** definitions —
  the layout of Pause / OverOcc / Pause-Error / Timeout / Column Hitmask /
  Trigger Counter fields inside the frame header

Supported ``ASIC_DATABUS_DWIDTH_C`` values: **4, 8, 12, 16, 20, 24, 28,
32 bits**. Using widths below 16 bits requires padding — bandwidth is
wasted. Widths above 32 bits should be split across multiple cycles.

Edit the RTL Top
================

Rename and edit ``NewAsic/rtl/Pix2PgpNewAsicTop.vhd``:

.. code-block:: bash

   $ cd NewAsic/rtl
   $ mv Pix2PgpSparkPixTTop.vhd Pix2PgpNewAsicTop.vhd

Update:

* Change the VHDL entity name to ``Pix2PgpNewAsicTop``
* Set the width of the ``sof``, ``eof``, ``overOcc`` (etc.) signals to
  ``NUM_OF_COL_MANAGERS_C``
* Set the number of ``dinXX`` ports to match ``NUM_OF_COL_MANAGERS_C``
* Set the width of each ``dinXX`` port to ``ASIC_DATABUS_DWIDTH_C``

.. note::

   The top-level intentionally uses **simple std_logic / std_logic_vector**
   ports rather than complex VHDL types. This is because the top-level is
   often instantiated within a SystemVerilog / Verilog context (many
   ASIC-integration flows still cannot handle VHDL records across
   language boundaries).

Edit the Testbench Files
========================

.. code-block:: bash

   $ cd ../tb
   $ mv DummySparkPixTPixel.vhd DummyNewAsicPixel.vhd
   $ mv Pix2PgpSparkPixTFpgaRxTop.vhd Pix2PgpNewAsicFpgaRxTop.vhd
   $ mv Pix2PgpSparkPixTTopTb.vhd Pix2PgpNewAsicTopTb.vhd

* ``DummyNewAsicPixel.vhd`` — behavioral model of a single pixel of the
  new ASIC. Adjust the pixel model's timing (delay between ``wrEn``
  strobes, delay between ``SRO`` assertion and the first ``wrEn``) to
  match the intended in-silicon behavior. The ``hitLen`` port is set from
  the top-level testbench and controls how many hits each pixel injects
  per event
* ``Pix2PgpNewAsicFpgaRxTop.vhd`` — wrapper for the FPGA receiver logic.
  Expand or collapse the number of input data ports to match
  ``NUM_OF_SERIALIZERS_C``
* ``Pix2PgpNewAsicTopTb.vhd`` — full behavioral testbench. Update all
  entity and instance names; adjust bus widths as needed. The testbench
  instantiates every lane of the ASIC and routes them into
  ``Pix2PgpNewAsicFpgaRxTop``

  * Per-column hit patterns are set via lines like
    ``hitLen(0)(3) <= toSlv(3, hitLen(0)(0)'length);`` — three hits for a
    pixel in column 3 of lane 0
  * For random stimuli, use the helper script:

    .. code-block:: bash

       $ python software/scripts/hitsToVhd.py \
            --numOfLanes=4 --numOfCols=40 \
            --minRange=0 --maxRange=4 \
            --laneEnable=1,1,1,1

Quick Syntax Check
==================

From ``firmware/ghdl``:

.. code-block:: bash

   $ make build ASIC=NewAsic

If the command exits without errors, the VHDL is well-formed.

Create a VCS Simulation Target
==============================

.. code-block:: bash

   $ cd pix2pgp/firmware/targets
   $ cp -r Pix2PgpSparkPixTEmu Pix2PgpNewAsicEmu

Update:

* ``hdl/`` — rename ``Pix2PgpEmuSparkPixT.vhd`` /
  ``Pix2PgpEmuSparkPixT.xdc`` to ``Pix2PgpEmuNewAsic.*`` and edit entity
  names inside. These are dummy files not actually used by the testbench
* ``tb/`` — rename ``Pix2PgpSparkPixTEmuTb.vhd`` to
  ``Pix2PgpNewAsicEmuTb.vhd``; update entity names inside. In particular,
  change ``U_Uut : entity pix2pgp.Pix2PgpSparkPixTTopTb`` to
  ``U_Uut : entity pix2pgp.Pix2PgpNewAsicTopTb``
* ``ruckus.tcl`` — change:

  .. code-block:: tcl

     loadRuckusTcl $::DIR_PATH/../../../gateware/asics/SparkPixT

  to:

  .. code-block:: tcl

     loadRuckusTcl $::DIR_PATH/../../../gateware/asics/NewAsic

  and

  .. code-block:: tcl

     set_property top {Pix2PgpSparkPixTEmuTb} [get_filesets sim_1]

  to:

  .. code-block:: tcl

     set_property top {Pix2PgpNewAsicEmuTb} [get_filesets sim_1]

Run the VCS testbench following :ref:`how_to_vcs_simulation`, substituting
``NewAsic`` for ``SparkPixS``.

Extend the Python Decoder
=========================

Once the VCS run produces a data dump, extend the Python decoder to parse
it. Four files must be edited under ``firmware/python/pix2pgp/``:

``_AsicParameters.py``
----------------------

Add ``NewAsic`` to ``asicTypeDict`` and ``asicParams``, then add a
parameter class:

.. code-block:: python

   asicTypeDict = {
       1: "SparkPixS",
       2: "SparkPixT",
       3: "NewAsic",
   }

   asicParams = {
       'SparkPixS': SparkPixSParameters,
       'SparkPixT': SparkPixTParameters,
       'NewAsic'  : NewAsicParameters,
   }

   class NewAsicParameters(AsicParameterBase):
       @property
       def asicTypeId(self):
           for key, value in AsicParameterBase.asicTypeDict.items():
               if value == "NewAsic":
                   return key
           raise ValueError("ASIC type not found in asicTypeDict!")

       def asicParamExtract(self):
           param_dict = {
               'asicTypeId' : self.asicTypeId,
               'asicType'   : AsicParameterBase.asicTypeDict[self.asicTypeId],
               'numOfLanes' : 4,     # NUM_OF_SERIALIZERS_C
               'numOfCols'  : 40,    # NUM_OF_COL_MANAGERS_C
               'wordLen'    : 10,    # PIX2PGP_DATABUS_DWIDTH_C in bytes
           }
           return param_dict

.. note::

   The ``asicTypeId`` value **must** equal the ``ASIC_TYPE_C`` constant
   set in ``NewAsicPkg.vhd``. ``wordLen`` is expressed in bytes (the VHDL
   constant is in bits).

``_Pix2PgpHeaderFormat.py``
--------------------------

Register a ``NewAsicHeaderFormat`` class and decode the header bit-mapping
in accordance with the header bitfield in ``Pix2PgpAsicPkg.vhd``. The
upper bit of the header must be at position ``(wordLen * 8) - 1``; the
Column Hitmask width must be ``NUM_OF_COL_MANAGERS_C`` bits.

``_Pix2PgpColMetadataFormat.py``
--------------------------------

Register a ``NewAsicColMetadataFormat`` class and decode the column
metadata bit-mapping according to the corresponding fields in
``Pix2PgpAsicPkg.vhd``.

``_Pix2PgpSparseDataFormat.py``
-------------------------------

Register a ``NewAsicDataFormat`` class and decode the individual hit data
words according to the ASIC's sparse-data layout (ADC + row, ToA + ToT +
row, etc.). Update both ``dataDecoder`` and ``dataPrinter``.

Housekeeping
============

#. Update the top-level ``README.md`` and the *Supported ASICs* list in
   this documentation (``docs/src/introduction.rst``)
#. Run benchmarking for ``NewAsic`` (see :ref:`how_to_run_benchmarking`)
#. Update the Pix2PGP Confluence page
