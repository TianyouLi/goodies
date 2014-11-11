#!/bin/bash

HOME=/root
PS1="root@host"

# start proxy
/etc/init.d/privoxy restart
netstat -l

# set alias
export aptool="apt-get -q -y"

# import env
. /root/.bashrc
export

