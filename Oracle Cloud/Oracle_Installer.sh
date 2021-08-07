#!/bin/bash
if [ $EUID != 0 ]; then
  sudo "$0" "$@"
  exit $?
fi

WGCONFLOC='/etc/wireguard/wg0.conf'
WGPUBKEY='/etc/wireguard/publickey'
WGPORTSFILE='/etc/wireguard/forwarded_ports'
WGCONFBOTTOM='/etc/wireguard/bottom_section'
WGCONFTOP='/etc/wireguard/top_section'

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
LCYAN='\033[96m'
MAGEN='\033[1;35m'

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
  echo -e "${YELLOW}Installing Required Software${NC}..."
  if [[ $SERVERTYPE == 1 ]]; then
    apt install iputils-ping ufw wireguard -y
  else
    apt install wireguard -y
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
    echo -en "${YELLOW}Reloading sysctl settings${NC}..."
    sysctl -q -p
    echo -e "[${GREEN}Done${NC}]"
  fi
}

get_ips () {
  echo "In the following steps, you will need to enter some IP addresses.  You can find your VPS Public IP address on your Oracle Cloud Instance Page under \"Public IP Address\"".
  echo "The other IP addresses & port have a default set (shown in square brackets).  If you don't want to change them, just press enter when prompted."
  echo ""
  LOCALIPS=$(ip a s | grep -Eo "inet [0-9|\.|/]+" | grep -v "127.0.0.1" | sed 's/inet //')

  if [ $3 ]; then
    PUBLIC_IP=$3
  else
  read -p $'\e[36mVPS Public IP\e[0m: ' PUBLIC_IP
  fi

  if [[ $SERVERTYPE == 1 ]]; then
    echo ""
    echo -e "${YELLOW}The following networks have been found on your system.  Please use a different network for your Wireguard Server & Client{$NC}"
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
      echo -e "${RED}$i is not a valid IP, exiting...${NC}"
      exit 1
    fi
  done
}

create_keys () {
  echo -en "${YELLOW}Creating new Private/Public Keys${NC}..."
  umask 077 && printf "[Interface]\nPrivateKey = " | sudo tee $WGCONFLOC > /dev/null
  sudo wg genkey | tee -a $WGCONFLOC | wg pubkey | sudo tee $WGPUBKEY > /dev/null
  echo -e "[${GREEN}Done${NC}]"
}

create_server_config () {
  PK_FOR_CLIENT=$(cat $WGPUBKEY)
  TUNNEL_IP=$(ip -4 a show scope global | grep global | awk '{print $2}' | sed 's/\/.*//g')
  TUNNEL_INT=$(ip -4 a show scope global | grep global | awk '{print $7}')
  SSHD_PORT=$(cat /etc/ssh/sshd_config | grep -E "Port [0-9]+" | grep -Eo "[0-9]+")
  echo -en "${YELLOW}Flushing default iptables${NC}..."
  iptables -F
  iptables -X
  echo -e "[${GREEN}Done${NC}]"
  echo ""
  echo "What ports/protcols do you want to pass through to your Local Server?"
  echo "Please enter them like the following (comma separated, no spaces):"
  echo "443/tcp,80/tcp,8123/udp,5128/tcp"
  echo "If you don't want any other traffic added, just press enter"
  echo ""
  read -p $'\e[36mEntry\e[0m: ' PORTLIST
  echo -en "${YELLOW}Saving the iptables to persist across reboots${NC}..."
  iptables-save > /etc/iptables/rules.v4
  echo -e "[${GREEN}Done${NC}]"
  echo -en "${YELLOW}Saving ports to ${WGPORTSFILE}${NC}..."
  echo $PORTLIST > $WGPORTSFILE
  echo -e "[${GREEN}Done${NC}]"
  echo ""
  echo ""
  echo -e "${MAGEN}Before continuing with the rest of this script, please run this script on your Local Server with the following line{$NC}:"
  echo ""
  echo -e "${LCYAN}./Oracle_Installer.sh Local $PK_FOR_CLIENT $PUBLIC_IP $WG_SERVER_IP $WG_CLIENT_IP $WGPORT $PORTLIST${NC}"
  echo ""
  echo -e "${MAGEN}That script will output a public key for you to input here.${NC}"
  read -p $'\e[36mPublic Key from Client\e[0m: ' PK_FOR_SERVER
  echo "ListenPort = $WGPORT" >> $WGCONFLOC
  echo "Address = $WG_SERVER_IP/24" >> $WGCONFLOC
  echo "" >> $WGCONFLOC
  echo "PostUp = iptables -t nat -A PREROUTING -p tcp -i $TUNNEL_INT '!' --dport $SSHD_PORT -j DNAT --to-destination $WG_CLIENT_IP; iptables -t nat -A POSTROUTING -o $TUNNEL_INT -j SNAT --to-source $TUNNEL_IP" >> $WGCONFLOC
  echo "PostUp = iptables -t nat -A PREROUTING -p udp -i $TUNNEL_INT '!' --dport $WGPORT -j DNAT --to-destination $WG_CLIENT_IP;" >> $WGCONFLOC
  echo "" >> $WGCONFLOC
  echo "PostDown = iptables -t nat -D PREROUTING -p tcp -i $TUNNEL_INT '!' --dport $SSHD_PORT -j DNAT --to-destination $WG_CLIENT_IP; iptables -t nat -D POSTROUTING -o $TUNNEL_INT -j SNAT --to-source $TUNNEL_IP" >> $WGCONFLOC
  echo "PostDown = iptables -t nat -D PREROUTING -p udp -i $TUNNEL_INT '!' --dport $WGPORT -j DNAT --to-destination $WG_CLIENT_IP;" >> $WGCONFLOC
  echo "" >> $WGCONFLOC
  echo "[Peer]" >> $WGCONFLOC
  echo "PublicKey = $PK_FOR_SERVER" >> $WGCONFLOC
  echo "AllowedIPs = $WG_CLIENT_IP/32" >> $WGCONFLOC
  echo -e "${GREEN}Wireguard Config file created at $WGCONFLOC${NC}"
  echo ""
  echo -en "${YELLOW}Starting Wireguard${NC}..."
  systemctl start wg-quick@wg0
  echo -e "[${GREEN}Done${NC}]"
  echo -e "${YELLOW}Waiting for connection${NC}..."
  while ! ping -c 1 -W 1 $WG_CLIENT_IP > /dev/null; do
    printf '.'
    sleep 2
  done
  echo -e "[${GREEN}Connection Established${NC}]"
  echo -en "${YELLOW}Enabling Wireguard to start across reboots${NC}..."
  systemctl enable wg-quick@wg0 >/dev/null
  echo -e "[${GREEN}Done${NC}]"
  echo "Your wireguard tunnel should be set up now.  If you need to reset the link for any reason, please run 'systemctl reboot wg-quick@wg0'"
}

create_client_config () {
  PUBLIC_IP=$1
  WG_CLIENT_IP=$2
  WGPORT=$3
  PORTLIST=$4
  PUBKEY=$5
  WG_SERVER_IP=$6
  PK_FOR_SERVER=$(cat $WGPUBKEY)
  echo "Address = $WG_CLIENT_IP/24" >> $WGCONFLOC
  echo "" >> $WGCONFLOC
  for i in $(echo $PORTLIST | sed "s/,/ /g")
  do
    PORT=$(echo $i| cut -d'/' -f 1)
    PROT=$(echo $i| cut -d'/' -f 2)
    printf "IP Address of service using $PORT/$PROT (Just press Enter if using this server): "
    read SVC_IP
    if [[ -n $SVC_IP ]]; then
      echo "PostUp = iptables -t nat -A PREROUTING -p $PROT --dport $PORT -j DNAT --to-destination $SVC_IP:$PORT; iptables -t nat -A POSTROUTING -p $PROT --dport $PORT -j MASQUERADE" >> $WGCONFLOC
      echo "PostDown = iptables -t nat -D PREROUTING -p $PROT --dport $PORT -j DNAT --to-destination $SVC_IP:$PORT; iptables -t nat -D POSTROUTING -p $PROT --dport $PORT -j MASQUERADE" >> $WGCONFLOC
      echo "" >> $WGCONFLOC
    fi
  done
  echo "[Peer]" >> $WGCONFLOC
  echo "PublicKey = $PUBKEY" >> $WGCONFLOC
  echo "AllowedIPs = 0.0.0.0/0" >> $WGCONFLOC
  echo "Endpoint = $PUBLIC_IP:$WGPORT" >> $WGCONFLOC
  echo "PersistentKeepalive = 25" >> $WGCONFLOC
  echo "Wireguard Config file created at $WGCONFLOC"
  echo ""
  echo "Here is the Public Key for you to enter back on the VPS."
  echo ""
  echo -e "${LCYAN}$PK_FOR_SERVER${NC}"
  echo ""
  echo -en "${YELLOW}Starting Wireguard${NC}..."
  systemctl start wg-quick@wg0
  echo -e "[${GREEN}Done${NC}]"
  echo -e "${YELLOW}Waiting for connection${NC}..."
  while ! ping -c 1 -W 1 $WG_SERVER_IP > /dev/null; do
    printf '.'
    sleep 1
  done
  echo -e "[${GREEN}Connection Established${NC}]"
  echo ""
  echo -en "${YELLOW}Enabling Wireguard to start across reboots${NC}..."
  systemctl enable wg-quick@wg0 >/dev/null
  echo -e "[${GREEN}Done${NC}]"
}

clear_firewall () {
  echo -en "${YELLOW}Clearing Old Firewall Rules${NC}..."
  ufw --force disable >/dev/null
  ufw --force reset >/dev/null
  echo -e "[${GREEN}Done${NC}]"
}

setup_firewall () {
  echo "Configuring ufw rules"
  echo "  Allowing OpenSSH($SSHD_PORT/tcp)"
  ufw allow $SSHD_PORT/tcp > /dev/null
  echo "  Allowing Wireguard Port($WGPORT)"
  ufw allow $WGPORT > /dev/null
  for i in $(echo $PORTLIST | sed "s/,/ /g")
  do
    PORT=$(echo $i| cut -d'/' -f 1)
    PROT=$(echo $i| cut -d'/' -f 2)
    echo "  Allowing $PORT/$PROT"
    ufw allow $PORT/$PROT > /dev/null
  done
  echo "  Allowing routing"
  ufw default allow routed > /dev/null
  echo "  Deny all other traffic"
  ufw default deny incoming > /dev/null
  echo ""
  echo "  Here are all the rules that have been added."
  ufw show added | tail -n +2 | sed -e 's/^/  /'
  echo ""
  echo "  Do the rules look good (at the very least, you should see your ssh port) for activating?"
  echo ""
  read -r -p $'  \e[36mActivate rules? [Y/n]\e[0m' UFW_ON
  if [[ ! "$UFW_ON" =~ ^([yY][eE][sS]|[yY]|"")$ ]]; then
    echo "  Firewall not enabled"
    echo -e "  You should limit access to your server by using ufw as described in \e[94;4mhttps://github.com/mochman/Bypass_CGNAT/wiki/Limiting-Access\e[0m"
    exit
  else
    ufw enable
  fi
  echo -e "[${GREEN}ufw Configured${NC}]"
}

get_ports () {
  OLDPORTS=$(cat $WGPORTSFILE)
  SSHD_PORT=$(cat /etc/ssh/sshd_config | grep -E "Port [0-9]+" | grep -Eo "[0-9]+")
  WGPORT=$(cat $WGCONFLOC | grep 'ListenPort' | awk '{print $3}')
  echo "What ports/protcols do you want to pass through to your Local Server?"
  echo "Please enter them like the following (comma separated, no spaces):"
  echo "443/tcp,80/tcp,8123/udp,5128/tcp"
  echo "If you don't want any other traffic added, just press enter"
  echo -e "Your current ports are ${CYAN}$OLDPORTS${NC}"
  echo ""
  read -p $'\e[36mEntry\e[0m: ' PORTLIST
  echo ""
  echo -e "\e[1;35mBefore continuing with the rest of this script, please run this script on your Local Server with the following line\e[0m:"
  echo ""
  echo -e "\"\e[96msudo ./Oracle_Installer.sh LocalMod $PORTLIST\e[0m\""
}

ask_firewall () {
  if [[ $1 == 1 ]]; then
    echo "Since the ports have been modified, the firewall needs to be changed"
    clear_firewall
    setup_firewall
  else
    read -r -p $'\e[36mWould you like this script to configure your firewall? [Y/n]\e[0m' UFW_YN
    if [[ ! "$UFW_YN" =~ ^([yY][eE][sS]|[yY]|"")$ ]]; then
      echo -e "You should limit access to your server by using ufw as described in \e[94;4mhttps://github.com/mochman/Bypass_CGNAT/wiki/Limiting-Access\e[0m"
      exit
    else
      clear_firewall
      setup_firewall
    fi
  fi
}

start_wireguard () {
  echo -en "${YELLOW}Starting wireguard services${NC}..."
  systemctl start wg-quick@wg0 2> /dev/null
  echo -e "[${GREEN}Done${NC}]"
}

modify_client_config () {
  PORTLIST=$1
  awk '{print} /Address/ {exit}' $WGCONFLOC > $WGCONFTOP
  sed -n '/\[Peer/,$p' < $WGCONFLOC > $WGCONFBOTTOM
  cat $WGCONFTOP > $WGCONFLOC
  echo "" >> $WGCONFLOC
  for i in $(echo $PORTLIST | sed "s/,/ /g")
  do
    PORT=$(echo $i| cut -d'/' -f 1)
    PROT=$(echo $i| cut -d'/' -f 2)
    printf "IP Address of service using $PORT/$PROT (Just press Enter if using this server): "
    read SVC_IP
    if [[ -n $SVC_IP ]]; then
      echo "PostUp = iptables -t nat -A PREROUTING -p $PROT --dport $PORT -j DNAT --to-destination $SVC_IP:$PORT; iptables -t nat -A POSTROUTING -p $PROT --dport $PORT -j MASQUERADE" >> $WGCONFLOC
      echo "PostDown = iptables -t nat -D PREROUTING -p $PROT --dport $PORT -j DNAT --to-destination $SVC_IP:$PORT; iptables -t nat -D POSTROUTING -p $PROT --dport $PORT -j MASQUERADE" >> $WGCONFLOC
      echo "" >> $WGCONFLOC
    fi
  done
  echo "" >> $WGCONFLOC
  cat $WGCONFBOTTOM >> $WGCONFLOC
  rm -f $WGCONFTOP $WGCONFBOTTOM
}

script_complete () {
  echo "Your system has been configured.  If you need to reset the VPN link for any reason, please run 'systemctl reboot wg-quick@wg0'"
}


#**********************Begin Script************************************

echo ""
echo -e "${LGREEN}***************************************************"
echo -e "*     ${WHITE}Oracle Cloud Wireguard Tunnel Installer${LGREEN}     *"
echo -e "*                ${LBLUE}Version 0.1.0               ${LGREEN}     *"
echo -e "***************************************************${NC}"
echo ""
echo "This script will install and configure wireguard on your machines."
if [[ $1 == "Local" ]]; then
  stop_wireguard
  update_system
  install_required
  configure_forwarding
  create_keys
  create_client_config $3 $5 $6 $7 $2 $4
  script_complete
  exit
elif [[ $1 == "LocalMod" ]]; then
  stop_wireguard
  modify_client_config $2
  start_wireguard
  script_complete
else
  SERVERTYPE=1
  echo ""
  echo -e "Make sure you have followed the Opening Up Ports section found on:"
  echo -e "${LBU}https://github.com/mochman/Bypass_CGNAT/wiki/Oracle-Cloud--(Opening-Up-Ports)${NC}"
  echo ""
  echo "Please have a terminal window running on both your VPS and your Local Server"
  echo "since this script will ask you to input information into/from each other."
  echo -e "${YELLOW}Be advised, this script will modify your iptables & ufw(firewall) settings.${NC}"
  echo -e "${CYAN}"
  read -n 1 -s -r -p 'Press q to quit, any other key to contine' YORN
  echo -e "${NC}"
  if [[ $YORN == [Qq] ]]; then
    echo "Exiting..."
    exit
  fi
fi

FOUNDOLD=0

# Look for an already set up wireguard config
if grep -q -E 'PrivateKey = .+' $WGCONFLOC 2>/dev/null; then
  # Check if Server/Client
  if grep -q 'Endpoint' $WGCONFLOC; then
    # Client
    FOUNDTYPE=2
    FOUNDOLD=1
    SERVERTYPE=2
    options=("Change Port Numbers" "Change Port->IP Mapping" "Exit Script")
  else
    # Server
    FOUNDTYPE=1
    FOUNDOLD=1
    SERVERTYPE=1
    options=("Change Ports Passed Through" "Create New Configuration" "Exit Script")
  fi
else
  FOUNDTYPE=0
fi

echo ""
echo -e "${LBLUE}***************************************************"
if [[ $FOUNDOLD == 1 ]]; then
  echo -e "*${NC}    Current Wireguard Configuration Detected    ${LBLUE} *"
fi
if [[ $FOUNDTYPE == 2 ]]; then
  echo -e "*${YELLOW}                 Local Client                ${LBLUE}    *"
elif [[ $FOUNDTYPE == 1 ]]; then
  echo -e "*${YELLOW}                  VPS Server              ${LBLUE}       *"
else
  echo -e "*${NC}        Wireguard Configuration Not Found  ${LBLUE}      *"
fi
echo -e "${LBLUE}***************************************************${NC}"
echo ""

if [[ $FOUNDOLD == 1 ]]; then
  echo "Options:"
  if [[ $FOUNDTYPE == 1 ]]; then #Server
    PS3="Select #: "
    select opt in "${options[@]}"
    do
      case $opt in
        "Change Ports Passed Through")
          echo "CHANGE PORTS"
          stop_wireguard
          get_ports
          ask_firewall 1
          script_complete
          exit
          ;;
        "Create New Configuration")
          stop_wireguard
          update_system
          install_required
          configure_forwarding
          get_ips $5 $6 $3
          create_keys
          create_server_config
          ask_firewall
          script_complete
          exit
          ;;
        "Exit Script")
          exit
          ;;
        *) exit;;
      esac
    done
  elif [[ $FOUNDTYPE == 2 ]]; then #Client
    PS3="Select #: "
    select opt in "${options[@]}"
    do
      case $opt in
        "Change Port Numbers")
          echo -e "${RED}Please run this script on the VPS to modify the ports${NC}"
          exit
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
  stop_wireguard
  update_system
  install_required
  configure_forwarding
  get_ips $5 $6 $3
  create_keys
  create_server_config
  ask_firewall
  script_complete
fi
