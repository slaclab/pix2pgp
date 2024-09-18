# Load RUCKUS library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Load Source Code
# note that synopsysFifo is sourced in the Vivado-based flow
loadSource -lib pix2pgp -dir "$::DIR_PATH/rtl"
loadSource -lib pix2pgp -dir "$::DIR_PATH/rtl/synopsysFifo"
loadSource -lib pix2pgp -dir "$::DIR_PATH/rtl/pkg"

# Load Simulation
loadSource -lib pix2pgp -sim_only -dir "$::DIR_PATH/tb"

# Define if we use ASIC post-synthesis simulation (0: pre-synth, 1:post-synth)
if { [info exists ::env(USE_ASIC_POST_SYN)] != 1 || $::env(USE_ASIC_POST_SYN) == 1 } {
   set nop ""
} else {
   # Load submodule/pix2pgp Source Code
}
