##############################################################################
## This file is part of 'pix2pgp-emu'.
## It is subject to the license terms in the LICENSE.txt file found in the
## top-level directory of this distribution and at:
##    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
## No part of 'pix2pgp-emu', including this file,
## may be copied, modified, propagated, or distributed except according to
## the terms contained in the LICENSE.txt file.
##############################################################################

# Get variables and procedures
source -quiet $::env(RUCKUS_DIR)/vivado/env_var.tcl
source -quiet $::env(RUCKUS_DIR)/vivado/proc.tcl

set simTbOutDir ${OUT_DIR}/${PROJECT}_project.sim/sim_1/behav
set tcb013ghp "/afs/slac/g/airic/ic_digital_flow/tech/tsmc130_digital/Front_End/verilog/tcb013ghp_220a/tcb013ghp.v"
set asic_list ""; # TODO: update this when ASIC design more mature

##############################################################################

# open the files
set in  [open ${simTbOutDir}/sim_vcs_mx.sh r]
set out [open ${simTbOutDir}/sim_vcs_mx.sh.new w]

# Find and replace the AFS path
while { [eof ${in}] != 1 } {

   gets ${in} line

   if { [string match {*vlogan -work xpm*}  $line]} {
      puts ${out} ""
      if { [info exists ::env(USE_ASIC_POST_SYN)] != 1 || $::env(USE_ASIC_POST_SYN) == 1 } {
         puts ${out} "  vlogan -work xil_defaultlib \$vlogan_opts \"$tcb013ghp\" \"$asic_list\" 2>&1 | tee -a vlogan.log"
      } else {
         puts ${out} "  vlogan -work xil_defaultlib \$vlogan_opts \"$tcb013ghp\" 2>&1 | tee -a vlogan.log"
      }
      puts ${out} ""
   }

   puts ${out} ${line}
}

# Close the files
close ${in}
close ${out}

# Overwrite the old file
exec mv -f ${simTbOutDir}/sim_vcs_mx.sh.new  ${simTbOutDir}/sim_vcs_mx.sh

# Update the permissions
exec chmod 0755 ${simTbOutDir}/sim_vcs_mx.sh