.. _setup_dependencies:

====================
External Dependencies
====================

Pix2PGP depends on the following external components; these are pulled in
as git submodules under ``firmware/submodules``:

* `SURF <https://github.com/slaclab/surf>`_ — SLAC Ultimate RTL Framework.
  Provides the standard building blocks such as AXI-Stream FIFOs, PGP4
  transceivers, clock-domain-crossing primitives, and the RTL utility
  packages used throughout Pix2PGP
* `Ruckus <https://github.com/slaclab/ruckus>`_ — the SLAC firmware build
  framework used by every VCS/Vivado target in ``firmware/targets``, and
  by the GHDL flow in ``ghdl/``

The Python data decoding suite requires:

* Python 3.7 or newer
* ``numpy``
* ``click``
* ``pyrogue`` (optional; only required if the user wishes to use
  ``Pix2PgpSparseProcessor`` as a rogue stream processor)

For the VCS behavioral simulation flow, the following tools are required:

* Xilinx Vivado (v2025.2 known-good as of ``v2.5.2``)
* Synopsys VCS (X-2025.06 known-good as of ``v2.5.2``)

For the GHDL flow, GHDL-LLVM is used by default. Any recent GHDL install
(with the LLVM backend) will suffice. One should change the associated ``Makefile``
accordingly if they want to use a different GHDL executable.
