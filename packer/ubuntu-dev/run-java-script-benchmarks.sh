#!/bin/bash

# launch nginx
/etc/init.d/nginx restart

# last: launch sshd
/usr/sbin/sshd -D

