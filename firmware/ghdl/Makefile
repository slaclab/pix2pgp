#-----------------------------------------------------------------------------
# This file is part of the 'pix2pgp'. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the 'pix2pgp', including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------

# Define TOP directory
export TOP_DIR = $(abspath $(PWD)/..)

# Define default SURF_FIFO for "pix2pgp/gateware/shared/ruckus.tcl"
export SURF_FIFO = 1

# Define the top-level VHDL lib
export GHDL_TOP_LIB = pix2pgp

# Define PROJECT with respect to $(ASIC) type
export PROJECT = Pix2Pgp$(ASIC)TopTb

# Define the simulation time
export GHDL_STOP_TIME = 10us

# Load the common makefile library
include $(TOP_DIR)/submodules/ruckus/system_ghdl.mk

# Define default target
target: check_asic build

# Check if ASIC is defined
check_asic:
	@if [ -z "$(ASIC)" ]; then \
		echo "[ERROR]: ASIC must be specified! Please use an ASIC from within gateware/asics/ (e.g., 'make ASIC=Thriglav build')"; \
		exit 1; \
	fi
