# How-To Add a New ASIC
Follow this guide to add support for a new ASIC.

Use a previous ASIC as a template. For this example, `SparkPix-T` will be used. Throughout this guide, `NewAsic` will refer to this new ASIC. The user should alter the name of `NewAsic` accordingly in all steps of this entire process, depending on the actual name of the ASIC they want to add.

There are two approaches in terms of generating event closure (i.e. `eof` assertion) for the sparse ASICs that Pix2Pgp typically supports:
* Self-Closure. If the user wishes to generate a Pix2Pgp variant for an ASIC that supports Self-Closure, they should pick `SparkPixS` as a template
* External-Trigger-Closure (i.e. `ERO` or End-Of-Readout signal support). If the user wishes to generate a Pix2Pgp variant for an ASIC that supports External-Trigger-Closure, they should pick `SparkPixT` as a template

In this example, it is assumed that `NewAsic` uses an `ERO` trigger to signal event closure. This is the reason why `SparkPixT` has been picked as its template.

## How-To Add a New ASIC in the RTL Codebase

### Create a New Directory Under `gateware/asics`

Navigate to `gateware/asics` and create a new directory for the `NewAsic`: do `$ cp -r SparkPixT NewAsic`

1. Under `NewAsic/rtl`, do:
    * `$ mv Pix2PgpSparkPixTTop.vhd Pix2PgpNewAsicTop.vhd`
    1. Edit `Pix2PgpAsicPkg.vhd` accordingly. Usually, what should be edited is the following: 
        1. `NUM_OF_COL_MANAGERS_C` (how many columns does each Pix2Pgp instance serve?)
        2. `NUM_OF_SERIALIZERS_C` (how many serializers/Pix2Pgp instances/lanes are on the ASIC?)
        3. `ASIC_DATABUS_DWIDTH_C` (what is the data bus width that is driven to Pix2Pgp?)
        4. Finally, depending on the internal data width (double the `ASIC_DATABUS_DWIDTH_C`), the user has to edit the Pix2Pgp data frame header bitfield structure accordingly.
    2. Edit `Pix2PgpNewAsicTop.vhd` accordingly. For example, one needs to change the width of the `sof, eof, overOcc` etc. signals to have the same width as `NUM_OF_COL_MANAGERS_C`, and the amount of `dinXX` ports to be the same as the `NUM_OF_COL_MANAGERS_C`. Also, the width of the data that are being written into Pix2Pgp by the Analog part of the ASIC (i.e. the value of `ASIC_DATABUS_DWIDTH_C` in the `*Pkg.vhd` file) must be the same as the width of each `dinXX` port. Note the lack of use of complex VHDL types (i.e. custom types/arrays) in the top-level interfacing. This is because there needs to be flexibility in terms of where the top-level can be instantiated in. If the top-level VHDL file needs to be instantiated within the context of Verilog/SystemVerilog, there can be no complex types at the top-level VHDL entity definition.
2. Under `NewAsic/tb`, do:
    * `$ mv DummySparkPixTPixel.vhd DummyNewAsicPixel.vhd`
    * `$ mv Pix2PgpSparkPixTFpgaRxTop.vhd Pix2PgpNewAsicFpgaRxTop.vhd`
    * `$ mv Pix2PgpSparkPixTTopTb.vhd Pix2PgpNewAsicTopTb.vhd`
    1. Edit `DummyNewAsicPixel.vhd` accordingly. This is a behavioral model of the pixel of the new ASIC and should be mimicking the behavior of the ASIC, e.g. in terms of the delay between the `wrEn` signals when writing multiple data words into the Pix2Pgp core and the delay between the `SRO` assertion and the first (if any) `wrEn` strobe. This model is used in the top-level VHDL testbench (`Pix2PgpNewAsicTopTb.vhd`). Note the `hitLen` port. Within the top-level VHDL testbench, one can edit the value of this dynamically to change how many hits each pixel model injects into Pix2Pgp.
    2. Edit `Pix2PgpNewAsicFpgaRxTop.vhd` accordingly. This entity is a wrapper for the FPGA-related receiver logic .vhd files. In principle, one needs to only expand/collapse the number of input ports for the data, and their associated allocation within the architecture, depending on the number of lanes the ASIC has (i.e. `NUM_OF_SERIALIZERS_C`). This file is to also be used within SystemVerilog verification context, hence the use of simple ports for the data buses.
    3. Edit `Pix2PgpNewAsicTopTb.vhd` accordingly. Change the names of the VHDL entities and widths of the buses depending on the amount of columns each Pix2Pgp instance serves. Note that the testbench is instantiating all Lanes of the ASIC (governed by the `NUM_OF_SERIALIZERS_C` parameter) and routing all of them into `Pix2PgpNewAsicFpgaRxTop` which wraps around the ASIC RX logic instantiated in the FPGA of the in-silicon system.
        1. The testbenches usually include a VHDL process that selects specific columns/pixels and assigns a `hitLen` value on a per-trigger/event basis (e.g., the line `hitLen(0)(3) <= toSlv(3, hitLen(0)(0)'length);` assigns three hits for a pixel in column 3 of lane 0). One can create random hit-lengths by using the `software/scripts/hitsToVhd.py` script (e.g. `$ python hitsToVhd.py --numOfLanes=4 --numOfCols=40 --minRange=0 --maxRange=4 --laneEnable=1,1,1,1`) will generate random stimuli for an ASIC with 40 columns-per-Pix2Pgp instance, and 2-lanes-per-ASIC.

### Test the VHDL syntax via GHDL

While under the `firmware/ghdl` directory, run:

```bash
$ clear && make clean && make prepare_tb ASIC=NewAsic
```

If that command exits without any errors, you can proceed with the next step.

### Create a New Directory Under `firmware/targets`

Go-To `firmware/targets` and crate a new directory for the `NewAsic`: do `$ cp -r Pix2PgpSparkPixTEmu Pix2PgpNewAsicEmu`

1. Go-To `firmware/targets/Pix2PgpNewAsicEmu/hdl` and do: `$ mv Pix2PgpEmuSparkPixT.vhd Pix2PgpEmuNewAsic.vhd` and `$ mv Pix2PgpEmuSparkPixT.xdc Pix2PgpEmuNewAsic.xdc`. Edit the VHDL entity names within `Pix2PgpEmuNewAsic.vhd` accordingly. Note that these are just dummy files that are not really used in the testbench.
2. Go-To `firmware/targets/Pix2PgpNewAsicEmu/tb` and do: `$ mv Pix2PgpSparkPixTEmuTb.vhd Pix2PgpNewAsicEmuTb.vhd`. Edit the VHDL entity names within `Pix2PgpNewAsicEmuTb.vhd` accordingly. Note that e.g. `U_Uut : entity pix2pgp.Pix2PgpSparkPixTTopTb` should be changed into `U_Uut : entity pix2pgp.Pix2PgpNewAsicTopTb` (`Pix2PgpNewAsicTopTb` should be the same as the top-level testbench entity name of file `gateware/asics/newAsic/tb/Pix2PgpNewAsicTopTb.vhd` that was created in one of the previous steps).
3. Edit `firmware/targets/Pix2PgpNewAsicEmu/ruckus.tcl`: Change `loadRuckusTcl $::DIR_PATH/../../../gateware/asics/SparkPixT` to `loadRuckusTcl $::DIR_PATH/../../../gateware/asics/NewAsic`. Change `set_property top {Pix2PgpSparkPixTEmuTb} [get_filesets sim_1]` into `set_property top {Pix2PgpNewAsicEmuTb} [get_filesets sim_1]`. Note that the name `Pix2PgpNewAsicEmuTb` should be the same as the VHDL entity name in `firmware/targets/Pix2PgpNewAsicEmu/tb/Pix2PgpNewAsicEmuTb.vhd`

### Run Testbench using VCS

Follow the instructions on how to run VCS from the `README.md` file at the top-level of this repository (Just change the `Pix2PgpSparkPixSEmu` reference in that section with `Pix2PgpNewAsicEmu`).

If the VCS simulation runs without any errors, one can go ahead and decode the data dump using `software/scripts/axiDataParser.py`; however, in order to do this, one has to add the new ASIC definition into the Pix2Pgp Python data decoding classes located under `firmware/python/pix2pgp/`. A How-To on this is included below.

## How-To Add a New ASIC in the Python Data Decoding Codebase

### firmware/python/pix2pgp/_AsicParameters.py

First, add a new entry in the `asicTypeDict` and `asicParams`. The number must correspond to the value of the `ASIC_TYPE_C` constant that was chosen in `NewAsicPkg.vhd`. If, e.g. that number was `3`:

```Python

    asicTypeDict = {
        1: "SparkPixS",
        2: "SparkPixT",
        3: "NewAsic"}

    asicParams = {
        'SparkPixS': SparkPixSParameters,
        'SparkPixT': SparkPixTParameters,
        'NewAsic'  : NewAsicParameters}
```

Note also the entry in the `asicParams` dictionary.

Next, add a new parameter class for `NewAsic`. For example, if for this given ASIC the number of serializers/lanes/Pix2Pgp instances is equal to `4`, the number of columns each Pix2Pgp instance is `40` (i.e. the total number of columns is `4x40 = 160`), and the data bus width is `5` bytes, then the parameter set will have the following values:

```Python
class NewAsicParameters(AsicParameterBase):
    '''
    NewAsic Parameters
    '''
    @property
    def asicTypeId(self):
        for key, value in AsicParameterBase.asicTypeDict.items():
            if value == "NewAsic":
                return key
        raise ValueError("ASIC type not found in asicTypeDict!")

    def asicParamExtract(self):
        '''
        Parameter dictionary
        '''

        param_dict = {'asicTypeId' : self.asicTypeId,
                      'asicType'   : AsicParameterBase.asicTypeDict[self.asicTypeId],
                      'numOfLanes' : 4,
                      'numOfCols'  : 40,
                      'wordLen'    : 10}

        return param_dict

```

All parameters above correspond to constants found in the `*Pkg.vhd` file. `numOfLanes` corresponds to `NUM_OF_SERIALIZERS_C`, `numOfCols` corresponds to `NUM_OF_COL_MANAGERS_C`, and `wordLen` corresponds to `PIX2PGP_DATABUS_DWIDTH_C`, with the difference being that `wordLen` is the width in bytes, while the `VHDL` constant width is in bits.

Note that the class name (`NewAsicParameters`) has the same name as the entry in the `asicParams` dictionary.

### firmware/python/pix2pgp/_Pix2PgpHeaderFormat.py

Add a new entry in the `self.asicHeader` dictionary. Name the class of `NewAsic` accordingly, and set the bit-mapping to be the same as the one set in the data header bitfield section of the `*Pkg.vhd` file. Example:

```Python
    @classmethod
    def setHeader(self):
        self.asicHeader = {
            'SparkPixS': SparkPixSHeaderFormat,
            'SparkPixT': SparkPixTHeaderFormat,
            'NewAsic'  : NewAsicHeaderFormat}

# [...]

class NewAsicHeaderFormat(Pix2PgpHeaderFormatBase):
    '''
    NewAsic Header Format
    '''
    def headerDecoder(self, header):
        '''
        Header mapping and decoding
        '''
        _header = int(header, 16)

        header_dict = {'overOcc'    : bool((_header >> 79) & 0x1),
                       'pause'      : bool((_header >> 78) & 0x1),
                       'colErr'     : bool((_header >> 77) & 0x1),
                       'pauseErr'   : bool((_header >> 76) & 0x1),
                       'dummy'      : bool((_header >> 75) & 0x1),
                       'timeout'    : bool((_header >> 74) & 0x1),
                       'colHitmask' :      (_header >>  8) & 0xFFFFFFFFFF,
                       'trgCnt'     :      (_header >>  0) & 0xFF}

        return header_dict
```

Note that the upper bit of the header corresponds to the `overOcc` flag, and its bit position (i.e. `79`) is associated with the overall length of the data word ('wordLen=10' in `_AsicParameters.py`; which is `10x8=80` bits). The `colHitmask` has a value of `0xFFFFFFFFFF`, which corresponds to the amount of columns (i.e. `numOfCols=40` in `_AsicParameters.py`) served by each Pix2Pgp instance of `NewAsic`.


### firmware/python/pix2pgp/_Pix2PgpColMetadataFormat.py

Add a new entry in the `self.asicMetadata` dictionary. Name the class of `NewAsic` accordingly, and set the bit-mapping to be the same as the one set in the data column metadata bitfield section of the `*Pkg.vhd` file. Example:

```Python
    @classmethod
    def setMetadata(self):
        self.asicMetadata = {
            'SparkPixS': SparkPixSColMetadataFormat,
            'SparkPixT': SparkPixTColMetadataFormat,
            'NewAsic'  : NewAsicColMetadataFormat}
# [...]

class NewAsicColMetadataFormat(Pix2PgpColMetadataFormatBase):
    '''
    NewAsic colMetaData Format
    '''
    def colMetadataDecoder(self, colMeta):
        '''
        Column Metadata mapping and decoding
        '''
        _colMeta = int(colMeta, 16)

        colMeta_dict = {'colTimeout' : bool((_colMeta >> 26) & 0x1),
                        'colOverOcc' : bool((_colMeta >> 25) & 0x1),
                        'colPause'   : bool((_colMeta >> 24) & 0x1),
                        'colId'      :      (_colMeta >> 16) & 0xFF,
                        'colTrgCnt'  :      (_colMeta >>  8) & 0xFF,
                        'colLen'     :      (_colMeta >>  0) & 0xFF}

        return colMeta_dict
```

### firmware/python/pix2pgp/_Pix2PgpSparseDataFormat.py

Add a new entry in the `self.asicData` dictionary. Name the class of `NewAsic` accordingly, and set the bit-mapping to be the same as the one dictated by the analog/digital sparse logic of the ASIC. Example:

```Python
    @classmethod
    def setData(self):
        self.asicData = {
            'SparkPixS': SparkPixSDataFormat,
            'SparkPixT': SparkPixTDataFormat,
            'NewAsic'  : NewAsicDataFormat}
# [...]

class NewAsicDataFormat(SparseDataFormatBase):
    '''
    NewAsic Data Format
    '''
    def dataDecoder(self, colId=0, hitData=None, rawData=False):
        '''
        Hit data mapping and decoding
        '''
        if hitData is None:
            click.secho("[WARNING]: dataDecoder; Received None for hitData", bg='yellow')
            return

        _hitData = int(hitData, 16)

        _hit = []
        ret  = []

        _hit.append((_hitData >> 40) & 0xFFFFFFFFFF)
        _hit.append((_hitData >>  0) & 0xFFFFFFFFFF)

        if rawData:
            ret.append({'col': colId, 'raw': hex(_hit[0]).upper().replace('0X', '0x')})
            ret.append({'col': colId, 'raw': hex(_hit[1]).upper().replace('0X', '0x')})

        else:
            _row = []
            _adc = []

            _row.append ((_hit[0] >> 20) & 0xFFFFF)
            _adc.append ((_hit[0] >>  0) & 0xFFFFF)

            _row.append ((_hit[1] >> 20) & 0xFFFFF)
            _adc.append ((_hit[1] >>  0) & 0xFFFFF)

            ret.append({'col': colId,
                        'row': _row[0],
                        'adc': _adc[0]})

            ret.append({'col': colId,
                        'row': _row[1],
                        'adc': _adc[1]})

        return ret

    def dataPrinter(self, asicHits=None, rawData=False):

        if asicHits is None or len(asicHits) == 0:
            click.secho("[INFO]: dataDecoder; Empty event...")
            return

        if rawData:
            _formatRaw = 'Col = {0:<4}  Raw = {1:<24}'

            for hit in asicHits:
                click.secho(_formatRaw.format(hit['col'], str(hit['raw'])))

        else:
            _formatAsic = 'Col = {0:<4} Row = {1:<8} ADC = {2:<8} '

            for hit in asicHits:
                click.secho(_formatAsic.format(hit['col'], hit['row'], hit['adc']))
```

## Miscellaneous
1. Update the repo's top-level `README.md` with the new ASIC entry
2. Perform benchmark measurements for the new ASIC (see `software/scripts/benchmarking/README.md` for more information)
3. Update Pix2Pgp Confluence page accordingly

## Limitations
The width of the data coming into Pix2Pgp from the data source dictates how wide the data frame will be. Pix2Pgp *doubles* the size of that bus. This means that each data bus that is connected to Pix2Pgp is half the width of the data word that Pix2Pgp transmits to the FPGA Receiver.

This can be observed in the `*Pkg.vhd` files found under the various ASIC variants under `gateware/asics`:

```VHDL
   -- data bus width is twice the pixel data width to maximize bandwidth
   constant PIX2PGP_DATABUS_DWIDTH_C : natural := ASIC_DATABUS_DWIDTH_C*2;
```

This sets a limitation on how many columns can be served by each Pix2Pgp instance of a specified data bus width. This is because of the structure of the Pix2Pgp Lane Header, which has to fit the following:

* Lane Header *Flags* (usually *six*)
* The *Trigger Counter*, that has a configurable width (usually *6-bit*)
* The *Column Hitmask*, which has the same width as the amount of columns served; i.e. this is what needs to fit in the header.

For example, If each Pix2Pgp instance of an ASIC serves `40` columns, then `ASIC_DATABUS_DWIDTH_C` has to be at least `26-`bit wide, in order for the header to fit `6` bits of Flags, plus `6` bits of Trigger Counter, plus the `40-`bit Hitmask (`40+6+6=52`, and since the final bus width is double the sparse data size: `52/2=26`). If this prerequisite is not satisfied, then the ASIC architecture needs to be modified accordingly by adding more Pix2Pgp modules and serializers to support them, in order to reduce the amount of columns served. Or, `ASIC_DATABUS_DWIDTH_C` can be widened (by e.g. padding) in order for the internal word to be able to accommodate the amount of column hitmask bits in the Lane Header.
