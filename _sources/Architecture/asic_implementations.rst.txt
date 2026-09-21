.. _architecture_asic_implementations:

===================
ASIC Implementations
===================

At the time of writing, Pix2PGP is integrated into four ASICs. Every
port was performed **solely** by editing the per-ASIC package file
(``Pix2PgpAsicPkg.vhd``), the ASIC top-level VHDL wrapper, and the
Python decoder parameter classes — no changes to the shared RTL core
or the FPGA receiver were needed. See :ref:`how_to_add_new_asic` for
the step-by-step porting procedure.

The structural parameters below are read directly from the per-ASIC
``Pix2PgpAsicPkg.vhd`` files in the repository. For measured trigger
rates, latencies and bandwidth as a function of occupancy, run the
benchmarking suite against the target's VCS testbench — see
:ref:`how_to_run_benchmarking`.

.. list-table:: Structural parameters of Pix2PGP-bearing ASICs
   :header-rows: 1
   :widths: 30 15 15 15 15

   * - Parameter
     - SparkPix-S
     - SparkPix-T
     - Thriglav
     - SparkPix-Sv2
   * - Technology
     - 130 nm
     - 130 nm
     - 28 nm
     - 130 nm
   * - Matrix Pixel Count
     - 119808
     - 32256
     - 10000
     - TBD
   * - Digital Core Count (lanes)
     - 8
     - 8
     - 2
     - TBD
   * - Column Managers / Core
     - 24
     - 24
     - 50
     - TBD
   * - ``ASIC_DATABUS_DWIDTH_C``
     - 20-bit
     - 32-bit
     - 32-bit
     - TBD
   * - Event closure
     - Self (EoF)
     - External (ERO)
     - External (ERO)
     - TBD
   * - Pix2PGP Core Clock
     - ~186 MHz
     - ~186 MHz
     - ~186 MHz
     - ~186 MHz
   * - User Logic Clock
     - ~140 MHz
     - ~40 MHz
     - ~20 MHz
     - TBD

Two families of event closure are supported:

* **Self-closure** — the ASIC User Logic determines when to issue the
  ``EoF`` internally. Template: SparkPix-S
* **External-trigger-closure (ERO)** — an End-Of-Readout trigger
  external to the ASIC closes the event. Template: SparkPix-T

.. _architecture_asic_impl_sparkpix_s:

SparkPix-S
==========

SparkPix-S is a sparse-readout X-Ray detector.

* Pixel matrix: 312 rows × 384 columns, laid out as 312 × 192
  **double-columns** (adjacent columns share resources). 50 µm pitch,
  total 119808 pixels
* Each pixel collects charge, digitized by a 10-bit ADC
* Each double-column shares an analog token circuit and a 10-bit ADC.
  The digital core sees 192 / 8 = 24 double-columns per Pix2PGP
  instance
* 8 Pix2PGP cores per ASIC, each with an integrated PGP4 encoder and
  a 32-bit serializer
* Data word per hit: 20-bit (10-bit ADC value + 10-bit row address)
* Internal Pix2PGP data-bus width: 40-bit

Readout Procedure
-----------------

1. External trigger (``SRO``) arrives
2. The User Logic asserts ``SoF`` and injects a **token** at the
   bottom of the double-column. A **tokFb** (token feedback) signal
   goes to its active state as the token enters the matrix
3. The token walks up through the rows:

   * If the pixel has no hit, the token passes to the next row
   * If the pixel has a hit, the token freezes and the analog side
     issues a request (``req``) to the ADC. After conversion, the ADC
     issues ``ack``, the token is released, and the User Logic writes
     a 20-bit data word to Pix2PGP via ``wrEn``
     (10-bit ADC value + 10-bit row address)

4. Once the token exits the matrix, ``tokFb`` transitions back. The
   User Logic issues ``EoF`` to close the Pix2PGP event

Over-Occupancy is asserted (as an ``EoF`` + ``SoF``) if a new ``SRO``
arrives while the token has not fully propagated.

Sources
-------

* Package: ``gateware/asics/SparkPixS/rtl/Pix2PgpAsicPkg.vhd``
* Top:     ``gateware/asics/SparkPixS/rtl/Pix2PgpSparkPixSTop.vhd``
* Model:   ``gateware/asics/SparkPixS/tb/SparkPixSColumnModel.vhd``
* TB:      ``gateware/asics/SparkPixS/tb/Pix2PgpSparkPixSTopTb.vhd``
* VCS TB target: ``firmware/targets/Pix2PgpSparkPixSEmu``

.. _architecture_asic_impl_timing:

Timing Detectors: SparkPix-T and Thriglav
=========================================

SparkPix-T and Thriglav are timing detector ASICs — Time-to-Digital
Converters (TDCs). Both measure Time-Over-Threshold (ToT) as an
energy indicator and Time-of-Arrival (ToA) with picosecond-level
resolution.

Unlike SparkPix-S, these ASICs **do not use a token-injecting**
readout. Instead, on ``SRO`` reception, each pixel of a column is
granted access to a shared bus tied to the column's digital converter
and Pix2PGP User Logic. When a pixel records a hit, the measurement
is converted and encoded into a 32-bit word (16-bit ToA + 8-bit ToT
+ 8-bit row address for SparkPix-T; 11-bit ToA + 8-bit ToT + 8-bit
row address + reserved bits for Thriglav) and forwarded to Pix2PGP.

The event does **not** close on token exit — it stays open
indefinitely until an **End-Of-Readout (ERO)** trigger external to
the ASIC arrives. This defines an *exposure window* within which
hits can be recorded. On ``ERO``, the User Logic issues ``EoF`` to
Pix2PGP and resets the pixel logic.

Over-Occupancy semantics differ from SparkPix-S: for timing
detectors, Over-Occupancy only **closes** the current event; a
subsequent conventional ``SRO`` opens the next one.

**Column Supervisor Pause handling** is also different for ASICs
featuring ERO. Rather than waiting for every Status FIFO to be
non-empty before starting a Pause sequence, the Supervisor enters a
short configurable **pause-timeout** on the first Pause, then reads
out only the paused columns.

**Timeout** watchdog is disabled for ASICs featuring ERO, since
event closure is externally-driven.

SparkPix-T
----------

* 168 rows × 192 columns = 32256 pixels
* 24 columns per Pix2PGP instance, 8 instances per ASIC
* Data word: 32-bit (16-bit ToA + 8-bit ToT + 8-bit row address)
* User Logic clock: ~40 MHz
* Sources: ``gateware/asics/SparkPixT/``,
  ``firmware/targets/Pix2PgpSparkPixTEmu``

Thriglav
--------

* 100 rows × 100 columns = 10000 pixels
* 50 columns per Pix2PGP instance, 2 instances per ASIC
* Data word: 32-bit (11-bit ToA + 8-bit ToT + 8-bit row address +
  reserved bits)
* User Logic clock: ~20 MHz
* Fabricated in 28 nm
* Sources: ``gateware/asics/Thriglav/``,
  ``firmware/targets/Pix2PgpThriglavEmu``

SparkPix-Sv2
============

Second-generation SparkPix-S. Structural parameters live in
``gateware/asics/SparkPixSv2/rtl/Pix2PgpAsicPkg.vhd``. VCS TB target:
``firmware/targets/Pix2PgpSparkPixSv2Emu``.
