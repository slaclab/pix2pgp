.. pix2pgp documentation master file

======================================
Welcome to pix2pgp's documentation!
======================================

This is currently a work in progress.
New documentation is being added incrementally over time.

**Pix2PGP** is a full-stack, highly-configurable data acquisition framework
designed to support front-end detector Application-Specific Integrated
Circuits (ASICs) that operate on a sparse readout scheme. It provides:

* An **ASIC RTL** core that receives sparse hit data from multiple sources
  and performs event building given externally-driven frame delimiters
* An **FPGA firmware** receiver that aggregates the ASIC-generated data lanes
  into a single consolidated event frame
* A **Python software** decoding suite for parsing the aggregated frames into
  an easily-accessible format

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   introduction
   Setup/index
   Architecture/index
   HowTo/index

Please email cbakalis@slac.stanford.edu if you see any errors or have any
questions about anything in the current documentation.

Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
