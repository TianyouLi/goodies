#!/bin/sh
HOME=/root
PS1="root@host"
export aptool="apt-get -q -y"

sudo /etc/init.d/privoxy restart
export http_proxy="http://localhost:8118"
export https_proxy=$http_proxy

echo "
deb http://archive.ubuntu.com/ubuntu/ precise multiverse
deb-src http://archive.ubuntu.com/ubuntu/ precise multiverse
" | tee -a /etc/apt/sources.list

${aptool} update

# install lsb-release, not default installed on 12.04
${aptool} install lsb-release

# install msttcorefonts
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections
${aptool} install ttf-mscorefonts-installer

export PATH=/home/lity/chromium/depot_tools:$PATH
ls /home/lity/chromium
cd /home/lity/chromium/src
git checkout master
build/install-build-deps.sh --syms --no-arm --no-chromeos-fonts --no-prompt

gclient sync

