#!/bin/bash

SCRIPT=$(readlink -f "$0")
BASEDIR=$(dirname $SCRIPT)

DOTEMACS=$BASEDIR/emacs/.emacs
DOTELISP=$BASEDIR/emacs/.elisp
DOTTMUX=$BASEDIR/tmux/.tmux.conf
DOTALIASES=$BASEDIR/.bash_aliases
DOTGITENV=$BASEDIR/git_env

ln -s -f $DOTEMACS ~/.emacs
ln -s -f $DOTELISP ~/.elisp
ln -s -f $DOTTMUX ~/.tmux.conf
ln -s -f $DOTALIASES ~/.bash_aliases

# set git
rm -f ~/.git_env
ln -s -f $DOTGITENV ~/.git_env

# set tpm
mkdir -p ~/.tmux/plugins
rm -f ~/.tmux/plugins/tpm 
ln -s -f ${BASEDIR}/tmux/tpm ~/.tmux/plugins/tpm

# kenrel tools path
KERNEL_TOOLS=${BASEDIR}/kernel
echo "# kernel tools path" >> ~/.bashrc 
echo "export PATH=${PATH}:${KERNEL_TOOLS}" >> ~/.bashrc 

