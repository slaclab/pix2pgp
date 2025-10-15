# Load RUCKUS library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Load Source Code
loadSource -lib pix2pgp           -dir "$::DIR_PATH/rtl"
loadSource -lib pix2pgp           -dir "$::DIR_PATH/rtl/asicTop"
loadSource -lib pix2pgp           -dir "$::DIR_PATH/rtl/pkg"
loadSource -lib pix2pgp -sim_only -dir "$::DIR_PATH/tb"
