#!/bin/bash

# launch privoxy
/etc/init.d/privoxy start

# last: launch sshd
/usr/sbin/sshd -D

