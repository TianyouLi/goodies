#!/bin/bash

SCRIPT=$(readlink -f "$0")
BASEDIR=$(dirname $SCRIPT)

# Get git autocomplete for bash
(cd $BASEDIR;
		rm git-completion.bash -f;
		wget https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash;
		ln -sf $BASEDIR/git-completion.bash ~/.git-completion.bash;
		echo "source ~/.git-completion.bash" >> ~/.bashrc;
)


# Get git branch name to bash PS
(cd $BASEDIR;
		rm git-prompt.sh -f;
		wget https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh;
		ln -sf $BASEDIR/git-prompt.sh ~/.git-prompt.sh;
		echo "source ~/.git-prompt.sh" >> ~/.bashrc;
		echo "export GIT_PS1_SHOWDIRTYSTATE=\"true\"" >> ~/.bashrc;
		echo "export GIT_PS1_SHOWUPSTREAM=\"auto\"" >> ~/.bashrc;
		echo "export GIT_PS1_SHOWUNTRACKEDFILES=\"true\"" >> ~/.bashrc
		echo "PS1='\${debian_chroot:+($debian_chroot)}\u@\h:\w\$(__git_ps1 \" (%s)\")\\$ '" >> ~/.bashrc;
)


### git info
git config --global user.name "Tianyou Li"
git config --global user.email "tianyou.li@gmail.com"
git config --global core.autocrlf false
git config --global core.filemode false
git config --global color.ui true

### configure git cache
git config --global credential.helper 'store'

### add some tools to bin path
sudo ln -s ${BASEDIR}/git-clang-format /usr/bin/git-clang-format
