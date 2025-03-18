# Pix2Pgp

Pix2PGP is a generic readout core designed to support Detector/Front-End ASICs that feature a sparsified readout scheme.

For more info:
[Google Doc Link](https://docs.google.com/document/d/1JWoombpoBZBulYuCbVD-M0LTDDdCfMX4FJ9Qwumctxg/edit?usp=sharing)

Currently, Pix2PGP Suports the following two ASIC variants:

* SparkPix-S
* SparkPix-T

## Important! How-To Import to Your Project
In order to import pix2pgp to your project:

1. Add this repo as a submodule in your project ($ git clone --recurse-submodules ...thisRepo.git)
2. Run `ghdlRun.sh` (run it while in the `ghdl` dir) at least *once*
    1. To import SparkPix-S, run `$ bash ghdlRun.sh Pix2PgpSparkPixSTopTb`
    2. To import SparkPix-T, run `$ bash ghdlRun.sh Pix2PgpSparkPixTTopTb`
3. The command creates symbolic links the surf libraries and the VHDL package file (which is ASIC-specific) into `core/rtl`
4. In your RTL analysis tool, parse everything inside the `core/rtl` director, including subdirectories
    1. Do *not* link anything else (e.g. the contents of `vault`), as this might cause naming conflicts

### How to simulate using GHDL
In order to simulate via GHDL, run, e.g. `$ bash ghdlRun.sh Pix2PgpSparkPixSTopTb 50` to run the testbench for 50us.