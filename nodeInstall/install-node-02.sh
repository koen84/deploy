#!/usr/bin/env bash
# Install Stashcore node on Ubuntu 18.04 LTS x64

# Usage
# ./install.sh [masternode] [testnet] [debug]

# Examples

#./install.sh
#./install.sh testnet
#./install.sh masternode
#./install.sh masternode testnet

## INIT
set -e

function boolean() {
  case $1 in
    1) echo Yes ;;
    0) echo No ;;
    *) echo "Err: Unknown boolean value \"$1\"" 1>&2; exit 1 ;;
   esac
}

if [ "$(whoami)" != "root" ]; then
  echo "Script should be run as user: root"
  exit 1
fi

# Check OS Version is Ubuntu
release=$( lsb_release -cs ) || true

if [ "$release" != "trusty" ] &&
   [ "$release" != "xenial" ] &&
   [ "$release" != "trusty" ] &&
   [ "$release" != "bionic" ] &&
   [ "$release" != "cosmic" ] &&
   [ "$release" != "disco" ]; then
   echo "WARNING: This script has been designed to work with Ubuntu 14.04+"

   # Ensure sudo and killall exist
   apt-get install -y sudo psmisc

   # Use generic release
   release=""
else
  # Use specific Ubuntu release
   release="-$release"   
fi
# Script Variables
_host=$( cat /etc/hostname )
_version="0.12.6.2"
_folder="stashcore-${_version}-x86_64-linux-gnu"
_binaries="${_folder}${release}.tar.gz"
_gitUser="stashpayio"
_binaryPath="https://github.com/${_gitUser}/stash/releases/download/v${_version}/${_binaries}"
_sentinelPath="https://github.com/stashpayio/sentinel.git"
_parametersPath="https://raw.githubusercontent.com/${_gitUser}/stash/master/zcutil/fetch-params.sh"

# Node variables
_masternode="0"
_testnet="0"
_litemode="0"
_debug="0"

# Network variables
_sshPort="22"
_port="9999"
_rpcPort="9998"
_testPort="19999"
_testRpcPort="19998"
_daemon="stashd"
_startDaemon=${_daemon}
_daemon_user="stashcore"
_cli="/usr/bin/stash-cli -conf=/home/${_daemon_user}/.stashcore/stash.conf"
_startCli=${_cli}
_configPath=/home/$_daemon_user/.stashcore
_configFile=${_configPath}/stash.conf
_stashdService=/lib/systemd/system/stashd.service

cat <<EOF

********************************************************************************
*                            Stash Core Installer v0.1                         *
********************************************************************************

EOF

# Initialise command line arguments
for i in "$@"; do

  if [ "$i" == "masternode" ]; then
    _masternode="1"
  fi

  if [ "$i" == "litemode" ]; then
    _litemode="1"
  fi

  if [ "$i" == "testnet" ]; then
    _testnet="1"
    _port=$_testPort
    _rpcPort=$_testRpcPort
    _startDaemon="$_daemon -testnet"
    _startCli="$_cli -testnet"
  fi

  if [ "$i" == "debug" ]; then
    _debug="1"
  fi

done

cat <<EOF
Stash node will be installed configured as follows:

Masternode: $(boolean "${_masternode}")
Testnet:    $(boolean "${_testnet}")
Litemode:   $(boolean "${_litemode}")
Port:       ${_port}
RPC port:   ${_rpcPort}
SSH port:   ${_sshPort}

EOF

printf  "Continue with install? (y/n) "

read -t 60 REPLY
if [ ${REPLY} != "y" ]; then
  exit 1
fi

## STAGE 2
# The RPC node will only accept connections from your localhost
_rpcUserName=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12 ; echo '')

# Choose a random and secure password for the RPC
_rpcPassword=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 ; echo '')

# Get the IP address of your vps which will be hosting the masternode
_nodeIpAddress=$(curl -s 4.icanhazip.com)

# Change the SSH port
sed -i "s/[#]\{0,1\}[ ]\{0,1\}Port [0-9]\{2,\}/Port ${_sshPort}/g" /etc/ssh/sshd_config

# Firewall security measures
apt install ufw -y
ufw disable
ufw allow ${_port}
ufw allow ${_sshPort}/tcp
ufw limit ${_sshPort}/tcp
ufw allow ${_rpcPort}
ufw logging on
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# Make a new directory for stash daemon
mkdir -p ${_configPath}

# Create a directory for masternode's cronjobs and the anti-ddos script
mkdir -p ~/deploy/bin

# Download and extract the binary files
wget ${_binaryPath} -NP ~/deploy/bin
tar xzf ~/deploy/bin/${_binaries} -C ~/deploy/bin
cp ~/deploy/bin/${_folder}/bin/stashd /usr/bin
cp ~/deploy/bin/${_folder}/bin/stash-cli /usr/bin

# Create the initial stash.conf file
echo "rpcuser=${_rpcUserName}
rpcpassword=${_rpcPassword}
rpcport=${_rpcPort}
port=${_port}
listen=1
server=1
daemon=1
logtimestamps=1
maxconnections=64
txindex=1
testnet=${_testnet}
litemode=${_litemode}
debug=${_debug}" > ${_configFile}

# Install stashd as a systemd service
cat <<EOF > ${_stashdService}
# It is not recommended to modify this file in-place, because it will
# be overwritten during package upgrades. If you want to add further
# options or overwrite existing ones then use
# $ systemctl edit stashd.service
# See "man systemd.service" for details.

# Note that almost all daemon options could be specified in
# /etc/stash/stash.conf

[Unit]
Description=stash daemon
After=network.target

[Service]
ExecStart=/usr/bin/stashd -daemon -conf=$_configFile -pid=/run/stashd/stashd.pid
# Creates /run/stashd owned by stashcore
RuntimeDirectory=stashd
User=$_daemon_user
Type=forking
PIDFile=/run/stashd/stashd.pid
Restart=on-failure

# Hardening measures
####################

# Provide a private /tmp and /var/tmp.
PrivateTmp=true

# Mount /usr, /boot/ and /etc read-only for the process.
ProtectSystem=full

# Disallow the process and all of its children to gain
# new privileges through execve().
NoNewPrivileges=true

# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random.
PrivateDevices=true


# Deny the creation of writable and executable memory mappings.
MemoryDenyWriteExecute=false

[Install]
WantedBy=multi-user.target
EOF

# Ensure zksnark setup params have been downloaded
bash <( wget -qO- ${_parametersPath} ) /home/${_daemon_user}
