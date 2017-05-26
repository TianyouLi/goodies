#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
export http_proxy="http://cdai2-linux64-2.sh.intel.com:8123"
export https_proxy=${http_proxy}
export aptool="apt-get -q -y"

# update to latest version
${aptool} update


# install nginx
${aptool} install nginx-full openssh-server openssh-client emacs net-tools sockstat tmux iputils-ping make sudo git


# change root password
echo 'root:123456' | chpasswd

# create directory for sshd
mkdir -p /var/run/sshd

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
echo 'export http_proxy="http://cdai2-linux64-2.sh.intel.com:8123"
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


## setup nginx
echo 'server {
  listen 8080 default_server;
  listen [::]:8080 default_server ipv6only=on;

  root /javascript-benchmarks;

  location / {
    autoindex  on;
    try_files $uri $uri/ =404;
  }
}' | tee -a /etc/nginx/sites-available/javascript-benchmarks
ln -s /etc/nginx/sites-available/javascript-benchmarks /etc/nginx/sites-enabled/javascript-benchmarks
git clone https://github.com/TianyouLi/javascript-benchmarks.git /javascript-benchmarks

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

