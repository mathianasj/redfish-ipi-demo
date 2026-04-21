# RHEL 9 Virtualization Setup

This document describes the RHEL 9-specific configuration for nested virtualization on EC2.

## RHEL 9 Packages Installed

### Virtualization Host Environment Group
```bash
@virtualization-host-environment
```
This group includes the core packages needed to run KVM/QEMU on RHEL 9.

### Core Virtualization Packages
- **qemu-kvm** - QEMU/KVM hypervisor
- **libvirt** - Virtualization management library
- **libvirt-daemon-kvm** - KVM-specific libvirt daemon
- **libvirt-daemon-config-network** - Default networking configuration
- **libvirt-daemon-config-nwfilter** - Network filtering configuration
- **virt-install** - Command-line tool to create VMs
- **virt-viewer** - VM console viewer
- **virt-top** - Virtual machine monitoring tool (like top for VMs)

### Guest Management Tools
- **libguestfs** - Tools for accessing and modifying VM disk images
- **libguestfs-tools** - Command-line tools for guest management
- **libguestfs-tools-c** - C-based guest tools
- **python3-libguestfs** - Python bindings for libguestfs
- **guestfs-tools** - Additional guest filesystem tools

### Web Management
- **cockpit** - Web-based server management
- **cockpit-machines** - Cockpit module for VM management
- **cockpit-storaged** - Storage management in Cockpit
- **cockpit-podman** - Container management in Cockpit

### Network Utilities
- **net-tools** - Network configuration tools (ifconfig, netstat, etc.)
- **iproute** - Advanced IP routing and network configuration (ip, ss, etc.)
- **NetworkManager** - Network management service (includes nmcli for bridge configuration)

## Firewall Configuration

The playbook automatically configures `firewalld` for:

### Libvirt Service
- Allows VM network traffic through the host firewall
- Enables libvirt management connections

### Cockpit Service
- Opens port 9090 for HTTPS web console access
- Enables secure web-based management

## Service Management

### Enabled Services
1. **libvirtd** - Main virtualization daemon
2. **cockpit.socket** - Cockpit web console (socket-activated)
3. **firewalld** - Firewall service

## Verification Steps

After the playbook completes, verify your setup:

### 1. Check KVM Modules
```bash
lsmod | grep kvm
```
Should show:
- `kvm_intel` (for Intel CPUs) or `kvm_amd` (for AMD CPUs)
- `kvm`

### 2. Verify Nested Virtualization
```bash
# For Intel CPUs
cat /sys/module/kvm_intel/parameters/nested

# For AMD CPUs
cat /sys/module/kvm_amd/parameters/nested
```
Should return: `Y` or `1`

### 3. Check CPU Virtualization Support
```bash
grep -E '(vmx|svm)' /proc/cpuinfo
```
Should show CPU flags with `vmx` (Intel) or `svm` (AMD)

### 4. Verify Libvirt is Running
```bash
sudo systemctl status libvirtd
```

### 5. List Available Networks
```bash
sudo virsh net-list --all
```
Should show the `default` network as active

### 6. List Storage Pools
```bash
sudo virsh pool-list --all
```
Should show the `default` pool as active

### 7. Check Firewall Rules
```bash
sudo firewall-cmd --list-all
```
Should show `libvirt` and `cockpit` services

### 8. Access Cockpit
Navigate to: `https://<instance-public-ip>:9090`
- Login with admin credentials (displayed at end of playbook):
  - Username: `admin` (default)
  - Password: As configured in `group_vars/all.yml`
- Navigate to "Virtual Machines" tab

**Note**: The admin user has sudo access and is a member of the `libvirt` and `wheel` groups.

## Creating Your First VM on RHEL 9

### Using virt-install (CLI)

```bash
# Download a cloud image (example: CentOS Stream 9)
sudo wget -O /var/lib/libvirt/images/centos-stream-9.qcow2 \
  https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2

# Create a VM from the cloud image
sudo virt-install \
  --name centos9-vm \
  --memory 2048 \
  --vcpus 2 \
  --disk /var/lib/libvirt/images/centos-stream-9.qcow2,device=disk,bus=virtio \
  --import \
  --os-variant centos-stream9 \
  --network network=default,model=virtio \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole

# List VMs
sudo virsh list --all

# Start the VM
sudo virsh start centos9-vm

# Connect to console
sudo virsh console centos9-vm
```

### Using Cockpit Web Console

1. Access: `https://<instance-ip>:9090`
2. Login with admin credentials (username: `admin`, password from config)
3. Go to "Virtual Machines"
4. Click "Create VM"
5. Choose installation method:
   - **Download an OS** - Cockpit downloads ISO
   - **Local install media** - Use uploaded ISO
   - **Import existing disk** - Use existing qcow2/raw image
6. Configure resources (CPU, RAM, disk)
7. Start the VM

**Admin User Details:**
- Username: `admin` (configurable in `group_vars/all.yml`)
- Groups: `wheel` (sudo), `libvirt` (VM management)
- Can execute all virsh/virt commands with sudo
- Full access to Cockpit web console

## RHEL 9 Specific Features

### SELinux
SELinux is enabled by default on RHEL 9. The libvirt packages include proper SELinux policies for VM management.

Verify SELinux status:
```bash
sestatus
```

Check libvirt SELinux contexts:
```bash
ls -lZ /var/lib/libvirt/images/
```

### Subscription Management

If you need to attach Red Hat subscriptions:
```bash
# Register the system
sudo subscription-manager register --username <username>

# Attach subscription
sudo subscription-manager attach --auto

# Enable required repositories (already enabled by default in RHEL 9)
sudo subscription-manager repos --enable rhel-9-for-x86_64-appstream-rpms
sudo subscription-manager repos --enable rhel-9-for-x86_64-baseos-rpms
```

**Note**: EC2 RHEL instances typically use cloud-based subscription access and don't require manual registration.

## Networking on RHEL 9

### Default NAT Network
The default network (`virbr0`) provides NAT networking for VMs:
- Network: 192.168.122.0/24
- Gateway: 192.168.122.1
- DHCP range: 192.168.122.2-254

### Create Additional Networks

#### Bridge Network (for direct network access)

**Note**: RHEL 9 uses NetworkManager (nmcli) for bridge management instead of bridge-utils.

```bash
# Check current network interface name
ip addr show

# Create bridge configuration (assuming eth0 is your interface)
sudo nmcli connection add type bridge con-name br0 ifname br0
sudo nmcli connection modify br0 ipv4.method auto

# Add physical interface to bridge
sudo nmcli connection add type ethernet slave-type bridge \
  con-name bridge-br0 ifname eth0 master br0

# Activate bridge
sudo nmcli connection up br0

# Verify bridge
ip addr show br0

# Define libvirt bridge network
cat > /tmp/bridge-network.xml <<EOF
<network>
  <name>host-bridge</name>
  <forward mode="bridge"/>
  <bridge name="br0"/>
</network>
EOF

sudo virsh net-define /tmp/bridge-network.xml
sudo virsh net-start host-bridge
sudo virsh net-autostart host-bridge

# List available networks
sudo virsh net-list --all
```

**Alternative: Use ip command directly**
```bash
# Create bridge (temporary, lost on reboot)
sudo ip link add name br0 type bridge
sudo ip link set br0 up
sudo ip addr add 192.168.100.1/24 dev br0
```

## Storage Management

### Default Pool Location
`/var/lib/libvirt/images`

### Create Additional Storage Pool
```bash
# Create directory
sudo mkdir -p /var/lib/libvirt/pool2

# Define pool
sudo virsh pool-define-as pool2 dir --target /var/lib/libvirt/pool2

# Build and start
sudo virsh pool-build pool2
sudo virsh pool-start pool2
sudo virsh pool-autostart pool2
```

### Extend Root Volume (if needed)
```bash
# Check current size
df -h /

# Extend partition and filesystem (after extending EBS volume in AWS)
sudo growpart /dev/nvme0n1 1
sudo xfs_growfs /
```

## Performance Tuning for RHEL 9 KVM

### Enable CPU Pinning for VMs
```bash
# Check CPU topology
lscpu

# Pin VM to specific CPUs (edit VM XML)
sudo virsh edit <vm-name>
```

Add:
```xml
<vcpu placement='static' cpuset='0-3'>4</vcpu>
```

### Hugepages for Better Performance
```bash
# Allocate hugepages
echo 1024 | sudo tee /proc/sys/vm/nr_hugepages

# Make persistent
echo "vm.nr_hugepages = 1024" | sudo tee -a /etc/sysctl.conf
```

## Troubleshooting

### Libvirt Not Starting
```bash
# Check logs
sudo journalctl -u libvirtd -f

# Restart service
sudo systemctl restart libvirtd
```

### VM Won't Start
```bash
# Check VM logs
sudo virsh dumpxml <vm-name>
sudo tail -f /var/log/libvirt/qemu/<vm-name>.log

# Check available resources
free -h
df -h
```

### Network Issues
```bash
# Check bridge status
ip addr show virbr0

# Restart network
sudo virsh net-destroy default
sudo virsh net-start default

# Check firewall
sudo firewall-cmd --list-all
```

### Cockpit Not Accessible
```bash
# Check cockpit status
sudo systemctl status cockpit.socket

# Check firewall
sudo firewall-cmd --list-services | grep cockpit

# Add cockpit service if missing
sudo firewall-cmd --permanent --add-service=cockpit
sudo firewall-cmd --reload
```

## Additional Resources

- [Red Hat Virtualization Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_virtualization/)
- [RHEL 9 KVM Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html-single/configuring_and_managing_virtualization/)
- [Cockpit Documentation](https://cockpit-project.org/documentation.html)
- [AWS Nested Virtualization](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html)
