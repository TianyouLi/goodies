#!/bin/bash 

CUR_DIR=`pwd`
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

usage() {
    echo "Usage: $0
                 [-s source_dir]
                 [-h help]";
    exit 1;
}

while getopts ":s:h:" o; do
    case "${o}" in
        b)
            SRC_DIR=${OPTARG}
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


if [ -z "${SRC_DIR}" ]; then
    SRC_DIR=${CUR_DIR}/clickhouse
fi

if [ ! -d "${BLD_DIR}" ]; then
    SRC_DIR=${CUR_DIR}/${SRC_DIR}
fi


CK_DIR=${SRC_DIR}
git clone https://github.com/TianyouLi/ClickHouse.git ${CK_DIR}

cd ${CK_DIR}
git remote add upstream git@github.com:ClickHouse/ClickHouse.git

cd ${CUR_DIR}
