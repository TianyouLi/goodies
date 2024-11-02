#!/bin/bash

CUR_DIR=`pwd`
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

usage() {
    echo "Usage: $0
    	 	 [-d database dir] 
                 [-h help]";
    exit 1;
}

while getopts ":d:h:" o; do
    case "${o}" in
        d)
            DB_DIR=${OPTARG}
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

if [ -z "${DB_DIR}" ]; then
    DB_DIR=${CUR_DIR}
elif [ ! -d "$DB_DIR" ]; then
    DB_DIR=${CUR_DIR}/${DB_DIR}
    mkdir -p ${DB_DIR}
fi

DB_DIR=$( cd "${DB_DIR}" && pwd )
cd ${DB_DIR}

# download file if necessary, cached in db dir
if [ ! -f "hits_v1.tsv" ]; then
        echo "Download test database..."
        wget https://datasets.clickhouse.com/hits/tsv/hits_v1.tsv.xz
        wget https://datasets.clickhouse.com/visits/tsv/visits_v1.tsv.xz
        wget https://datasets.clickhouse.com/hits/tsv/hits_100m_obfuscated_v1.tsv.xz

        xz -v -d hits_v1.tsv.xz
        xz -v -d visits_v1.tsv.xz
        xz -v -d hits_100m_obfuscated_v1.tsv.xz
fi

if [ ! -f "hits.tsv" ]; then
	echo "Download test database..."
    wget --continue 'https://datasets.clickhouse.com/hits_compatible/hits.tsv.gz'
    gzip -d hits.tsv.gz
fi


echo "Database downloaded."
