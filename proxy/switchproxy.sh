#!/bin/bash

if [ -z "${PROXY_NAME}" ]; then
		PROXY_NAME="default"
fi

if [ "${PROXY_NAME}" == "default" ]; then
    CURRENT_NAME="google gerrit"
fi

if [ "${PROXY_NAME}" == "google gerrit" ]; then
    CURRENT_NAME="default"
fi

export PROXY_NAME=${CURRENT_NAME}

if [ "$PROXY_NAME" == "default" ]; then
		http_proxy="http://child-prc.intel.com:913"
		https_proxy=${http_proxy}
fi

if [ "$PROXY_NAME" == "google gerrit" ]; then
		http_proxy="http://shiyuzha:900812_Y@child-prc.intel.com:914"
		https_proxy=${http_proxy}
fi

export http_proxy
export https_proxy

git config --global http.proxy ${http_proxy}
git config --global https.proxy ${https_proxy}

echo "Proxy Name: ${PROXY_NAME}"
echo "http_proxy=${http_proxy}"
echo "https_proxy=${https_proxy}"
echo "git config http.proxy  " `git config http.proxy`
echo "git config https.proxy " `git config https.proxy`
