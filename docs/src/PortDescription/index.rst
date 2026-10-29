.. _port_description:

====================================
ASIC/FPGA Top-Level Port Description
====================================

This section describes every generic and port of the two top-level
entities a user instantiates:

* :ref:`port_description_asic` — the per-ASIC wrapper
  ``Pix2Pgp<AsicName>Top`` that goes into the ASIC's digital section
  (one instance per Pix2PGP core / lane)
* :ref:`port_description_fpga` — ``Pix2PgpAsicStreamRx``, the FPGA
  receiver that consolidates every lane of one ASIC

For step-by-step integration guides, see
:ref:`how_to_integrate_asic_core` and :ref:`how_to_integrate_fpga_receiver`.

.. toctree::
   :maxdepth: 1
   :caption: Top-Level Port Description:

   asic_top_level
   fpga_top_level
