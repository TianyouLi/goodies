#!/bin/bash

CUR_DIR=`pwd`
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

usage() {
    echo "Usage: $0
    	 	 [-s source_dir <default current dir>] 
                 [-t tag <default master>]
                 [-b build_dir <default source_dir/buidl_tag]
                 [-h help]";
    exit 1;
}

while getopts ":t:s:b:h:" o; do
    case "${o}" in
        t)
            TAG=${OPTARG}
            ;;
        s)
            SRC_DIR=${OPTARG}
            ;;
	b)
	    BLD_DIR=${OPTARG}
	    ;;
	h)
	    usage
	    ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${TAG}" ]; then
    TAG="master"
fi


if [ -z "${SRC_DIR}" ]; then
    SRC_DIR=${CUR_DIR}
fi

if [ ! -d ${SRC_DIR} ]; then
    SRC_DIR=${CUR_DIR}/${SRC_DIR};
fi

if [ ! -d ${SRC_DIR} ]; then
    echo "Can not find clickhouse source directory";
    exit 1;
fi

SRC_DIR=$(cd "${SRC_DIR}" && pwd)

if [ -z "${BLD_DIR}" ]; then
    BLD_DIR=${CUR_DIR}/${TAG}
fi

mkdir -p ${BLD_DIR}
BLD_DIR=$(cd "${BLD_DIR}" && pwd)

echo "Build ${SRC_DIR} on directory ${BLD_DIR} with tag ${TAG}"

cd ${SRC_DIR}
git checkout ${TAG}
git submodule update --init 
git submodule sync --recursive


export CC=clang CXX=clang++
mkdir -p ${BLD_DIR}
cmake -S . -B ${BLD_DIR}
ninja -C ${BLD_DIR} -j $(nproc --all)


cd ${CUR_DIR}
