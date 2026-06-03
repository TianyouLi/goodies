#!/bin/bash

CUR_DIR=`pwd`
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

usage() {
    echo "Usage: $0
    	 	 [-d database dir]
		 [-b build dir]
		 [-p clickhouse instance port] 
                 [-h help]";
    exit 1;
}

while getopts ":d:b:p:h:" o; do
    case "${o}" in
        d)
            DB_DIR=${OPTARG}
            ;;
	p)
	    PORT=${OPTARG}
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


if [ -z "${DB_DIR}" ]; then
    DB_DIR=${CUR_DIR}
fi

if [ ! -d "${DB_DIR}" ]; then
    DB_DIR=${CUR_DIR}/${DB_DIR}
fi

if [ ! -d "${DB_DIR}" ]; then
    echo "Database dir ${DBDIR} does not exist."
    exit 1
fi

if [ -z "${BLD_DIR}" ]; then
    BLD_DIR=${CUR_DIR}
fi

DB_DIR=$( cd "${DB_DIR}" && pwd)
BLD_DIR=$( cd "${BLD_DIR}" && pwd)

CK_BIN=${BLD_DIR}/programs/clickhouse-client
if [ ! -f ${CK_BIN} ]; then
    echo "Clickhouse client binary does not exist."
    exit 1
fi

if [ -z "${PORT}" ]; then
    PORT=9000
fi

if [ ! -f "${DB_DIR}/hits_v1.tsv" ]; then
    echo "Table data does not exist."
    exit 1
fi


SQL_FILE=$SCRIPT_DIR/sql/test_db_setup.sql
echo "Create tables with command ${CK_BIN} --port $PORT --multiquery < $SQL_FILE"
${CK_BIN} --port $PORT --multiquery < $SQL_FILE

echo "Import ${CK_BIN} --port $PORT --max_insert_block_size 100000 --query \"INSERT INTO test.hits FORMAT TSV\" < ${DB_DIR}/hits_v1.tsv"
${CK_BIN} --port $PORT --max_insert_block_size 100000 --query "INSERT INTO test.hits FORMAT TSV" < ${DB_DIR}/hits_v1.tsv

echo "Import ${CK_BIN} --port $PORT --max_insert_block_size 100000 --query \"INSERT INTO test.visits FORMAT TSV\" < ${DB_DIR}/visits_v1.tsv"
${CK_BIN} --port $PORT --max_insert_block_size 100000 --query "INSERT INTO test.visits FORMAT TSV" < ${DB_DIR}/visits_v1.tsv

echo "Import ${CK_BIN} --port $PORT --max_insert_block_size 100000 --query \"INSERT INTO hits_100m_single FORMAT TSV\" < ${DB_DIR}/hits_100m_obfuscated_v1.tsv"
${CK_BIN} --port $PORT --max_insert_block_size 100000 --query "INSERT INTO hits_100m_single FORMAT TSV" < ${DB_DIR}/hits_100m_obfuscated_v1.tsv


SQL_FILE=$SCRIPT_DIR/../benchmarks/clickbench/table_setup.sql
echo "Create tables with command ${CK_BIN} --port $PORT --multiquery < $SQL_FILE"
${CK_BIN} --port $PORT --multiquery < $SQL_FILE

echo "Import ${CK_BIN} --port $PORT --time --query \"INSERT INTO hits FORMAT TSV\" < ${DB_DIR}/hits.tsv"
${CK_BIN} --port $PORT --time --query "INSERT INTO hits FORMAT TSV" < ${DB_DIR}/hits.tsv

