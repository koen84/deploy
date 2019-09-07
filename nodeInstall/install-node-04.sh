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

  ## STAGE 4

  # Get a new privatekey
  _nodePrivateKey=$( ${_startCli} masternode genkey )
  echo "masternode=${_masternode}" >> ${_configFile}
  echo "externalip=${_nodeIpAddress}:${_port}" >> ${_configFile}
  echo "masternodeprivkey=${_nodePrivateKey}" >> ${_configFile}

#  popd
#  popd

  # Create a cronjob for making sure stashd runs after reboot
  if ! crontab -l 2>/dev/null | grep "#node maintenance scripts"; then
    (crontab -l; echo "") | crontab - # work around for 'first time crontab error'
  fi

  # Create a cronjob for sentinel
  if ! crontab -l | grep "${_configPath}/sentinel && ./venv/bin/python bin/sentinel.py 2>&1"; then
    (crontab -l; echo "* * * * * cd ${_configPath}/sentinel && ./venv/bin/python bin/sentinel.py 2>&1 >> sentinel-cron.log") | crontab -
  fi
#fi

# Update folder permissionss
chown -R $_daemon_user:$_daemon_user /home/$_daemon_user

# Create alias for user ease
alias cli="$_cli"
grep -q -F "alias watch='watch '" ~/.bashrc || echo "alias watch='watch '" >> ~/.bashrc
grep -q -F "alias cli='$_cli'" ~/.bashrc || echo "alias cli='$_cli'" >> ~/.bashrc
grep -q -F "alias restart='systemctl restart stashd.service'" ~/.bashrc || echo "alias restart='systemctl restart stashd.service'" >> ~/.bashrc
grep -q -F "alias stop='systemctl stop stashd.service'" ~/.bashrc || echo "alias stop='systemctl stop stashd.service'" >> ~/.bashrc

# Install finished, display info
privateKey=$( cat $_configFile | grep masternodeprivkey | sed "s/masternodeprivkey=//g" )

cat <<EOF

********************************************************************************
*                         Stash Core install complete                          *
********************************************************************************

Stash node setup complete. Please make a note of the network address and key:

EOF
echo -n "Network address: "; tput bold; tput setaf 2; echo "${_nodeIpAddress}:${_port}"; tput sgr0

if [ "$_masternode" == "1" ]; then
  echo -n "Masternode Key:  "; tput bold; tput setaf 2; echo "${privateKey}"; tput sgr0
fi

cat <<EOF

For your convenience the following alias have been set:

alias cli='/usr/bin/stash-cli -conf=/home/$_daemon_user/.stashcore/stash.conf'
alias restart='systemctl restart stashd.service'
alias stop='systemctl stop stashd.service'

To check masternode status type:
> cli masternode status
EOF

if [ "$_masternode" == "1" ]; then
cat <<EOF
To check the block sync status type:
> cli getinfo

To check masternode sync status type:
> cli mnsync status
EOF
# restart as maternode
systemctl restart stashd.service
fi