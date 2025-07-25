# Benchmarking
Follow this guide to perform bandwidth measurements for your ASIC design. The top-level VHDL testbench of an ASIC allows for measurement of the maximum trigger rate that a Pix2Pgp implementation for a specific ASIC can cope with, as a function of the occupancy percentage (i.e. amount of hits per column). It also measures the total time that it takes for the final AXI-Stream frame to be transmitted from the FPGA receiver that aggregates the Pix2Ppg Lane frames, with starting time measured from the Start-Of-Readout trigger.

## Preliminaries: `asics/AsicName.json`
The `asics` directory contains one `.json` file for each ASIC that is supported. Each entry in the `.json` has the following format:

```json
  {
    "occ": 80.0,
    "colHits": 512,
    "allHits": 12288,
    "colBusy": 25367,
    "superBusy": 11459,
    "totalLatency": 25796
  },
```
* `occ`    : Represents the Occupancy percentage
* `colHits`: Represents the number of hits per column; this entry can be populated `benchmarking.py`
* `allHits`: Represents the total number of hits per lane; this entry can be populated `benchmarking.py`
* `colBusy`: Represents the number of clock ticks the columnManager of Pix2Pgp is busy for; this entry is calculated by the behavioral testbench
* `superBusy`: Represents the amount of clock ticks the columnSupervisor of Pix2Pgp is busy for; this entry is calculated by the behavioral testbench
* `totalLatency`: Represents the amount of clock ticks between the `Start-Of-Readout` trigger and the `tLast` signal of the AXI frame sent out by the FPGA Receiver; this entry is calculated by the behavioral testbench

Note that the calculated values are in clock ticks; the period of the said clock is configurable and is mentioned later in this README file.

## Step 1: `colHits` and `allHits` of the corresponding `.json` file

First of all, the `colHits` and `allHits` entries in the `.json` file must be populated by `benchmarking.py`. This can be done, e.g. by running the following command:
```
$ python benchmarking.py --getHitArray --updateJson --cols=24 --rows=640 --asicType=SparkPixS
```

This will edit the `.json` file of `SparkPix-S`, located in `asics` under the name of `SparkPixS.json`. The amount of `cols` per lane needs to be given as an input, as well as the total number of rows. The printouts represent the following:

* The `_colHitArray` lists the amount of hits on a per-column basis given the occupancy percentages of `occ` as listed in the `.json`
  * Depending on the amount of *rows* each column of the ASIC has, the amount of hits changes. For example, if an ASIC has `224` rows, an occupancy of `1%` corresponds to: `224*0.01 = 2.24` hits; therefore, that `_colHitArray` position will have a value of `2`. `_colHitArray` corresponds to `colHits` of the `.json`
* The `_allHitArray` lists the total amount of hits across the entire lane. This is appended as metadata in the `.json` file and then appears in the plot.

## Step 2: VHDL Testbench file

1. Set the `BENCHMARKING_G` generic under the `firmware/targets/Pix2PgpAsicTypeEmu/tb/Pix2PgpAsicTypeEmuTb.vhd` to `true`. Change `AsicType` to the ASIC type/name that you wish to test
2. Locate the definition of the `colHitsArray`. It is defined at the top-level testbench file. The entries of the said array should correspond to the values of `colHits` in the `.json` file of the associated ASIC.
3. Take a note of the `pgpClk` frequency. This should be defined in the testbench (in `CLK_PERIOD_PGP_C`). This is the frequency that the ASIC pix2pgp logic runs on, and this is the period of the clock that `colBusy`, `superBusy`, `totalLatency` are measured against. The said clock period has to be used as an argument input in `benchmarking.py` when producing the benchmarking plots and tables for the given ASIC
4. Take a note of the matrix clock frequency. This should be defined in the testbench (in `CLK_PERIOD_SPARSE_C`). This frequency should correspond to the clocking frequency of the data generation agent; e.g. the ASIC's Matrix clock frequency
5. It is advised to run the testbench first with `BENCHMARKING_G` set to false, and take a note of the time-distance between the frame delimiters (`eof` and `sof`) and between the `wrEn` signals that are issued to `Pix2Pgp`. The timing of all the above should represent an accurate model of the behavior of the actual in-silicon implementation. If needed, locate the `U_DummyPixel` VHDL instance that produces the frame delimiters and the data and adjust it accordingly
6. The generic of the Pix2Pgp FPGA Receiver logic (i.e. `Pix2PgpAsicStreamRx`) that controls each Lane's FIFO depth (`AXIS_FIFO_ADDR_WIDTH_G`) might have to be increased in order to accommodate for large frame sizes
7. Run the testbench, preferably via VCS. You should be getting continuous printouts in the VCS (or whatever tool is used) console in the form of e.g. `"[INFO]: occ = 1.500000% superBusyCnt = 253"`. After all the data have been transmitted out of the ASIC behavioral model, the printouts should stop updating, and the testbench should print-out a summary of all the results for all given occupancy percentages. Copy the last counter values for `colBusyCnt`, `superBusyCnt` and `totalLatencyCnt` that were printed-out, and paste them to the corresponding positions of the `.json` file of the ASIC-under-test

## Step 3: Produce the Plots and the Tables via `benchmarking.py`
Run `benchmarking.py` under `software/scripts/benchmarking`:

`$ python benchmarking.py --verbose --pgpClkPeriod=5.384 --matrixClkPeriod=10.768 --cols=24 --rows=640 --asicType=SparkPixS`

Change `--pgpClkPeriod` accordingly, if the `CLK_PERIOD_PGP_C` value is different than the default value of `5.384 ns` used in the script. Change `--cols` to the amount of columns each pix2pgp instance serves. Same with `--rows`. The `--matrixClkPeriod` value only affects the plot title. The `asicType` argument has to be set in order for the python script to parse in the appropriate `.json` within the `asic/` directory
