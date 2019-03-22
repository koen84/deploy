#!/usr/bin/env bash
# Install Stashcore node on Ubuntu 18.04 LTS x64

# Usage
# ./install.sh [masternode] [testnet] [debug]

# Examples

#./install.sh
#./install.sh testnet
#./install.sh masternode
#./install.sh masternode testnet

set -e

function boolean() {
  case $1 in
    1) echo Yes ;;
    0) echo No ;;
    *) echo "Err: Unknown boolean value \"$1\"" 1>&2; exit 1 ;;
   esac
}

# Script Variables
_host=$( cat /etc/hostname )
_version="0.12.6.0"
_folder="stashcore-${_version}-x86_64-linux-gnu"
_binaries="${_folder}.tar.gz"
_gitUser="beachm"
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

if [ "$(whoami)" != "root" ]; then
  echo "Script should be run as user: root"
  exit 1
fi

# Check OS Version is Ubuntu 18.04
. /etc/lsb-release

if [ "$DISTRIB_RELEASE" != "18.04" ] &&
   [ "$DISTRIB_RELEASE" != "18.10" ]; then
  echo "WARNING: This script has been designed to work with Ubuntu 18.04"
  exit 1 # Comment out to ignore warning
fi

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

  # Get a new privatekey
  _nodePrivateKey=$( ${_startCli} masternode genkey )
  echo "masternode=${_masternode}" >> ${_configFile}
  echo "externalip=${_nodeIpAddress}:${_port}" >> ${_configFile}
  echo "masternodeprivkey=${_nodePrivateKey}" >> ${_configFile}

  popd
  popd

  # Create a cronjob for making sure stashd runs after reboot
  if ! crontab -l 2>/dev/null | grep "#node maintenance scripts"; then
    (crontab -l; echo "") | crontab - # work around for 'first time crontab error'
  fi

  # Create a cronjob for sentinel
  if ! crontab -l | grep "${_configPath}/sentinel && ./venv/bin/python bin/sentinel.py 2>&1"; then
    (crontab -l; echo "* * * * * cd ${_configPath}/sentinel && ./venv/bin/python bin/sentinel.py 2>&1 >> sentinel-cron.log") | crontab -
  fi
fi

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