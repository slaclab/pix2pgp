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

RTL_DIR=${ROOT_DIR}/firmware/core/rtl
TB_DIR=${ROOT_DIR}/firmware/core/tb

RTL=${RTL_DIR}/*.vhd

# ASIC Top-level
PIX2PGP_ASIC_TOP_DIR=${RTL_DIR}/asicTop
PIX2PGP_ASIC_TOP=${PIX2PGP_ASIC_TOP_DIR}/*Top.vhd

# note that the package has to be declared separately in order to be imported first
PIX2PGP_PKG_DIR=${RTL_DIR}/pkg
PIX2PGP_PKG=${PIX2PGP_PKG_DIR}/Pix2PgpPkg.vhd

# Vault stuff
VAULT_DIR=${ROOT_DIR}/firmware/vault
VAULT_RTL_DIR=${VAULT_DIR}/rtl
VAULT_TB_DIR=${VAULT_DIR}/tb

VAULT_SHARED_TB_DIR=${VAULT_TB_DIR}/shared
VAULT_FIFO_DIR=${VAULT_DIR}/ghdlFifo
VAULT_FIFO=${VAULT_FIFO_DIR}/*.vhd

# ASIC-specific
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
SPARKPIX_S_DIR=${VAULT_RTL_DIR}/sparkPixS
SPARKPIX_T_DIR=${VAULT_RTL_DIR}/sparkPixT

SPARKPIX_S_PKG=${SPARKPIX_S_DIR}/SparkPixSPkg.vhd
SPARKPIX_T_PKG=${SPARKPIX_T_DIR}/SparkPixTPkg.vhd

SPARKPIX_S_TOP=${SPARKPIX_S_DIR}/Pix2PgpSparkPixSTop.vhd
SPARKPIX_T_TOP=${SPARKPIX_T_DIR}/Pix2PgpSparkPixTTop.vhd

SPARKPIX_S_TB_DIR=${VAULT_TB_DIR}/sparkPixS
SPARKPIX_T_TB_DIR=${VAULT_TB_DIR}/sparkPixT
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Surf stuff
SURF_DIR=${RTL_DIR}/surf
SURF=${SURF_DIR}/*.vhd
SURF_SUBMODULE_DIR=${ROOT_DIR}/firmware/submodules/surf

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

CF=${GHDL_DIR}/*.cf
GTKW=${GHDL_DIR}/*.gtkw
GHW=${GHDL_DIR}/*.ghw
VCD=${GHDL_DIR}/*.vcd
TB=${TB_DIR}/*.vhd
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

  ln -s ${SURF_SUBMODULE_DIR}/base/general/tb/ClkRst.vhd                           ${SURF_DIR}/ClkRst.vhd
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
  ln -s ${SURF_SUBMODULE_DIR}/axi/axi-stream/rtl/AxiStreamGearbox.vhd              ${SURF_DIR}/AxiStreamGearbox.vhd
  ln -s ${SURF_SUBMODULE_DIR}/axi/axi-stream/rtl/AxiStreamResize.vhd               ${SURF_DIR}/AxiStreamResize.vhd
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

ghdlPrepare()
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

  # the command below deletes the tb linked files...!
  cleanFiles "$TB"

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

  ghdlLink $1

}

linkManyFiles()
{
  # Ensure both directories exist
  if [ ! -d "${1}" ]; then
    echo "Error: ${1} does not exist."
    exit 1
  fi

  if [ ! -d "${2}" ]; then
    echo "Error: ${2} does not exist."
    exit 1
  fi

  # If the destination directory is empty, print a message
  if [ -z "$(ls -A "${2}")" ]; then
    echo "The destination directory (${2}) is empty."
  else
    echo "The destination directory (${2}) contains files."
  fi

  # Loop through all .vhd files in the source dir
  for sharedFile in "${1}"/*.vhd; do
    # Ensure the file exists
    if [ -e "$sharedFile" ]; then
      # Get the filename from the full path
      filename=$(basename "$sharedFile")
      destination="${2}/$filename"

      # Check if the file or symlink already exists in the destination directory
      if [ -e "$destination" ]; then
        echo "File or symlink already exists: $destination"
        # Optionally, remove the existing file/symlink before creating a new one
        # rm "$destination"
      else
        ln -s "$sharedFile" "$destination"
        echo "Created symlink: $destination -> $sharedFile"
      fi
    else
      echo "No .vhd files found in ${1}"
    fi
  done
}

##########################################################################
# links the corresponding ASIC files from the vault/ dir
ghdlLink()
{
  checkFileExists ${RTL}
  rtl_exists=$?

  checkFileExists ${PIX2PGP_PKG}
  pkg_exists=$?

  checkFileExists ${PIX2PGP_ASIC_TOP}
  top_exists=$?

  checkFileExists ${TB}
  tb_exists=$?

  if [[ $1 == *"SparkPixS"* ]]; then
    echo "[INFO]: Preparing for SparkPix-S!"

    if [[ $pkg_exists -eq 1 ]]; then
      echo "[INFO]: Pkg exists! Removing file..."
      rm ${PIX2PGP_PKG}
    fi

    if [[ $top_exists -eq 1 ]]; then
      echo "[INFO]: Top-Level exists! Removing file..."
      rm ${PIX2PGP_ASIC_TOP}
    fi

    if [[ $tb_exists -eq 1 ]]; then
      echo "[INFO]: Tb-Stuff exist! Removing files..."
      rm ${TB}
    fi

    echo "[INFO]: linking firmware/vault/rtl/sparkPixS/SparkPixSPkg.vhd"
    ln -s ${SPARKPIX_S_PKG} ${PIX2PGP_PKG}
    echo "[INFO]: linking firmware/vault/rtl/sparkPixS/Pix2PgpSparkPixSTop.vhd"
    ln -s ${SPARKPIX_S_TOP} ${PIX2PGP_ASIC_TOP_DIR}
    echo "[INFO]: linking Testbench stuff..."
    linkManyFiles ${VAULT_SHARED_TB_DIR} ${TB_DIR}
    linkManyFiles ${SPARKPIX_S_TB_DIR} ${TB_DIR}


  elif [[ $1 == *"SparkPixT"* ]]; then
    echo "[INFO]: Preparing for SparkPix-T!"

    if [[ $pkg_exists -eq 1 ]]; then
      echo "[INFO]: Pkg exists! Removing file..."
      rm ${PIX2PGP_PKG}
    fi

    if [[ $top_exists -eq 1 ]]; then
      echo "[INFO]: Top-Level exists! Removing file..."
      rm ${PIX2PGP_ASIC_TOP}
    fi

    if [[ $tb_exists -eq 1 ]]; then
      echo "[INFO]: Tb-Stuff exist! Removing files..."
      rm ${TB}
    fi

    echo "[INFO]: linking firmware/vault/rtl/sparkPixS/SparkPixSPkg.vhd"
    ln -s ${SPARKPIX_T_PKG} ${PIX2PGP_PKG}
    echo "[INFO]: linking firmware/vault/rtl/sparkPixS/Pix2PgpSparkPixSTop.vhd"
    ln -s ${SPARKPIX_T_TOP} ${PIX2PGP_ASIC_TOP_DIR}
    echo "[INFO]: linking Testbench stuff..."
    linkManyFiles ${VAULT_SHARED_TB_DIR} ${TB_DIR}
    linkManyFiles ${SPARKPIX_T_TB_DIR} ${TB_DIR}

  else
    echo "[ERROR]: Not sourcing any ASIC-specific tesbench!"
    echo "[ERROR]: Please give a valid first argument that contains a valid option of an ASIC name!"
    exit 1
  fi
}


##########################################################################


ghdlAnalyze()
{

##########################################################################
  # analyze the files to make sure their syntax is correct
  echo "List of Files:"
  echo "$(ls ${RTL})"
  echo "$(ls ${PIX2PGP_PKG})"
  echo "$(ls ${PIX2PGP_ASIC_TOP})"
  echo "$(ls ${TB})"
  echo "$(ls ${VAULT_FIFO})"

  echo "[INFO]: Importing RTL Files..."
  ${GHDL_IMPORT_PIX2PGP} ${PIX2PGP_PKG}
  ${GHDL_IMPORT_PIX2PGP} ${RTL}
  ${GHDL_IMPORT_PIX2PGP} ${TB}
  ${GHDL_IMPORT_PIX2PGP} ${PIX2PGP_ASIC_TOP}
  ${GHDL_IMPORT_PIX2PGP} ${VAULT_FIFO}

  echo "[INFO]: Analyzing RTL Files..."
  ${GHDL_ANALYZE} ${PIX2PGP_PKG}
  ${GHDL_ANALYZE} ${RTL}
  ${GHDL_ANALYZE} ${TB}
  ${GHDL_ANALYZE} ${PIX2PGP_ASIC_TOP}
  ${GHDL_ANALYZE} ${VAULT_FIFO}
  echo "[INFO]: Success!"
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
  if [[ -z "$1" ]]; then
    echo "[ERROR]: No arguments are given!"
    echo "[ERROR]: Please give a valid first argument that contains a valid option of an ASIC name!"
    echo "[INFO]:  Valid options: Pix2PgpSparkPixSTopTb, Pix2PgpSparkPixTTopTb"
    echo "[INFO]:  Example: bash ghdlRun.sh Pix2PgpSparkPixSTopTb to prepare for SparkPix-S"
    echo "[INFO]:  Example: bash ghdlRun.sh Pix2PgpSparkPixSTopTb 50 to run the GHDL tb in addition"
    exit 1
  fi

  checkFileExists "$RTL"
  rtlExists=$?
  if [[ $rtlExists -eq 0 ]]; then
    echo "[ERROR]: There are no .vhd files in rtl/."
    echo "[ERROR]: Are you in the right directory? You need to run this from the ghdl/ dir."
    exit 1
  fi

  ghdlPrepare $1
  ghdlAnalyze

  if [[ $# -ge 2 ]]; then
    ghdlTestbench "$1" "$2"
  fi

}

main "$@"

