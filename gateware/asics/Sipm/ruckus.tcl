# Load RUCKUS environment and library
source $::env(RUCKUS_PROC_TCL)

# Load ruckus library (ruckus.BuildInfoPkg.vhd only)
if { [info exists ::env(SYN_DIR)] } {
   GenBuildString $::env(SYN_DIR)
}

# Load the pix2pgp library for this ASIC
loadSource -lib pix2pgp -dir "$::DIR_PATH/rtl"
loadSource -lib pix2pgp -dir "$::DIR_PATH/tb"

# Load the shared source files
loadRuckusTcl "$::DIR_PATH/../../shared"

# Analyze source code loaded into ruckus for Cadence Genus
# Comment-out here; add in ASIC's synthesis flow
# AnalyzeSrcFileLists
