#/bin/bash
NONE='\033[00m'
RED='\033[01;31m'
GREEN='\033[01;32m'
YELLOW='\033[01;33m'
PURPLE='\033[01;35m'
CYAN='\033[01;36m'
WHITE='\033[01;37m'
BOLD='\033[1m'
UNDERLINE='\033[4m'

declare -r NODE_USER=x42
declare -r CONF=release
declare -r COINGITHUB=https://github.com/x42protocol/X42-FullNode.git
declare -r COINPORT=52342
declare -r COINRPCPORT=52343
declare -r COINDAEMON=x42d
declare -r COINCORE=/home/${NODE_USER}/.x42node/x42/x42Main/
declare -r COINCONFIG=x42.conf
declare -r COINRUNCMD="sudo dotnet ./x42.x42D.dll -datadir=${COINCORE}" ## additional commands can be used here e.g. -testnet or -stake=1
declare -r COINSTARTUP=/home/${NODE_USER}/x42d
declare -r COINSRCLOC=/home/${NODE_USER}/X42-FullNode
declare -r COINDLOC=/home/${NODE_USER}/x42node   
declare -r COINDSRC=/home/${NODE_USER}/X42-FullNode/src/x42.x42D
declare -r COINSERVICELOC=/etc/systemd/system/
declare -r COINSERVICENAME=${COINDAEMON}@${NODE_USER}
declare -r DATE_STAMP="$(date +%y-%m-%d-%s)"
declare -r SCRIPT_LOGFILE="/tmp/${NODE_USER}_${DATE_STAMP}_output.log"
declare -r SWAPSIZE="1024" ## =1GB
declare -r OS_VER=*Ubuntu*

function check_root() {
if [ "$(id -u)" != "0" ]; then
    echo "Sorry, this script needs to be run as root. Do \"sudo su root\" and then re-run this script"
    exit 1
fi
}

create_mn_user() {
    echo
    echo "* Checking for user & add if required. Please wait..."
    # our new mnode unpriv user acc is added
    if id "${NODE_USER}" >/dev/null 2>&1; then
        echo "user exists already, do nothing"
    else
        echo -e "${NONE}${GREEN}* Adding new system user ${NODE_USER}${NONE}"
        sudo adduser --disabled-password --gecos "" ${NODE_USER} &>> ${SCRIPT_LOGFILE}
        sudo echo -e "${NODE_USER} ALL=(ALL) NOPASSWD:ALL" &>> /etc/sudoers.d/90-cloud-init-users

    fi
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function set_permissions() {
    chown -R ${NODE_USER}:${NODE_USER} ${COINCORE} ${COINSTARTUP} ${COINDLOC} &>> ${SCRIPT_LOGFILE}
    # make group permissions same as user, so vps-user can be added to node group
    chmod -R g=u ${COINCORE} ${COINSTARTUP} ${COINDLOC} ${COINSERVICELOC} &>> ${SCRIPT_LOGFILE}
}

checkOSVersion() {
   echo
   echo "* Checking OS version..."
    if [[ `cat /etc/issue.net`  == ${OS_VER} ]]; then
        echo -e "${GREEN}* You are running `cat /etc/issue.net` . Setup will continue.${NONE}";
    else
        echo -e "${RED}* You are not running ${OS_VER}. You are running `cat /etc/issue.net` ${NONE}";
        echo && echo "Installation cancelled" && echo;
        exit;
    fi
}

updateAndUpgrade() {
    echo
    echo "* Running update and upgrade. Please wait..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq -y &>> ${SCRIPT_LOGFILE}
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq &>> ${SCRIPT_LOGFILE}
    sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -qq &>> ${SCRIPT_LOGFILE}
    echo -e "${GREEN}* Done${NONE}";
}

setupSwap() {
#check if swap is available
    echo
    echo "* Creating Swap File. Please wait..."
    if [ $(free | awk '/^Swap:/ {exit !$2}') ] || [ ! -f "/var/mnode_swap.img" ];then
    echo -e "${GREEN}* No proper swap, creating it.${NONE}";
    # needed because ant servers are ants
    sudo rm -f /var/mnode_swap.img &>> ${SCRIPT_LOGFILE}
    sudo dd if=/dev/zero of=/var/mnode_swap.img bs=1024k count=${SWAPSIZE} &>> ${SCRIPT_LOGFILE}
    sudo chmod 0600 /var/mnode_swap.img &>> ${SCRIPT_LOGFILE}
    sudo mkswap /var/mnode_swap.img &>> ${SCRIPT_LOGFILE}
    sudo swapon /var/mnode_swap.img &>> ${SCRIPT_LOGFILE}
    echo '/var/mnode_swap.img none swap sw 0 0' | sudo tee -a /etc/fstab &>> ${SCRIPT_LOGFILE}
    echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf &>> ${SCRIPT_LOGFILE}
    echo 'vm.vfs_cache_pressure=50' | sudo tee -a /etc/sysctl.conf &>> ${SCRIPT_LOGFILE}
else
    echo -e "${GREEN}* All good, we have a swap.${NONE}";
fi
}

installFail2Ban() {
    echo
    echo -e "* Installing fail2ban. Please wait..."
    sudo apt-get -y install fail2ban &>> ${SCRIPT_LOGFILE}
    sudo systemctl enable fail2ban &>> ${SCRIPT_LOGFILE}
    sudo systemctl start fail2ban &>> ${SCRIPT_LOGFILE}
    # Add Fail2Ban memory hack if needed
    if ! grep -q "ulimit -s 256" /etc/default/fail2ban; then
       echo "ulimit -s 256" | sudo tee -a /etc/default/fail2ban &>> ${SCRIPT_LOGFILE}
       sudo systemctl restart fail2ban &>> ${SCRIPT_LOGFILE}
    fi
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

setupTmpRAM() {
    echo
    echo -e "* Pushing tmp files to RAM for performance. Please wait..."
    echo 'tmpfs   /tmp            tmpfs   defaults,noatime,nosuid,nodev,noexec,mode=1777,size=512M          0       0' | tee -a /etc/fstab &>> ${SCRIPT_LOGFILE}
    echo 'tmpfs   /var/tmp        tmpfs   defaults,noatime,mode=1777,size=2M                      0       0' | tee -a /etc/fstab &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

installFirewall() {
    echo
    echo -e "* Installing UFW. Please wait..."
    sudo apt-get -y install ufw &>> ${SCRIPT_LOGFILE}
    sudo ufw allow OpenSSH &>> ${SCRIPT_LOGFILE}
    sudo ufw allow $COINPORT/tcp &>> ${SCRIPT_LOGFILE}
    sudo ufw allow $COINRPCPORT/tcp &>> ${SCRIPT_LOGFILE}
    echo "y" | sudo ufw enable &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

installDependencies() {
    echo
    echo -e "* Installing dependencies. Please wait..."
    sudo apt-get install git nano wget curl software-properties-common -y &>> ${SCRIPT_LOGFILE}
    sudo wget -q https://packages.microsoft.com/config/ubuntu/16.04/packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
    sudo dpkg -i packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
    sudo apt-get install apt-transport-https -y &>> ${SCRIPT_LOGFILE}
    sudo apt-get update -y &>> ${SCRIPT_LOGFILE}
    sudo apt-get install dotnet-sdk-2.1 -y --allow-unauthenticated &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

compileWallet() {
    echo
    echo -e "* Compiling wallet. Please wait, this might take a while to complete..."
    cd /home/${NODE_USER}/
    git clone ${COINGITHUB} &>> ${SCRIPT_LOGFILE}
    cd ${COINSRCLOC} 
    git submodule update --init --recursive &>> ${SCRIPT_LOGFILE}
    cd ${COINDSRC} 
    dotnet restore &>> ${SCRIPT_LOGFILE}
    dotnet publish -c ${CONF} -r linux-x64 -v m -o ${COINDLOC} &>> ${SCRIPT_LOGFILE}	   ### compile & publish code 
    rm -rf ${COINSRCLOC} &>> ${SCRIPT_LOGFILE} 	   ### Remove source
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

installWallet() {
    echo
    echo -e "* Installing wallet. Please wait..."
    cd /home/${NODE_USER}/
    echo -e "#!/bin/bash\nexport DOTNET_CLI_TELEMETRY_OPTOUT=1\ncd $COINDLOC\n$COINRUNCMD" > ${COINSTARTUP}
    echo -e "[Unit]\nDescription=${COINDAEMON}\nAfter=network-online.target\n\n[Service]\nType=simple\nUser=${NODE_USER}\nGroup=${NODE_USER}\nExecStart=${COINSTARTUP}\nRestart=always\nRestartSec=5\nPrivateTmp=true\nTimeoutStopSec=60s\nTimeoutStartSec=5s\nStartLimitInterval=120s\nStartLimitBurst=15\n\n[Install]\nWantedBy=multi-user.target" >${COINSERVICENAME}.service
    chown -R ${NODE_USER}:${NODE_USER} ${COINSERVICELOC} &>> ${SCRIPT_LOGFILE}
    sudo mv $COINSERVICENAME.service ${COINSERVICELOC} &>> ${SCRIPT_LOGFILE}
    sudo chmod 777 ${COINSTARTUP} &>> ${SCRIPT_LOGFILE}
    sudo systemctl --system daemon-reload &>> ${SCRIPT_LOGFILE}
    sudo systemctl enable ${COINSERVICENAME} &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

configureWallet() {
    echo
    echo -e "* Configuring wallet. Please wait..."
    cd /home/${NODE_USER}/
    mnip=$(curl --silent ipinfo.io/ip)
    rpcuser=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`
    rpcpass=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`
    sudo mkdir -p $COINCORE
    echo -e "externalip=${mnip}\ntxindex=1\nlisten=1\ndaemon=1\nmaxconnections=64" > $COINCONFIG
    sudo mv $COINCONFIG $COINCORE
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

startWallet() {
    echo
    echo -e "* Starting wallet daemon..."
    sudo service ${COINSERVICENAME} start &>> ${SCRIPT_LOGFILE}
    sleep 2
    echo -e "${GREEN}* Done${NONE}";
}
stopWallet() {
    echo
    echo -e "* Stopping wallet daemon..."
    sudo service ${COINSERVICENAME} stop &>> ${SCRIPT_LOGFILE}
    sleep 2
    echo -e "${GREEN}* Done${NONE}";
}

function installUnattendedUpgrades() {

    echo
    echo "* Installing Unattended Upgrades..."
    sudo apt install unattended-upgrades -y &>> ${SCRIPT_LOGFILE}
    sleep 3
    sudo sh -c 'echo "Unattended-Upgrade::Allowed-Origins {" >> /etc/apt/apt.conf.d/50unattended-upgrades'
    sudo sh -c 'echo "        "${distro_id}:${distro_codename}";" >> /etc/apt/apt.conf.d/50unattended-upgrades'
    sudo sh -c 'echo "        "${distro_id}:${distro_codename}-security";" >> /etc/apt/apt.conf.d/50unattended-upgrades'
    sudo sh -c 'echo "APT::Periodic::AutocleanInterval "7";" >> /etc/apt/apt.conf.d/20auto-upgrades'
    sudo sh -c 'echo "APT::Periodic::Unattended-Upgrade "1";" >> /etc/apt/apt.conf.d/20auto-upgrades'
    cat /etc/apt/apt.conf.d/20auto-upgrades &>> ${SCRIPT_LOGFILE}
    echo -e "${GREEN}* Done${NONE}";
}

displayServiceStatus() {
	echo
	echo
	on="${GREEN}ACTIVE${NONE}"
	off="${RED}OFFLINE${NONE}"

	if systemctl is-active --quiet cityd@city; then echo -e "City Chain Service: ${on}"; else echo -e "City Chain Service: ${off}"; fi
}

clear
cd
echo && echo
echo -e "${WHITE}            --------------------------------------------------------------------------${NONE}"
echo -e "${WHITE}            ${NONE}"
echo -e "${WHITE}                                          444444444   222222222222222    ${NONE}"
echo -e "${WHITE}                                         4::::::::4  2:::::::::::::::22  ${NONE}"
echo -e "${WHITE}                                        4:::::::::4  2::::::222222:::::2 ${NONE}"
echo -e "${WHITE}                                       4::::44::::4  2222222     2:::::2 ${NONE}"
echo -e "${WHITE}                  xxxxxxx      xxxxxxx4::::4 4::::4              2:::::2 ${NONE}"
echo -e "${WHITE}                   x:::::x    x:::::x4::::4  4::::4              2:::::2 ${NONE}"
echo -e "${WHITE}                    x:::::x  x:::::x4::::4   4::::4           2222::::2  ${NONE}"
echo -e "${WHITE}                     x:::::xx:::::x4::::444444::::444    22222::::::22   ${NONE}"
echo -e "${WHITE}                      x::::::::::x 4::::::::::::::::4  22::::::::222     ${NONE}"
echo -e "${WHITE}                       x::::::::x  4444444444:::::444 2:::::22222        ${NONE}"
echo -e "${WHITE}                       x::::::::x            4::::4  2:::::2             ${NONE}"
echo -e "${WHITE}                      x::::::::::x           4::::4  2:::::2             ${NONE}"
echo -e "${WHITE}                     x:::::xx:::::x          4::::4  2:::::2       222222${NONE}"
echo -e "${WHITE}                    x:::::x  x:::::x       44::::::442::::::2222222:::::2${NONE}"
echo -e "${WHITE}                   x:::::x    x:::::x      4::::::::42::::::::::::::::::2${NONE}"
echo -e "${WHITE}                  xxxxxxx      xxxxxxx     444444444422222222222222222222${NONE}"
echo -e "${WHITE}                  ${NONE}"
echo -e "${WHITE}            --------------------------------------------------------------------------${NONE}"
echo -e ${WHITE}
echo -e ${WHITE}
echo -e "${WHITE}**********************************************************************${NONE}"
echo -e "${WHITE}      This script will install and configure your ${NODE_USER} node.${NONE}"
echo -e "${WHITE}**********************************************************************${NONE}"
echo -e "${BOLD}"
read -p "Please run this script as the root user. Do you want to setup (y) or upgrade (u) your ${NODE_USER} node. (y/n/u)?" response
echo -e "${NONE}"

if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then

    check_root
    create_mn_user
    checkOSVersion
    updateAndUpgrade
    setupSwap
    setupTmpRAM
    installFail2Ban
    installFirewall
    installDependencies
    compileWallet
    installWallet
    #configureWallet ### commented out so uses the default configuration
    installUnattendedUpgrades
    startWallet
    set_permissions
    displayServiceStatus

echo
echo -e "${GREEN} Installation complete. Check service with: journalctl -f -u ${COINSERVICENAME} ${NONE}"
echo -e "${GREEN} The log file can be found here: ${SCRIPT_LOGFILE}${NONE}"
echo -e "${GREEN} thecrypt0hunter(2018) - Tips: XBYgUtCNDGTPcCuK8M2AbAz4LvdVPLBr8a${NONE}"
else
    if [[ "$response" =~ ^([uU])+$ ]]; then
        check_root
        stopWallet
	updateAndUpgrade
        compileWallet
        startWallet
        displayServiceStatus
        echo -e "${GREEN} Upgrade complete. Check service with: sudo journalctl -f -u ${COINSERVICENAME} ${NONE}"
	echo -e "${GREEN} The log file can be found here: ${SCRIPT_LOGFILE}${NONE}"
        echo -e "${GREEN} thecrypt0hunter 2018 - Tips: XBYgUtCNDGTPcCuK8M2AbAz4LvdVPLBr8a${NONE}"
    else
      echo && echo -e "${RED} Installation cancelled! ${NONE}" && echo
    fi
fi
    cd ~
