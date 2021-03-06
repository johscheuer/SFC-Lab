# Bare-metal Installation with Fuel

## Jumphost

OS: Ubuntu 16.04

```bash
sudo systemctl disable NetworkManager
sudo service network restart

sudo apt-get -qq -y install bridge-utils qemu-kvm libvirt-bin virtinst arping iptables-persistent vlan
sudo adduser $USER libvirtd

sudo tee -a /etc/network/interfaces <<-'EOF'
# Managment Network
iface enp11s0f0 inet manual

# br-enp11s0f0, the Admin (PXE) network bridge used to connect Fuel VM's eth0 to Admin (PXE) network.
auto br-enp11s0f0
iface br-enp11s0f0 inet static
    hwaddress ether $(ip address show dev enp11s0f0 | awk '$1=="link/ether" {print $2}')
    address 10.20.0.1
    network 10.20.0.0
    netmask 255.255.255.0
    broadcast 10.20.0.255
    bridge_ports enp11s0f0
    bridge_stp off
    bridge_fd 0
    bridge_maxwait 0

iface enp4s0f1 inet manual

# Public Network 172.16.0.0/24 (VID 104)
auto enp4s0f1.104
iface enp4s0f1.104 inet static
    address 172.16.0.1
    netmask 255.255.255.0
    vlan-raw-device enp4s0f1

# Storage Network 192.168.1.0/24 (VID 102)
auto enp4s0f1.102
iface enp4s0f1.102 inet static
    address 192.168.1.1
    netmask 255.255.255.0
    vlan-raw-device enp4s0f1

# Management Network 192.168.0.0/24 (VID 101)
auto enp4s0f1.101
iface enp4s0f1.101 inet static
    address 192.168.0.1
    netmask 255.255.255.0
    vlan-raw-device enp4s0f1

# Private Network 192.168.2.0/24 (VID 103)
auto enp4s0f1.103
iface enp4s0f1.103 inet static
    address 192.168.2.1
    netmask 255.255.255.0
    vlan-raw-device enp4s0f1

# IPMI network
auto enp11s0f1
iface enp11s0f1 inet static
    address 192.168.106.43
    netmask 255.255.255.0
    mtu 1500
EOF

sudo modprobe 8021q
sudo modprobe br_netfilter
sudo sh -c 'echo -e "br_netfilter\n8021q" >> /etc/modules'

reboot

brctl show br-enp11s0f0
sudo cat /proc/net/vlan/config
route -n

sudo iptables -F

# Allow Jump Host as gateway - validate these
sudo iptables -t nat -A POSTROUTING -o enp4s0f0 -j MASQUERADE
sudo iptables -A FORWARD -i enp11s0f0 -o enp4s0f0 -j ACCEPT
sudo iptables -A FORWARD -i enp4s0f0 -o enp11s0f0 -m state --state RELATED,ESTABLISHED -j ACCEPT

sudo iptables -A FORWARD -i br-enp11s0f0 -o enp4s0f0 -j ACCEPT
sudo iptables -A FORWARD -i enp4s0f0 -o br-enp11s0f0 -m state --state RELATED,ESTABLISHED -j ACCEPT

sudo iptables -A FORWARD -i enp4s0f1 -o enp4s0f0 -j ACCEPT
sudo iptables -A FORWARD -i enp4s0f0 -o enp4s0f1 -m state --state RELATED,ESTABLISHED -j ACCEPT

sudo iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS  --clamp-mss-to-pmtu

sudo iptables-save > ~/iptables-rules/ruleset-v4
sudo ip6tables-save > ~/iptables-rules/ruleset-v6

# Setting for systctl
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=0
sudo sysctl -w net.bridge.bridge-nf-call-iptables=0
sudo sysctl -w net.bridge.bridge-nf-call-arptables=0
sudo sysctl -w net.ipv6.conf.all.forwarding=1
sudo sysctl -w net.ipv4.conf.all.forwarding=1
sudo sysctl -p

rm -f ~/opnfv_fuel.iso && curl -sLo ~/opnfv_fuel.iso http://artifacts.opnfv.org/fuel/danube/opnfv-danube.1.0.iso

# Start the Fuel Master
sudo virt-install -n opnfv_fuel \
                  -r 8192 \
                  --vcpus=4 \
                  --cpuset=0-3 \
                  -c ~/opnfv_fuel.iso \
                  --os-type=linux \
                  --os-variant=rhel7 \
                  --boot hd,cdrom \
                  --disk path=/var/lib/libvirt/images/opnfv_fuel.qcow2,bus=virtio,size=50,format=qcow2 \
                  -w bridge=br-enp11s0f0,model=virtio \
                  --graphics vnc,listen=0.0.0.0

# Auto Start Fuel VM
sudo virsh autostart opnfv_fuel

# get VNC port
sudo virsh vncdisplay opnfv_fuel
```

## Fuel

- eth0
- Default gateway `10.20.0.1`
- Change DNS to 10.20.0.2 (Fuel VM IP)
- Shell login
- Ensure that 10.20.0.1 is the default gw `route -n` -> `route add default gw 10.20.0.1 eth0`
- use default PXE and NTP settings
- External DNS `8.8.8.8`
- Save & Quit

### Access Fuel VM

ssh into fuel VM:

```bash
# Password if not set: r00tme
ssh-copy-id -i ~/.ssh/id_rsa root@10.20.0.2
ssh root@10.20.0.2
```

Allow Traffic forwarding

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -p

sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

### Install Fuel Plugins

List all installed fuel plugins:

```bash
fuel plugins
```

All OPNFV related fuel plugins are on `/opt/opnfv/` for the scenario `no-ha_odl-l2_sfc_heat_ceilometer_scenario.yaml` you need to install the following plugins:

```bash
fuel plugins --install /opt/opnfv/opendaylight-*.noarch.rpm
fuel plugins --install /opt/opnfv/fuel-plugin-ovs-*.noarch.rpm
fuel plugins --install /opt/opnfv/tacker-*.noarch.rpm
# Optional
fuel plugins --install /opt/opnfv/fuel-plugin-kvm-*.noarch.rpm
```

Validate all Plugins:

```bash
fuel plugins --list
```

### Add Fuel Nodes

```bash
fuel node list
```

Now reboot all Fuel Slave Nodes (do this on the Jump Host not inside the Fuel VM):

```bash
sudo modprobe ipmi_devintf
sudo modprobe ipmi_si
# make it persistent
sudo sh -c 'echo -e "ipmi_devintf\nipmi_si" > /etc/modules'
sudo apt-get -qq -y install ipmitool openipmi freeipmi-tools

export NODES=(192.168.106.112 192.168.106.113 192.168.106.114)
for i in "${NODES[@]}"; do sudo ipmitool -I lanplus -H $i -U root -P changeme chassis power off; done
sleep 10
for i in "${NODES[@]}"; do sudo ipmitool -I lanplus -H $i -U root -P changeme chassis power on; done
sleep 10
for i in "${NODES[@]}"; do sudo ipmitool -I lanplus -H $i -U root -P changeme chassis power status; done
```

It takes a little bit to boot all nodes, then go to `equipment` and you should see the newly booted machines.

```bash
fuel node list
```

### Access Fuel Web UI

Tunnel the traffic over ssh (if needed):

```bash
ssh -A -t user@host1 -L 8443:localhost:8443 ssh -A -t user@host2 -L 8443:10.20.0.2:8443
```

User: `admin` and password: `admin`

## Deploy OPNFV

### Setup an environment

- Name: `OPNFV`
- Compute: `QEMU-KVM`
- Network: `OpenDayLight with tunneling segmentation`
- Storage: `Ceph`

### Setttings

#### Security

- [X] Open vSwitch Firewall Driver

#### Compute

- [X] KVM
- [X] Resume guests state on host boot

#### Storage

- [X] Use qcow format for images
- [X] Ceph RBD for volumes (Cinder)
- [X] Ceph RBD for images (Glance)
- [X] Ceph RBD for ephemeral volumes (Nova)
- [X] Ceph RadosGW for objects (Swift API)

IF you have less then 3 Ceph Nodes set `Ceph object replication factor` to the number of Ceph Nodes - 1 (not recommended).

#### Other

- [X] Install Open vSwitch with NSH

  - [X] Install NSH
  - [X] Install same OVS version on the Controller

- [X] OpenDaylight plugin

- [X] SFC features (NetVirt)

- OpenDaylight Version: `5.2.0-1`

#### OpenStack Services

- [X] Tacker VNF manager

### Networks

#### Other

- [X] Neutron L2 population
- [X] Assign public network to all nodes

### Nodes

#### Controller

- [X] Controller
- [X] Tacker
- [X] OpenDaylight
- [X] Ceph-OSD
- [X] Base-OS

#### Compute

- [X] Compute
- [X] Ceph-OSD
- [X] Base-OS

#### Setup Network Interfaces

Select all Nodes -> Configure interfaces

- enp4s0f0: `Admin (PXE)`
- enp11s0f1: `Public (VID 104), Management (VID 101), Storage (VID 102), Private (VID 103)`

Click apply and wait.

#### Fuel Nodes SSH

If you want to be able to login into the OPNFV Nodes from your Jump Host (not the fuel VM) execute the following steps:

```bash
scp -r root@10.20.0.2:/root/.ssh/* ~/.ssh/fuel
ssh -i ~/.ssh/fuel 10.20.0.4 -l root
```

or use the Jumphost:

```bash
ssh -A -t root@10.20.0.2 ssh -A -t 10.20.0.4
```

#### Setup Network

We need to setup the network to make the Network checks succeed. SSH into each Fuel Node and execute the following steps:

```bash
sudo modprobe 8021q
sudo sh -c 'echo -e "8021q" >> /etc/modules'

export LAST_BYTE=$(ifconfig enp4s0f0 | grep 'inet addr' | cut -d: -f2 | awk '{print $1}' | awk -F. '{print $4}')

echo "iface enp11s0f1 inet manual

# Public Network 172.16.0.0/24 (VID 104)
auto enp11s0f1.104
iface enp11s0f1.104 inet static
    address 172.16.0.${LAST_BYTE}
    netmask 255.255.255.0
    vlan-raw-device enp11s0f1

# Storage Network 192.168.1.0/24 (VID 102)
auto enp11s0f1.102
iface enp11s0f1.102 inet static
    address 192.168.1.${LAST_BYTE}
    netmask 255.255.255.0
    vlan-raw-device enp11s0f1

# Management Network 192.168.0.0/24 (VID 101)
auto enp11s0f1.101
iface enp11s0f1.101 inet static
    address 192.168.0.${LAST_BYTE}
    netmask 255.255.255.0
    vlan-raw-device enp11s0f1

# Private Network 192.168.2.0/24 (VID 103)
auto enp11s0f1.103
iface enp11s0f1.103 inet static
    address 192.168.2.${LAST_BYTE}
    netmask 255.255.255.0
    vlan-raw-device enp11s0f1

# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d" > /etc/network/interfaces

ifdown enp11s0f1; ifup enp11s0f1
ifdown enp11s0f1.102; ifup enp11s0f1.102
ifdown enp11s0f1.101; ifup enp11s0f1.101
ifdown enp11s0f1.103; ifup enp11s0f1.103
ifdown enp11s0f1.104; ifup enp11s0f1.104

cat /proc/net/vlan/config
```

### Deployment

Go to the `Dashboard` and press deploy now you can grab a coffee and comeback later :)

### Tacker UI

On the Controller Node:

```bash
git clone -b SFC https://github.com/trozet/tacker-horizon.git
cd tacker-horizon/
sudo python setup.py install
cp openstack_dashboard_extensions/* /usr/share/openstack-dashboard/openstack_dashboard/enabled/
sudo service apache2 restart
```

### SSH pass

Install this tool for simple ssh authentication (**only for testing!**) On the Controller Node:

```bash
apt-get update
apt-get -qq install -y sshpass
```

### Auto Complete

To use auto complete in the openstack cli use the following commands:

```bash
openstack complete | sudo tee /etc/bash_completion.d/osc.bash_completion > /dev/null
. ~/.bashrc
```

### SFC testing

[SFC testing](./sfc_testing.md)

### SFC/VNF demo

[SFC demo](docs/sfc_demo.md)

### Clean Up

If you want to delete the fuel VM execute the following steps

```bash
sudo virsh destroy opnfv_fuel
sudo virsh undefine opnfv_fuel
sudo rm /var/lib/libvirt/images/opnfv_fuel.qcow2
```

## Danube

Currently the generated `tackerc` file is missing two env variables:

```bash
echo -e "export OS_USER_DOMAIN_NAME='Default'\nexport OS_PROJECT_DOMAIN_NAME='Default'" >> tackerc
```
