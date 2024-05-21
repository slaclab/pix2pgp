# pix2pgp
## How to Run the Simulation
Based on GHDL. Navigate to the ghdl/ dir and execute this to simply analyze the files:
```
$ bash ghdlRun.sh
```

If you want to run a testbench (here it is `Pix2PgpTopTb`), run:
```
$ bash ghdlRun.sh Pix2PgpTopTb
```
### Dependencies
You should have the following two packages in your server to run the simulation:
```
* ghdl-llvm
* gtkwave
```

## What to Include When Synthesizing
### In a VHDL library called `pix2pgp` import the following files:
```
* firmware/rtl/Pix2PgpGearbox.vhd
* firmware/rtl/Pix2PgpFifoCascade.vhd
* firmware/rtl/Pix2PgpFifoMux.vhd
* firmware/rtl/Pix2PgpFifo.vhd
* firmware/rtl/Pix2PgpBridge.vhd
* firmware/rtl/Pix2PgpColumnSupervisor.vhd
* firmware/rtl/pkg/Pix2PgpPkg.vhd
* firmware/rtl/Pix2PgpGearboxWrapper.vhd
* firmware/rtl/Pix2PgpArbiter.vhd
* firmware/rtl/Pix2PgpColumnManager.vhd
* firmware/rtl/Pix2PgpTop.vhd
* firmware/rtl/Pix2PgpFifoWrapper.vhd
* firmware/rtl/Pix2PgpAdapter.vhd
* firmware/rtl/Pix2PgpTopSparkPixS.vhd
```

### In a VHDL library called `surf` import the following files:
```
* firmware/submodules/surf/base/general/rtl/StdRtlPkg.vhd
* firmware/submodules/surf/base/sync/rtl/RstSync.vhd
* firmware/submodules/surf/base/sync/rtl/Synchronizer.vhd
* firmware/submodules/surf/base/sync/rtl/SynchronizerOneShot.vhd
* firmware/submodules/surf/base/sync/rtl/SynchronizerEdge.vhd
* firmware/submodules/surf/base/sync/rtl/SynchronizerVector.vhd
* firmware/submodules/surf/base/ram/inferred/SimpleDualPortRam.vhd
* firmware/submodules/surf/base/fifo/rtl/FifoOutputPipeline.vhd
* firmware/submodules/surf/base/fifo/rtl/inferred/FifoWrFsm.vhd
* firmware/submodules/surf/base/fifo/rtl/inferred/FifoRdFsm.vhd
* firmware/submodules/surf/base/fifo/rtl/inferred/FifoSync.vhd
* firmware/submodules/surf/base/fifo/rtl/inferred/FifoASync.vhd
```

Note that the FIFO/RAM related files of both libraries might not be needed, since we will import the DWare FIFOs for synthesis.

### In a VHDL library called `dware` import the following files (afs paths):
```
* /afs/slac.stanford.edu/g/reseng/vol30/synopsys/syn/P-2019.03-SP3/packages/dware/src/DWpackages.vhd
* /afs/slac.stanford.edu/g/reseng/vol30/synopsys/syn/P-2019.03-SP3/dw/dw06/src/DW_asymfifo_s2_sf.vhd
* /afs/slac.stanford.edu/g/reseng/vol30/synopsys/syn/P-2019.03-SP3/dw/dw06/src/DW_fifo_s2_sf.vhd
```

## Other related info regarding Synthesis
The top-level that is to be instantiated within the Verilog/SystemVerilog containing the columns/SARlogic/SparseItfLogic etc. is: `firmware/rtl/Pix2PgpTopSparkPixS.vhd`

Note that apart from the column-related ports, the said file also contains the following PGP-related ports:

```
[...]
  txReady   : in  std_logic;
  txValid   : out std_logic;
  txData    : out std_logic_vector(63 downto 0);
  txSof     : out std_logic;
  txEof     : out std_logic;
  txEofe    : out std_logic);
[...]
```

It is assumed that the module that is to be used to implement PGP4TxLite is the following:
[Pgp4TxLiteWrapper](https://github.com/slaclab/surf/blob/master/protocols/pgp/pgp4/core/rtl/Pgp4TxLiteWrapper.vhd)