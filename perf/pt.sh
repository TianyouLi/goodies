#!/bin/sh

CUR_DIR=`pwd`
SCR_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )


if [[ $# -lt 2 ]]
then
    echo -e "Not enough arguments($#): $0 [PLATFORM] [CMD] eg.\n\
    	      pt.sh spr.opt1 find . -iname *"
    exit 1
fi

# usually platform.optimization, eg. spr.opt1
FOLDER=${CUR_DIR}/$1
mkdir -p ${FOLDER}
shift

CMD=$(printf " %q" "${@}")
SURFIX=`echo ${CMD// /_}`

echo "Executing ${CMD}"


# hotspot analysis
HOTSPOTDATA=${FOLDER}/perf.hotspot.${SURFIX}.data
HOTSPOTLOG=${FOLDER}/perf.hotspot.${SURFIX}.log
HOTSPOT_OUTPUT_NO_CALLGRAPH=${FOLDER}/perf.hotspot.${SURFIX}.nocg.txt
HOTSPOT_OUTPUT_CALLGRAPH=${FOLDER}/perf.hotspot.${SURFIX}.cg.txt

bash -c "perf record -a -g -e cycles:pp,instructions:pp -o ${HOTSPOTDATA} ${CMD} | tee ${HOTSPOTLOG}"

bash -c "perf report -i ${HOTSPOTDATA} --comm=spawn --percentage relative --no-children --call-graph none --stdio > ${HOTSPOT_OUTPUT_NO_CALLGRAPH}"
bash -c "perf report -i ${HOTSPOTDATA} --comm=spawn --percentage relative --stdio                                 > ${HOTSPOT_OUTPUT_CALLGRAPH}"


# c2c analysis
C2CDATA=${FOLDER}/perf.c2c.${SURFIX}.data
C2CLOG=${FOLDER}/perf.c2c.${SURFIX}.log

bash -c "perf c2c record -a -g -o ${C2CDATA} ${CMD} | tee ${C2CLOG}"

C2C_OUTPUT_NO_CALLGRAPH=${FOLDER}/perf.c2c.${SURFIX}.nocg.txt
C2C_OUTPUT_CALLGRAPH=${FOLDER}/perf.c2c.${SURFIX}.cg.txt
bash -c "perf c2c report  -i ${C2CDATA} --call-graph none --stdio  > ${C2C_OUTPUT_NO_CALLGRAPH}"
bash -c "perf c2c report  -i ${C2CDATA}                   --stdio  > ${C2C_OUTPUT_CALLGRAPH}"

