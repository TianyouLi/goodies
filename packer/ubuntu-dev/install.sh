#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
export http_proxy="http://proxy01.cd.intel.com:911"
export https_proxy=${http_proxy}
export aptool="apt-get -q -y"

# update to latest version
${aptool} update
${aptool} upgrade
${aptool} install apt-utils

# install ssh
${aptool} install openssh-server openssh-client

# install other tools
${aptool} install git-core gitk git-gui subversion curl g++

# install proxy
${aptool} install privoxy

# install emacs
${aptool} install emacs

# install net-tools
${aptool} install net-tools
${aptool} install sockstat

# install pip
${aptool} install python-pip

# install tmux
${aptool} install tmux

# install ping
${aptool} install iputils-ping

# install xslt processor
${aptool} install syslinux
${aptool} install openjdk-7-jre
${aptool} install libsaxonb-java

# install make tools
${aptool} install make

# install sudo tools
${aptool} install sudo

# change root password
echo 'root:123456' | chpasswd

# create directory for sshd
mkdir -p /var/run/sshd

