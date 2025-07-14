# Benchmarking
Follow this guide to perform available bandwidth measurements for your ASIC design.

## measurements.py
This is the file that is being used by `plot.py` to generate the plots and the tables. One needs to populate `hitArray` defined in `plot.py` in order to perform the bandwidth measurements. Notes about two arrays:

* The `occArray` lists all occupancy percentages to-be tested.
* The `hitArray` lists the amount of hits on a per-column basis given the occupancy percentages of `occArray`
    * Depending on the amount of *rows* each column of your ASIC has, the amount of hits changes. For example, if an ASIC has `224` rows, an occupancy of `1%` corresponds to: `224*0.01 = 2.24` hits; therefore, that `hitArray` position will have a value of `2`.
    * One can run the `getHitArray.py` script to get the `hitArray` list and paste it back to `measurements.py`. Adjust the `--rows` number accordingly

Each ASIC should have an associated file under `asics/` (e.g. `asics/sparkPixS.py`) that has the same structure as `measurements.py`. Use that file to keep a record of the measurements, and copy-paste the `hitArray, colBusy, superBusy` of that file into `measurements.py` so that `plot.py` can produce the plots.

## VHDL Testbench file; Updating the colBusy/superBusy lists in the associated file under `asics/`
After populating `hitArray` given the amount of rows of the ASIC-under-evaluation, one has to go to the stimuli section of the top-level VHDL testbench, and find the following snippet:

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

1. Change `hitLen(ser)(col) <= toSlv(0, hitLen(ser)(col)'length);` to `hitLen(ser)(col) <= toSlv(hitArray[i], hitLen(ser)(col)'length);` where `hitArray[i]` is the single `hitArray` value of the efficiency percentage you wish to test
2. Comment-out *all* following stimuli of the process, (from `-- regular stimuli begin` all the way down to `-- regular stimuli end`; do not edit whatever is below that part)
  1. The goal is to have only one trigger with the required amount of hits, in order to perform the measurement
3. Include the two commented-out processes at the end of the testbench. These are: `MeasureColBusyProc` and `MeasureSuperBusyProc`; they are commented-out by default 
4. Please note the `pgpClk` frequency. This should be defined in the testbench (in `CLK_PERIOD_PGP_C`). That is the frequency that the ASIC pix2pgp logic runs on
5. Run the testbench, preferrably via VCS. You should be getting continuous printouts in the VCS (or whatever tool is used) console in the form of e.g. `[INFO]: SuperBusy: superBusyCnt = 14342`. After all the data have been transmitted out of the ASIC behavioral model, the printouts should stop. Copy the last counter values for `colBusyCnt` and `superBusyCnt` that were printed-out, and paste them to the corresponding array positions of `colBusy` and `superBusy` located in `measurements.py`
6. Run the above for all occupancy cases and populate both `colBusy` and `superBusy` lists with the corresponding values for all occupancy cases

## plot.py
Run `plot.py` under `software/scripts/benchmarking`:

`$ python plot.py --verbose --pgpClkPeriod=5.384 --matrixClkPeriod=10.768 --cols=24 --asicType=SparkPixS`

Change `--pgpClkPeriod` accordingly, if the `CLK_PERIOD_PGP_C` value is different than the default value of `5.384 ns` used in the script. Change `--cols` to the amount of columns each pix2pgp instance serves. The `--asicType`, `--matrixClkPeriod` values only affect the plot title.
