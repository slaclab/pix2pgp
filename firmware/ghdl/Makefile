# Makefile for GHDL wrapper script
# Example usage: $ make clean && make ASIC=SparkPixS 10
# To run the SparkPixS testbench for 10us

# If using this Makefile as a template for a manual importing script for ASIC Synthesis flow, import:
# * $(SURF_PKG)
# * $(SURF_ASIC_RTL)
# * $(ASIC_PKG)
# * $(ASIC_RTL)
# * $(ASIC_TOP)

# If using this Makefile as a template for a manual importing script for ASIC+FPGA Behavioral Simulation flow, import:
# * $(SURF_PKG)
# * $(SURF_ASIC_RTL)
# * $(SURF_FPGA_RTL)
# * $(ASIC_PKG)
# * $(ASIC_RTL)
# * $(ASIC_TOP)
# * $(ASIC_TB)
# * $(FPGA_RTL)
# * $(FPGA_TB)

# In this flow, a GHDL-compatible FIFO RTL wrapper source is used, under gateware/shared/rtl/surfFifo;
# *Never* include this file if manually importing surf/Pix2Pgp source files into your project.
# Pix2Pgp is designed to implement proprietary FIFOs in the ASIC flow that should be available in the host
# The wrapper file for the said FIFOs can be found under gateware/shared/rtl/synopsysFifo

# =============================================
# Directories
# =============================================
ROOT_DIR     := $(CURDIR)/../..
GATEWARE_DIR := $(ROOT_DIR)/gateware
FIRMWARE_DIR := $(ROOT_DIR)/firmware
GHDL_DIR     := $(FIRMWARE_DIR)/ghdl
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ASIC_RTL_DIR := $(GATEWARE_DIR)/shared/rtl
FPGA_RTL_DIR := $(FIRMWARE_DIR)/fpga/rtl
FPGA_TB_DIR  := $(FIRMWARE_DIR)/fpga/tb
SURF_DIR     := $(FIRMWARE_DIR)/submodules/surf
# =============================================


# =============================================
# Files
# =============================================
ASIC_RTL := $(wildcard $(ASIC_RTL_DIR)/*.vhd)
FPGA_RTL := $(wildcard $(FPGA_RTL_DIR)/*.vhd)
FPGA_TB  := $(wildcard $(FPGA_TB_DIR)/*.vhd)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ASIC-Specific
ASIC_PKG     := $(GATEWARE_DIR)/asics/$(ASIC)/rtl/Pix2PgpAsicPkg.vhd
ASIC_TOP     := $(GATEWARE_DIR)/asics/$(ASIC)/rtl/Pix2Pgp$(ASIC)Top.vhd
ASIC_TB      := $(wildcard $(GATEWARE_DIR)/asics/$(ASIC)/tb/*.vhd)
ASIC_TB_TOP  := $(GATEWARE_DIR)/asics/$(ASIC)/tb/Pix2Pgp$(ASIC)TopTb.vhd
ASIC_TB_NAME := Pix2Pgp$(ASIC)TopTb

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Surf FIFO Wrapper (do *not* include in any ASIC RTL Synthesis flow)
GHDL_FIFO_DIR := $(ASIC_RTL_DIR)/surfFifo
GHDL_FIFO_RTL := $(wildcard $(GHDL_FIFO_DIR)/*.vhd)
# =============================================

# =====================================================================================
# Surf Packages and Source Files
# Note that the packages have to be declared separately in order to be imported first
# The order of the package declaration within SURF_PKG *matters*.
# =====================================================================================

# =====================================================================================
# If following a manual ASIC RTL Synthesis flow, include these files
SURF_PKG = 	$(SURF_DIR)/base/general/rtl/StdRtlPkg.vhd \
			$(SURF_DIR)/axi/axi4/rtl/AxiPkg.vhd \
			$(SURF_DIR)/base/general/rtl/TextUtilPkg.vhd \
			$(SURF_DIR)/base/crc/rtl/CrcPkg.vhd \
			$(SURF_DIR)/axi/axi-stream/rtl/AxiStreamPkg.vhd \
			$(SURF_DIR)/axi/axi-lite/rtl/AxiLitePkg.vhd \
			$(SURF_DIR)/protocols/ssi/rtl/SsiPkg.vhd \
			$(SURF_DIR)/protocols/rssi/v1/rtl/RssiPkg.vhd \
			$(SURF_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4Pkg.vhd \
			$(SURF_DIR)/protocols/packetizer/rtl/AxiStreamPacketizer2Pkg.vhd \
			$(SURF_DIR)/base/general/rtl/ArbiterPkg.vhd
# =====================================================================================

# =====================================================================================
# If following a manual ASIC RTL Synthesis flow, include these files
SURF_ASIC_RTL = $(SURF_DIR)/base/general/tb/ClkRst.vhd \
				$(SURF_DIR)/base/delay/rtl/SlvDelay.vhd \
				$(SURF_DIR)/base/sync/rtl/RstSync.vhd \
				$(SURF_DIR)/base/sync/rtl/Synchronizer.vhd \
				$(SURF_DIR)/base/sync/rtl/SynchronizerOneShot.vhd \
				$(SURF_DIR)/base/sync/rtl/SynchronizerEdge.vhd \
				$(SURF_DIR)/base/sync/rtl/SynchronizerVector.vhd \
				$(SURF_DIR)/base/ram/inferred/SimpleDualPortRam.vhd \
				$(SURF_DIR)/base/fifo/rtl/FifoOutputPipeline.vhd \
				$(SURF_DIR)/base/fifo/rtl/inferred/FifoWrFsm.vhd \
				$(SURF_DIR)/base/fifo/rtl/inferred/FifoRdFsm.vhd \
				$(SURF_DIR)/base/fifo/rtl/inferred/FifoSync.vhd \
				$(SURF_DIR)/base/fifo/rtl/inferred/FifoAsync.vhd \
				$(SURF_DIR)/axi/axi-stream/rtl/AxiStreamPipeline.vhd \
				$(SURF_DIR)/base/crc/rtl/Crc32Parallel.vhd \
				$(SURF_DIR)/base/crc/rtl/Crc32.vhd \
				$(SURF_DIR)/base/general/rtl/Gearbox.vhd \
				$(SURF_DIR)/base/general/rtl/Scrambler.vhd \
				$(SURF_DIR)/protocols/packetizer/rtl/AxiStreamDepacketizer2.vhd \
				$(SURF_DIR)/base/ram/inferred/DualPortRam.vhd \
				$(SURF_DIR)/base/ram/inferred/LutRam.vhd \
				$(SURF_DIR)/base/ram/inferred/TrueDualPortRam.vhd \
				$(SURF_DIR)/base/sync/rtl/SynchronizerFifo.vhd \
				$(SURF_DIR)/protocols/pgp/pgp3/core/rtl/Pgp3RxGearboxAligner.vhd \
				$(SURF_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4RxEb.vhd \
				$(SURF_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4RxProtocol.vhd \
				$(SURF_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4Rx.vhd \
				$(SURF_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4TxLite.vhd \
				$(SURF_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4TxLiteProtocol.vhd \
				$(SURF_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4TxLiteWrapper.vhd \
				$(SURF_DIR)/axi/axi-stream/rtl/AxiStreamMux.vhd \
				$(SURF_DIR)/axi/axi-stream/rtl/AxiStreamDeMux.vhd \
				$(SURF_DIR)/axi/axi-stream/rtl/AxiStreamGearbox.vhd \
				$(SURF_DIR)/axi/axi-stream/rtl/AxiStreamResize.vhd
# =====================================================================================

# =====================================================================================
# If following a manual ASIC RTL Behavioral Verification flow, include these files
# Do *not* include the following in the ASIC RTL Synthesis flow (will throw Cadence/Synopsys errors/warnings)
SURF_FPGA_RTL = $(SURF_DIR)/base/fifo/rtl/Fifo.vhd \
				$(SURF_DIR)/base/fifo/rtl/FifoCascade.vhd \
				$(SURF_DIR)/base/fifo/rtl/FifoMux.vhd \
				$(SURF_DIR)/base/fifo/rtl/xilinx/FifoXpm.vhd \
				$(SURF_DIR)/base/fifo/rtl/altera/FifoAlteraMf.vhd \
				$(SURF_DIR)/base/fifo/rtl/dummy/FifoAlteraMfDummy.vhd \
				$(SURF_DIR)/base/fifo/rtl/dummy/FifoXpmDummy.vhd \
				$(SURF_DIR)/axi/axi-lite/rtl/AxiLiteAsync.vhd \
				$(SURF_DIR)/axi/axi-stream/ip_integrator/MasterAxiStreamIpIntegrator.vhd \
				$(SURF_DIR)/axi/axi-stream/rtl/AxiStreamFifoV2.vhd
# =====================================================================================

CF   := $(wildcard $(GHDL_DIR)/*.cf)
GTKW := $(wildcard $(GHDL_DIR)/*.gtkw)
GHW  := $(wildcard $(GHDL_DIR)/*.ghw)
VCD  := $(wildcard $(GHDL_DIR)/*.vcd)
FST  := $(wildcard $(GHDL_DIR)/*.fst)
OUT  := $(wildcard $(GHDL_DIR)/*.o)

# GHDL Command and Flags
GHDL_CMD        := ghdl-mcode # Or your specific GHDL path, e.g., /home/cb/Work/tools/ghdl/bin/ghdl
GHDL_GLBL_FLAGS := --ieee=standard -fexplicit -fsynopsys
GHDL_STD_FLAG   := --std=93c

GHDL_ANALYZE        := $(GHDL_CMD) -s $(GHDL_GLBL_FLAGS) $(GHDL_STD_FLAG)
GHDL_IMPORT_SURF    := $(GHDL_CMD) -i $(GHDL_GLBL_FLAGS) --work=surf
GHDL_IMPORT_PIX2PGP := $(GHDL_CMD) -i $(GHDL_GLBL_FLAGS) --work=pix2pgp
GHDL_IMPORT_WORK    := $(GHDL_CMD) -i $(GHDL_GLBL_FLAGS) --work=work
GHDL_MAKE           := $(GHDL_CMD) -m -Psurf -Ppix2pgp -Pwork --warn-unused $(GHDL_GLBL_FLAGS)
GHDL_RUN            := $(GHDL_CMD) --elab-run $(GHDL_GLBL_FLAGS)

DEFAULT_STOP_TIME := 10
STOP_TIME ?= $(DEFAULT_STOP_TIME)

# Helper function as a macro (Makefile way of "functions")
check_directory = $(shell if test -d "$1"; then echo 1; else echo 0; fi)

# Targets
.PHONY: all analyze tb clean

all: tb

analyze: check_asic $(ASIC_PKG) $(ASIC_RTL) $(ASIC_TOP) $(ASIC_TB) $(FPGA_RTL) $(FPGA_TB) $(GHDL_FIFO_RTL)
	@echo "List of Pix2Pgp Files:"
	@echo "ASIC_PKG: $(ASIC_PKG)"
	@echo "ASIC_RTL: $(ASIC_RTL)"
	@echo "ASIC_TOP: $(ASIC_TOP)"
	@echo "ASIC_TB:  $(ASIC_TB)"
	@echo "FPGA_RTL: $(FPGA_RTL)"
	@echo "FPGA_TB:  $(FPGA_TB)"
	@echo "GHDL_FIFO_RTL (please omit if using an external script and use gateware/shared/rtl/synopsysFifo): $(GHDL_FIFO_RTL)"

	@echo "[INFO]: Importing surf pkg files..."
	@echo "============================================================================================"
	for package in $(SURF_PKG); do \
		$(GHDL_IMPORT_SURF) $$package; \
	done; \

	@echo "============================================================================================"

	@echo "============================================================================================"
	@echo "[INFO]: Importing surf ASIC RTL support files..."
	@echo "============================================================================================"
	$(GHDL_IMPORT_SURF) $(SURF_ASIC_RTL); \

	@echo "============================================================================================"

	@echo "============================================================================================"
	@echo "[INFO]: Importing surf FPGA RTL/TB support files..."
	@echo "============================================================================================"
	$(GHDL_IMPORT_SURF) $(SURF_FPGA_RTL); \

	@echo "============================================================================================"

	@echo "============================================================================================"
	@echo "[INFO]: Importing RTL Files..."
	@echo "============================================================================================"
	$(GHDL_IMPORT_PIX2PGP) $(ASIC_PKG)
	$(GHDL_IMPORT_PIX2PGP) $(ASIC_RTL)
	$(GHDL_IMPORT_PIX2PGP) $(ASIC_TOP)
	$(GHDL_IMPORT_PIX2PGP) $(ASIC_TB)
	$(GHDL_IMPORT_PIX2PGP) $(FPGA_RTL)
	$(GHDL_IMPORT_PIX2PGP) $(FPGA_TB)
	$(GHDL_IMPORT_PIX2PGP) $(GHDL_FIFO_RTL)

	@echo "============================================================================================"
	@echo "[INFO]: Analyzing RTL Files..."
	@echo "============================================================================================"
	$(GHDL_ANALYZE) $(ASIC_PKG)
	$(GHDL_ANALYZE) $(ASIC_RTL)
	$(GHDL_ANALYZE) $(ASIC_TOP)
	$(GHDL_ANALYZE) $(ASIC_TB)
	$(GHDL_ANALYZE) $(FPGA_RTL)
	$(GHDL_ANALYZE) $(FPGA_TB)
	$(GHDL_ANALYZE) $(GHDL_FIFO_RTL)
	@echo "[INFO]: Done!"

# Check if ASIC is defined
check_asic:
	@if [ -z "$(ASIC)" ]; then \
		echo "[ERROR]: ASIC must be specified! Please use an ASIC from within gateware/asics/ (e.g., 'make analyze ASIC=SparkPixS')"; \
		exit 1; \
	fi

tb: analyze
	@echo "[INFO]: Assuming testbench entity name: $(ASIC_TB_NAME)"
	@echo "[INFO]: Assuming testbench top-level file: $(ASIC_TB_TOP)"

	${GHDL_IMPORT_WORK} $(ASIC_TB_TOP)

	$(GHDL_MAKE) $(ASIC_TB_NAME)

	@echo "Will run testbench for $(STOP_TIME)us."

	$(GHDL_RUN) $(ASIC_TB_NAME) --wave=$(ASIC_TB_NAME).ghw --stop-time="$(STOP_TIME)us"
	gtkwave $(ASIC_TB_NAME).ghw

clean:
	@rm -f $(OUT) $(CF) $(GHW) $(VCD) $(FST) # Clean up generated files
