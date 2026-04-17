# VyOS Router VM Deployment Guide

Quick guide for deploying VyOS router VMs on your nested virtualization host.

## Quick Start

Deploy a VyOS router VM with one command:

```bash
ansible-playbook deploy-vyos-vm.yml
```

This will:
1. ✅ Download VyOS ISO (if not already present)
2. ✅ Create a VM with 2GB RAM, 2 vCPUs, 20GB disk
3. ✅ Automatically install VyOS to disk
4. ✅ Configure VM to boot from disk
5. ✅ Start the VM

**Default credentials:**
- Username: `vyos`
- Password: `vyos`

## Custom Configuration

### Change VM Specifications

```bash
ansible-playbook deploy-vyos-vm.yml \
  -e vyos_vm_name=my-router \
  -e vyos_vm_memory=4096 \
  -e vyos_vm_vcpus=4 \
  -e vyos_vm_disk_size=40
```

### Set Custom Password

```bash
ansible-playbook deploy-vyos-vm.yml \
  -e vyos_root_password=MySecurePassword123
```

### Custom Network Settings

```bash
ansible-playbook deploy-vyos-vm.yml \
  -e vyos_vm_mac_address=52:54:00:aa:bb:cc \
  -e vyos_management_ip=192.168.122.150/24
```

### Manual Installation (No Automation)

```bash
ansible-playbook deploy-vyos-vm.yml \
  -e vyos_auto_install=false
```

Then connect to console and install manually:
```bash
ssh ec2-user@3.144.128.251 -i ~/.ssh/id_rsa_fips
sudo virsh console vyos-router
# Login: vyos / vyos
# Run: install image
# Follow prompts
```

## Accessing Your VyOS Router

### Via VM Console

```bash
# SSH to EC2 instance
ssh ec2-user@3.144.128.251 -i ~/.ssh/id_rsa_fips

# Connect to VyOS console
sudo virsh console vyos-router

# Login credentials
# Username: vyos
# Password: vyos (or your custom password)

# Exit console: Press Ctrl+]
```

### Via noVNC (Web Browser)

1. **Open noVNC in browser:**
   ```
   https://3.144.128.251:6081/vnc.html
   ```

2. **In the desktop, open terminal:**
   ```bash
   sudo virsh console vyos-router
   ```

3. **Or use virt-manager GUI** (if installed)

## Initial VyOS Configuration

After installation, configure VyOS networking and services:

```bash
# Connect to VyOS
sudo virsh console vyos-router

# Login with vyos/vyos

# Enter configuration mode
configure

# Set hostname
set system host-name vyos-router

# Configure management interface
set interfaces ethernet eth0 address 192.168.122.100/24
set interfaces ethernet eth0 description 'Management'

# Set default gateway
set protocols static route 0.0.0.0/0 next-hop 192.168.122.1

# Configure DNS
set system name-server 8.8.8.8
set system name-server 1.1.1.1

# Enable SSH
set service ssh port 22

# Configure NTP
set system ntp server time.google.com

# Commit and save
commit
save
exit
```

## SSH Access to VyOS

After configuring the network interface:

```bash
# From EC2 instance
ssh vyos@192.168.122.100

# Or from your laptop via EC2 as jump host
ssh -J ec2-user@3.144.128.251 vyos@192.168.122.100 -i ~/.ssh/id_rsa_fips
```

## Common VyOS Configurations

### NAT Router

```bash
configure

# Outside interface (connected to internet)
set interfaces ethernet eth0 address dhcp
set interfaces ethernet eth0 description 'WAN'

# Inside interface (private network)
set interfaces ethernet eth1 address 10.0.0.1/24
set interfaces ethernet eth1 description 'LAN'

# NAT configuration
set nat source rule 100 outbound-interface 'eth0'
set nat source rule 100 source address '10.0.0.0/24'
set nat source rule 100 translation address 'masquerade'

# DHCP server for LAN
set service dhcp-server shared-network-name LAN subnet 10.0.0.0/24 range 0 start 10.0.0.100
set service dhcp-server shared-network-name LAN subnet 10.0.0.0/24 range 0 stop 10.0.0.200
set service dhcp-server shared-network-name LAN subnet 10.0.0.0/24 default-router 10.0.0.1
set service dhcp-server shared-network-name LAN subnet 10.0.0.0/24 name-server 8.8.8.8

commit
save
```

### Firewall Rules

```bash
configure

# Create firewall rule set
set firewall name WAN-LOCAL default-action drop
set firewall name WAN-LOCAL rule 10 action accept
set firewall name WAN-LOCAL rule 10 state established enable
set firewall name WAN-LOCAL rule 10 state related enable
set firewall name WAN-LOCAL rule 20 action drop
set firewall name WAN-LOCAL rule 20 state invalid enable

# Allow SSH
set firewall name WAN-LOCAL rule 30 action accept
set firewall name WAN-LOCAL rule 30 destination port 22
set firewall name WAN-LOCAL rule 30 protocol tcp

# Apply to interface
set interfaces ethernet eth0 firewall local name WAN-LOCAL

commit
save
```

### VPN Server (WireGuard)

```bash
configure

# Generate key pair
run generate pki wireguard key-pair

# Configure WireGuard interface
set interfaces wireguard wg0 address 10.10.0.1/24
set interfaces wireguard wg0 description 'VPN'
set interfaces wireguard wg0 port 51820
set interfaces wireguard wg0 private-key <YOUR_PRIVATE_KEY>

# Add peer
set interfaces wireguard wg0 peer client1 allowed-ips 10.10.0.2/32
set interfaces wireguard wg0 peer client1 public-key <CLIENT_PUBLIC_KEY>

# Firewall rule for WireGuard
set firewall name WAN-LOCAL rule 40 action accept
set firewall name WAN-LOCAL rule 40 destination port 51820
set firewall name WAN-LOCAL rule 40 protocol udp

commit
save
```

## VM Management

### Basic Operations

```bash
# Check VM status
sudo virsh domstate vyos-router

# Start VM
sudo virsh start vyos-router

# Graceful shutdown
sudo virsh shutdown vyos-router

# Force shutdown
sudo virsh destroy vyos-router

# Reboot VM
sudo virsh reboot vyos-router

# Get VM info
sudo virsh dominfo vyos-router
```

### Network Information

```bash
# Get VM IP address
sudo virsh domifaddr vyos-router

# List all VMs
sudo virsh list --all

# Get VNC display port
sudo virsh domdisplay vyos-router
```

### Delete VM

```bash
# Delete VM (keeps disk)
sudo virsh undefine vyos-router

# Delete VM and all storage
sudo virsh undefine vyos-router --remove-all-storage
```

## Deploying Multiple VyOS VMs

Create a custom playbook for multiple routers:

```yaml
---
- name: Deploy multiple VyOS routers
  hosts: nested_virt_hosts
  become: true
  
  tasks:
    - name: Deploy VyOS routers
      include_role:
        name: vyos_vm
      vars:
        vyos_vm_name: "{{ item.name }}"
        vyos_vm_mac_address: "{{ item.mac }}"
        vyos_root_password: "{{ item.password }}"
      loop:
        - name: vyos-router-1
          mac: "52:54:00:6b:3c:58"
          password: "router1pass"
        - name: vyos-router-2
          mac: "52:54:00:6b:3c:59"
          password: "router2pass"
```

## Troubleshooting

### VM Won't Start

```bash
# Check logs
sudo journalctl -u libvirtd -n 50

# Check QEMU logs
sudo tail -50 /var/log/libvirt/qemu/vyos-router.log

# Check VM definition
sudo virsh dumpxml vyos-router
```

### Can't Connect to Console

```bash
# List all VMs
sudo virsh list --all

# Force restart
sudo virsh destroy vyos-router
sudo virsh start vyos-router

# Wait 30 seconds, then retry
sleep 30
sudo virsh console vyos-router
```

### Installation Hangs

```bash
# Connect to console
sudo virsh console vyos-router

# Check what's happening
# If stuck, press Enter or Ctrl+C

# If completely hung, restart VM
sudo virsh destroy vyos-router
sudo virsh start vyos-router
```

### ISO Download Fails

```bash
# Manually download ISO
wget https://github.com/vyos/vyos-rolling-nightly-builds/releases/latest/download/vyos-1.4-rolling-latest-amd64.iso \
  -O /var/lib/libvirt/images/vyos.iso

# Run playbook with manual ISO path
ansible-playbook deploy-vyos-vm.yml \
  -e vyos_iso_path=/var/lib/libvirt/images/vyos.iso
```

## VyOS Useful Commands

### Show Commands

```bash
# Show configuration
show configuration

# Show interfaces
show interfaces

# Show routing table
show ip route

# Show system info
show system image
show version
show hardware cpu

# Show running processes
show system processes
show system memory

# Monitor interface traffic
monitor interfaces ethernet eth0
```

### Operational Commands

```bash
# Ping test
ping 8.8.8.8

# Traceroute
traceroute google.com

# DNS lookup
nslookup google.com

# Show log
show log

# Restart service
restart service ssh
```

### Configuration Commands

```bash
# Enter configuration mode
configure

# Compare configurations
compare

# Show unsaved changes
compare saved

# Discard changes
discard

# Commit changes
commit

# Save configuration
save

# Load saved config
load

# Exit configuration mode
exit
```

## Advanced Features

### High Availability (VRRP)

```bash
configure

# Router 1
set high-availability vrrp group 1 vrid 10
set high-availability vrrp group 1 interface eth0
set high-availability vrrp group 1 virtual-address 192.168.122.10/24
set high-availability vrrp group 1 priority 200

# Router 2 (lower priority)
set high-availability vrrp group 1 vrid 10
set high-availability vrrp group 1 interface eth0
set high-availability vrrp group 1 virtual-address 192.168.122.10/24
set high-availability vrrp group 1 priority 100

commit
save
```

### BGP Routing

```bash
configure

set protocols bgp system-as 65001
set protocols bgp neighbor 192.168.1.1 remote-as 65002
set protocols bgp neighbor 192.168.1.1 address-family ipv4-unicast
set protocols bgp parameters router-id 192.168.122.100

commit
save
```

### QoS / Traffic Shaping

```bash
configure

# Create traffic policy
set traffic-policy shaper WAN bandwidth 100mbit
set traffic-policy shaper WAN default bandwidth 50mbit
set traffic-policy shaper WAN default ceiling 100mbit
set traffic-policy shaper WAN default priority 5

# Apply to interface
set interfaces ethernet eth0 traffic-policy out WAN

commit
save
```

## Resources

- **VyOS Documentation:** https://docs.vyos.io/
- **VyOS Downloads:** https://vyos.io/download/
- **VyOS Community:** https://forum.vyos.io/
- **VyOS GitHub:** https://github.com/vyos/vyos-1x

## Quick Reference

```
╔════════════════════════════════════════════════════╗
║ VyOS VM Quick Reference                            ║
╠════════════════════════════════════════════════════╣
║ Deploy:     ansible-playbook deploy-vyos-vm.yml    ║
║ Console:    sudo virsh console vyos-router         ║
║ Login:      vyos / vyos                            ║
║ Configure:  configure                              ║
║ Commit:     commit                                 ║
║ Save:       save                                   ║
║ Exit:       exit (config) / Ctrl+] (console)       ║
╠════════════════════════════════════════════════════╣
║ VM Start:   sudo virsh start vyos-router           ║
║ VM Stop:    sudo virsh shutdown vyos-router        ║
║ VM Force:   sudo virsh destroy vyos-router         ║
║ VM Delete:  sudo virsh undefine vyos-router \      ║
║               --remove-all-storage                 ║
╚════════════════════════════════════════════════════╝
```
