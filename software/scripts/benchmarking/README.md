# Benchmarking
Follow this guide to perform bandwidth measurements for your ASIC design.

## Preliminaries: `asics/AsicName.json`
The `asics` directory contains one `.json` file for each ASIC that is supported. Each entry in the `.json` has the following format:

```json
  {
    "occ": 80.0,
    "colHits": 512,
    "allHits": 12288,
    "colBusy": 25394,
    "superBusy": 11491,
    "totalLatency": 100,
  },
```
* `occ`    : Represents the Occupancy percentage
* `colHits`: Represents the number of hits per column; this entry can be populated up by `benchmarking.py`
* `allHits`: Represents the total number of hits per lane; this entry can be populated up by `benchmarking.py`
* `colBusy`: Represents the number of clock ticks the columnManager of Pix2Pgp is busy for; this entry is calculated by the behavioral testbench
* `superBusy`: Represents the amount of clock ticks the columnSupervisor of Pix2Pgp is busy for; this entry is calculated by the behavioral testbench
* `totalLatency`: Represents the amount of clock ticks between the `Start-Of-Readout` trigger and the `tLast` signal of the AXI frame sent out by the FPGA Receiver; this entry is calculated by the behavioral testbench

Note that the calculated values are in clock ticks; the period of the said clock is configurable and is mentioned later in this README file.

## Step 1: `colHits` and `allHits` of the corresponding `.json` file

First of all, the `colHits` and `allHits` must be populated by `benchmarking.py`. This can be done, e.g. by running the following command:
```
$ python benchmarking.py --getHitArray --updateJson --cols=24 --rows=640 --asicType=SparkPixS
```

This will edit the `.json` file of `SparkPix-S`, located in `asics` under the name of `SparkPixS.json`. The amount of `cols` per lane needs to be given as an input, as well as the total number of rows. The printouts represent the following:

* The `_colHitArray` lists the amount of hits on a per-column basis given the occupancy percentages of `occ` as listed in the `.json`
  * Depending on the amount of *rows* each column of the ASIC has, the amount of hits changes. For example, if an ASIC has `224` rows, an occupancy of `1%` corresponds to: `224*0.01 = 2.24` hits; therefore, that `_colHitArray` position will have a value of `2`. `_colHitArray` corresponds to `colHits` of the `.json`
* The `_allHitArray` lists the total amount of hits across the entire lane. This is appended as metadata in the `.json` file and then appears in the plot.

## Step 2: VHDL Testbench file; Updating the colBusy/superBusy lists in the associated file under `asics/`
After populating `colHits`, one has to go to the stimuli section of the top-level VHDL testbench, and find the following snippet:

```VHDL
    -- Wait for the rst to be released before doing anything else
    wait until (rst = not(RST_POLARITY_G));
    for ser in 0 to NUM_OF_SERIALIZERS_C-1 loop
       for col in 0 to NUM_OF_COL_MANAGERS_C-1 loop
         hitLen(ser)(col) <= toSlv(0, hitLen(ser)(col)'length);
       end loop;
    end loop;

    wait for CLK_PERIOD_SPARSE_C*2100; -- extend wait to align pgp protocol
      sro <= '1';
    wait for CLK_PERIOD_SPARSE_C*2;
      sro  <= '0';
```

1. Change `hitLen(ser)(col) <= toSlv(0, hitLen(ser)(col)'length);` to `hitLen(ser)(col) <= toSlv(hitArray[i], hitLen(ser)(col)'length);` where `hitArray[i]` is the single `colHits`/`_colHitArray` value of the efficiency percentage you wish to test
2. Comment-out *all* following stimuli of the process, (from `-- regular stimuli begin` all the way down to `-- regular stimuli end`; do not edit whatever is below that part)
    1. The goal is to have only one trigger with the required amount of hits in order to perform the measurement
3. Include the three commented-out processes at the end of the testbench. These are: `MeasureColBusyProc`, `MeasureSuperBusyProc` and `MeasureTotalLatencyProc`; they are commented-out by default 
4. If the ASIC under-test features an ERO trigger, locate the `U_DummyPixel` VHDL instance that produces the frame delimiters and the data in the testbench top-level, and set the `IGNORE_ERO` generic to `true`
5. Please note the `pgpClk` frequency. This should be defined in the testbench (in `CLK_PERIOD_PGP_C`). This is the frequency that the ASIC pix2pgp logic runs on, and this is the period of the clock that `colBusy`, `superBusy`, `totalLatency` are measured against. The said clock period has to be used as an argument input in `benchmarking.py` when producing the benchmarking plots and tables for the given ASIC
6. Run the testbench, preferably via VCS. You should be getting continuous printouts in the VCS (or whatever tool is used) console in the form of e.g. `[INFO]: SuperBusy: superBusyCnt = 14342`. After all the data have been transmitted out of the ASIC behavioral model, the printouts should stop updating. Copy the last counter values for `colBusyCnt`, `superBusyCnt` and `totalLatencyCnt` that were printed-out, and paste them to the corresponding positions of the `.json` file of the ASIC-under-test
7. Run the above for all occupancy cases

## Step 3: Produce the Plots and the Tables via `benchmarking.py`
Run `benchmarking.py` under `software/scripts/benchmarking`:

`$ python benchmarking.py --verbose --pgpClkPeriod=5.384 --matrixClkPeriod=10.768 --cols=24 --asicType=SparkPixS`

Change `--pgpClkPeriod` accordingly, if the `CLK_PERIOD_PGP_C` value is different than the default value of `5.384 ns` used in the script. Change `--cols` to the amount of columns each pix2pgp instance serves. The `--matrixClkPeriod` value only affect the plot title. The `asicType` argument has to be set in order for the python script to parse in the appropriate `.json` within the `asic/` directory
