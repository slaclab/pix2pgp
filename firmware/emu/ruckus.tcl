# Load RUCKUS library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Load Source Code
loadSource -dir "$::DIR_PATH/rtl"

# Load Source Code
loadConstraints -dir "$::DIR_PATH/xdc"

# Define if we use ASIC post-synthesis simulation (0: pre-synth, 1:post-synth)
if { [info exists ::env(USE_ASIC_POST_SYN)] != 1 || $::env(USE_ASIC_POST_SYN) == 1 } {
   set nop ""
} else {
   # Load submodule/pix2pgp Source Code
}

