#!/bin/bash

. $(dirname $0)/common

ipset_func() {
  VAR="$1"
  IPTABLES="$2"             # "iptables" or "ip6tables"
  IPTABLES_CHAIN="$3"       # "INPUT" or "FORWARD"
  IPTABLES_PROTO="$4"       # "tcp" or "udp"
  IPTABLES_PORT_MODULE="$5" # "multiport" (INPUT) or "tcp"/"udp" (FORWARD)
  IP="$6"                   # "ipv4" or "ipv6"
  IPSET_PREFIX="$7"         # "ipset" or "ipset6"
  IPSET_CREATE_ARG="$8"     # null or "family inet6"

  if [ -z "$VAR" ]; then return; fi

  echo "$VAR" | while read line; do
    # Get list of countries
    COUNTRY=""
    PORTS=""
    TMP=/tmp/geoip-$(uuidgen)
    for token in $line; do
      if [ -e "$IP/${token}.cidr" ]; then
        cat "$IP/${token}.cidr" >> $TMP
        COUNTRY="$token $COUNTRY"
      else
        PORTS="$token"
        break
      fi
    done
    LINES=$(cat $TMP | wc -l)
    IPSET_NAME=${IPSET_PREFIX}-geoip-$(echo $COUNTRY | tr -d ' ')
    if ! ipset list -name | grep -qw "$IPSET_NAME"; then
      echo "Building ipset $IPSET_NAME for $COUNTRY"
      ipset create $IPSET_NAME hash:net maxelem ${LINES} $IPSET_CREATE_ARG
      cat $TMP | sed -e "s/^/add $IPSET_NAME /g" | ipset restore -!
    fi
    rm $TMP
    $IPTABLES -I $IPTABLES_CHAIN -p $IPTABLES_PROTO -m conntrack --ctstate NEW -m $IPTABLES_PORT_MODULE --dport "$PORTS" -m set --match-set $IPSET_NAME src -j ACCEPT
  done
}

if [[ "$1" != "skip" ]]; then
  echo "Updating GeoIP"

  cd $(dirname $0)
  if [ ! -d country-ip-blocks ]; then
    git clone https://github.com/herrbischoff/country-ip-blocks
  fi
  cd country-ip-blocks
  git fetch
  git reset --hard origin/master
fi

cd $ROOTDIR/country-ip-blocks

# Get all geoip ports
GEOIP_ALL_TCP_PORTS="$(echo "$GEOIP_TCP_PORTS" | tr ' ' '\n' | grep '^[0-9]')"
GEOIP_ALL_UDP_PORTS="$(echo "$GEOIP_UDP_PORTS" | tr ' ' '\n' | grep '^[0-9]')"
GEOIP_ALL_TCP_FORWARD_PORTS="$(echo "$GEOIP_TCP_FORWARD_PORTS" | tr ' ' '\n' | grep '^[0-9]')"
GEOIP_ALL_UDP_FORWARD_PORTS="$(echo "$GEOIP_UDP_FORWARD_PORTS" | tr ' ' '\n' | grep '^[0-9]')"

# IPv4

# Remove existing geoip rules
iptables-save | grep -w ipset-geoip | while read l; do
  iptables $(echo $l | sed 's/-A /-D /g')
done
ipset list -name | grep -w ipset-geoip | while read IPSET_NAME; do
  ipset flush $IPSET_NAME
  until ipset destroy $IPSET_NAME; do sleep 0.1; done
done

# Sanity check
if ! ls ipv4/ | grep -q '\.cidr$'; then
  echo "country-ip-blocks repository data error, opening IPv4 ports to all countries"
  if [ ! -z "$GEOIP_TCP_PORTS" ]; then
    iptables -I INPUT -p tcp -m conntrack --ctstate NEW -m multiport --dport "$GEOIP_ALL_TCP_PORTS" -m comment --comment "ipset-geoip-data-error" -j ACCEPT
  fi
  if [ ! -z "$GEOIP_UDP_PORTS" ]; then
    iptables -I INPUT -p udp -m conntrack --ctstate NEW -m multiport --dport "$GEOIP_ALL_UDP_PORTS" -m comment --comment "ipset-geoip-data-error" -j ACCEPT
  fi
  if [[ "$APPLY_FORWARD_RULES" == "1" ]]; then
    if [ ! -z "$GEOIP_TCP_FORWARD_PORTS" ]; then
      iptables -I FORWARD -p tcp -m conntrack --ctstate NEW -m multiport --dport "$GEOIP_ALL_TCP_FORWARD_PORTS" -m comment --comment "ipset-geoip-data-error" -j ACCEPT
    fi
    if [ ! -z "$GEOIP_UDP_FORWARD_PORTS" ]; then
      iptables -I FORWARD -p udp -m conntrack --ctstate NEW -m multiport --dport "$GEOIP_ALL_UDP_FORWARD_PORTS" -m comment --comment "ipset-geoip-data-error" -j ACCEPT
    fi
  fi
else
  # Compile ipv4
  ipset_func "$GEOIP_TCP_PORTS" iptables INPUT tcp multiport ipv4 ipset
  ipset_func "$GEOIP_UDP_PORTS" iptables INPUT udp multiport ipv4 ipset
  if [[ "$APPLY_FORWARD_RULES" == "1" ]]; then
    ipset_func "$GEOIP_TCP_FORWARD_PORTS" iptables FORWARD tcp tcp ipv4 ipset
    ipset_func "$GEOIP_UDP_FORWARD_PORTS" iptables FORWARD udp udp ipv4 ipset
  fi
fi

# IPv6
if [[ "$IPV6" != "1" ]]; then
  exit 0
fi

# Remove existing geoip rules
ip6tables-save | grep ipset6-geoip | while read l; do
  ip6tables $(echo $l | sed 's/-A /-D /g')
done
ipset list -name | grep -w ipset6-geoip | while read IPSET_NAME; do
  ipset flush $IPSET_NAME
  until ipset destroy $IPSET_NAME; do sleep 0.1; done
done

# Sanity check
if ! ls ipv6/ | grep -q '\.cidr$'; then
  echo "country-ip-blocks repository data error, opening IPv6 ports to all countries"
  if [ ! -z "$GEOIP_TCP_PORTS" ]; then
    ip6tables -I INPUT -p tcp -m conntrack --ctstate NEW -m multiport --dport "$GEOIP_ALL_TCP_PORTS" -m comment --comment "ipset6-geoip-data-error" -j ACCEPT
  fi
  if [ ! -z "$GEOIP_UDP_PORTS" ]; then
    ip6tables -I INPUT -p udp -m conntrack --ctstate NEW -m multiport --dport "$GEOIP_ALL_UDP_PORTS" -m comment --comment "ipset6-geoip-data-error" -j ACCEPT
  fi
  if [[ "$APPLY_FORWARD_RULES" == "1" ]]; then
    if [ ! -z "$GEOIP_TCP_FORWARD_PORTS" ]; then
      ip6tables -I FORWARD -p tcp -m conntrack --ctstate NEW -m multiport --dport "$GEOIP_ALL_TCP_FORWARD_PORTS" -m comment --comment "ipset6-geoip-data-error" -j ACCEPT
    fi
    if [ ! -z "$GEOIP_UDP_FORWARD_PORTS" ]; then
      ip6tables -I FORWARD -p udp -m conntrack --ctstate NEW -m multiport --dport "$GEOIP_ALL_UDP_FORWARD_PORTS" -m comment --comment "ipset6-geoip-data-error" -j ACCEPT
    fi
  fi
else
  # Compile ipv6
  ipset_func "$GEOIP_TCP_PORTS" ip6tables INPUT tcp multiport ipv6 ipset6 "family inet6"
  ipset_func "$GEOIP_UDP_PORTS" ip6tables INPUT udp multiport ipv6 ipset6 "family inet6"
  if [[ "$APPLY_FORWARD_RULES" == "1" ]]; then
    ipset_func "$GEOIP_TCP_FORWARD_PORTS" ip6tables FORWARD tcp tcp ipv6 ipset6 "family inet6"
    ipset_func "$GEOIP_UDP_FORWARD_PORTS" ip6tables FORWARD udp udp ipv6 ipset6 "family inet6"
  fi
fi
