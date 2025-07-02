# How-To Add a New ASIC
Follow this guide to add support for a new ASIC.

Use a previous ASIC as a template. For this purpose, we will use `SparkPix-T` as a template for a new ASIC, called `NewAsic`. The user should alter the name of `NewAsic` accordingly in all steps of this entire process.

It is assumed that `NewAsic` uses an `ERO` trigger to signal event closure (see the documentation link in this repo's top-level `README.md` file). This is the reason why `SparkPix-T` has been picked as its template. If the new ASIC you want to support does not feature an `ERO` trigger, then you should use `SparkPix-S` instead, which generates its event closure internally.

## How-To Add a New ASIC in the RTL Codebase

### Create a New Directory Under `firmware/vault`

Go-To `firmware/vault` and create a new directory for the `NewAsic`: do `$ cp -r sparkPixT newAsic`

1. Under `newAsic/rtl`, do: `$ mv Pix2PgpSparkPixTTop.vhd Pix2PgpNewAsicTop.vhd` and `$ mv SparkPixTPkg.vhd NewAsicPkg.vhd`
    1. Edit `NewAsicPkg.vhd` accordingly. Edit the parameters in the `*Pkg.vhd` file. Usually the parameters that need to be edited are within the first few lines, between the `Tunable parameters begin` and `Tunable parameters end` comments. Some examples of what should be edited are: `NUM_OF_COL_MANAGERS_C` (how many columns does each pix2pgp instance serve?), `NUM_OF_SERIALIZERS_C` (how many serializers/pix2pgp instances/lanes are on the ASIC?), etc.
    2. Edit `Pix2PgpNewAsicTop.vhd` accordingly. Note the lack of use of complex VHDL types (i.e. custom types/arrays) in the top-level interfacing. This is because there needs to be flexibility in terms of where the top-level can be instantiated in; if the top-level VHDL file needs to be instantiated within the context of Verilog/SystemVerilog, there can be no complex types at the top-level VHDL entity definition. For example, one needs to change the width of the `sof, eof, overOcc` etc. signals to have the same width as `NUM_OF_COL_MANAGERS_C`, and the amount of `dinXX` ports to be the same as the `NUM_OF_COL_MANAGERS_C`. Also, the width of the data that are being written into pix2pgp by the Analog part of the ASIC must be the same as the width of each `dinXX` port.
2. Under `newAsic/tb`, do: `$ mv DummySparkPixTPixel.vhd DummyNewAsicPixel.vhd` and `$ mv Pix2PgpSparkPixTTopTb.vhd Pix2PgpNewAsicTopTb.vhd`
    1. Edit `DummyNewAsicPixel.vhd` accordingly. This is a behavioral model of the pixel of the new ASIC and should mimick (to some extent) the behavior of the ASIC. This model is used in the top-level VHDL testbench (`Pix2PgpNewAsicTopTb.vhd`). Note the `hitLen` port. Within the top-levl VHDL testbench, one can edit the value of this dynamically to change how many hits each pixel model injects into pix2pgp.
    2. Edit `Pix2PgpNewAsicTopTb.vhd` accordingly. Change the names of the VHDL entities and widths of the buses depending on the amount of columns each pix2pgp instance serves. Note that the testbench should be instantiating all Lanes of the ASIC (governed by the `NUM_OF_SERIALIZERS_C` parameter) and routing all of them into `Pix2PgpAsicStreamRx` (via `Pgp4Rx` instances), which is the ASIC RX logic instantiated in the FPGA of the in-silicon system.
        1. The testbenches usually include a VHDL process that selects specific columns/pixels and assigns a `hitLen` value on a per-trigger/event basis (e.g., the line `hitLen(0)(3) <= toSlv(3, hitLen(0)(0)'length);` assigns three hits for a pixel in column 3 of lane 0). One can create random hit-lengths by using the `software/scripts/hitsToVhd.py` script (e.g. `$ python hitsToVhd.py --numOfLanes=2 --numOfCols=50 --minRange=0 --maxRange=4 --laneEnable=1,1`) will generate random stimuli for an ASIC with 50 columns-per-pix2pgp instance, and 2-lanes-per-ASIC.

### Create a New Entry In the `firmware/Makefile`

There should be a commented-out snippet at the top of the `Makefile`:

```Makefile
# else ifeq ($(ASIC), Template)
#     ASIC_SOURCED  := 1
#     ASIC_LINK_DIR := $(ROOT_DIR)/vault/Template
#     ASIC_LINK_PKG := $(ASIC_LINK_DIR)/rtl/TemplatePkg.vhd
#     ASIC_LINK_TOP := $(ASIC_LINK_DIR)/rtl/Pix2PgpTemplateTop.vhd
```

Keep that snippet, and copy and paste a new entry above it. For `NewAsic`, it should look like:

```Makefile
else ifeq ($(ASIC), NewAsic)
    ASIC_SOURCED  := 1
    ASIC_LINK_DIR := $(ROOT_DIR)/vault/newAsic
    ASIC_LINK_PKG := $(ASIC_LINK_DIR)/rtl/NewAsicPkg.vhd
    ASIC_LINK_TOP := $(ASIC_LINK_DIR)/rtl/Pix2PgpNewAsicTop.vhd
```

### Test Makefile and VHDL syntax via GHDL

While under the `firmware` directory, run:

```bash
$ clear && make clean && make ASIC=NewAsic && cd ghdl/ && bash ghdlRun.sh Pix2PgpNewAsicTopTb && cd ..
```

If that command exits without any errors, you can proceed with the next step.

### Create a New Directory Under `firmware/targets`

Go-To `firmware/targets` and crate a new directory for the `NewAsic`: do `$ cp -r Pix2PgpSparkPixTEmu Pix2PgpNewAsicEmu`

1. Go-To `firmware/targets/Pix2PgpNewAsicEmu/hdl` and do: `$ mv Pix2PgpEmuSparkPixT.vhd Pix2PgpEmuNewAsic.vhd` and `$ mv Pix2PgpEmuSparkPixT.xdc Pix2PgpEmuNewAsic.xdc`. Edit the VHDL entity names within `Pix2PgpEmuNewAsic.vhd` accordingly. Note that these are just dummy files that are not really used in the testbench.
2. Go-To `firmware/targets/Pix2PgpNewAsicEmu/tb` and do: `$ mv Pix2PgpSparkPixTEmuTb.vhd Pix2PgpNewAsicEmuTb.vhd`. Edit the VHDL entity names within `Pix2PgpNewAsicEmuTb.vhd` accordingly. Note that e.g. `U_Uut : entity pix2pgp.Pix2PgpSparkPixTTopTb` should be changed into `U_Uut : entity pix2pgp.Pix2PgpNewAsicTopTb` (`Pix2PgpNewAsicTopTb` should be the same as the top-level testbench entity name of file `firmware/vault/newAsic/tb/Pix2PgpNewAsicTopTb.vhd` that was created in one of the previous steps).
3. Edit `firmware/targets/Pix2PgpNewAsicEmu/ruckus.tcl`: Change `set_property top {Pix2PgpSparkPixTEmuTb} [get_filesets sim_1]` into `set_property top {Pix2PgpNewAsicEmuTb} [get_filesets sim_1]`. Note that the name `Pix2PgpNewAsicEmuTb` should be the same as the VHDL entity name in `firmware/targets/Pix2PgpNewAsicEmu/tb/Pix2PgpNewAsicEmuTb.vhd`

### Run Testbench using VCS

Follow the instructions on how to run VCS from the `README.md` file at the top-level of this repository (Just change the Pix2PgpSparkPixSEmu` reference in that section with `Pix2PgpNewAsicEmu`).

If the VCS simulation runs without any errors, one can go ahead and decode the data dump using `software/scripts/axiDataParser.py`; however, in order to do this, one has to add the new ASIC definition into the pix2pgp Python data decoding classes. A How-To on this is included below.

## How-To Add a New ASIC in the Python Data Decoding Codebase

### Test


## Limitations
TBD
