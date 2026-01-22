# Load RUCKUS environment and library
source $::env(RUCKUS_QUIET_FLAG) $::env(RUCKUS_PROC_TCL)

# Load ruckus library (ruckus.BuildInfoPkg.vhd only)
GenBuildString $::env(SYN_DIR)

# Load the surf library
loadRuckusTcl "$::env(TOP_DIR)/submodules/surf"

# Load the work library
loadSource -lib pix2pgp -dir "$::DIR_PATH/rtl"
loadSource -lib pix2pgp -dir "$::DIR_PATH/../vault/rtl"

# Analyze source code loaded into ruckus for Cadence Genus
AnalyzeSrcFileLists
