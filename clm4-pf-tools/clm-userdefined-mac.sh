#!/bin/bash
################################################################################
#
# Script to setup a clm case on Mac OS X
#
# Author: Ben Andre <bandre@lbl.gov>
#
#  README:
#
#    - The purpose of this script is to make development easier by
#      working locally for initial debugging and testing. Your laptop
#      or workstation are NOT "production" machines, and all formal
#      testing and production (i.e. science) should be done on a
#      supported machine!
#
#    - This will only work with CLM offline. It will NOT work with the
#      fully coupled model. The darwin related flags in cam are
#      broken, and there is a duplicate module name that will prevent
#      linking. These can be fixed, but requires invasive changes to
#      the code that need to be cleared with the module owners at
#      NCAR.
#
#    - You must apply the clang-isnan patch to the source. This patch
#      has not been cleared by NCAR, so it should only be done
#      locally.
#
#    - Strange issues can crop up linking if you have different
#      version of the compilers compiling different libraries. To
#      simplify life, it is HIGHLY RECOMMENDED that you mpich,
#      gfortran and netcdf installed through macports. Other compilers
#      and mpi libraries SHOULD work, but will require debugging.
#
#  USE:
#
#    - install netcdf and mpich based on gfortran-4.7+ from mac ports:
#
#      sudo port install mpich +gcc47 hdf5-18 +mpich netcdf-fortran +gcc47 +mpich
#
#    - Some of the shell scripts used by clm/cesm hard code "gmake"
#      instead of using the GMAKE variable from env_build.xml. To work
#      around this, you should create a link to gmake in you path.
#
#      mkdir -p ${HOME}/local/bin
#      ln -s `whereis make` ${HOME}/local/bin/gmake
#      vi ${HOME}/.bashrc
#          export PATH=${PATH}:${HOME}/local/bin
#
#    - Create a directory for the local copy of the cesm input data:
#
#      mkdir -p /path/to/cesm-inputdata
#
#      You should plan on downloading ~30 GB of data
#
#    - apply the clang-isnan patch to the source.
#
#    - Create a new case based on the following command. You must
#      select compiler = gnu and mach = userdefined, adjust the
#      remaining flags as desired:
#
#      ./create_newcase \
#          -mach userdefined \
#          -compiler gnu \
#          -case ${WORK_DIR}/${CASE_NAME} \
#          -compset ICLM45CN \
#          -res f45_f45
#
#    - This script will create a Macros file for you. If you have a
#    - previously tweaked file, create a link in your case directory:
#
#      ln -s /path/to/Macros ${CASE_DIR}/Macros
#
#    - setup the user defined machine:
#
#      clm-mac-workstation.sh -d /path/to/cesm-inputdata -c ${CASE_DIR} -s configure
#
################################################################################

################################################################################
#
# Hard coded paths assuming macports
#
################################################################################
CC=/usr/bin/clang
CXX=/usr/bin/clang++
FC=/opt/local/bin/gfortran-mp-4.7
MPICC=/opt/local/bin/mpicc
MPICXX=/opt/local/bin/mpicxx
MPIFC=/opt/local/bin/mpif90
MPIEXEC=/opt/local/bin/mpirun
MPI_VENDOR=mpich

FFLAGS="-fno-range-check"
SLIBS="-L/opt/local/lib -lnetcdff -L/opt/local/lib -lnetcdf"
NETCDF_PATH="/opt/local"
LDFLAGS="-framework Accelerate"



################################################################################
#
# Functions to modify the case files
#
################################################################################
function modify_env_build() {
    ./xmlchange -file env_build.xml -id OS -val Darwin
    ./xmlchange -file env_build.xml -id COMPILER -val gnu
    ./xmlchange -file env_build.xml -id MPILIB -val ${MPI_VENDOR}
    ./xmlchange -file env_build.xml -id EXEROOT -val ${CASE_DIR}/bld
    ./xmlchange -file env_build.xml -id SUPPORTED_BY -val ${USER}
    ./xmlchange -file env_build.xml -id GMAKE -val make
}

function modify_env_mach_pes() {
    ./xmlchange -file env_mach_pes.xml -id NTASKS_ATM -val ${NP}
    ./xmlchange -file env_mach_pes.xml -id NTASKS_LND -val ${NP}
    ./xmlchange -file env_mach_pes.xml -id NTASKS_ICE -val ${NP}
    ./xmlchange -file env_mach_pes.xml -id NTASKS_OCN -val ${NP}
    ./xmlchange -file env_mach_pes.xml -id NTASKS_CPL -val ${NP}
    ./xmlchange -file env_mach_pes.xml -id NTASKS_GLC -val ${NP}
    ./xmlchange -file env_mach_pes.xml -id NTASKS_ROF -val ${NP}
    ./xmlchange -file env_mach_pes.xml -id NTASKS_WAV -val ${NP}
    ./xmlchange -file env_mach_pes.xml -id MAX_TASKS_PER_NODE -val ${NP}
    ./xmlchange -file env_mach_pes.xml -id TOTALPES -val ${NP}
}

function modify_env_run() {
    ./xmlchange -file env_run.xml -id RUNDIR -val ${CASE_DIR}/run
    ./xmlchange -file env_run.xml -id DIN_LOC_ROOT -val ${DATA_DIR}
    ./xmlchange -file env_run.xml -id DIN_LOC_ROOT_CLMFORC -val '$DIN_LOC_ROOT'
}


function configure_step() {

    cd ${CASE_DIR}

    mkdir -p bld
    mkdir -p run

    check_macros

    modify_env_build
    modify_env_mach_pes
    modify_env_run

    # create the run script
    ./cesm_setup
    perl -w -i -p -e "s@#mpirun@${MPIEXEC}@" ${CASE_NAME}.run
}

function build_step() {
    cd ${CASE_DIR}

    ./${CASE_NAME}.clean_build
    ./${CASE_NAME}.build
}

function clobber_step() {
    cd ${CASE_DIR}
    ./${CASE_NAME}.clean_build
    ./cesm_setup -clean
    rm -rf bld
    rm -rf run
}

################################################################################
#
# check the user input
#
################################################################################
function check_data_dir() {
    if [ ! -d ${DATA_DIR} ]; then
        echo "ERROR: The cesm inputdata directory does not exist: '${DATA_DIR}'"
        exit
    fi
}

function check_case() {
    # check that the case exists and was set up correctly...
    if [ ! -d ${CASE_DIR} ]; then
        echo "ERROR: The case directory does not exist: '${CASE_DIR}'"
        exit
    fi

    if [ ! -f ${CASE_DIR}/CaseStatus ] ; then
        echo "ERROR: The directory '${CASE_DIR}' is missing the CaseStatus file. Has the new case been created correctly?"
        exit
    fi

    if [ ! -f ${CASE_DIR}/${CASE_NAME}.build ] ; then
        echo "ERROR: The directory '${CASE_DIR}' is missing the ${CASE_NAME}.build script. Has the new case been created correctly?"
        exit
    fi
}

function check_macros() {
    # check if the user already provided a Macros file, create it if
    # necessary. We do NOT want to automatically override in case the
    # user has modified something!
    if [ ! -f ${CASE_DIR}/Macros ]; then
        if [ ! -z ${MACRO_FILE} ]; then
            MACRO_FILE=$(abspath ${MACRO_FILE})
            ln -s ${MACRO_FILE} ${CASE_DIR}/Macros
            echo "  Linking command line Macros file into case."
        else
            create_macros_file
        fi
    else
        echo "  Using existing Macros file."
    fi

    if [ ! -f ${CASE_DIR}/Macros ]; then
        echo "ERROR: could not create Macros file...?"
        exit
    fi
}

function create_macros_file() {
    echo "  Creating new userdefined Macros file from template."
    cd ${CASE_DIR}
    cat > Macros <<EOF
#
# Makefile Macros generated from clm4_5_04/scripts/ccsm_utils/Machines/config_compilers.xml using
# COMPILER=gnu
# OS=Darwin
# MACH=userdefined
#
CPPDEFS+= -DFORTRANUNDERSCORE -DNO_R16 -DSYSDARWIN  -DDarwin -DCPRGNU

#SLIBS+=# USERDEFINED \$(shell \$(NETCDF_PATH)/bin/nc-config --flibs)
SLIBS+=${SLIBS}

CONFIG_ARGS:=

CXX_LINKER:=FORTRAN

ESMF_LIBDIR:=

FC_AUTO_R8:= -fdefault-real-8

FFLAGS:= -O -fconvert=big-endian -ffree-line-length-none -ffixed-line-length-none
FFLAGS+=${FFLAGS}

FFLAGS_NOOPT:= -O0

FIXEDFLAGS:=  -ffixed-form

FREEFLAGS:= -ffree-form

MPICC:=${MPICC}

MPICXX:=${MPICXX}

MPIFC:=${MPIFC}

MPI_LIB_NAME:=

MPI_PATH:=

NETCDF_PATH:=${NETCDF_PATH}

PNETCDF_PATH:=

SCC:=${CC}

SCXX:=${CXX}

SFC:=${FC}

SUPPORTS_CXX:=TRUE

# linking to external libraries...
USER_INCLDIR:=
LDFLAGS +=

ifeq (\$(DEBUG), TRUE)
   FFLAGS += -g -Wall
endif

ifeq (\$(compile_threaded), true)
   LDFLAGS += -fopenmp
   CFLAGS += -fopenmp
   FFLAGS += -fopenmp
endif

ifeq (\$(MODEL), cism)
   CMAKE_OPTS += -D CISM_GNU=ON
endif

ifeq (\$(MODEL), driver)
   LDFLAGS += -all_load
   # mac os blas/lapack
   LDFLAGS += ${LDFLAGS}
   # NOTE(bandre): ugly hack to get around linking error...
   LDFLAGS += ${CASE_DIR}/bld/lib/libice.a
endif

EOF

}

################################################################################
#
# helper routines
#
################################################################################

function usage() {
    echo "
Usage: $0 [options]
    -c CASE_NAME    set the case name
    -d DATA_DIR     cesm input data directory
    -h              print this help message
    -n NP           number of mpi processors
    -s BUILD_STAGE  build stage must be one of:
                        clobber configure build all

Notes:

  This script is used to: set the userdefined machine variables in
  env_build.xml, env_machine_pes.xml, and env_run.xml. It creates a
  Macros file with the correct compilers and paths based on a
  template. It also calls cesm_setup and then modifies the run script
  to set the correct mpiexec.

  Assumes:

    - using gfortran and apple clang

    - you are using netcdf and mpich installed by mac ports

  Requires:

    - you have already called scripts/create_newcase with:
      '-mach userdefined -compiler gnu'

    - run and build files will be added to the case directory as:

           /path/to/CASE_DIR/run

           /path/to/CASE_DIR/bld

    - A Macros file will be created based on the above assumptions

"
}

function abspath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

################################################################################
#
# main program
#
################################################################################


# setup based on commandline args
BUILD_STEP=
CASE_DIR=
DATA_DIR=
MACRO_FILE=
NP=2
while getopts "c:d:hm:n:s:" FLAG
do
  case ${FLAG} in
    c) CASE_DIR=${OPTARG};;
    d) DATA_DIR=${OPTARG};;
    h) usage; exit;;
    m) MACRO_FILE=${OPTARG};;
    n) NP=${OPTARG};;
    s) BUILD_STEP=${OPTARG};;
  esac
done

# verify all required info is set
if [ -z "${CASE_DIR}" ]; then
    echo "ERROR: The case directory name must be provided on the command line."
    exit
fi

if [ -z "${DATA_DIR}" ]; then
    echo "ERROR: The cesm input data directory name must be provided on the command line."
    exit
fi

DATA_DIR=$(abspath ${DATA_DIR})
CASE_DIR=$(abspath ${CASE_DIR})
CASE_NAME=`basename ${CASE_DIR}`

echo "Configuring userdefined machine using:"
echo "    CASE_DIR = ${CASE_DIR}"
echo "    CASE_NAME = ${CASE_NAME}"
echo "    DATA_DIR = ${DATA_DIR}"

check_data_dir
check_case
check_macros

case ${BUILD_STEP} in
    all) clobber; configure_step; build_step;;
    clobber) clobber_step;;
    configure) configure_step;;
    build) build_step;;
    *) echo "ERROR: The requested build stage '${BUILD_STEP}' is invalid."; exit;;
esac