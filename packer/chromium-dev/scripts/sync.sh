#!/bin/sh
sudo /etc/init.d/privoxy restart
export http_proxy="http://localhost:8118"
export https_proxy=$http_proxy

export PATH=/home/lity/depot_tools:$PATH
ls /home/lity
cd /home/lity/src
git checkout master
build/install-build-deps.sh --syms --no-arm --no-chromeos-fonts --no-nacl --no-prompt

gclient sync

