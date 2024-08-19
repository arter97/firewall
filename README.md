# GeoIP and bad IP filtering for Linux

This repository contains several script to provide protections against malicious IPs and provide Country-based port opening.

This repository uses [stamparm/ipsum](https://github.com/stamparm/ipsum) for malicious IP database and [MaxMind's GeoIP/GeoLite](https://www.maxmind.com) for Geolocation CIDR database. If you do not trust those, do not use this repository either.

You need to write your own GeoIP/GeoLite's URL to the config file.

## Features

 * Ban malicious IPv4 IPs using lightweight ipset
 * Location-based port opening (e.g., SSH port only allowed in Korea)

## Warning

 * **Do not attempt to install this script over the network without a way to recover. Make sure you can recover (reboot) from a script failure or config mistake.**
 * Malicious IP is banned only on IPv4 as the upstream repository does not provide IPv6 lists.
 * Using this with ufw is not tested and not recommended.

## Config

 * A valid config must be located at the same path.
 * Example config:

```
# Log path
LOG_PATH=/var/log/firewall.log
# Enable ICMP echo-request to allow ping requests
ENABLE_PING=1
# Disable IPv6 rules
IPV6=0
# Allowed TCP ports, no country limit: 80, 443 and 5000 to 6000
TCP_PORTS="80,443,5000:6000"
# Allowed UDP ports, no country limit: 443 and 60000 to 61000
UDP_PORTS="443,60000:61000"
# Whitelisted interfaces, firewall rules are excluded from those interfaces
WHITELISTED_INTERFACES="lo enx1831bf4dd4ff enx6805cad2ee1b wg0"
# Country-based port
GEOIP_TCP_PORTS="kr us 80,443"
GEOIP_UDP_PORTS="kr us 30000:40000"
# Apply forward rules for NAT
APPLY_FORWARD_RULES=1
TCP_FORWARD_PORTS="7000:8000"
UDP_FORWARD_PORTS="70000:80000"
GEOIP_TCP_FORWARD_PORTS="kr 7500:8000"
GEOIP_UDP_FORWARD_PORTS="kr 75000:80000"
# MaxMind's GeoLite2 URL with token
GEOIP_CSV_ZIP_LINK="https://download.maxmind.com/app/geoip_download_by_token?edition_id=GeoLite2-Country-CSV&token=[YOUR_TOKEN]&suffix=zip"
```

#### - LOG_PATH

Log path for both stdout and stderr.

#### - ENABLE_PING

Enable or disable ICMP echo-request to allow ping requests.

#### - IPV6

Enable or disable IPv6 rules.

Do note that Malicious IP is banned only on IPv4 as the upstream repository does not provide IPv6 lists.

You do not need to set this if you're system is not exposed through IPv6 address.

#### - TCP_PORTS, UDP_PORTS

Allowed TCP/UDP ports, no country limit. See above for example.

#### - WHITELISTED_INTERFACES

Whitelisted interfaces. Firewall rules are excluded from those interfaces. Intended for internal network.

In most cases, "lo" must always be included for proper 127.0.0.1 operation.

#### - GEOIP_TCP_PORTS, GEOIP_UDP_PORTS

Country-based port access. This variable accepts multi-line. Each line denotes which ports should be opened to which country(ies). Country should be written in [ccTLD](https://en.wikipedia.org/wiki/Country_code_top-level_domain) format.

#### - GEOIP_CSV_ZIP_LINK

MaxMind's direct link with personal token.

You may use `GEOIP_IPV4_CSV_LINK` and `GEOIP_IPV6_CSV_LINK` as alternatives.

### Forwarding rules

Some rules can be applied specific to the `FORWARD` chain.

#### - TCP_FORWARD_PORTS, UDP_FORWARD_PORTS

Same as `TCP_PORTS` and `UDP_PORTS`, but for the `FORWARD` chain.

#### - GEOIP_TCP_FORWARD_PORTS, GEOIP_UDP_FORWARD_PORTS

Same as `GEOIP_TCP_PORTS` and `GEOIP_UDP_PORTS`, but for the `FORWARD` chain.

##### Syntax

```
COUNTRY1 [ COUNTRY2, COUNTRY3, ... ] PORTS
```

##### Examples

```
GEOIP="kr us 80,2222
kr 7000:8000"
```

 * Allow ports 80 and 2222 to Korea and United States, allow ports from 7000 to 8000 to Korea only.

## Installation

### 1. Install required packages

``` bash
sudo apt install iptables ipset curl wget git python3-netaddr unzip
```

### 2. Download

``` bash
sudo -s
cd /root
git clone https://github.com/arter97/firewall.git
```

 * As this script will be executed as root, it is recommended to have it installed to a directory that's only accessible by root (e.g., `/root`).

### 3. Configure

``` bash
cd firewall
vim config
```

 * See [config](#config) and configure firewall.

 * A custom post script can be added to `post-firewall-hook` at the same directory.

### 4. Install

``` bash
# Run it once manually so it's effective without a reboot
sudo /root/firewall/firewall.sh
# Add it to crontab
sudo crontab -e
```

 * You can pass `skip` to the first argument of `firewall.sh` to skip network pull. Use this to quickly test new rules.

```
@reboot /root/firewall
0 5 * * * /root/firewall
```

 * This will run the script on each reboot and 05:00 AM everyday.

 * Visit [crontab guru](https://crontab.guru) to customize timings.

### 5. View logs

``` bash
sudo cat /var/log/firewall.log
```

## Demo

 * Installation

``` bash
# ./firewall.sh 
Starting ./firewall.sh: Sat Aug 17 02:01:20 AM KST 2024
Updating firewall data
Creating ipset set with 177240 matches
Name: ipsum
Type: hash:ip
Revision: 6
Header: family inet hashsize 65536 maxelem 177240 bucketsize 12 initval 0xc5560cb0
Size in memory: 4199488
References: 0
Number of entries: 177240
Starting ./geoip.sh: Sat Aug 17 02:01:21 AM KST 2024
Updating GeoIP
HEAD is now at 7a5bbabc1235 Update 2024-08-16T17:00:22+00:00
Building ipset ipset-geoip-uskr for us kr 
Building ipset ipset-geoip-kr for kr 
Updated firewall data
```

 * Before

``` bash
# iptables-save
# Generated by iptables-save v1.8.10 (nf_tables) on Sat Aug 17 00:28:07 2024
*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [1184197:24923822483]
:POSTROUTING ACCEPT [0:0]
COMMIT
# Completed on Sat Aug 17 00:28:07 2024
# Generated by iptables-save v1.8.10 (nf_tables) on Sat Aug 17 00:28:07 2024
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
# Completed on Sat Aug 17 00:28:08 2024

```

 * After

``` bash
# iptables-save
# Generated by iptables-save v1.8.10 (nf_tables) on Sat Aug 17 02:01:35 2024
*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [1210668:24927874993]
:POSTROUTING ACCEPT [0:0]
COMMIT
# Completed on Sat Aug 17 02:01:35 2024
# Generated by iptables-save v1.8.10 (nf_tables) on Sat Aug 17 02:01:35 2024
*filter
:INPUT DROP [6:1206]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -i wg0 -m comment --comment arter97-firewall -j ACCEPT
-A INPUT -i enx6805cad2ee1b -m comment --comment arter97-firewall -j ACCEPT
-A INPUT -i enx1831bf4dd4ff -m comment --comment arter97-firewall -j ACCEPT
-A INPUT -i lo -m comment --comment arter97-firewall -j ACCEPT
-A INPUT -m set --match-set ipsum src -j DROP
-A INPUT -p udp -m conntrack --ctstate NEW -m multiport --dports 443,60000:61000 -m comment --comment arter97-firewall -j ACCEPT
-A INPUT -p tcp -m conntrack --ctstate NEW -m multiport --dports 80,443,5000:6000 -m comment --comment arter97-firewall -j ACCEPT
-A INPUT -p icmp -m icmp --icmp-type 8 -m comment --comment arter97-firewall -j ACCEPT
-A INPUT -p udp -m conntrack --ctstate NEW -m multiport --dports 30000:40000 -m set --match-set ipset-geoip-uskr src -j ACCEPT
-A INPUT -p tcp -m conntrack --ctstate NEW -m multiport --dports 80,443 -m set --match-set ipset-geoip-uskr src -j ACCEPT
-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i wg0 -m comment --comment arter97-firewall -j ACCEPT
-A FORWARD -i enx6805cad2ee1b -m comment --comment arter97-firewall -j ACCEPT
-A FORWARD -i enx1831bf4dd4ff -m comment --comment arter97-firewall -j ACCEPT
-A FORWARD -i lo -m comment --comment arter97-firewall -j ACCEPT
-A FORWARD -m set --match-set ipsum src -j DROP
-A FORWARD -p udp -m conntrack --ctstate NEW -m udp --dport 4464:14464 -m comment --comment arter97-firewall -j ACCEPT
-A FORWARD -p tcp -m conntrack --ctstate NEW -m tcp --dport 7000:8000 -m comment --comment arter97-firewall -j ACCEPT
-A FORWARD -p udp -m conntrack --ctstate NEW -m udp --dport 9464:14464 -m set --match-set ipset-geoip-kr src -j ACCEPT
-A FORWARD -p tcp -m conntrack --ctstate NEW -m tcp --dport 7500:8000 -m set --match-set ipset-geoip-kr src -j ACCEPT
COMMIT
# Completed on Sat Aug 17 02:01:35 2024
```
