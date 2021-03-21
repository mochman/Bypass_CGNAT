#!/bin/bash

# For Oracle Cloud Computer VMs runninf Ubuntu 20.04
# Usage:
#  Oracle_Installer.sh <VPS/Local> <PUBKEY> <PUBLIC_IP> <SERVER_IP> <CLIENT WG IP> <WG PORT> <SRV_ARR>

echo "This script will install and configure wireguard on your machines"
if [[ $(/usr/bin/id -u) -ne 0 ]]; then
    echo "Please run with sudo"
    exit
fi
echo "Make sure you have followed the Opening Ports section found on https://"

if [[ $1 == "VPS" ]]; then
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

echo "Stopping any current wireguard services"
systemctl stop wg-quick@wg0
wg-quick down wg0 2> /dev/null

echo "Updating System..."
#apt update
#apt upgrade -y
echo ""
echo "Upgrade Complete.  Installing Software..."

#if [ $SERVERTYPE -eq 1 ]; then
#  apt install nano iputils-ping wireguard -y
#else
#  apt install wireguard -y
#fi
echo "Software Installation Complete"
echo ""
echo "Configuring Forwarding Settings"
if grep -e "^net.ipv4.ip_forward=1$" /etc/sysctl.conf >/dev/null; then
  echo "Already set correctly"
else
  sed -i 's/^\#net.ipv4.ip_forward=1$/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
  if ! grep -e "^net.ipv4.ip_forward=1$" /etc/sysctl.conf >/dev/null; then
    echo "Appending to /etc/sysctl.conf"
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  fi
  sysctl -p
  echo "Complete."
fi
echo ""

LOCALIPS=$(ip a s | grep -Eo "inet [0-9|\.|/]+" | grep -v "127.0.0.1" | sed 's/inet //')

if [ $3 ]; then
  PUBLIC_IP=$3
else
 read -p 'VPS Public IP: ' PUBLIC_IP
fi

if [ $SERVERTYPE -eq 1 ]; then
  echo "The following networks have been found on your system.  Please use a different network for your Wireguard Config"
  echo $LOCALIPS
  echo ""
  read -p 'Wireguard Server IP [10.1.0.1]: ' WG_SERVER_IP
fi
WG_SERVER_IP=${WG_SERVER_IP:-10.1.0.1}

if [ $5 ]; then
  WG_CLIENT_IP=$5
else
  read -p 'Wireguard Client IP [10.1.0.2]: ' WG_CLIENT_IP
  WG_CLIENT_IP=${WG_CLIENT_IP:-10.1.0.2}
fi

if [ $6 ]; then
  WGPORT=$6
else
  read -p 'Wireguard Port [55108]: ' WGPORT
  WGPORT=${WGPORT:-55108}
fi

for i in "PUBLIC_IP" "WG_SERVER_IP" "WG_CLIENT_IP"
do
  if [[ ${!i} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    :
  else
    echo "$i is not a valid IP, exiting..."
    exit 1
  fi
done


#Set the Configuration Files
echo "Writing the configuration files..."
umask 077 && printf "[Interface]\nPrivateKey = " | sudo tee /etc/wireguard/wg0.conf > /dev/null
sudo wg genkey | tee -a /etc/wireguard/wg0.conf | wg pubkey | sudo tee /etc/wireguard/publickey > /dev/null
echo "Done."
echo ""

if [ $SERVERTYPE -eq 1 ]; then
  PK_FOR_CLIENT=$(cat /etc/wireguard/publickey)
  echo "Allowing wireguard connection in iptables"
  if iptables -S INPUT | grep -- "INPUT -p udp -m udp --dport $WGPORT -j ACCEPT" >/dev/null; then
    echo "Connection alrady allowed"
  else
    echo "Adding iptable rule"
    iptables -I INPUT -p udp --dport $WGPORT -j ACCEPT
  fi
  echo ""
  echo "What other ports/prot do you want to pass through to your Local Server?"
  echo "Please enter like the following (no spaces):"
  echo "443/tcp,80/tcp,8123/udp,8843/tcp"
  read -p 'Entry: ' PORTLIST
  for i in $(echo $PORTLIST | sed "s/,/ /g")
  do
    PORT=$(echo $i| cut -d'/' -f 1)
    PROT=$(echo $i| cut -d'/' -f 2)
    if iptables -S INPUT | grep -- "INPUT -p $PROT -m $PROT --dport $PORT -j ACCEPT" >/dev/null; then
      echo "$PORT/$PROT already allowed"
    else
      iptables -I INPUT -p $PROT --dport $PORT -j ACCEPT
    fi
  done
  echo ""
  echo "Please look over these iptables rules."
  echo ""
  iptables -S INPUT
  echo ""
  echo "Saving the iptables to persist across reboots"
  iptables-save > /etc/iptables/rules.v4
  echo "Saved."
  echo ""
  echo ""
  echo "Before continuing this script, please run this script on your Local Server with the following line:"
  echo ""
  echo "sudo ./Oracle_Installer.sh Local $PK_FOR_CLIENT $PUBLIC_IP $WG_SERVER_IP $WG_CLIENT_IP $WGPORT $PORTLIST"
  echo ""
  echo "That script will output a public key for you to input here."
  read -p 'Public Key from Client: ' PK_FOR_SERVER
  echo "ListenPort = $WGPORT" >> /etc/wireguard/wg0.conf
  echo "Address = $WG_SERVER_IP/24" >> /etc/wireguard/wg0.conf
  echo "" >> /etc/wireguard/wg0.conf
  echo "PostUp = iptables -t nat -A PREROUTING -p tcp -i eth0 '!' --dport 22 -j DNAT --to-destination $WG_CLIENT_IP; iptables -t nat -A POSTROUTING -o eth0 -j SNAT --to-source $PUBLIC_IP" >> /etc/wireguard/wg0.conf
  echo "PostUp = iptables -t nat -A PREROUTING -p udp -i eth0 '!' --dport $WGPORT -j DNAT --to-destination $WG_CLIENT_IP;" >> /etc/wireguard/wg0.conf
  echo "" >> /etc/wireguard/wg0.conf
  echo "PostDown = iptables -t nat -D PREROUTING -p tcp -i eth0 '!' --dport 22 -j DNAT --to-destination $WG_CLIENT_IP; iptables -t nat -D POSTROUTING -o eth0 -j SNAT --to-source $PUBLIC_IP" >> /etc/wireguard/wg0.conf
  echo "PostDown = iptables -t nat -D PREROUTING -p udp -i eth0 '!' --dport $WGPORT -j DNAT --to-destination $WG_CLIENT_IP;" >> /etc/wireguard/wg0.conf
  echo "" >> /etc/wireguard/wg0.conf
  echo "[Peer]" >> /etc/wireguard/wg0.conf
  echo "PublicKey = $PK_FOR_SERVER" >> /etc/wireguard/wg0.conf
  echo "AllowedIPs = $WG_CLIENT_IP/32" >> /etc/wireguard/wg0.conf
  echo "Wireguard Config file created at /etc/wireguard/wg0.conf"
  echo ""
  echo "Starting Wireguard..."
  systemctl start wg-quick@wg0
  echo ""
  echo "Waiting for connection..."
  while ! ping -c 1 -W 1 $WG_CLIENT_IP > /dev/null; do
    printf '.'
    sleep 1
  done
  echo "Connection Established!"
  echo ""
  echo "Enabling Wireguard to start across reboots..."
  systemctl enable wg-quick@wg0
  echo "Done."
  echo ""
  echo "Your wireguard tunnel should be set up now.  If you need to reset the link for any reason, please run 'systemctl reboot wg-quick@wg0'"

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
  echo "Here is the Public Key for the Server."
  echo ""
  echo $PK_FOR_SERVER
  echo ""
  echo "Starting Wireguard..."
  systemctl start wg-quick@wg0
  echo "Waiting for connection"
  while ! ping -c 1 -W 1 $WG_SERVER_IP > /dev/null; do
    printf '.'
    sleep 1
  done
  echo "Connection Established!"
  echo ""
  echo "Enabling Wireguard to start across reboots..."
  systemctl enable wg-quick@wg0
  echo "Done."
  echo ""
  echo "Your wireguard tunnel should be set up now.  If you need to reset the link for any reason, please run 'systemctl reboot wg-quick@wg0'"
fi
