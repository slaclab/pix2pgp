# Load RUCKUS environment and library
source $::env(RUCKUS_PROC_TCL)

# Load ruckus files
loadRuckusTcl $::env(TOP_DIR)/submodules/surf
loadRuckusTcl $::env(TOP_DIR)/../gateware/asics/$::env(ASIC)
loadRuckusTcl $::env(TOP_DIR)/fpga
