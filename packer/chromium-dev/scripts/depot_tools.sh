#!/bin/sh
HOME=/root
PS1="root@host"
export aptool="apt-get -q -y"

sudo /etc/init.d/privoxy restart
export http_proxy="http://localhost:8118"
export https_proxy=$http_proxy

git config -f /home/lity/.gitconfig  user.name "Tianyou Li"
git config -f /home/lity/.gitconfig  user.email "tianyou.li@gmail.com"
git config -f /home/lity/.gitconfig  core.autocrlf false
git config -f /home/lity/.gitconfig  core.filemode false
git config -f /home/lity/.gitconfig  branch.autosetuprebase always

mkdir -p /home/lity/chromium
cd /home/lity/chromium
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git

echo "export PATH=/home/lity/depot_tools:$PATH\n" >> /home/lity/.bashrc
