#!/bin/sh
HOME=/root
PS1="root@host"

sudo /etc/init.d/privoxy restart
. /home/lity/.bashrc
export http_proxy="http://localhost:8118"
export socks_proxy="proxy.jf.intel.com:1080"
export all_proxy=${socks_proxy}
export ftp_proxy=${http_proxy}
export https_proxy=${http_proxy}
export RSYNC_PROXY=${http_proxy}
export no_proxy=".intel.com,.jf.intel.com,.sh.intel.com"
export GIT_PROXY_COMMAND=/usr/local/bin/socks-git
export PATH=/home/lity/chromium/depot_tools:$PATH
export

cd /home/lity/chromium
fetch --nohooks chromium

