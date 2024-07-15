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

RTL_DIR=${ROOT_DIR}/firmware/core/rtl
TB_DIR=${ROOT_DIR}/firmware/core/tb
GHDL_DIR=${ROOT_DIR}/firmware/ghdl

RTL=${RTL_DIR}/*.vhd

# note that the package has to be declared separately in order to be imported first
PIX2PGP_PKG_DIR=${RTL_DIR}/pkg
PIX2PGP_PKG=${PIX2PGP_PKG_DIR}/Pix2PgpPkg.vhd

SURF_DIR=${RTL_DIR}/surf
SURF=${SURF_DIR}/*.vhd
SURF_SUBMODULE_DIR=${ROOT_DIR}/firmware/submodules/surf

TB=${TB_DIR}/*Tb.vhd

# note that the packages hav to be declared separately in order to be imported first
# the order of the packages *matter*.
SURF_PKG_DIR=${SURF_DIR}/pkg
SURF_PKG_ALL=${SURF_PKG_DIR}/*Pkg.vhd
SURF_PKG=("${SURF_PKG_DIR}/StdRtlPkg.vhd"
          "${SURF_PKG_DIR}/CrcPkg.vhd"
          "${SURF_PKG_DIR}/AxiStreamPkg.vhd"
          "${SURF_PKG_DIR}/SsiPkg.vhd"
          "${SURF_PKG_DIR}/Pgp4Pkg.vhd"
          "${SURF_PKG_DIR}/AxiStreamPacketizer2Pkg.vhd"
          "${SURF_PKG_DIR}/ArbiterPkg.vhd")

# stub dware files
DWARE_DIR=${RTL_DIR}/dw
DWARE=${DWARE_DIR}/*.vhd
DWARE_PKG_DIR=${DWARE_DIR}/pkg
DWARE_PKG=${DWARE_PKG_DIR}/dw06_components.vhd

CF=${GHDL_DIR}/*.cf
GTKW=${GHDL_DIR}/*.gtkw
GHW=${GHDL_DIR}/*.ghw
VCD=${GHDL_DIR}/*.vcd
TB=${TB_DIR}/*Tb.vhd
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

prepareSurf()
{
  checkFileExists ${SURF}
  surf_exists=$?

  if [[ $surf_exists -eq 1 ]]; then
    echo "[INFO]: Surf libraries found in ${SURF}. Cleaning up..."
    rm ${SURF}
  fi

  checkFileExists ${SURF_PKG_ALL}
  surfPkg_exists=$?

  if [[ $surfPkg_exists -eq 1 ]]; then
    echo "[INFO]: Surf packages found in ${SURF_PKG_ALL}. Cleaning up..."
    rm ${SURF_PKG_ALL}
  fi

  # add files here accordingly
  # note that I add all the *Pkg.vhd in a separate dir that will be imported *first*;
  # otherwise, this ERROR shows up: `entity "xxx" is obsoleted by package "stdrtlpkg"` (or whatever *pkg)
  ln -s ${SURF_SUBMODULE_DIR}/base/general/rtl/StdRtlPkg.vhd                       ${SURF_PKG_DIR}/StdRtlPkg.vhd
  ln -s ${SURF_SUBMODULE_DIR}/protocols/pgp/pgp4/core/rtl/Pgp4Pkg.vhd              ${SURF_PKG_DIR}/Pgp4Pkg.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/crc/rtl/CrcPkg.vhd                              ${SURF_PKG_DIR}/CrcPkg.vhd
  ln -s ${SURF_SUBMODULE_DIR}/protocols/ssi/rtl/SsiPkg.vhd                         ${SURF_PKG_DIR}/SsiPkg.vhd
  ln -s ${SURF_SUBMODULE_DIR}/axi/axi-stream/rtl/AxiStreamPkg.vhd                  ${SURF_PKG_DIR}/AxiStreamPkg.vhd
  ln -s ${SURF_SUBMODULE_DIR}/protocols/packetizer/rtl/AxiStreamPacketizer2Pkg.vhd ${SURF_PKG_DIR}/AxiStreamPacketizer2Pkg.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/general/rtl/ArbiterPkg.vhd                      ${SURF_PKG_DIR}/ArbiterPkg.vhd

  ln -s ${SURF_SUBMODULE_DIR}/base/delay/rtl/SlvDelay.vhd                          ${SURF_DIR}/SlvDelay.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/sync/rtl/RstSync.vhd                            ${SURF_DIR}/RstSync.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/sync/rtl/Synchronizer.vhd                       ${SURF_DIR}/Synchronizer.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/sync/rtl/SynchronizerOneShot.vhd                ${SURF_DIR}/SynchronizerOneShot.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/sync/rtl/SynchronizerEdge.vhd                   ${SURF_DIR}/SynchronizerEdge.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/sync/rtl/SynchronizerVector.vhd                 ${SURF_DIR}/SynchronizerVector.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/ram/inferred/SimpleDualPortRam.vhd              ${SURF_DIR}/SimpleDualPortRam.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/fifo/rtl/FifoOutputPipeline.vhd                 ${SURF_DIR}/FifoOutputPipeline.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/fifo/rtl/inferred/FifoWrFsm.vhd                 ${SURF_DIR}/FifoWrFsm.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/fifo/rtl/inferred/FifoRdFsm.vhd                 ${SURF_DIR}/FifoRdFsm.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/fifo/rtl/inferred/FifoSync.vhd                  ${SURF_DIR}/FifoSync.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/fifo/rtl/inferred/FifoAsync.vhd                 ${SURF_DIR}/FifoAsync.vhd

  # PGP4-related
  ln -s ${SURF_SUBMODULE_DIR}/axi/axi-stream/rtl/AxiStreamPipeline.vhd             ${SURF_DIR}/AxiStreamPipeline.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/crc/rtl/Crc32Parallel.vhd                       ${SURF_DIR}/Crc32Parallel.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/crc/rtl/Crc32.vhd                               ${SURF_DIR}/Crc32.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/general/rtl/Gearbox.vhd                         ${SURF_DIR}/Gearbox.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/general/rtl/Scrambler.vhd                       ${SURF_DIR}/Scrambler.vhd
  ln -s ${SURF_SUBMODULE_DIR}/protocols/packetizer/rtl/AxiStreamDepacketizer2.vhd  ${SURF_DIR}/AxiStreamDepacketizer2.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/ram/inferred/DualPortRam.vhd                    ${SURF_DIR}/DualPortRam.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/ram/inferred/LutRam.vhd                         ${SURF_DIR}/LutRam.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/ram/inferred/TrueDualPortRam.vhd                ${SURF_DIR}/TrueDualPortRam.vhd
  ln -s ${SURF_SUBMODULE_DIR}/base/sync/rtl/SynchronizerFifo.vhd                   ${SURF_DIR}/SynchronizerFifo.vhd
  ln -s ${SURF_SUBMODULE_DIR}/protocols/pgp/pgp3/core/rtl/Pgp3RxGearboxAligner.vhd ${SURF_DIR}/Pgp3RxGearboxAligner.vhd
  ln -s ${SURF_SUBMODULE_DIR}/protocols/pgp/pgp4/core/rtl/Pgp4RxEb.vhd             ${SURF_DIR}/Pgp4RxEb.vhd
  ln -s ${SURF_SUBMODULE_DIR}/protocols/pgp/pgp4/core/rtl/Pgp4RxProtocol.vhd       ${SURF_DIR}/Pgp4RxProtocol.vhd
  ln -s ${SURF_SUBMODULE_DIR}/protocols/pgp/pgp4/core/rtl/Pgp4Rx.vhd               ${SURF_DIR}/Pgp4Rx.vhd
  ln -s ${SURF_SUBMODULE_DIR}/protocols/pgp/pgp4/core/rtl/Pgp4TxLite.vhd           ${SURF_DIR}/Pgp4TxLite.vhd
  ln -s ${SURF_SUBMODULE_DIR}/protocols/pgp/pgp4/core/rtl/Pgp4TxLiteProtocol.vhd   ${SURF_DIR}/Pgp4TxLiteProtocol.vhd
  ln -s ${SURF_SUBMODULE_DIR}/protocols/pgp/pgp4/core/rtl/Pgp4TxLiteWrapper.vhd    ${SURF_DIR}/Pgp4TxLiteWrapper.vhd
  ln -s ${SURF_SUBMODULE_DIR}/axi/axi-stream/rtl/AxiStreamMux.vhd                  ${SURF_DIR}/AxiStreamMux.vhd
  ln -s ${SURF_SUBMODULE_DIR}/axi/axi-stream/rtl/AxiStreamDeMux.vhd                ${SURF_DIR}/AxiStreamDeMux.vhd

 }

 prepareDWare()
 {
    echo "[WARNING]: DWare Libraries NOT needed for GHDL simulation! Importing the local stub files instead..."

    ${GHDL_IMPORT_DWARE} ${DWARE_PKG}
    ${GHDL_IMPORT_DWARE} ${DWARE}

 }

printHelp()
{
  if [ "$1" == "--help" ]; then
    echo ""
    echo "Simple ghdl wrapper script."
    echo "It is assumed that there are three directories: rtl/ tb/ ghdl/ ; all on the same level"
    echo "rtl/ is where the source files are located; tb/ are all sim-related files; ghdl/ is where the ghdl script is"
    echo "this script will *not* work if this structure is not followed"
    echo "Provide the name of the top-level testbench entity as a first argument."
    echo "If no argument is given, the files in rtl/ will simply be analyzed."
    echo "Provide the stop time (in us) as a second argument"
    echo "example usage: $ bash ghdlRun.sh my_tb 100"
    echo "NB: The script assumes "
    echo "NB: The top-level VHDL testbench file must have a name of *_tb.vhd"
    echo ""
    exit 0
  fi
}

checkFileExists()
{
  retVal=0
  if compgen -G $1 > /dev/null; then
    retVal=1
  fi
  return $retVal
}

cleanFiles()
{
  checkFileExists $1
  exists=$?
  if [[ exists -eq 1 ]]; then
    rm $1
  fi
}

##########################################################################

ghdlClean()
{

  echo "[INFO]: Cleaning up GHDL directory..."

  # the command below deletes the .cf file(s), which is like a compiled library. Acts as a cleanup
  cleanFiles "$CF"

  # the command below deletes the .vcd file(s). Acts as a cleanup
  cleanFiles "$VCD"

  # the command below deletes the .ghw file(s). Acts as a cleanup
  cleanFiles "$GHW"

  # the command below deletes the .fst file(s). Acts as a cleanup
  cleanFiles "$FST"

  # the command below deletes the ghdl output file(s). Acts as a cleanup
  cleanFiles "$OUT"

  # add the vhd surf packages files into a new .cf file library named surf
  echo "[INFO]: Preparing surf directory..."
  prepareSurf
  echo ${SURF_DIR}
  echo ${SURF}
  checkFileExists ${SURF}
  surf_exists=$?

  # surf import
  if [[ $surf_exists -eq 1 ]]; then
    echo "[INFO]: Surf libraries found in ${SURF}. Importing..."
    for package in "${SURF_PKG[@]}"
    do
      ${GHDL_IMPORT_SURF} $package
    done
    ${GHDL_IMPORT_SURF} ${SURF}
  else
    echo "[ERROR]: No surf files found..."
    exit 1
  fi

  prepareDWare

  checkFileExists ${RTL}
  pix2pgp_exists=$?

  # pix2pgp import
  if [[ $pix2pgp_exists -eq 1 ]]; then
    echo "[INFO]: Pix2pgp libraries found in ${RTL}. Importing..."
    ${GHDL_IMPORT_PIX2PGP} ${PIX2PGP_PKG}
    ${GHDL_IMPORT_PIX2PGP} ${TB}
    ${GHDL_IMPORT_PIX2PGP} ${RTL}
  else
    echo "[ERROR]: No pix2pgp files found..."
    exit 1
  fi

}

ghdlAnalyze()
{

##########################################################################
  # analyze the files to make sure their syntax is correct
  echo "Analyzing:"
  echo "$(ls ${RTL})"
  echo "$(ls ${TB})"
  ${GHDL_ANALYZE} ${RTL}
  ${GHDL_ANALYZE} ${TB}
}

ghdlTestbench()
{
  tbFilePath="${TB_DIR}/${1}.vhd"
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

main()
{
  printHelp $1

  doTb=1
  if [[ -z "$1" ]]; then
    echo "[INFO]: No arguments are given. Simple analysis is performed."
    doTb=0
  fi

  checkFileExists "$RTL"
  rtlExists=$?
  if [[ $rtlExists -eq 0 ]]; then
    echo "[ERROR]: There are no .vhd files in rtl/."
    exit 1
  fi

  ghdlClean
  ghdlAnalyze

  if [[ $doTb -eq 1 ]]; then
    ghdlTestbench "$1" "$2"
  fi

}

main "$@"
