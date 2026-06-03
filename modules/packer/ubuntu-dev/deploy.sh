#!/bin/bash

function runcmd() {
		echo $1
		eval $1
		echo "$1 ... done!"
}

# now setup some environment, first let's change privoxy settings
echo "forward-socks5 / proxy.jf.intel.com:1080 ." >> /etc/privoxy/config
echo "listen-address 127.0.0.1:8118" >> /etc/privoxy/config
/etc/init.d/privoxy restart

# then change subversion config
mkdir -p /root/.subversion
echo " [global] 
 http-proxy-host = localhost 
 http-proxy-port = 8118 
 http-proxy-exceptions = \*.intel.com" >> /root/.subversion/servers

# then change the apt proxy
echo "Acquire::http::proxy \"http://proxy01.cd.intel.com:911\";
Acquire::https::proxy \"http://proxy01.cd.intel.com:911\";
Acquire::ftp::proxy \"http://proxy01.cd.intel.com:911\";
Acquire::socks::proxy \"socks://proxy.jf.intel.com:1080/\";" >> /etc/apt/apt.conf

# chmod for run.sh
chmod +x /etc/init.d/run.sh

# add user
adduser --disabled-password --gecos ""  lity

# change user passwd
echo 'lity:123456' | chpasswd


# modify sudoers file
echo "Defaults        env_keep = \"http_proxy ftp_proxy all_proxy https_proxy no_proxy socks_proxy\"
# Allow krom to have root access for ChromeOS build
lity ALL=(ALL) NOPASSWD: ALL" | tee -a /etc/sudoers


## append environment vars
echo 'export http_proxy="http://localhost:8118"
export socks_proxy="proxy.jf.intel.com:1080"

export all_proxy=${socks_proxy}
export ftp_proxy=${http_proxy}
export https_proxy=${http_proxy}
export RSYNC_PROXY=${http_proxy}

export no_proxy=".intel.com,.jf.intel.com,.sh.intel.com"
export GIT_PROXY_COMMAND=/usr/local/bin/socks-git

export PATH=$PATH:/home/krom/tools/depot_tools' | tee -a /etc/bash.bashrc

## create socks-git script
# then set link
echo '#!/bin/sh

echo $1 | grep "\.intel\.com$" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    connect $@
else
    connect -S proxy-socks.jf.intel.com:1080 $@
fi' | tee -a /usr/local/bin/socks-git


echo 'PS1=lity@lity-ubuntu-dev
source /etc/bash.bashrc

## show system env for debug purpose
export

# config git globals
git config --global user.email "tianyou.li@gmail.com"
git config --global user.name "Tianyou Li"
git config --global push.default matching

# download the goodies
git clone https://github.com/TianyouLi/goodies.git

# make symbol link
ln -s ~/goodies/tmux/.tmux.conf ~/.tmux.conf
ln -s ~/goodies/emacs/.emacs ~/.emacs' | tee /usr/local/bin/lity-ubuntu-dev-env.sh

##swith to user lity
su -l lity -c "bash /usr/local/bin/lity-ubuntu-dev-env.sh"


