#!/bin/bash

CUR_DIR=`pwd`
SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

usage() {
    echo "Usage: $0
		 [-b build_dir]
		 [-p port]
		 [-c config_dir]
                 [-h help]";
    exit 1;
}

while getopts ":p:b:h:" o; do
    case "${o}" in
        p)
            PORT=${OPTARG}
            ;;
        b)
            BLD_DIR=${OPTARG}
            ;;
	c)
	    CONF_DIR=${OPTARG}
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
BLD_DIR=$( cd "${BLD_DIR}" && pwd)


if [ -z "${PORT}" ]; then
    PORT=9000
fi

if [ -z "${CONF_DIR}" ]; then
    CONF_DIR=${SCRIPT_DIR}/../config
fi

CONFIG_FILE=${CONF_DIR}/config.xml
BIN_FILE=${BLD_DIR}/programs/clickhouse-server
if [ ! -f ${BIN_FILE} ]; then
    echo "Can not find the binary file at ${BIN_FILE}"
    exit 1
fi


SESSION_NAME="clickhouse"

# create the tmux session if not exist
! tmux has-session -t ${SESSION_NAME} && tmux new-session -s ${SESSION_NAME} -d

# find the window exist or not
WINDOW_NAME=$( tmux list-windows -t clickhouse -F "#{window_name}" -f "#{m:${PORT},#{window_name}}")
if [ ! -z "${WINDOW_NAME}" ]; then
    echo "The clickhouse server bind to ${PORT} already exist in tmux session ${SESSION_NAME}, please check"
    exit 1
fi


# create a new window and launch the server
WINDOW_NO=$( tmux list-windows -t clickhouse | wc -l )
WINDOW_NO=$((${WINDOW_NO} + 1))
tmux new-window -t ${SESSION_NAME}:${WINDOW_NO} -n "${PORT}"


echo "Launch ${BIN_FILE} server at ${PORT} with ${CONFIG_FILE} on tmux session ${SESSION_NAME}:${WINDOW_NO} ..."
tmux send-keys -t ${SESSION_NAME}:${WINDOW_NO} "cd ${BLD_DIR} && ${BIN_FILE} --config-file=${CONFIG_FILE} -- --tcp_port \"${PORT}\" 2>&1 | tee console_${PORT}.log | grep \"error\"" C-m

