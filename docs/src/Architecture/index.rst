.. _architecture:

============
Architecture
============

This section describes the internal architecture of Pix2PGP. It covers the
ASIC-side core (Column Manager / Column Supervisor / Arbiter), the FPGA
receiver (LaneRx / Lane Supervisor / Lane Merger / Trigger Manager), the
data frame format, and per-ASIC parameterization.

.. toctree::
   :maxdepth: 1
   :caption: Architecture:

   top_level
   asic_core
   flow_control
   fpga_receiver
   frame_format
   asic_implementations
