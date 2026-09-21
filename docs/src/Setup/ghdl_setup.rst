.. _setup_ghdl:

============================
GHDL Setup
============================

The Pix2PGP repository ships with a GHDL-based flow under ``ghdl/`` that
supports:

* **Quick VHDL syntax checking** across the entire Pix2PGP codebase (shared
  RTL + selected ASIC + FPGA receiver)
* **Behavioral simulation** using GHDL-LLVM

Installation
------------

Install GHDL with the LLVM backend. On Ubuntu-like systems this can be
done through the distribution package manager, or by building from source
following the instructions at:

   https://ghdl.github.io/ghdl/

The default simulator command used in ``ghdl/Makefile`` is:

.. code-block:: makefile

   export GHDL_CMD = ghdl-llvm

If your GHDL install uses a different binary name (e.g. ``ghdl-mcode``),
either override this variable when invoking ``make``, or edit the ``Makefile``.

Verifying the Install
---------------------

Once GHDL is installed, verify the flow by running a quick syntax check on
one of the supported ASICs:

.. code-block:: bash

   $ cd pix2pgp/ghdl
   $ make build ASIC=SparkPixS

See :ref:`how_to_ghdl_syntax` and :ref:`how_to_ghdl_simulation` for details.

.. note::

   GHDL should be used only for lightweight syntax checks
   and short-duration behavioral simulations. Full VCS-based
   (or any proprietary simulator meant for large designs)
   simulation is the recommended flow for anything beyond that.
