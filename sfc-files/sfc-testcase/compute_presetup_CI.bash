#!/bin/bash

# This script must be use with vxlan-gpe + nsh. Once we have eth + nsh support
# in ODL, we will not need it anymore

set -e
ssh_options='-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
BASEDIR=`dirname $0`
INSTALLER_IP=${INSTALLER_IP:-10.20.0.2}

# Results in error: /home/opnfv/repos/functest/testcases/features/sfc/compute_presetup_CI.bash: line 13: pushd: write error: Broken pipe
#pushd $BASEDIR
ip=$(sshpass -p r00tme ssh $ssh_options root@${INSTALLER_IP} 'fuel node'|grep compute| awk '{print $9}' | head -1)

sshpass -p r00tme ssh $ssh_options root@${INSTALLER_IP} 'ssh root@'"$ip"' ifconfig br-int up'
output=$(sshpass -p r00tme ssh $ssh_options root@${INSTALLER_IP} 'ssh root@'"$ip"' ip route | \
cut -d" " -f1 | grep 11.0.0.0')

# didn't worked and hang added manualy
if [ -z "$output" ]; then
sshpass -p r00tme ssh $ssh_options root@${INSTALLER_IP} 'ssh root@'"$ip"' ip route add 11.0.0.0/24 \
dev br-int'
fi
