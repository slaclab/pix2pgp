.. _how_to_import_sources:

===========================================
How to Import Pix2PGP Sources in Your Project
===========================================

Pix2PGP is normally consumed as a git submodule of a larger project. First,
clone your parent project and add Pix2PGP as a submodule:

.. code-block:: bash

   $ git submodule add https://github.com/slaclab/pix2pgp.git submodules/pix2pgp
   $ git submodule update --init --recursive submodules/pix2pgp

Automatic Import via Ruckus
============================

Cadence Genus
-------------

To pull the ASIC RTL into Cadence Genus, invoke the per-ASIC ``ruckus.tcl``
from a TCL script of your own. Example for SparkPix-S:

.. code-block:: tcl

   # Load RUCKUS environment and library
   source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

   # Load surf source code
   loadRuckusTcl $::env(TOP_DIR)/submodules/surf

   # Load SparkPix-S source code
   loadRuckusTcl $::env(TOP_DIR)/submodules/pix2pgp/gateware/asics/SparkPixS

   # Analyze source code loaded into ruckus for Cadence Genus
   AnalyzeSrcFileLists

Synopsys DC / Fusion Compiler
-----------------------------

.. code-block:: tcl

   # Load RUCKUS environment and library
   source $::env(RUCKUS_QUIET_FLAG) $::env(RUCKUS_PROC_TCL)

   # Load the surf library
   loadRuckusTcl "$::env(TOP_DIR)/submodules/surf"
   AnalyzeSrcFileLists -vhdlLib "surf"

   # Load ruckus library (ruckus.BuildInfoPkg.vhd only)
   GenBuildString $::env(SYN_DIR)
   AnalyzeSrcFileLists -vhdlLib "ruckus"

   # Load SparkPix-S source code
   loadRuckusTcl $::env(TOP_DIR)/submodules/pix2pgp/gateware/asics/SparkPixS
   AnalyzeSrcFileLists -vhdlLib "pix2pgp" -vhdlTop $::env(PROJECT)

Manual Import
=============

If you do not use ruckus, run the GHDL Makefile in list-only mode to
print out the full set of source files needed for your ASIC. From the
top of pix2pgp:

.. code-block:: bash

   $ cd firmware/ghdl
   $ make ASIC=SparkPixS build

Follow the warning messages printed on the terminal:

* Replace ``surfFifo/`` with ``synopsysFifo/`` if you are using a
  proprietary simulator or synthesis tool
* For **ASIC + FPGA behavioral simulation**, use every listed file
* For **ASIC RTL synthesis only**, omit:

  * ``pix2pgp-fpga`` (the FPGA receiver)
  * ``pix2pgp-tb`` (testbench files)
  * ``surf-fifo`` (use ``synopsysFifo/`` instead)
