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

## STAGE 3
# Start the daemon
echo "Starting ${_daemon}....please wait"
systemctl daemon-reload
systemctl start stashd
systemctl enable stashd
#sleep 3

# Install masternode
if [ "$_masternode" == "1" ]; then

  # Install sentinel
  sudo apt-get install -y git python-virtualenv
  sudo apt-get install -y virtualenv
  pushd ${_configPath}
  git clone ${_sentinelPath}
  pushd sentinel
  virtualenv venv
  venv/bin/pip install -r requirements.txt

  # Update sentinel config
  sed -i 's/#stash_conf/stash_conf/g' sentinel.conf
  sed -i "s/username/$_daemon_user/g" sentinel.conf

  if [ "$_testnet" == "1" ]; then
    sed -i 's/network=mainnet/#network=mainnet/g' sentinel.conf
    sed -i 's/#network=testnet/network=testnet/g' sentinel.conf
  fi
fi