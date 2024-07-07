# Load RUCKUS library
source $::env(RUCKUS_PROC_TCL)

# Load Source Code
loadSource -lib pix2pgp -dir "$::DIR_PATH/firmware/rtl"
loadSource -lib pix2pgp -dir "$::DIR_PATH/firmware/rtl/pkg"

# Load Simulation
loadSource -lib pix2pgp -sim_only -dir "$::DIR_PATH/firmware/tb"
