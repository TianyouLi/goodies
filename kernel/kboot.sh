#!/bin/sh

kernels=($(ls -f /boot/vmlinuz-* | cut -c 15-))
kernels+=("Quit")
counts=${#kernel[@]}


CURRENT_KERNEL=`uname -r`
PS3="Select a kernel(current is ${CURRENT_KERNEL}): "
select k in "${kernels[@]}"; do
    case ${k} in
	Quit)
	    exit
	    ;;
	*)
	    if [ -z "${k}" ]; then
		continue
	    fi
	    kernel=${k} 
	    break
	    ;;
    esac
done

echo "Selected ${kernel}, reloading..."


if [[ "$1" == '-' ]]; then
    reuse=--reuse-cmdline
    shift
fi
[[ $# == 0 ]] && reuse=--reuse-cmdline
kernel="${kernel:-$(uname -r)}"
kargs="/boot/vmlinuz-$kernel --initrd=/boot/initramfs-$kernel.img"

kexec -l -t bzImage $kargs $reuse --append="$*" && \
    systemctl kexec
