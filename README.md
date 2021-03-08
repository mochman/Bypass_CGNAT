# Bypassing a CGNAT with Wireguard

## Contents
1. [VPS Setup](#1-vps-setup)
1a. [Locking down your server](#1a-locking-down-your-server)
1b. [System config](#1b-system-config)
1c. [Installing Wireguard](#1c-installing-wireguard)
2. [Home Server Setup](#2-home-server-setup)
2a. [System Config](#2a-system-config)
2b. [Installing Wireguard](#2b-installing-wireguard)
3. [Starting Wireguard](#3-starting-wireguard)
4. [Limiting Access](#4-limiting-access)
5. [All Done/References](#5-all-done-references)
6. [Thanks](#6-thanks)

# Overview
Before switching ISPs, I had a public IP that allowed me to use port forwarding on my router to pass traffic to services hosted on my internal network.  My new ISP uses a CGNAT, so I had to find a solution.  I chose this path, because it keeps pretty puch everything the same on my services.  The main things I wanted to do with my setup were:
* Forward only specific traffic from the internet to my services
* Provide my NPM (Nginx Proxy Manager) Server with clients real IPs (for blocking purposes)
* Allow for traffic to flow internal services that NPM doesn't manage

I went through a couple configurations and VPS providers before I created this solution.  Prior to attempting this, I had little to no knowledge about VPS providers, wireguard, ufw, and iptables.  This will hopefully be a useful tutorial for people who are in a similar situation.  This tutorial assumes you have some basic knowledge about how to use Ubuntu from the command line.

Here is a basic diagram of my configuration.  The IPs and ports will need to be changed by you to meet your requirements.

![Topology](Basic%20Topology.png)

For reference, here are all the IPs, Ports, and Names that I will be using in this guide for you to reference and change as appropriate.

Name | IP used in tutorial | Port | Description
------------ | ------------- | ------------- | -------------
VPS IP | 1.2.3.4 | N/A | Your VPS's IP (Assigned to you)
VPS Wireguard IP | 10.0.0.1 | 55107 | The Wireguard IP:Port we will set up in our VPN connection (Created by you)
Nginx IP | 192.168.2.5 | 443 | The Local IP of our NPM Server (Should already exist in your local network)
Nginx Wireguard IP | 10.0.0.2 | N/A | The Wireguard IP we will use to talk with the VPS Server (Created by you)
Home Assistant IP | 192.168.2.6 | 1234 | The IP:Port of another service that NPM doesn't provide routing for (Should already exist / Home Assistant is just an example)
Synology NAS | 192.168.2.4 | 5001 | The IP:Port of another service that NPM doesn't provide routing for (Should already exist / Synology NAS is just an example)
Docker Server App | 192.168.2.7 | 1194 | The IP:Port of another service that NPM doesn't provide routing for (Should already exist / OpenVPN is an example)

# 1. VPS Setup
I am using [Digital Ocean](https://www.digitalocean.com/) as my VPS provider.  I tried using Hostinger before since it was cheaper, but since they use OpenVZ for their virtualization, I couldn't get wireguard to work properly on it.  I am using their cheapest droplet which runs around $6 a month. 
If you want to use Digital Ocean, [here is a tutorial](https://www.digitalocean.com/docs/droplets/how-to/create/) on how to set up a droplet.  I am using Ubuntu 20.04 on mine, but wireguard should work with 18.04 as well.
After you have your droplet set up, you should see your given IP.  You should use that for all instances you see here of "VPS IP".

## 1a. Locking down your server
I recommend following a system hardening guide like [this one](https://www.digitalocean.com/community/tutorials/how-to-harden-openssh-on-ubuntu-18-04) or [this one](https://medium.com/@jasonrigden/hardening-ssh-1bcb99cd4cef).  After this, I will assume you have kept sshd running on port 22.  If you changed the port, pay attention in the following steps and adjust as appropriate.
## 1b. System config
Enable forwarding by running:
```bash
sudo nano /etc/sysctl.conf
```
Make sure `net.ipv4.ip_forward=1` is uncommented, save the file then run:
```bash
sudo sysctl -p
```
## 1c. Installing Wireguard
After a `sudo apt update && sudo apt upgrade` run:
```bash
sudo apt install wireguard
sudo (umask 077 && printf "[Interface]\nPrivateKey = " | sudo tee /etc/wireguard/wg0.conf > /dev/null)
sudo wg genkey | sudo tee -a /etc/wireguard/wg0.conf | wg pubkey | sudo tee /etc/wireguard/publickey
```
Those commands will install wireguard, create a file in `/etc/wireguard/wg0.conf`, place a generated private key into that file.  Then it prints out a public key **that you need to keep** (if you forget it, the public key is also in the `/etc/wireguard/publickey` file).
Now open the wireguard configuration file.
```bash
sudo nano /etc/wireguard/wg0.conf
```
### Use the following config:
**Things you need to change:**
Name | Item | Description
--- | --- | ---
*VPS IP* | 1.2.3.4 | The IP of your VPS
*interface* | eth0 | Your internet facing interface.

**Things you can change:**

Name | Item | Description
--- | --- | ---
*Wireguard Port* | 55107 | Any unused port you like
*Wireguard Server IP* | 10.0.0.1/24 | Any RFC1918 IP/CIDR.  Don't you your home network's IPs (192.168.2.0/24 in this tutorial).
*Wireguard Host IP* | 10.0.0.2 | Same as above, make sure it's in the same address range.
*Wireguard Host IP/32* | 10.0.0.2/32 | The above IP with /32 after it.
```
[Interface]
PrivateKey = SHOULD_ALREADY_BE_FILLED_OUT
ListenPort = 55107
Address = 10.0.0.1/24

PostUp = iptables -t nat -A PREROUTING -p tcp -i eth0 '!' --dport 22 -j DNAT --to-destination 10.0.0.2; iptables -t nat -A POSTROUTING -o eth0 -j SNAT --to-source 1.2.3.4
PostUp = iptables -t nat -A PREROUTING -p udp -i eth0 '!' --dport 55107 -j DNAT --to-destination 10.0.0.2;

PostDown = iptables -t nat -D PREROUTING -p tcp -i eth0 '!' --dport 22 -j DNAT --to-destination 10.0.0.2; iptables -t nat -D POSTROUTING -o eth0 -j SNAT --to-source 1.2.3.4
PostDown = iptables -t nat -D PREROUTING -p udp -i eth0 '!' --dport 55107 -j DNAT --to-destination 10.0.0.2;

[Peer]
PublicKey = 
AllowedIPs = 10.0.0.2/32
```
We will fill in the PublicKey section after we install Wireguard on our local server.

For your inforamtion, the PostUp and PostDown commands will run when wireguard makes/looses connection.
The first PostUp command will forward all TCP traffic (except our SSH traffic on port 22) through the wireguard VPN to our server without changing any of the IP addresses.
The second PostUp command will do the same with UDP traffic (except our wireguard traffic on port 55107).
The PostDown commands just remove what was created with the PostUp commands.

# 2. Home Server Setup
## 2a. System config
Enable forwarding by running:
```bash
sudo nano /etc/sysctl.conf
```
Make sure `net.ipv4.ip_forward=1` is uncommented, save the file then run:
```bash
sudo sysctl -p
```
## 2b. Installing Wireguard
We're going to do the same installation steps as we did on the VPS.
```bash
sudo apt install wireguard
sudo (umask 077 && printf "[Interface]\nPrivateKey = " | sudo tee /etc/wireguard/wg0.conf > /dev/null)
sudo wg genkey | sudo tee -a /etc/wireguard/wg0.conf | wg pubkey | sudo tee /etc/wireguard/publickey
```
**Take this public key and place it in the `PublicKey = ` section on the VPS's `/etc/wireguard/wg0.conf` file.**
Now open the wireguard configuration file.
```bash
sudo nano /etc/wireguard/wg0.conf
```
### Use the following config:
**Things you need to change:**
Name | Item | Description
--- | --- | ---
*Peer PublicKey* | THE_PUBLIC_KEY_FROM_YOUR_VPS_WIREGUARD_INSTALL | The public key you copied when installing wireguard on the **VPS**.

**Things you may have to change:**

Name | Item | Description
--- | --- | ---
*Wireguard Port* | 55107 | The port you used in the VPS config
*Wireguard Host IP* | 10.0.0.2/24 | The Host IP you used in the VPS config with a /24 after it
```
[Interface]
PrivateKey = SHOULD_ALREADY_BE_FILLED_OUT
Address = 10.0.0.2/24

PostUp = iptables -t nat -A PREROUTING -p tcp --dport 1234 -j DNAT --to-destination 192.168.2.6:1234; iptables -t nat -A POSTROUTING -p tcp --dport 1234 -j MASQUERADE
PostUp = iptables -t nat -A PREROUTING -p tcp --dport 5001 -j DNAT --to-destination 192.168.2.4:5001; iptables -t nat -A POSTROUTING -p tcp --dport 5001 -j MASQUERADE
PostUp = iptables -t nat -A PREROUTING -p udp --dport 1194 -j DNAT --to-destination 192.168.2.7:1194; iptables -t nat -A POSTROUTING -p udp --dport 1194 -j MASQUERADE

PostDown = iptables -t nat -D PREROUTING -p tcp --dport 1234 -j DNAT --to-destination 192.168.2.6:1234; iptables -t nat -D POSTROUTING -p tcp --dport 1234 -j MASQUERADE
PostDown = iptables -t nat -D PREROUTING -p tcp --dport 5001 -j DNAT --to-destination 192.168.2.4:5001; iptables -t nat -D POSTROUTING -p tcp --dport 5001 -j MASQUERADE
PostDown = iptables -t nat -D PREROUTING -p udp --dport 1194 -j DNAT --to-destination 192.168.2.7:1194; iptables -t nat -D POSTROUTING -p udp --dport 1194 -j MASQUERADE

[Peer]
PublicKey = THE_PUBLIC_KEY_FROM_YOUR_VPS_WIREGUARD_INSTALL
AllowedIPs = 0.0.0.0/0
Endpoint = 1.2.3.4:55107
PersistentKeepalive = 25
```
If all of your traffic just needs to be routed to NPM, then you can delete all of the PostUp and PostDown lines.
Otherwise, you will **need to edit the PostUp and PostDown lines** to suit your needs.  Here is an explanation of the ones I have provided:

Lets say you have Home Assistant running on port 1234 on a different server (IP 192.168.2.6).  You also have a Synology (port 5001) running on a server with the IP 192.168.2.4.  Finally you have an OpenVPN server (port 1194 UDP) running on 192.168.2.7.
 * The first PostUp command will route all (tcp) traffic coming through the VPN on port 1234 to 192.168.2.6
 * The second PostUp command will route all (tcp) traffic from the VPN on port 5001 to 192.168.2.4
 * The third PostUp command will route all (udp) traffic from the VPN on port 1194 to 192.168.2.7

The postDown commands are exactly the same as the PostUp couterparts except that '-A' becomes '-D'.

# 3. Starting Wireguard
On both the VPS and Local Server, run:
```bash
sudo systemctl start wg-quick@wg0
```
After you have run both of those commands, test your connection from the VPS:
```bash
ping 10.0.0.2
```
You should see the ping replies.  If you don't please make sure you followed all of the steps and have not received any errors during the installation processes.  Once you have a good connection, run:
```bash
sudo systemctl enable wg-quick@wg0
```
on both machines to ensure that wireguard automatically starts.

# 4. Limiting Access
So now, any requests coming into your VPS will be sent to your home server.  Lets say you only have services running on 443(https for nginx), 1234(Home Assistant), 5001(Synology), and 1194 UDP(OpenVPN).  There is no reason for any other port to be open on your VPS (except 22, and 55107).  So we will use ufw to block all other access.
On your VPS, run the following commands (using your ports):
**If you aren't using 22 as the sshd port, make sure you change the first line to match your port.  If you don't; as soon as you enable ufw, you will be locked out of your VPS**
```bash
sudo ufw allow OpenSSH
sudo ufw allow 55107
sudo ufw allow 443/tcp
sudo ufw allow 1234/tcp
sudo ufw allow 5001/tcp
sudo ufw allow 1194/udp
sudo default allow routed
sudo default deny incoming
sudo ufw enable
```

On your Local Server, if you have ufw enabled, make sure you open up the same ports as you have on your VPS.  Also be sure to run ```sudo default allow routed```.  If ufw is disabled/not installed, then you don't need to worry.

I recommend installing fail2ban on both your Local Server and your VPS.  The VPS fail2ban will handle your ssh and the one on the local server can handle the others.  That's why I set it up so that all the Original IPs are sent through the VPN, so I can still block them.

# 5. All Done / References

The last thing you need to do is point your DNS records to the VPS IP.  That is outside the scope of this tutorial.

Here are the websites I used to come up with my own solution.  If you run into problems, look through these to see if you can find a solution.
[How to setup a wireguard server](https://www.cyberciti.biz/faq/ubuntu-20-04-set-up-wireguard-vpn-server/)
[Set up a wireguard vpn on ubuntu](https://www.linode.com/docs/guides/set-up-wireguard-vpn-on-ubuntu/)
[Expose server behind NAT with Wireguard and a VPS](https://golb.hplar.ch/2019/01/expose-server-vpn.html)
[Wireguard site to site](https://gist.github.com/insdavm/b1034635ab23b8839bf957aa406b5e39)
[My config for bypassing CGNAT with VPS](https://www.reddit.com/r/WireGuard/comments/duif1e/my_config_for_bypassing_cgnat_with_vps/)
[Bypass CGNAT, public access to home services](https://www.reddit.com/r/WireGuard/comments/blcxb2/bypass_cgnat_public_access_to_home_services/)

# 6. Thanks!
If you want to use Digital Ocean as your VPS, please use this [referral link](https://m.do.co/c/7680995597d6).  You'll get $100 worth of credit over 60 days and I'll get $25 worth of service credit to keep my VPS up.  Thanks.