# Merge and shorten CIDR list, requires python3-netaddr

import sys
from netaddr import IPSet

input = sys.stdin.readlines()
nets = IPSet(input)
for cidr in nets.iter_cidrs():
    print(cidr)
