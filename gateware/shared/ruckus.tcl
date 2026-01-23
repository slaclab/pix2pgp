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

# Load the appropriate FIFOs
# Default is Synopsys DesignWare FIFOs; these should be used when building the ASIC RTL
# this is overriden in case one wants to emulate the ASIC in an FPGA in-silicon implementation;
# or if the DesignWare FIFOs are not available for simulation at the host
if { [info exists ::env(SURF_FIFO)] != 0 && $::env(SURF_FIFO) == 1 } {   
   puts "\[INFO]: Loading surf generic FIFOs for this project."
   puts "\[WARNING]: **********************************************"
   puts "\[WARNING]: Do *NOT* use for ASIC in-silicon RTL building!"
   puts "\[WARNING]: **********************************************"
   loadSource -lib pix2pgp -dir "$::DIR_PATH/rtl/surfFifo"
} else {

   puts "\[INFO]: Loading Synopsys FIFOs for this project."
   loadSource -lib pix2pgp -dir "$::DIR_PATH/rtl/synopsysFifo"
}
