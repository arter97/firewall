#!/bin/bash

. $(dirname $0)/common

if [[ "$1" != "skip" ]]; then
  TMP=/tmp/ipsum-$(uuidgen).txt

  until wget --spider https://raw.githubusercontent.com/stamparm/ipsum/master/ipsum.txt > /dev/null 2>&1; do
    echo "Waiting for GitHub to be accessible"
    sleep 1
  done

  while true; do
    until curl --compressed https://raw.githubusercontent.com/stamparm/ipsum/master/ipsum.txt > $TMP 2>/dev/null; do
      echo "Retrying ipsum download"
    done

    if [ $(stat -c%s $TMP) -le 65536 ]; then
      echo "WARNING: Downloaded ipsum firewall database looks wrong, retrying"
    else
      break
    fi

    sleep 1
  done

  echo "Updating firewall data"

  LINES=$(cat $TMP | grep -v '#' | wc -l)
  echo "Creating ipset set with $LINES matches"

  if ipset list -name | grep -qw "ipsum"; then
    iptables-save | grep -w "ipsum" | while read l; do
      iptables $(echo $l | sed 's/-A /-D /g')
    done
    ipset flush ipsum
    until ipset destroy ipsum; do sleep 0.1; done
  fi

  # Whitelist DNS
  cat $TMP | grep -v '#' | grep -vE $(cat /etc/resolv.conf | grep '^nameserver' | awk '{print $2}' | sed -z '$ s/\n$//' | tr '\n' '|') > ${TMP}.dns
  mv ${TMP}.dns $TMP

  # Create ipsum
  LINES=$(cat $TMP | wc -l)
  ipset create ipsum hash:ip maxelem $LINES
  cat $TMP | cut -f 1 | sed -e 's/^/add ipsum /g' | ipset restore -!
  rm $TMP
  ipset list | grep -A6 "Name: ipsum"
fi

# Call geoip script
if \
 [ ! -z "$GEOIP_TCP_PORTS" ] ||
 [ ! -z "$GEOIP_UDP_PORTS" ] ||
 [ ! -z "$GEOIP_TCP_FORWARD_PORTS" ] ||
 [ ! -z "$GEOIP_UDP_FORWARD_PORTS" ]; then
  $(dirname $0)/geoip.sh $@
fi

# Remove existing rules
iptables-save | grep -w "arter97-firewall" | while read l; do
  iptables $(echo $l | sed 's/-A /-D /g')
done
if [[ "$IPV6" == "1" ]]; then
  ip6tables-save | grep -w "arter97-firewall" | while read l; do
    ip6tables $(echo $l | sed 's/-A /-D /g')
  done
fi

# Enable ping
if [[ "$ENABLE_PING" == "1" ]]; then
  iptables -I INPUT -p icmp --icmp-type echo-request -m comment --comment "arter97-firewall" -j ACCEPT
  if [[ "$IPV6" == "1" ]]; then
    ip6tables -I INPUT -p ipv6-icmp --icmpv6-type echo-request -m comment --comment "arter97-firewall" -j ACCEPT
  fi
fi

# Whitelisted ports
if [ ! -z "$TCP_PORTS" ]; then
  iptables46 -I INPUT -p tcp -m conntrack --ctstate NEW -m multiport --dports "$TCP_PORTS" -m comment --comment "arter97-firewall" -j ACCEPT
fi
if [ ! -z "$UDP_PORTS" ]; then
  iptables46 -I INPUT -p udp -m conntrack --ctstate NEW -m multiport --dports "$UDP_PORTS" -m comment --comment "arter97-firewall" -j ACCEPT
fi

# Block bad IPs (IPv6 is unsupported)
iptables -D INPUT -m set --match-set ipsum src -j DROP 2>/dev/null
iptables -I INPUT -m set --match-set ipsum src -j DROP

# Block all incoming connections if there are whitelisted ports
if [ ! -z "$TCP_PORTS" ] || [ ! -z "$GEOIP_TCP_PORTS" ] || [ ! -z "$UDP_PORTS" ] || [ ! -z "$GEOIP_UDP_PORTS" ]; then
  # Whitelisted interface
  for i in $WHITELISTED_INTERFACES; do
    iptables46 -I INPUT -i $i -m comment --comment "arter97-firewall" -j ACCEPT
  done
  iptables46 -P INPUT DROP
fi

# Accept existing connections
iptables46 -D INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
iptables46 -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

if [[ "$APPLY_FORWARD_RULES" == "1" ]]; then
  # Whitelisted forward ports
  if [ ! -z "$TCP_FORWARD_PORTS" ]; then
    iptables46 -I FORWARD -p tcp -m conntrack --ctstate NEW -m tcp --dport "$TCP_FORWARD_PORTS" -m comment --comment "arter97-firewall" -j ACCEPT
  fi
  if [ ! -z "$UDP_FORWARD_PORTS" ]; then
    iptables46 -I FORWARD -p udp -m conntrack --ctstate NEW -m udp --dport "$UDP_FORWARD_PORTS" -m comment --comment "arter97-firewall" -j ACCEPT
  fi

  # Block all incoming connections if there are whitelisted ports
  if [ ! -z "$TCP_FORWARD_PORTS" ] || [ ! -z "$GEOIP_TCP_FORWARD_PORTS" ] || [ ! -z "$UDP_FORWARD_PORTS" ] || [ ! -z "$GEOIP_UDP_FORWARD_PORTS" ]; then
    # Whitelisted interface
    for i in $WHITELISTED_INTERFACES; do
      if [[ "$i" == "lo" ]]; then continue; fi # Skip "lo" for FORWARD
      iptables46 -I FORWARD -i $i -m comment --comment "arter97-firewall" -j ACCEPT
    done
    iptables46 -P FORWARD DROP
  fi

  # Accept existing forward connections
  iptables46 -D FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
  iptables46 -I FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
fi

# Load custom script
if [ -e $(dirname $0)/post-firewall-hook ]; then
  . $(dirname $0)/post-firewall-hook
fi

echo "Updated firewall data"
