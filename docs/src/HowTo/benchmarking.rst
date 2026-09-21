.. _how_to_run_benchmarking:

=========================================
How to Benchmark Throughput and Latency
=========================================

Pix2PGP includes a benchmarking suite under ``software/scripts/benchmarking``
that measures the maximum trigger rate an ASIC's Pix2PGP implementation can
sustain as a function of hit occupancy, and the total time it takes for a
consolidated frame to be transmitted by the FPGA receiver (measured from
the ``SRO`` trigger).

The suite is driven by a per-ASIC JSON file (``asics/<AsicName>.json``) and
a top-level VHDL testbench with the ``BENCHMARKING_G`` generic set to
``true``.

JSON File Format
================

Each entry in ``asics/<AsicName>.json`` has the following structure:

.. code-block:: json

   {
     "occ": 80.0,
     "colHits": 512,
     "allHits": 12288,
     "colBusy": 25367,
     "superBusy": 11459,
     "totalLatency": 25796
   }

Field meanings:

* ``occ``          — occupancy percentage
* ``colHits``      — hits per column at this occupancy (populated by
  ``benchmarking.py``)
* ``allHits``      — total hits per lane (populated by ``benchmarking.py``)
* ``colBusy``      — clock ticks the Column Manager is busy for
  (measured by the testbench)
* ``superBusy``    — clock ticks the Column Supervisor is busy for
  (measured by the testbench)
* ``totalLatency`` — clock ticks between ``SRO`` and the ``tLast`` of the
  final FPGA-side AXI frame (measured by the testbench)

Clock-tick values are measured against the PGP clock — the period must be
provided as a command-line argument when producing plots (default:
5.384 ns).

Step 1 — Populate colHits and allHits
=====================================

From ``software/scripts/benchmarking``:

.. code-block:: bash

   $ python benchmarking.py --getHitArray --updateJson \
                            --cols=24 --rows=640 \
                            --asicType=SparkPixS

* ``--cols``     — columns per Pix2PGP lane (``NUM_OF_COL_MANAGERS_C``)
* ``--rows``     — total rows per column
* ``--asicType`` — ASIC name (must match ``asics/<AsicName>.json``)

The script prints two arrays:

* ``_colHitArray`` — the number of hits per column corresponding to each
  ``occ`` entry in the JSON. E.g. for 224 rows and 1 % occupancy:
  ``224 * 0.01 = 2.24`` → the entry becomes ``2``
* ``_allHitArray`` — total hits across the entire lane. This is stored in
  the JSON as metadata and shown in the resulting plot

Step 2 — Run the VHDL Testbench
===============================

In ``firmware/targets/Pix2Pgp<Asic>Emu/tb/Pix2Pgp<Asic>EmuTb.vhd``:

#. Set ``BENCHMARKING_G = true`` (change ``<Asic>`` accordingly)
#. Locate the ``colHitsArray`` definition at the top-level testbench.
   Its entries must match the ``colHits`` values in the JSON
#. Note ``CLK_PERIOD_PGP_C`` — the Pix2PGP core clock period
#. Note ``CLK_PERIOD_SPARSE_C`` — the User Logic / matrix clock period
#. Optionally, first run with ``BENCHMARKING_G = false`` and inspect the
   timing between ``sof``/``eof``/``wrEn`` strobes. Adjust the
   ``U_DummyPixel`` model if the simulated behavior does not match the
   in-silicon reality
#. If the frames grow very large at high occupancy, increase
   ``AXIS_FIFO_ADDR_WIDTH_G`` in the FPGA receiver logic
   (``Pix2PgpAsicStreamRx``)
#. Run the testbench (VCS recommended). Watch for messages such as::

      [INFO]: occ = 1.500000%  superBusyCnt = 253

   After the sweep, a summary of ``colBusyCnt``, ``superBusyCnt``, and
   ``totalLatencyCnt`` is printed. Copy the last counter values into the
   matching positions of ``asics/<AsicName>.json``

Step 3 — Produce Plots and Tables
=================================

.. code-block:: bash

   $ python benchmarking.py --verbose \
                            --pgpClkPeriod=5.384 \
                            --matrixClkPeriod=10.768 \
                            --cols=24 --rows=640 \
                            --asicType=SparkPixS

* ``--pgpClkPeriod``    — PGP clock period in ns (default 5.384). Must
  match ``CLK_PERIOD_PGP_C`` in the testbench
* ``--matrixClkPeriod`` — matrix / User Logic clock period. Only affects
  the plot title
* ``--cols`` / ``--rows`` / ``--asicType`` — same as Step 1

Outputs
-------

* Occupancy-vs-max-trigger-rate plot
* A tabular Markdown file (``table.md`` under
  ``software/scripts/benchmarking/``) summarizing the same numbers

For a full comparison of measured performance across every deployed ASIC,
see :ref:`architecture_asic_implementations`.
