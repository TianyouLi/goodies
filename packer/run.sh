#!/bin/bash

# launch privoxy
/etc/init.d/privoxy start

# last: lauch sshd
/usr/sbin/sshd -D

