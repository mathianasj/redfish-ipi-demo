# Network Configuration

This document describes the network configuration created by the playbook.

## Overview

The playbook configures two network types:

1. **Baremetal Bridge** - For direct network access (used by OpenShift)
2. **NAT Network** - For isolated VMs

## Baremetal Bridge

### Configuration

- **Bridge Name**: `baremetal`
- **Type**: Linux bridge (managed by NetworkManager)
- **Primary Interface**: Automatically detected (usually `eth0` or `ens5` on EC2)
- **IP Assignment**: DHCP (from VPC subnet)
- **Connection Name**: `baremetal`
- **Slave Connection**: `baremetal-slave`

### How the Bridge is Created

The playbook creates the bridge safely to avoid connection loss:

1. **Creates the bridge connection** (inactive) with high autoconnect priority
2. **Creates the slave connection** linking the primary interface to the bridge  
3. **Schedules network switch** using systemd-run:
   - Creates a script at `/tmp/switch-to-bridge.sh`
   - Uses `systemd-run --on-active=3s` to schedule execution in 3 seconds
   - The systemd unit runs completely detached from the SSH session
4. **Exits the play cleanly** - The SSH/sudo session ends before the network switches
5. **Waits from localhost** - A separate play waits 20 seconds for the transition
6. **Waits for SSH** - Uses wait_for to check when SSH is available again
7. **Reconnects and verifies** - A new SSH session verifies the bridge is active

This approach is very safe because:
- The network switch is scheduled via systemd (survives SSH disconnection)
- The Ansible task completes successfully before the network changes
- We wait from the control machine (localhost) not over SSH
- A fresh SSH connection is established to verify the bridge

**No password prompts** - By exiting the become context before the network switches, we avoid sudo password issues when reconnecting.

### Purpose

The baremetal bridge is used for:
- OpenShift bare-metal IPI deployments
- VMs that need direct network access
- Services that require stable MAC addresses
- Scenarios where VMs need to be on the same network as the host

### Viewing Bridge Configuration

```bash
# Show bridge interface
ip addr show baremetal

# Show bridge connections
nmcli connection show

# Show bridge details
bridge link show

# Show bridge MAC addresses
bridge fdb show br baremetal
```

### Example Output

```bash
$ ip addr show baremetal
5: baremetal: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9001 qdisc noqueue state UP group default qlen 1000
    link/ether 02:xx:xx:xx:xx:xx brd ff:ff:ff:ff:ff:ff
    inet 10.0.1.236/24 brd 10.0.1.255 scope global dynamic noprefixroute baremetal
       valid_lft 3477sec preferred_lft 3477sec
```

## NAT Network (virbr0)

### Configuration

- **Bridge Name**: `virbr0`
- **Type**: Libvirt NAT network
- **Network**: 192.168.122.0/24
- **Gateway**: 192.168.122.1
- **DHCP Range**: 192.168.122.2 - 192.168.122.254
- **DNS**: Forwarded to host DNS

### Purpose

The NAT network is used for:
- Isolated VMs that don't need direct network access
- Testing and development
- VMs that should not be accessible from outside the host

### Managing NAT Network

```bash
# View network details
sudo virsh net-dumpxml default

# Start/stop network
sudo virsh net-start default
sudo virsh net-destroy default

# View DHCP leases
sudo virsh net-dhcp-leases default

# Edit network configuration
sudo virsh net-edit default
```

## Creating VMs with Different Networks

### Option 1: VM on Baremetal Bridge (Direct Network Access)

```bash
sudo virt-install \
  --name myvm \
  --memory 4096 \
  --vcpus 2 \
  --disk path=/storage/vms/myvm.qcow2,size=40 \
  --network bridge=baremetal,model=virtio \
  --os-variant rhel9.0 \
  --boot uefi \
  --graphics vnc \
  --noautoconsole
```

**Benefits**:
- VM gets IP from VPC subnet (10.0.1.x)
- Directly accessible from network
- Required for OpenShift deployments
- Stable network identity

**Drawbacks**:
- VMs visible to external network
- Need to manage IPs carefully

### Option 2: VM on NAT Network (Isolated)

```bash
sudo virt-install \
  --name myvm \
  --memory 4096 \
  --vcpus 2 \
  --disk path=/storage/vms/myvm.qcow2,size=40 \
  --network network=default,model=virtio \
  --os-variant rhel9.0 \
  --boot uefi \
  --graphics vnc \
  --noautoconsole
```

**Benefits**:
- VM isolated from external network
- DHCP automatic
- NAT provides internet access
- More secure for testing

**Drawbacks**:
- Not accessible from outside host
- Not suitable for OpenShift

## OpenShift Network Configuration

For OpenShift deployments, use the baremetal bridge:

### install-config.yaml

```yaml
platform:
  baremetal:
    provisioningNetwork: Disabled
    externalBridge: baremetal  # Use the baremetal bridge
    # ...
```

### VM Network Configuration

When creating OpenShift VMs:

```bash
sudo virt-install \
  --name master-1 \
  --memory 32768 \
  --vcpus 8 \
  --disk path=/var/lib/libvirt/openshift-images/master-1.qcow2,size=120 \
  --network bridge=baremetal,model=virtio \
  --os-variant rhel9.0 \
  --boot uefi \
  --graphics vnc \
  --noautoconsole
```

The VM will:
- Be on the same network as the EC2 host
- Get an IP from the VPC subnet
- Be accessible for OpenShift installation

## Troubleshooting

### Bridge Not Working

```bash
# Check if bridge exists
ip link show baremetal

# Check NetworkManager connections
nmcli connection show

# Restart bridge
sudo nmcli connection down baremetal
sudo nmcli connection up baremetal

# Check bridge ports
bridge link show
```

### VM Can't Get IP on Baremetal Bridge

```bash
# Check if bridge is up
ip addr show baremetal

# Check if interface is enslaved
bridge link show

# Restart NetworkManager
sudo systemctl restart NetworkManager

# Check VM network interface
sudo virsh domiflist <vm-name>
```

### Lost Network Connectivity After Bridge Creation

The playbook uses systemd-run to prevent this, but if connectivity is lost:

```bash
# From EC2 console (not SSH), check connections
sudo nmcli connection show

# Bring up the bridge
sudo nmcli connection up baremetal

# If bridge won't come up, bring up the original connection
sudo nmcli connection show  # Find the original connection name
sudo nmcli connection up "System eth0"  # Or whatever the original name was

# Check if the systemd unit ran
sudo systemctl status switch-to-bridge

# View the switch script
cat /tmp/switch-to-bridge.sh

# As a last resort, reboot the instance
sudo reboot
```

**Prevention**: The playbook uses systemd-run to schedule the network switch, which:
- Runs independently of the SSH session (survives disconnection)
- Allows the Ansible playbook to exit cleanly before the network changes
- Prevents "password required" errors by exiting the sudo context first

### Check What Interface is in Bridge

```bash
# Show bridge ports
bridge link show

# Should show something like:
# 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> master baremetal state forwarding priority 32 cost 100
```

## Advanced Configuration

### Static IP on Baremetal Bridge

If you need a static IP instead of DHCP:

```bash
sudo nmcli connection modify baremetal \
  ipv4.method manual \
  ipv4.addresses "10.0.1.236/24" \
  ipv4.gateway "10.0.1.1" \
  ipv4.dns "8.8.8.8,8.8.4.4"

sudo nmcli connection up baremetal
```

### Add VLAN to Bridge

```bash
sudo nmcli connection add type vlan \
  con-name baremetal.100 \
  dev baremetal \
  id 100 \
  ipv4.method auto

sudo nmcli connection up baremetal.100
```

### Multiple Bridges

Create additional bridges for isolation:

```bash
# Create a second bridge
sudo nmcli connection add type bridge \
  con-name baremetal2 \
  ifname baremetal2 \
  ipv4.method manual \
  ipv4.addresses "192.168.100.1/24"

sudo nmcli connection up baremetal2
```

## Network Diagram

```
┌─────────────────────────────────────────────────────┐
│ EC2 Instance (RHEL 9)                               │
│                                                     │
│  ┌──────────────┐         ┌──────────────┐        │
│  │ baremetal    │         │ virbr0       │        │
│  │ (bridge)     │         │ (NAT)        │        │
│  │ 10.0.1.x/24  │         │ 192.168.122.1│        │
│  └──────┬───────┘         └──────┬───────┘        │
│         │                        │                 │
│    ┌────┴────┐              ┌────┴────┐           │
│    │ eth0    │              │ VMs     │           │
│    │ (slave) │              │ (NAT)   │           │
│    └────┬────┘              └─────────┘           │
│         │                                          │
└─────────┼──────────────────────────────────────────┘
          │
          ▼
    VPC Network (10.0.1.0/24)
```

## References

- [RHEL 9 Network Bridge Configuration](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_networking/configuring-a-network-bridge_configuring-and-managing-networking)
- [NetworkManager Bridge Configuration](https://networkmanager.dev/docs/api/latest/settings-bridge.html)
- [Libvirt Networking](https://wiki.libvirt.org/Networking.html)
- [OpenShift Bare Metal Networking](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal-network-customizations.html)
