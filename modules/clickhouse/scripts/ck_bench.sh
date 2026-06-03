#!/bin/bash

CUR_DIR=`pwd`
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

usage() {
    echo "Usage: $0
                 [-b build_dir]
		 [-p port]
		 [-q query]
		 [-i iterations]
                 [-h help]";
    exit 1;
}

while getopts ":b:p:q:i:h:" o; do
    case "${o}" in
        b)
            BLD_DIR=${OPTARG}
            ;;
        p)
            PORT=${OPTARG}
            ;;
	q)
	    QUERY=${OPTARG}
	    ;;
	i)
	    ITERATIONS=${OPTARG}
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

if [ -z "${BLD_DIR}" ]; then
    BLD_DIR=${CUR_DIR}
fi

if [ ! -d "${BLD_DIR}" ]; then
    BLD_DIR=${CUR_DIR}/${BLD_DIR}
fi

if [ ! -d "${BLD_DIR}" ]; then
    echo "Build dir ${BLD_DIR} does not exist."
    exit 1
fi

if [ -z "${PORT}" ]; then
    PORT=9000
fi

if [ -z "${ITERATIONS}" ]; then
    ITERATIONS=10
fi


BLD_DIR=$( cd "${BLD_DIR}" && pwd)
CK_BIN=${BLD_DIR}/programs/clickhouse-benchmark
if [ ! -f ${CK_BIN} ]; then
    echo "Clickhouse benchmark binary does not exist."
    exit 1
fi

if [ -z "${QUERY}" ]; then
    QUERY="select \"Hello World\"";
else
    QUERY=`cat ${SCRIPT_DIR}/../benchmarks/${QUERY} | tr '\n' ' '`
fi

echo -e "Will bencmark query ${ITERATIONS} times: \n\t ${QUERY}"

${CK_BIN} --port ${PORT} -i ${ITERATIONS} -q "${QUERY}" 
