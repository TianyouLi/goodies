#!/bin/bash

SCRIPT=$(readlink -f "$0")
BASEDIR=$(dirname $SCRIPT)

DOTEMACS=$BASEDIR/emacs/.emacs
DOTELISP=$BASEDIR/emacs/.elisp
DOTTMUX=$BASEDIR/tmux/.tmux.conf
DOTALIASES=$BASEDIR/.bash_aliases

ln -s -f $DOTEMACS ~/.emacs
ln -s -f $DOTELISP ~/.elisp
ln -s -f $DOTTMUX ~/.tmux.conf
ln -s -f $DOTALIASES ~/.bash_aliases
