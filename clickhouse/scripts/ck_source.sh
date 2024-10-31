#!/bin/bash 

CUR_DIR=`pwd`
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

if [ -z "$1" ]; then
    SRC_DIR=${CUR_DIR}/clickhouse
else
    SRC_DIR=${1}
fi

CK_DIR=${SRC_DIR}
git clone https://github.com/TianyouLi/ClickHouse.git ${CK_DIR}

cd ${CK_DIR}
git remote add upstream git@github.com:ClickHouse/ClickHouse.git

cd ${CUR_DIR}
