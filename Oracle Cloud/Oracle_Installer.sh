#!/bin/bash
WGCONFLOC='/etc/wireguard/wg0.conf'

RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
LGREEN='\033[92m'
WHITE='\033[97m'
LBLUE='\033[94m'
LBU='\033[94;4m'
CYAN='\033[36m'

stop_wireguard () {
  echo -en "${YELLOW}Stopping any current wireguard services${NC}..."
  systemctl stop wg-quick@wg0 2> /dev/null
  wg-quick down wg0 2> /dev/null
  echo -e "[${GREEN}Done${NC}]"
}

update_system () {
  echo -e "${YELLOW}Updating System${NC}..."
  apt update
  apt upgrade -y
  echo -e "[${GREEN}Done${NC}]"
}

install_required () {
  echo -e "${YELLOW}Installing Software${NC}..."
  if [ $SERVERTYPE -eq 1 ]; then
    echo "installingS"
    #apt install iputils-ping ufw wireguard -y
  else
    echo "installingC"
    #apt install wireguard -y
  fi
  echo -e "[${GREEN}Done${NC}]"
}

configure_forwarding () {
  echo -en "${YELLOW}Configuring Forwarding Settings${NC}..."
  if grep -e "^net.ipv4.ip_forward=1$" /etc/sysctl.conf >/dev/null; then
    echo -e "[${GREEN}Already set${NC}]"
  else
    sed -i 's/^\#net.ipv4.ip_forward=1$/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
    if ! grep -e "^net.ipv4.ip_forward=1$" /etc/sysctl.conf >/dev/null; then
      echo -e "[${CYAN}Appending to /etc/sysctl.conf${NC}]"
      echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -p
    echo -e "[${GREEN}Done${NC}]"
  fi
}

get_ips () {
  if [ $SERVERTYPE -eq 1 ]; then
    echo ""
    echo -e "\e[33mThe following networks have been found on your system.  Please use a different network for your Wireguard Server & Client\e[0m"
    echo $LOCALIPS
    echo ""
    read -p $'\e[36mWireguard Server IP \e[0m[\e[32m10.1.0.1\e[0m]: ' WG_SERVER_IP
  fi
  WG_SERVER_IP=${WG_SERVER_IP:-10.1.0.1}

  if [ $1 ]; then
    WG_CLIENT_IP=$1
  else
    read -p $'\e[36mWireguard Client IP \e[0m[\e[32m10.1.0.2\e[0m]: ' WG_CLIENT_IP
    WG_CLIENT_IP=${WG_CLIENT_IP:-10.1.0.2}
  fi

  if [ $2 ]; then
    WGPORT=$2
  else
    read -p $'\e[36mWireguard Port \e[0m[\e[32m55108\e[0m]: ' WGPORT
    WGPORT=${WGPORT:-55108}
  fi

  for i in "PUBLIC_IP" "WG_SERVER_IP" "WG_CLIENT_IP"
  do
    if [[ ${!i} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      :
    else
      echo -e "\e[31m$i is not a valid IP, exiting...\e[0m"
      exit 1
    fi
  done
}

# For Oracle Cloud Computer VMs running Ubuntu 20.04 Minimal
# Usage:
#  on VPS - ./Oracle_Installer.sh
#  on Local Server - ./Oracle_Installer.sh <Local> <PUBKEY> <PUBLIC_IP> <SERVER_IP> <CLIENT WG IP> <WG PORT> <SRV_ARR>

echo ""
echo ""
echo -e "${LGREEN}***************************************************"
echo -e "*     ${WHITE}Oracle Cloud Wireguard Tunnel Installer${LGREEN}     *"
echo -e "*                ${LBLUE}Version 0.1.0               ${LGREEN}     *"
echo -e "***************************************************${NC}"
echo ""
echo "This script will install and configure wireguard on your machines."
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Please run with sudo"
    exit
fi
if [[ $1 != "Local" ]]; then
  echo ""
  echo -e "Make sure you have followed the Opening Up Ports section found on:"
  echo -e "${LBU}https://github.com/mochman/Bypass_CGNAT/wiki/Oracle-Cloud--(Opening-Up-Ports)${NC}"
  echo ""
  echo "Please have a terminal window running on both your VPS and your Local Server"
  echo "since this script will ask you to input information into/from each other."
  echo -e "${YELLOW}Be advised, this script will modify your iptables & ufw(firewall) settings.${NC}"
fi

FOUNDOLD=0

# Look for an already set up wireguard config
if grep -q -E 'PrivateKey = .+' $WGCONFLOC 2>/dev/null; then
  # Check if Server/Client
  if grep -q 'Endpoint' $WGCONFLOC; then
    # Client
    FOUNDTYPE=2
    FOUNDOLD=1
    options=("Change Port Numbers" "Change Port->IP Mapping" "Exit Script")
  else
    # Server
    FOUNDTYPE=1
    FOUNDOLD=1
    options=("Change Ports Passed Through" "Create New Configuration" "Exit Script")
  fi
else
  FOUNDTYPE=0
fi

echo ""
echo -e "${LBLUE}***************************************************"
if [[ $FOUNDTYPE == 2 ]]; then
  echo -e "*${NC}    Current Wireguard Configuration Detected    ${LBLUE} *"
  echo -e "*${YELLOW}                 Local Client                ${LBLUE}    *"
elif [[ $FOUNDTYPE == 1 ]]; then
  echo -e "*${NC}    Current Wireguard Configuration Detected    ${LBLUE} *"
  echo -e "*${YELLOW}                  VPS Server              ${LBLUE}       *"
else
  echo -e "*${NC}        Wireguard Configuration Not Found  ${LBLUE}      *"
fi
echo -e "${LBLUE}***************************************************${NC}"
echo ""

if [[ $FOUNDOLD == 1 ]]; then
  echo "Options:"
  if [[ $FOUNDTYPE == 1 ]]; then
    PS3="Select #: "
    select opt in "${options[@]}"
    do
      case $opt in
        "Change Ports Passed Through")
          echo "CHANGE PORTS"
          break
          ;;
        "Create New Configuration")
          echo "NEW"
          break
          ;;
        "Exit Script")
          exit
          ;;
        *) exit;;
      esac
    done
  elif [[ $FOUNDTYPE == 2 ]]; then
    PS3="Select #: "
    select opt in "${options[@]}"
    do
      case $opt in
        "Change Port Numbers")
          echo "CHANGE PORT NUMS"
          break
          ;;
        "Change Port->IP Mapping")
          echo "MAPPING"
          break
          ;;
        "Exit Script")
          exit
          ;;
        *) exit;;
      esac
    done
  fi
else
  echo "FRESH"
  #Fresh Install Here
fi


if [[ $1 == "VPS" ]] || [ ! $1 ]; then
  SERVERTYPE=1
elif [[ $1 == "Local" ]]; then
  SERVERTYPE=2
else
  echo ""
  printf "Select Server\n1. VPS\n2. Local Server\n"
  read -p 'Number: ' SERVERTYPE
fi

if ! [ $SERVERTYPE -eq 1 -o $SERVERTYPE -eq 2 ] 2>/dev/null; then
  echo "Incorrect Entry.  Exiting..."
  exit
fi

echo ""
stop_wireguard
echo ""
update_system
echo ""
install_required
echo ""
configure_forwarding
echo ""

echo "In the following steps, you will need to enter some IP addresses.  You can find your VPS Public IP address on your Oracle Cloud Instance Page under \"Public IP Address\"".
echo "The other IP addresses & port have a default set (shown in square brackets).  If you don't want to change them, just press enter when prompted."
echo ""
LOCALIPS=$(ip a s | grep -Eo "inet [0-9|\.|/]+" | grep -v "127.0.0.1" | sed 's/inet //')

if [ $3 ]; then
  PUBLIC_IP=$3
else
 read -p $'\e[36mVPS Public IP\e[0m: ' PUBLIC_IP
fi

get_ips $5 $6

exit #REMOVE

#Set the Configuration Files
echo "Writing the configuration files..."
umask 077 && printf "[Interface]\nPrivateKey = " | sudo tee /etc/wireguard/wg0.conf > /dev/null
sudo wg genkey | tee -a /etc/wireguard/wg0.conf | wg pubkey | sudo tee /etc/wireguard/publickey > /dev/null
echo -e "\e[92mDone.\e[0m"
echo ""

if [ $SERVERTYPE -eq 1 ]; then
  PK_FOR_CLIENT=$(cat /etc/wireguard/publickey)
  TUNNEL_IP=$(ip -4 a show scope global | grep global | awk '{print $2}' | sed 's/\/.*//g')
  TUNNEL_INT=$(ip -4 a show scope global | grep global | awk '{print $7}')
  SSHD_PORT=$(cat /etc/ssh/sshd_config | grep -E "Port [0-9]+" | grep -Eo "[0-9]+")
  echo "Flushing default iptables"
  iptables -F 
  iptables -X
  echo -e "\e[92mDone.\e[0m"
  echo ""
  echo "What ports/protcols do you want to pass through to your Local Server?"
  echo "Please enter them like the following (comma separated, no spaces):"
  echo "443/tcp,80/tcp,8123/udp,5128/tcp"
  echo "If you don't want any other traffic added, just press enter"
  echo ""
  read -p $'\e[36mEntry\e[0m: ' PORTLIST
  echo "Saving the iptables to persist across reboots"
  iptables-save > /etc/iptables/rules.v4
  echo -e "\e[92mDone.\e[0m"
  echo ""
  echo ""
  echo -e "\e[1;35mBefore continuing with the rest of this script, please run this script on your Local Server with the following line\e[0m:"
  echo ""
  echo -e "\"\e[96msudo ./Oracle_Installer.sh Local $PK_FOR_CLIENT $PUBLIC_IP $WG_SERVER_IP $WG_CLIENT_IP $WGPORT $PORTLIST\e[0m\""
  echo ""
  echo -e "\e[1;35mThat script will output a public key for you to input here.\e[0m"
  read -p $'\e[36mPublic Key from Client\e[0m: ' PK_FOR_SERVER
  echo "ListenPort = $WGPORT" >> /etc/wireguard/wg0.conf
  echo "Address = $WG_SERVER_IP/24" >> /etc/wireguard/wg0.conf
  echo "" >> /etc/wireguard/wg0.conf
  echo "PostUp = iptables -t nat -A PREROUTING -p tcp -i $TUNNEL_INT '!' --dport $SSHD_PORT -j DNAT --to-destination $WG_CLIENT_IP; iptables -t nat -A POSTROUTING -o $TUNNEL_INT -j SNAT --to-source $TUNNEL_IP" >> /etc/wireguard/wg0.conf
  echo "PostUp = iptables -t nat -A PREROUTING -p udp -i $TUNNEL_INT '!' --dport $WGPORT -j DNAT --to-destination $WG_CLIENT_IP;" >> /etc/wireguard/wg0.conf
  echo "" >> /etc/wireguard/wg0.conf
  echo "PostDown = iptables -t nat -D PREROUTING -p tcp -i $TUNNEL_INT '!' --dport $SSHD_PORT -j DNAT --to-destination $WG_CLIENT_IP; iptables -t nat -D POSTROUTING -o $TUNNEL_INT -j SNAT --to-source $TUNNEL_IP" >> /etc/wireguard/wg0.conf
  echo "PostDown = iptables -t nat -D PREROUTING -p udp -i $TUNNEL_INT '!' --dport $WGPORT -j DNAT --to-destination $WG_CLIENT_IP;" >> /etc/wireguard/wg0.conf
  echo "" >> /etc/wireguard/wg0.conf
  echo "[Peer]" >> /etc/wireguard/wg0.conf
  echo "PublicKey = $PK_FOR_SERVER" >> /etc/wireguard/wg0.conf
  echo "AllowedIPs = $WG_CLIENT_IP/32" >> /etc/wireguard/wg0.conf
  echo -e "\e[92mWireguard Config file created at /etc/wireguard/wg0.conf\e[0m"
  echo ""
  echo "Starting Wireguard..."
  systemctl start wg-quick@wg0
  echo ""
  echo "Waiting for connection..."
  while ! ping -c 1 -W 1 $WG_CLIENT_IP > /dev/null; do
    printf '.'
    sleep 2
  done
  echo -e "\e[92mConnection Established!\e[0m"
  echo ""
  echo "Enabling Wireguard to start across reboots..."
  systemctl enable wg-quick@wg0
  echo -e "\e[92mDone.\e[0m"
  echo ""
  echo "Your wireguard tunnel should be set up now.  If you need to reset the link for any reason, please run 'systemctl reboot wg-quick@wg0'"
  echo ""
  read -r -p $'\e[36mWould you like this script to configure your firewall? [Y/n]\e[0m' UFW_YN
  if [[ ! "$UFW_YN" =~ ^([yY][eE][sS]|[yY]|"")$ ]]; then
    echo -e "You should limit access to your server by using ufw as described in \e[94;4mhttps://github.com/mochman/Bypass_CGNAT/wiki/Limiting-Access\e[0m"
    exit
  fi
  echo "Adding OpenSSH($SSHD_PORT/tcp)"
  ufw allow $SSHD_PORT/tcp > /dev/null
  echo "Adding Wireguard Port($WGPORT)"
  ufw allow $WGPORT > /dev/null
  for i in $(echo $PORTLIST | sed "s/,/ /g")
  do
    PORT=$(echo $i| cut -d'/' -f 1)
    PROT=$(echo $i| cut -d'/' -f 2)
    echo "Adding $PORT/$PROT"
    ufw allow $PORT/$PROT > /dev/null
  done
  echo "Allowing routing"
  ufw default allow routed > /dev/null
  echo "Deny all other traffic"
  ufw default allow routed
  echo -e "\e[92mDone.\e[0m"
  echo ""
  echo "Here are all the rules that have been added."
  ufw show added | tail -n +2
  echo ""
  echo "Do the rules look good (at the very least, you should see your ssh port) for activating?"
  echo ""
  read -r -p $'\e[36mActivate rules? [Y/n]\e[0m' UFW_ON
  if [[ ! "$UFW_ON" =~ ^([yY][eE][sS]|[yY]|"")$ ]]; then
    echo "Firewall not enabled"
    echo -e "You should limit access to your server by using ufw as described in \e[94;4mhttps://github.com/mochman/Bypass_CGNAT/wiki/Limiting-Access\e[0m"
    exit
  else
    ufw enable
  fi
  
  echo ""
  echo "Your system has been configured.  If you need to reset the link for any reason, please run 'systemctl reboot wg-quick@wg0'"
  echo ""
else
  PK_FOR_SERVER=$(cat /etc/wireguard/publickey)
  if [ $7 ]; then
   PORTLIST=$7
  fi
  echo "Address = $WG_CLIENT_IP/24" >> /etc/wireguard/wg0.conf
  echo "" >> /etc/wireguard/wg0.conf
  for i in $(echo $PORTLIST | sed "s/,/ /g")
  do
    PORT=$(echo $i| cut -d'/' -f 1)
    PROT=$(echo $i| cut -d'/' -f 2)
    printf "IP Address of service using $PORT/$PROT (Just press Enter if using this server): "
    read SVC_IP
    if [[ -n $SVC_IP ]]; then
      echo "PostUp = iptables -t nat -A PREROUTING -p $PROT --dport $PORT -j DNAT --to-destination $SVC_IP:$PORT; iptables -t nat -A POSTROUTING -p $PROT --dport $PORT -j MASQUERADE" >> /etc/wireguard/wg0.conf
      echo "PostDown = iptables -t nat -D PREROUTING -p $PROT --dport $PORT -j DNAT --to-destination $SVC_IP:$PORT; iptables -t nat -D POSTROUTING -p $PROT --dport $PORT -j MASQUERADE" >> /etc/wireguard/wg0.conf
      echo "" >> /etc/wireguard/wg0.conf
    fi
  done
  echo "[Peer]" >> /etc/wireguard/wg0.conf
  echo "PublicKey = $2" >> /etc/wireguard/wg0.conf
  echo "AllowedIPs = 0.0.0.0/0" >> /etc/wireguard/wg0.conf
  echo "Endpoint = $PUBLIC_IP:$WGPORT" >> /etc/wireguard/wg0.conf
  echo "PersistentKeepalive = 25" >> /etc/wireguard/wg0.conf
  echo "Wireguard Config file created at /etc/wireguard/wg0.conf"
  echo ""
  echo "Here is the Public Key for you to enter back on the VPS."
  echo ""
  echo -e "\e[96m$PK_FOR_SERVER\e[0m"
  echo ""
  echo "Starting Wireguard..."
  systemctl start wg-quick@wg0
  echo "Waiting for connection"
  while ! ping -c 1 -W 1 $WG_SERVER_IP > /dev/null; do
    printf '.'
    sleep 1
  done
  echo -e "\e[92mConnection Established!\e[0m"
  echo ""
  echo "Enabling Wireguard to start across reboots..."
  systemctl enable wg-quick@wg0
  echo -e "\e[92mDone.\e[0m"
  echo ""
  echo "Your system has been configured.  If you need to reset the link for any reason, please run 'systemctl reboot wg-quick@wg0'"
  echo ""
fi
