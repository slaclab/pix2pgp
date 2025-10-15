# Load RUCKUS library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Load Source Code
loadSource -lib pix2pgp -path "$::DIR_PATH/../asic/rtl/pkg/Pix2PgpAsicPkg.vhd"
loadSource -lib pix2pgp -path "$::DIR_PATH/../asic/rtl/pkg/Pix2PgpPkg.vhd"
loadSource -lib pix2pgp -path "$::DIR_PATH/../asic/rtl/Pix2PgpWatchdog.vhd"
loadSource -lib pix2pgp -dir "$::DIR_PATH/rtl"
loadSource -lib pix2pgp -dir "$::DIR_PATH/tb"

# Load the appropriate FIFOs
if { [info exists ::env(SYNOPSYS_FIFO)] != 0 && $::env(SYNOPSYS_FIFO) == 1 } {
   loadSource -lib pix2pgp -sim_only -dir "$::DIR_PATH/../asic/rtl/synopsysFifo"
   puts "\[INFO]: Loading Synopsys FIFOs for this project; for behavioral simulation only!"
} else {
   loadSource -lib pix2pgp -dir "$::DIR_PATH/../ghdl/vivadoFifo"
   puts "\[INFO]: Loading Vivado/surf FIFOs for this project; for behavioral simulation and in-silicon implementation!"
}

# Load Source Code
loadConstraints -dir "$::DIR_PATH/xdc"
