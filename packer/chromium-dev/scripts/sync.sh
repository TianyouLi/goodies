#!/bin/sh
HOME=/root
PS1="root@host"
export aptool="apt-get -q -y"

sudo /etc/init.d/privoxy restart
export http_proxy="http://localhost:8118"
export https_proxy=$http_proxy

export PATH=/home/lity/depot_tools:$PATH
ls /home/lity/chromium
cd /home/lity/chromium/src
git checkout master
build/install-build-deps.sh --syms --no-arm --no-chromeos-fonts --no-prompt

gclient sync

