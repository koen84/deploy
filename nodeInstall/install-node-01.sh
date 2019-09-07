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
## STAGE 1
# Check for previous installation

if [ -d ${_configPath} ]; then
  echo -n "Previous installation detected..."
  printf  "continue with overwrite? (y/n) "
  read -t 60 REPLY
  if [ ${REPLY} != "y" ]; then
    exit 1
  fi

  if pgrep "${_daemon}" > /dev/null
  then
    echo "Stopping ${_daemon}..."
    killall ${_daemon} > /dev/null
    sleep 3
  fi

  # cleanup config folder for backup

  echo "cleaning config folders"
  rm -rf ${_configPath}/backups/
  rm -rf ${_configPath}/blocks/
  rm -rf ${_configPath}/blocks/
  rm -rf ${_configPath}/chainstate/
  rm -rf ${_configPath}/database/

  rm -rf ${_configPath}/testnet3/backups/
  rm -rf ${_configPath}/testnet3/blocks/
  rm -rf ${_configPath}/testnet3/blocks/
  rm -rf ${_configPath}/testnet3/chainstate/
  rm -rf ${_configPath}/testnet3/database/

  echo "creating config backups"
  unixTime=$( date +%s )
  backupDir=${HOME}/backups
  mkdir -p $backupDir
  tar -czvf ${backupDir}/backup_${unixTime}.tar.gz ${_configPath}
  echo "removing  ${_configPath}..."
  rm -rf ${_configPath}
fi

adduser --disabled-password --gecos "" $_daemon_user || true
usermod -aG sudo $_daemon_user || true
mkdir -p $_configPath
chown -R $_daemon_user:$_daemon_user $_configPath

# Create swapfile if less then 4GB memory
totalmem=$(free -m | awk '/^Mem:/{print $2}')
totalswp=$(free -m | awk '/^Swap:/{print $2}')
totalm=$(($totalmem + $totalswp))
if [ $totalm -lt 4000 ]; then
  echo "Server memory is less then 4GB..."
  if ! grep -q '/swapfile' /etc/fstab ; then
    echo "Creating a 4GB swapfile..."
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
fi
