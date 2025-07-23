#!/bin/sh
# simple GHDL wrapper script
##########################################################################
# it is assumed that there are three directories: rtl/ tb/ ghdl/ ; all on the same level
# rtl/ is where the source files are located; tb/ are all sim-related files; ghdl/ is where the ghdl script is
# this script will *not* work if this structure is not followed
# also, the surf library files should be added in a dir named surf/ directly under rtl/
##########################################################################
# two uses: 1) $ bash ghdlRun.sh
#           2) $ bash ghdlRun.sh <name of top-level tb name> <stop time (e.g. 100us)>
# if no arguments are given (option 1), then a simple analysis of the .vhd files in the rtl/ dir is performed.
# if arguments are given (option 2), then a testbench is compiled and run
# e.g.: bash ghdlRun.sh ModuleTb 5
# the command above will run the ModuleTb.vhd testbench for 5us.
# it is assumed that ModuleTb.vhd is under tb/
##########################################################################
##########################################################################

ROOT_DIR=${PWD}/../../

GHDL_DIR=${ROOT_DIR}/firmware/ghdl


ASIC_RTL_DIR=${ROOT_DIR}/firmware/asic/rtl
ASIC_TB_DIR=${ROOT_DIR}/firmware/asic/tb
# --
ASIC_RTL=${ASIC_RTL_DIR}/*.vhd
ASIC_TB=${ASIC_TB_DIR}/*.vhd


FPGA_RTL_DIR=${ROOT_DIR}/firmware/fpga/rtl
FPGA_TB_DIR=${ROOT_DIR}/firmware/fpga/tb
# --
FPGA_RTL=${FPGA_RTL_DIR}/*.vhd
FPGA_TB=${FPGA_TB_DIR}/*.vhd

# ASIC Top-level
PIX2PGP_ASIC_TOP_DIR=${ASIC_RTL_DIR}/asicTop
PIX2PGP_ASIC_TOP=${PIX2PGP_ASIC_TOP_DIR}/*Top.vhd

# note that the package has to be declared separately in order to be imported first
PIX2PGP_PKG_DIR=${ASIC_RTL_DIR}/pkg
PIX2PGP_PKG=${PIX2PGP_PKG_DIR}/Pix2PgpPkg.vhd

# these are only used by GHDL
GHDL_FIFO_DIR=${GHDL_DIR}/ghdlFifo
GHDL_FIFO=${GHDL_FIFO_DIR}/*.vhd

# Vault stuff
VAULT_DIR=${ROOT_DIR}/firmware/vault

# ASIC-specific
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
SPARKPIX_S_DIR=${VAULT_DIR}/sparkPixS
SPARKPIX_T_DIR=${VAULT_DIR}/sparkPixT

SPARKPIX_S_RTL_DIR=${SPARKPIX_S_DIR}/rtl
SPARKPIX_T_RTL_DIR=${SPARKPIX_T_DIR}/rtl

SPARKPIX_S_TB_DIR=${SPARKPIX_S_DIR}/tb
SPARKPIX_T_TB_DIR=${SPARKPIX_T_DIR}/tb

SPARKPIX_S_PKG=${SPARKPIX_S_RTL_DIR}/SparkPixSPkg.vhd
SPARKPIX_T_PKG=${SPARKPIX_T_RTL_DIR}/SparkPixTPkg.vhd

SPARKPIX_S_TOP=${SPARKPIX_S_RTL_DIR}/Pix2PgpSparkPixSTop.vhd
SPARKPIX_T_TOP=${SPARKPIX_T_RTL_DIR}/Pix2PgpSparkPixTTop.vhd
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Surf stuff
SURF_DIR=${ASIC_RTL_DIR}/surf
SURF=${SURF_DIR}/*.vhd

SURF_FPGA_DIR=${FPGA_RTL_DIR}/surf
SURF_FPGA=${SURF_FPGA_DIR}/*.vhd

SURF_SUBMODULE_DIR=${ROOT_DIR}/firmware/submodules/surf

# note that the packages hav to be declared separately in order to be imported first
# the order of the packages *matter*.
SURF_PKG_DIR=${SURF_DIR}/pkg
SURF_FPGA_PKG_DIR=${SURF_FPGA_DIR}/pkg

SURF_PKG=("${SURF_PKG_DIR}/StdRtlPkg.vhd"
          "${SURF_FPGA_PKG_DIR}/TextUtilPkg.vhd"
          "${SURF_PKG_DIR}/CrcPkg.vhd"
          "${SURF_PKG_DIR}/AxiStreamPkg.vhd"
          "${SURF_FPGA_PKG_DIR}/AxiLitePkg.vhd"
          "${SURF_PKG_DIR}/SsiPkg.vhd"
          "${SURF_PKG_DIR}/Pgp4Pkg.vhd"
          "${SURF_PKG_DIR}/AxiStreamPacketizer2Pkg.vhd"
          "${SURF_PKG_DIR}/ArbiterPkg.vhd")

CF=${GHDL_DIR}/*.cf
GTKW=${GHDL_DIR}/*.gtkw
GHW=${GHDL_DIR}/*.ghw
VCD=${GHDL_DIR}/*.vcd
FST=${GHDL_DIR}/*.fst
OUT=${GHDL_DIR}/*.o

#############################
GHDL_CMD="ghdl-llvm"
# check if your ghdl version is < 1.0.0; if it is, you need to use a downloaded tarball from https://github.com/ghdl/ghdl/releases
# example below...
# GHDL_CMD="/home/cb/Work/tools/ghdl/bin/ghdl"
#############################
GHDL_GLBL_FLAGS="--ieee=standard -fexplicit -fsynopsys"
GHDL_STD_FLAG="--std=93c"

GHDL_ANALYZE="${GHDL_CMD} -s ${GHDL_GLBL_FLAGS} ${GHDL_STD_FLAG}"
GHDL_IMPORT_SURF="${GHDL_CMD} -i ${GHDL_GLBL_FLAGS} --work=surf"
GHDL_IMPORT_PIX2PGP="${GHDL_CMD} -i ${GHDL_GLBL_FLAGS} --work=pix2pgp"
GHDL_IMPORT_DWARE="${GHDL_CMD} -i ${GHDL_GLBL_FLAGS} --work=dw06"
GHDL_IMPORT_WORK="${GHDL_CMD} -i ${GHDL_GLBL_FLAGS} --work=work"
GHDL_MAKE="${GHDL_CMD} -m  -g -Psurf -Ppix2pgp -Pdware -Pwork --warn-unused ${GHDL_GLBL_FLAGS}"
GHDL_RUN="${GHDL_CMD} --elab-run ${GHDL_GLBL_FLAGS}"

DEFAULT_STOP_TIME_US="10"

##########################################################################

checkFileExists()
{
  retVal=0
  if compgen -G $1 > /dev/null; then
    retVal=1
  fi
  return $retVal
}

##########################################################################
ghdlAnalyze()
{
  # analyze the files to make sure their syntax is correct
  echo "List of Files:"
  echo "$(ls ${ASIC_RTL})"
  echo "$(ls ${ASIC_TB})"
  echo "$(ls ${FPGA_RTL})"
  echo "$(ls ${FPGA_TB})"
  echo "$(ls ${PIX2PGP_PKG})"
  echo "$(ls ${PIX2PGP_ASIC_TOP})"
  echo "$(ls ${FPGA_RTL})"
  echo "$(ls ${FPGA_TB})"
  echo "$(ls ${GHDL_FIFO})"

  echo "List of ASIC SURF stuff..."
  checkFileExists ${SURF}
  surf_exists=$?

  # surf import
  if [[ $surf_exists -eq 1 ]]; then
    echo "[INFO]: Surf libraries found in ${SURF}. Importing following files..."
    echo "${SURF}"
    for package in "${SURF_PKG[@]}"
    do
      ${GHDL_IMPORT_SURF} $package
    done
    ${GHDL_IMPORT_SURF} ${SURF}
    ${GHDL_IMPORT_SURF} ${SURF_FPGA}
  else
    echo "[ERROR]: No surf files found..."
    exit 1
  fi

  echo "[INFO]: Importing RTL Files..."
  ${GHDL_IMPORT_PIX2PGP} ${PIX2PGP_PKG}
  ${GHDL_IMPORT_PIX2PGP} ${ASIC_RTL}
  ${GHDL_IMPORT_PIX2PGP} ${ASIC_TB}
  ${GHDL_IMPORT_PIX2PGP} ${FPGA_RTL}
  ${GHDL_IMPORT_PIX2PGP} ${FPGA_TB}
  ${GHDL_IMPORT_PIX2PGP} ${TB_SHARED}
  ${GHDL_IMPORT_PIX2PGP} ${PIX2PGP_ASIC_TOP}
  ${GHDL_IMPORT_PIX2PGP} ${GHDL_FIFO}

  echo "[INFO]: Analyzing RTL Files..."
  ${GHDL_ANALYZE} ${PIX2PGP_PKG}
  ${GHDL_ANALYZE} ${ASIC_RTL}
  ${GHDL_ANALYZE} ${ASIC_TB}
  ${GHDL_ANALYZE} ${FPGA_RTL}
  ${GHDL_ANALYZE} ${FPGA_TB}
  ${GHDL_ANALYZE} ${TB_SHARED}
  ${GHDL_ANALYZE} ${PIX2PGP_ASIC_TOP}
  ${GHDL_ANALYZE} ${GHDL_FIFO}
  echo "[INFO]: Done!"
}
##########################################################################

##########################################################################
ghdlTestbench()
{
  tbFilePath="${ASIC_TB_DIR}/${1}.vhd"
  tbFileName="${1}.vhd"
  checkFileExists ${tbFilePath}
  tbExists=$?
  if [[ $tbExists -eq 1 ]]; then
    echo "Assuming testbench entity name: ${1}"
    echo "Assuming testbench file name: ${1}.vhd"
    ${GHDL_IMPORT_WORK} ${tbFilePath}

    # compile an executable to-be-run.
    # the argument name has to be the SAME as the entity name of the testbench at the top-level of your testbench file
    ${GHDL_MAKE} $1

    if [[ -z "$2" ]]; then
      echo "Default stopping time of ${DEFAULT_STOP_TIME_US}us not overriden by user."
      stopTime=$DEFAULT_STOP_TIME_US
    else
      stopTime=$2
    fi

    echo "Will run for ${stopTime}us."

    gtkwFile=""
    checkFileExists "${1}.gtkw"
    gtkwExists=$?
    if [[ $tbExists -eq 1 ]]; then
      echo "GTKW file exists. Will load."
      gtkwFile="${1}.gtkw"
    fi

    # note the use of .ghw. We like .ghw. .ghw is good; it supports records on the waveform!
    ${GHDL_RUN} $1 --wave=$1.ghw --stop-time="${stopTime}us"

    gtkwave $1.ghw ${gtkwFile}

  else
    echo "[ERROR]: ${tbFilePath} not found! Is it under the tb/ directory as it is supposed to?"
    exit 1
  fi

}
##########################################################################

##########################################################################

main()
{
  if [[ -z "$1" ]]; then
    echo "[ERROR]: No arguments are given!"
    echo "[ERROR]: Please give a valid first argument that contains a valid option of an ASIC name!"
    echo "[INFO]:  Valid options: Pix2PgpSparkPixSTopTb, Pix2PgpSparkPixTTopTb"
    echo "[INFO]:  Example: bash ghdlRun.sh Pix2PgpSparkPixSTopTb to prepare for SparkPix-S"
    echo "[INFO]:  Example: bash ghdlRun.sh Pix2PgpSparkPixSTopTb 50 to run the GHDL tb in addition"
    exit 1
  fi

  checkFileExists "${ASIC_RTL}"
  rtlExists=$?
  if [[ $rtlExists -eq 0 ]]; then
    echo "[ERROR]: There are no .vhd files in rtl/."
    echo "[ERROR]: Are you in the right directory? You need to run this from the ghdl/ dir."
    exit 1
  fi

  # ghdlPrepare $1
  ghdlAnalyze

  if [[ $# -ge 2 ]]; then
    ghdlTestbench "$1" "$2"
  fi

}

main "$@"

