# Load RUCKUS library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Check for submodule tagging
if { [info exists ::env(OVERRIDE_SUBMODULE_LOCKS)] != 1 || $::env(OVERRIDE_SUBMODULE_LOCKS) == 0 } {
   if { [SubmoduleCheck {ruckus} {4.22.0} ] < 0 } {exit -1}
   if { [SubmoduleCheck {surf}   {2.67.0} ] < 0 } {exit -1}
} else {
   puts "\n\n*********************************************************"
   puts "OVERRIDE_SUBMODULE_LOCKS != 0"
   puts "Ignoring the submodule locks in pix2pgp/ruckus.tcl"
   puts "*********************************************************\n\n"
}

# Load Source Code
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
