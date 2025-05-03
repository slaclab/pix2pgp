ROOT_DIR := .

ASIC_SOURCED := 0
##################################################
ifeq ($(ASIC), SparkPixS)
    ASIC_SOURCED  := 1
    ASIC_LINK_DIR := $(ROOT_DIR)/vault/sparkPixS
    ASIC_LINK_PKG := $(ASIC_LINK_DIR)/rtl/SparkPixSPkg.vhd
    ASIC_LINK_TOP := $(ASIC_LINK_DIR)/rtl/Pix2PgpSparkPixSTop.vhd
else ifeq ($(ASIC), SparkPixT)
    ASIC_SOURCED  := 1
    ASIC_LINK_DIR := $(ROOT_DIR)/vault/sparkPixT
    ASIC_LINK_PKG := $(ASIC_LINK_DIR)/rtl/SparkPixTPkg.vhd
    ASIC_LINK_TOP := $(ASIC_LINK_DIR)/rtl/Pix2PgpSparkPixTTop.vhd
# else ifeq ($(ASIC), Template)
#     ASIC_SOURCED  := 1
#     ASIC_LINK_DIR := $(ROOT_DIR)/vault/Template
#     ASIC_LINK_PKG := $(ASIC_LINK_DIR)/rtl/TemplatePkg.vhd
#     ASIC_LINK_TOP := $(ASIC_LINK_DIR)/rtl/Pix2PgpTemplateTop.vhd
endif
##################################################

##################################################
GHDL_DIR := $(ROOT_DIR)/ghdl

ASIC_RTL_DIR := $(ROOT_DIR)/asic/rtl
ASIC_TB_DIR := $(ROOT_DIR)/asic/tb

PIX2PGP_ASIC_TOP_DIR := $(ASIC_RTL_DIR)/asicTop
PIX2PGP_PKG_DIR := $(ASIC_RTL_DIR)/pkg

SURF_DIR := $(ASIC_RTL_DIR)/surf
SURF_PKG_DIR := $(SURF_DIR)/pkg

SURF_SUBMODULE_DIR := $(ROOT_DIR)/submodules/surf

PIX2PGP_PKG := $(PIX2PGP_PKG_DIR)/Pix2PgpPkg.vhd

PIX2PGP_PKG_FILES      := $(wildcard $(PIX2PGP_PKG_DIR)/*.vhd)
PIX2PGP_ASIC_TOP_FILES := $(wildcard $(PIX2PGP_ASIC_TOP_DIR)/*.vhd)
ASIC_TB_FILES          := $(wildcard $(ASIC_TB_DIR)/*.vhd)
SURF_FILES             := $(wildcard $(SURF_DIR)/*.vhd)
SURF_PKG_FILES         := $(wildcard $(SURF_PKG_DIR)/*.vhd)
GHDL_FILES             := $(wildcard $(GHDL_DIR)/*.cf $(GHDL_DIR)/*.ghw $(GHDL_DIR)/*.vcd $(GHDL_DIR)/*.fst $(GHDL_DIR)/*.o)

ASIC_LINK_TB_FILES     := $(wildcard $(ASIC_LINK_DIR)/tb/*.vhd)

define create_link
    ln -sf $(shell readlink -f $(1)) $(2)/
endef
##################################################


# Targets
.PHONY: all clean prepareSurf prepare

all: prepare

clean:
	@echo "[INFO]: Cleaning up..."
	rm -f $(PIX2PGP_PKG_FILES)
	rm -f $(PIX2PGP_ASIC_TOP_FILES)
	rm -f $(ASIC_TB_FILES)
	rm -f $(SURF_FILES)
	rm -f $(SURF_PKG_FILES)
	rm -f $(GHDL_FILES)
	@echo "[INFO]: Clean complete."

prepareSurf:
	@echo "[INFO]: Preparing surf directories..."
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/general/rtl/TextUtilPkg.vhd)                     $(SURF_PKG_DIR)/TextUtilPkg.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/general/rtl/StdRtlPkg.vhd)                       $(SURF_PKG_DIR)/StdRtlPkg.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4Pkg.vhd)              $(SURF_PKG_DIR)/Pgp4Pkg.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/crc/rtl/CrcPkg.vhd)                              $(SURF_PKG_DIR)/CrcPkg.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/protocols/ssi/rtl/SsiPkg.vhd)                         $(SURF_PKG_DIR)/SsiPkg.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/axi/axi-stream/rtl/AxiStreamPkg.vhd)                  $(SURF_PKG_DIR)/AxiStreamPkg.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/axi/axi-lite/rtl/AxiLitePkg.vhd)                      $(SURF_PKG_DIR)/AxiLitePkg.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/protocols/packetizer/rtl/AxiStreamPacketizer2Pkg.vhd) $(SURF_PKG_DIR)/AxiStreamPacketizer2Pkg.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/general/rtl/ArbiterPkg.vhd)                      $(SURF_PKG_DIR)/ArbiterPkg.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/general/tb/ClkRst.vhd)                           $(SURF_DIR)/ClkRst.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/delay/rtl/SlvDelay.vhd)                          $(SURF_DIR)/SlvDelay.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/sync/rtl/RstSync.vhd)                            $(SURF_DIR)/RstSync.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/sync/rtl/Synchronizer.vhd)                       $(SURF_DIR)/Synchronizer.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/sync/rtl/SynchronizerOneShot.vhd)                $(SURF_DIR)/SynchronizerOneShot.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/sync/rtl/SynchronizerEdge.vhd)                   $(SURF_DIR)/SynchronizerEdge.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/sync/rtl/SynchronizerVector.vhd)                 $(SURF_DIR)/SynchronizerVector.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/ram/inferred/SimpleDualPortRam.vhd)              $(SURF_DIR)/SimpleDualPortRam.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/fifo/rtl/Fifo.vhd)                               $(SURF_DIR)/Fifo.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/fifo/rtl/FifoOutputPipeline.vhd)                 $(SURF_DIR)/FifoOutputPipeline.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/fifo/rtl/inferred/FifoWrFsm.vhd)                 $(SURF_DIR)/FifoWrFsm.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/fifo/rtl/inferred/FifoRdFsm.vhd)                 $(SURF_DIR)/FifoRdFsm.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/fifo/rtl/inferred/FifoSync.vhd)                  $(SURF_DIR)/FifoSync.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/fifo/rtl/inferred/FifoAsync.vhd)                 $(SURF_DIR)/FifoAsync.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/axi/axi-stream/rtl/AxiStreamPipeline.vhd)             $(SURF_DIR)/AxiStreamPipeline.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/crc/rtl/Crc32Parallel.vhd)                       $(SURF_DIR)/Crc32Parallel.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/crc/rtl/Crc32.vhd)                               $(SURF_DIR)/Crc32.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/general/rtl/Gearbox.vhd)                         $(SURF_DIR)/Gearbox.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/general/rtl/Scrambler.vhd)                       $(SURF_DIR)/Scrambler.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/protocols/packetizer/rtl/AxiStreamDepacketizer2.vhd)  $(SURF_DIR)/AxiStreamDepacketizer2.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/ram/inferred/DualPortRam.vhd)                    $(SURF_DIR)/DualPortRam.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/ram/inferred/LutRam.vhd)                         $(SURF_DIR)/LutRam.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/ram/inferred/TrueDualPortRam.vhd)                $(SURF_DIR)/TrueDualPortRam.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/base/sync/rtl/SynchronizerFifo.vhd)                   $(SURF_DIR)/SynchronizerFifo.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/protocols/pgp/pgp3/core/rtl/Pgp3RxGearboxAligner.vhd) $(SURF_DIR)/Pgp3RxGearboxAligner.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4RxEb.vhd)             $(SURF_DIR)/Pgp4RxEb.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4RxProtocol.vhd)       $(SURF_DIR)/Pgp4RxProtocol.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4Rx.vhd)               $(SURF_DIR)/Pgp4Rx.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4TxLite.vhd)           $(SURF_DIR)/Pgp4TxLite.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4TxLiteProtocol.vhd)   $(SURF_DIR)/Pgp4TxLiteProtocol.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/protocols/pgp/pgp4/core/rtl/Pgp4TxLiteWrapper.vhd)    $(SURF_DIR)/Pgp4TxLiteWrapper.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/axi/axi-lite/rtl/AxiLiteAsync.vhd)                    $(SURF_DIR)/AxiLiteAsync.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/axi/axi-stream/rtl/AxiStreamMux.vhd)                  $(SURF_DIR)/AxiStreamMux.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/axi/axi-stream/rtl/AxiStreamFifoV2.vhd)               $(SURF_DIR)/AxiStreamFifoV2.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/axi/axi-stream/rtl/AxiStreamDeMux.vhd)                $(SURF_DIR)/AxiStreamDeMux.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/axi/axi-stream/rtl/AxiStreamGearbox.vhd)              $(SURF_DIR)/AxiStreamGearbox.vhd
	ln -sf $(shell readlink -f $(SURF_SUBMODULE_DIR)/axi/axi-stream/rtl/AxiStreamResize.vhd)               $(SURF_DIR)/AxiStreamResize.vhd
	@echo "[INFO]: surf preparation complete."

# prepare: clean prepareSurf
# 	@if [ "$(ASIC)" = "SparkPixS" ]; then \
# 		echo "[INFO]: Preparing SparkPix-S Specific Files..." ;\
# 		ln -sf $(shell readlink -f $(SPARKPIX_S_PKG)) $(PIX2PGP_PKG) ;\
# 		ln -sf $(shell readlink -f $(SPARKPIX_S_TOP)) $(PIX2PGP_ASIC_TOP_DIR)/ ;\
#         for file in $(SPARKPIX_S_TB_FILES); do \
#             $(MAKE) create-link FILE=$$file DIR=$(ASIC_TB_DIR); \
#         done; \
# 		echo "[INFO]: Successfully linked SparkPix-S files!" ;\
# 	elif [ "$(ASIC)" = "SparkPixT" ]; then \
# 		echo "[INFO]: Preparing SparkPix-T Specific Files..." ;\
# 		ln -sf $(shell readlink -f $(SPARKPIX_T_PKG)) $(PIX2PGP_PKG) ;\
# 		ln -sf $(shell readlink -f $(SPARKPIX_T_TOP)) $(PIX2PGP_ASIC_TOP_DIR)/ ;\
#         for file in $(SPARKPIX_T_TB_FILES); do \
#             $(MAKE) create-link FILE=$$file DIR=$(ASIC_TB_DIR); \
#         done; \
# 		echo "[INFO]: Successfully linked SparkPix-T files!" ;\
# 	else \
# 		echo "[ERROR]: The 'ASIC' variable was not set properly! Please check; Currently: ASIC = $(ASIC)" ;\
# 	fi

prepare: clean prepareSurf
	@if [ "$(ASIC_SOURCED)" = 1 ]; then \
		echo "[INFO]: Preparing $(ASIC) Specific Files..." ;\
		ln -sf $(shell readlink -f $(ASIC_LINK_PKG)) $(PIX2PGP_PKG) ;\
		ln -sf $(shell readlink -f $(ASIC_LINK_TOP)) $(PIX2PGP_ASIC_TOP_DIR)/ ;\
		for file in $(ASIC_LINK_TB_FILES); do \
			$(MAKE) create-link FILE=$$file DIR=$(ASIC_TB_DIR); \
		done; \
		echo "";\
		echo "[INFO]: $(ASIC) Importing successful!";\
		echo "";\
	else \
		echo "[ERROR]: The 'ASIC' variable was not set properly! Please check; Currently: ASIC = $(ASIC)" ;\
	fi

create-link:
	$(call create_link, $(FILE), $(DIR))
