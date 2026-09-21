.. _how_to_ghdl_simulation:

===============================
How to Simulate Using GHDL
===============================

The GHDL flow supports lightweight behavioral simulation of the top-level
testbench for a selected ASIC.

#. Setup GHDL (refer to :ref:`setup_ghdl`)

#. From the ``ghdl`` directory, run:

   .. code-block:: bash

      $ cd pix2pgp/ghdl
      $ make tb ASIC=SparkPixS GHDL_STOP_TIME=50us

   * ``ASIC``           — the ASIC variant to simulate
   * ``GHDL_STOP_TIME`` — how long to run the simulator (default: 10 us)

#. The testbench that is elaborated is ``Pix2Pgp<Asic>TopTb`` from
   ``gateware/asics/<Asic>/tb/``, which drives a behavioral model of the
   ASIC pixel + digitizer combined with a synthesizable FPGA receiver
   instance. Waveform output (VCD/GHW) can be captured with the standard
   GHDL flags — see ``firmware/submodules/ruckus/system_ghdl.mk`` for the
   available make targets

.. note::

   GHDL-based simulation is intended for quick sanity checks and small
   testbench iterations. Full-scale behavioral verification (all-hits,
   walking-one, spike-occupancy, pauseError-threshold, etc.) is done
   with VCS. See :ref:`how_to_vcs_simulation`.
