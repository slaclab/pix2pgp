# Load RUCKUS environment and library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Load submodules and shared source code
loadRuckusTcl $::env(TOP_DIR)/submodules/surf

# the paths below contain the proprietary Synopsys stuff that are instantiated by pix2pgp
# It is assumed that the user has access to the said dirs when invoking this .tcl script
# the code below checks for existence to avoid any errors...
set file_test "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw06/src/DW06_components.vhd"
if { [file exists $file_test] == 1} {
  puts "Synopsys files exist! adding..."
  loadSource           -lib dw06  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw06/src/DW06_components.vhd"
  loadSource           -lib dw03  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw03/src/DW03_components.vhd"
  loadSource           -lib dware -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/packages/dware/src/DWpackages.vhd"
  loadSource           -lib dware -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/packages/dware/src/DW_Foundation_arith.vhd"
  loadSource           -lib dware -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/packages/dware/src/DW_Foundation_comp_arith.vhd"

  loadSource           -lib dw06  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw06/src/DW_ram_r_w_s_dff.vhd"
  loadSource           -lib dw03  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw03/src/DW_asymfifoctl_s2_sf.vhd"
  loadSource           -lib dw03  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw03/src/DW_fifoctl_s2_sf.vhd"
  loadSource           -lib dw06  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw06/src/DW_fifo_s2_sf.vhd"
  loadSource           -lib dw06  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw06/src/DW_asymfifo_s2_sf.vhd"

  loadSource -sim_only -lib dw06  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw06/src/DW_ram_r_w_s_dff_sim.vhd"
  loadSource -sim_only -lib dw03  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw03/src/DW_asymfifoctl_s2_sf_sim.vhd"
  loadSource -sim_only -lib dw03  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw03/src/DW_fifoctl_s2_sf_sim.vhd"
  loadSource -sim_only -lib dw06  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw06/src/DW_fifo_s2_sf_sim.vhd"
  loadSource -sim_only -lib dw06  -path "/sdf/group/faders/tools/synopsys/syn/P-2019.03-SP3/dw/dw06/src/DW_asymfifo_s2_sf_sim.vhd"
} else {
  puts "Synopsys files do NOT exist! Setting the SURF_FIFO variable..."
  set ::env(SURF_FIFO) "1"
}

# SparkPix-S Specific
loadRuckusTcl "$::DIR_PATH/../../../gateware/asics/SparkPixT"

# Pix2Pgp FPGA sources
loadRuckusTcl $::env(TOP_DIR)/fpga

# Load target's source code and constraints
loadSource      -dir  "$::DIR_PATH/hdl"
loadConstraints -dir  "$::DIR_PATH/hdl"

# Load the simulation testbed
loadSource -sim_only -dir "$::DIR_PATH/tb"
set_property top {Pix2PgpSparkPixTEmuTb} [get_filesets sim_1]
