#!/bin/bash

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

# then set link
echo "#!/bin/sh

echo $1 | grep \"\.intel\.com$\" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    connect $@
else
    connect -S proxy-socks.jf.intel.com:1080 $@
fi" >> /usr/local/bin/socks-git

# chmod for run.sh
chmod +x /etc/init.d/run.sh

# config git globals
git config --global user.email "tianyou.li@gmail.com"
git config --global user.name "Tianyou Li"
git config --global push.default matching

# download the goodies
git clone https://github.com/TianyouLi/goodies.git

