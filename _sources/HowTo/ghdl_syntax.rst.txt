.. _how_to_ghdl_syntax:

===========================================
How to Perform VHDL Syntax Checks with GHDL
===========================================

Pix2PGP ships with a GHDL-based flow under ``ghdl/`` that provides fast
syntax checking for the entire codebase (shared RTL + selected ASIC + FPGA
receiver).

#. Setup GHDL (refer to :ref:`setup_ghdl`)

#. From the ``ghdl`` directory, run:

   .. code-block:: bash

      $ cd pix2pgp/ghdl
      $ make build ASIC=SparkPixS

   The ``ASIC`` argument selects the ASIC variant to include in the check.
   Supported values as of ``v2.7.8``: ``SparkPixS``, ``SparkPixSv2``,
   ``SparkPixT``, ``Thriglav``.

#. If the command exits without errors, all VHDL source files parse
   correctly under GHDL-LLVM. The build directory (``build/``) contains
   the analyzed units and a list of every file that was compiled

.. note::

   This flow is **only** a syntax check. It does not exercise the design.
   For behavioral simulation with GHDL, see :ref:`how_to_ghdl_simulation`.
   For proper simulation coverage, use the VCS flow (see
   :ref:`how_to_vcs_simulation`).
