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
#      clm-userdefined-mac.sh -d /path/to/cesm-inputdata -c ${CASE_DIR} -s configure
#
################################################################################

#!/bin/bash

################################################################################
#
# Read configuration file
#
################################################################################
config_read_file() {
  (grep -E "^${2}=" -m 1 "${1}" 2>/dev/null || echo "VAR=__UNDEFINED__") \
    | head -n 1 | cut -d '=' -f 2-
}

config_get() {
  val="$(config_read_file "$MACHINE_CONFIG_FILE" "${1}")"
  if [ "${val}" = "__UNDEFINED__" ]; then
    val="$2"
  fi
  printf -- "%s" "${val}"
}

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
    # doing dev work on an unsupported machine, always use a debug build
    ./xmlchange -file env_build.xml -id DEBUG -val TRUE
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
    perl -w -i -p -e "s@^sleep@#sleep@" ${CASE_NAME}.run

    setup_clm_user_namelist
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
# reads machine configuration file
#
################################################################################
function read_machine_cfg(){

CC="$(config_get CC)"
CXX="$(config_get CXX)"
FC="$(config_get FC)"
MPICC="$(config_get MPICC)"
MPICXX="$(config_get MPICXX)"
MPIFC="$(config_get MPIFC)"
MPIEXEC="$(config_get MPIEXEC)"
FFLAGS="$(config_get FFLAGS)"
SLIBS="$(config_get SLIBS)"
NETCDF_PATH="$(config_get NETCDF_PATH)"
BLAS_FLAGS="$(config_get BLAS_FLAGS)"
MPI_VENDOR="$(config_get MPI_VENDOR)"

if [ -z "${CC}" ]; then
    echo "ERROR: CC must be defined in the machine configuration file"
    exit
fi

if [ -z "${CXX}" ]; then
    echo "ERROR: CXX must be defined in the machine configuration file"
    exit
fi

if [ -z "${FC}" ]; then
    echo "ERROR: CC must be defined in the machine configuration file"
    exit
fi

if [ -z "${MPICC}" ]; then
    echo "ERROR: MPICC must be defined in the machine configuration file"
    exit
fi

if [ -z "${MPICXX}" ]; then
    echo "ERROR: MPICXX must be defined in the machine configuration file"
    exit
fi

if [ -z "${MPIFC}" ]; then
    echo "ERROR: MPIFC must be defined in the machine configuration file"
    exit
fi

if [ -z "${MPIEXEC}" ]; then
    echo "ERROR: MPIEXEC must be defined in the machine configuration file"
    exit
fi

if [ -z "${FFLAGS}" ]; then
    echo "ERROR: FFLAGS must be defined in the machine configuration file"
    exit
fi

if [ -z "${SLIBS}" ]; then
    echo "ERROR: SLIBS must be defined in the machine configuration file"
    exit
fi

if [ -z "${NETCDF_PATH}" ]; then
    echo "ERROR: NETCDF_PATH must be defined in the machine configuration file"
    exit
fi

if [ -z "${BLAS_FLAGS}" ]; then
    echo "ERROR: BLAS_FLAGS must be defined in the machine configuration file"
    exit
fi

if [ -z "${MPI_VENDOR}" ]; then
    echo "ERROR: MPI_VENDOR must be defined in the machine configuration file"
    exit
fi

}

################################################################################
#
# check the user input
#
################################################################################
function check_pflotran() {
    _valid_pflotran_env=1
    if [ "XXX${PETSC_DIR}" == "XXX" ]; then
        echo "ERROR: PETSC_DIR must be set to link pflotran"
        _valid_pflotran_env=0
    else
        if [ ! -d ${PETSC_DIR} ]; then
            echo "ERROR: PETSC_DIR must be set and point to a valid directory."
            echo "PETSC_DIR = ${PETSC_DIR}"
            _valid_pflotran_env=0
        fi
    fi

    if [ "XXX${PETSC_ARCH}" == "XXX" ]; then
        echo "ERROR: PETSC_ARCH must be set to link pflotran"
        _valid_pflotran_env=0
    else
        if [ ! -d ${PETSC_DIR}/${PETSC_ARCH} ]; then
            echo "ERROR: PETSC_ARCH does not exist inside PETSC_DIR."
            echo "PETSC_DIR = ${PETSC_DIR}"
            echo "PETSC_ARCH = ${PETSC_ARCH}"
            _valid_pflotran_env=0
        fi
    fi

    if [ "XXX${PFLOTRAN_DIR}" == "XXX" ]; then
        echo "ERROR: PFLOTRAN_DIR must be set to link pflotran"
        _valid_pflotran_env=0
    else
        if [ ! -d ${PFLOTRAN_DIR} ]; then
            echo "ERROR: PFLOTRAN_DIR does not exist."
            echo "PFLOTRAN_DIR = ${PFLOTRAN_DIR}"
            _valid_pflotran_env=0
        fi

        if [ ! -f ${PFLOTRAN_DIR}/src/clm-pflotran/libpflotran.a ]; then
            echo "ERROR: \${PFLOTRAN_DIR}/src/clm-pflotran/libpflotran.a must be built."
        fi
    fi

    if [ ${_valid_pflotran_env} != 1 ]; then
        echo "ERROR: invalid pflotran environment. exiting."
        exit 1
    else
        echo "pflotran environment:"
        echo "    PETSC_DIR=${PETSC_DIR}"
        echo "    PETSC_ARCH=${PETSC_ARCH}"
        echo "    PFLOTRAN_DIR=${PFLOTRAN_DIR}"
    fi
}

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
        create_macros_file
    elif [ "${OVERWRITE}" == "Macros" ]; then
        echo "WARNING: overwriting existing Macro's file!"
        create_macros_file
    else
        echo "  Using existing Macros file."
    fi

    if [ ! -f ${CASE_DIR}/Macros ]; then
        echo "ERROR: could not create Macros file...?"
        exit
    fi
}

function create_macros_file() {
    if [ ! -z ${MACRO_FILE} ]; then
        MACRO_FILE=$(abspath ${MACRO_FILE})
        ln -s ${MACRO_FILE} ${CASE_DIR}/Macros
        echo "  Linking command line Macros file into case."
    else
        macros_from_template
    fi
}

function macros_from_template() {
    echo "  Creating new userdefined Macros file from template."
    _petsc_include=
    _user_include=
    _user_fflags=
    _user_ldflags=
    if [ ! -z ${LINK_PFLOTRAN} ]; then
        _petsc_include='include ${PETSC_DIR}/conf/variables'
        _user_include='-I${PETSC_DIR}/${PETSC_ARCH}/include -I${PETSC_DIR}/include -I${PFLOTRAN_DIR}/src/clm-pflotran'
        _user_fflags=-DCLM_PFLOTRAN
        _user_ldflags='${PFLOTRAN_DIR}/src/clm-pflotran/libpflotran.a -L${PETSC_DIR}/${PETSC_ARCH}/lib $(PETSC_LIB) -lnetcdff -lnetcdf'
    fi
    cat > ${CASE_DIR}/Macros <<EOF
#
# Makefile Macros generated from clm4_5_04/scripts/ccsm_utils/Machines/config_compilers.xml using
# COMPILER=gnu
# OS=Darwin
# MACH=userdefined
#

${_petsc_include}

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
USER_INCLDIR:=${_user_include}
FFLAGS+=${_user_fflags}
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
   LDFLAGS += ${_user_ldflags}
   # mac os blas/lapack
   LDFLAGS += ${BLAS_FLAGS}
endif

EOF

}

function setup_clm_user_namelist() {
    if [ ! -z ${LINK_PFLOTRAN} ]; then
        echo "Adding pflotran flags to user_nl_clm"
        cat >> ${CASE_DIR}/user_nl_clm <<EOF
use_pflotran = .true.

&clm_pflotran_inparm
    pflotran_prefix = "${CASE_NAME}"
/
EOF
    fi

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
    -m FILENAME     link to existing macros file instead of generating
    -M FILENAME     machine configuration file
    -n NP           number of mpi processors
    -o FILENAME     over write existing file FILENAME
    -p              add petsc/pflotran info to Macros
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
LINK_PFLOTRAN=
OVERWRITE=
MACHINE_CONFIG_FILE=
while getopts "c:d:hm:M:n:o:ps:" FLAG
do
  case ${FLAG} in
    c) CASE_DIR=${OPTARG};;
    d) DATA_DIR=${OPTARG};;
    h) usage; exit;;
    m) MACRO_FILE=${OPTARG};;
    M) MACHINE_CONFIG_FILE=${OPTARG};;
    n) NP=${OPTARG};;
    o) OVERWRITE=${OPTARG};;
    p) LINK_PFLOTRAN=1;;
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

if [ ! -z ${LINK_PFLOTRAN} ]; then
    check_pflotran
fi

if [ -z "${MACHINE_CONFIG_FILE}" ]; then
    echo "ERROR: The machine configuration file must be provided on the command line."
    exit
else
    read_machine_cfg
fi


DATA_DIR=$(abspath ${DATA_DIR})
CASE_DIR=$(abspath ${CASE_DIR})
CASE_NAME=`basename ${CASE_DIR}`

echo "Configuring userdefined machine using:"
echo "    CASE_DIR = ${CASE_DIR}"
echo "    CASE_NAME = ${CASE_NAME}"
echo "    DATA_DIR = ${DATA_DIR}"
echo "    linking pflotran in macros = ${LINK_PFLOTRAN}"
echo "    overwrite = ${OVERWRITE}"

check_data_dir
check_case

case ${BUILD_STEP} in
    all) clobber; configure_step; build_step;;
    clobber) clobber_step;;
    configure) configure_step;;
    build) build_step;;
    *) echo "ERROR: The requested build stage '${BUILD_STEP}' is invalid."; exit;;
esac
