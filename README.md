# EC2 Nested Virtualization Setup with Redfish Support

This Ansible playbook creates an AWS EC2 instance configured for nested virtualization, allowing you to run multiple VMs inside the EC2 instance using KVM/QEMU.

**Operating System**: Red Hat Enterprise Linux 9 (RHEL 9)

**Features**:
- KVM/QEMU nested virtualization
- **Baremetal network bridge** for direct network access
- Cockpit web console for VM management
- **Sushy Redfish emulator** for BMC-style VM control
- **Virtual Media support** for ISO mounting via Redfish API
- **Multi-volume storage** - 500GB root, 1TB storage, 500GB OpenShift

See documentation:
- [QUICK_START.md](QUICK_START.md) - Quick reference guide
- [RHEL_SETUP.md](RHEL_SETUP.md) - RHEL 9-specific configuration and usage
- [NETWORKING.md](NETWORKING.md) - Network bridge and configuration details
- [SUSHY_REDFISH.md](SUSHY_REDFISH.md) - Redfish API and virtual media guide
- [DNS_SETUP.md](DNS_SETUP.md) - DNS configuration for OpenShift
- [CPU_OPTIONS.md](CPU_OPTIONS.md) - CPU configuration for nested virtualization
- [INSTANCE_TYPES.md](INSTANCE_TYPES.md) - Instance type comparison and pricing
- [CLEANUP.md](CLEANUP.md) - How to delete all resources

## Prerequisites

1. **AWS Account** with appropriate permissions to create:
   - VPC, Subnets, Internet Gateways
   - Security Groups
   - EC2 Instances

2. **AWS Credentials** configured via:
   - AWS CLI (`aws configure`)
   - Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
   - IAM role (if running from EC2)

3. **SSH Key Pair** - The playbook will automatically create one from your public key (default: `~/.ssh/id_rsa.pub`)

4. **Python packages**:
   ```bash
   pip install -r requirements.txt
   ```

5. **Ansible collections**:
   ```bash
   ansible-galaxy collection install -r requirements.yml
   ```

## Instance Types Supporting Nested Virtualization

AWS now supports nested virtualization on many Nitro-based instance types (no bare metal required!):

### Recommended (Cost-Effective):
- **M7i family**: `m7i.large`, `m7i.xlarge`, `m7i.2xlarge`, etc. (~$0.20-$0.40/hour)
- **M6i family**: `m6i.large`, `m6i.xlarge`, `m6i.2xlarge`, etc. (~$0.19-$0.38/hour)
- **C7i family**: `c7i.large`, `c7i.xlarge`, `c7i.2xlarge`, etc. (compute-optimized)
- **C6i family**: `c6i.large`, `c6i.xlarge`, `c6i.2xlarge`, etc. (compute-optimized)

### Other Supported Families:
- M7a, M6a, M5n, M5zn (AMD-based)
- R7i, R7a, R6i, R6a (memory-optimized)
- C7a, C6a, C5n (compute-optimized)

### Expensive Options (if needed):
- **Metal instances**: `m5.metal`, `c5.metal`, `r5.metal`, etc. (~$4-5/hour)

**Default**: The playbook uses `m7i.2xlarge` (8 vCPUs, 32GB RAM, ~$0.40/hour) - a great balance of performance and cost.

Adjust `instance_type` in `group_vars/all.yml` based on your needs and budget.

## Configuration

1. **Update `group_vars/all.yml`**:
   - Set `ssh_public_key_path` to your SSH public key (default: `~/.ssh/id_rsa.pub`)
   - **IMPORTANT**: Change `cockpit_admin_password` to a secure password
   - Optionally change `cockpit_admin_user` (default: `admin`)
   - Choose your `aws_region` (default: `us-east-2`)
   - Select appropriate `instance_type` (default: `m8i.16xlarge`)
   - Configure CPU options for nested virtualization:
     - `cpu_core_count`: Number of CPU cores (default: 32 for m8i.16xlarge)
     - `cpu_threads_per_core`: Threads per core (2 = hyperthreading enabled, recommended)
   - See [CPU_OPTIONS.md](CPU_OPTIONS.md) for configuration by instance type
   - Optionally update `key_name` (EC2 key pair name to create)
   - Update `ami_mappings` for your region if needed

2. **Update security settings**:
   - The playbook creates a security group allowing:
     - SSH (22)
     - Cockpit web console (9090)
     - Redfish API (8000)
     - VNC (5900-5910)
   - Restrict CIDR blocks in `playbook.yml` for production use

## Usage

### Deploy the EC2 Instance

```bash
# Activate the virtual environment
source venv/bin/activate

# Run the playbook
ansible-playbook playbook.yml
```

This will:
1. Import your SSH public key to create an EC2 key pair
2. Create VPC, subnet, internet gateway, and security group
3. Launch an EC2 instance with nested virtualization support and configure storage:
   - 500GB root volume (boot disk)
   - 1TB volume for general VM storage at `/storage`
   - 500GB volume for OpenShift images at `/var/lib/libvirt/openshift-images`
4. Install and configure KVM/QEMU
5. Create a network bridge named `baremetal` using the primary network interface
6. Set up libvirt for VM management with storage at `/storage/vms`
7. Install Cockpit web console for easy VM management
8. Install and configure Sushy Redfish emulator with virtual media support
9. Create a sudo-enabled admin user for Cockpit access

**Note**: The playbook automatically creates the EC2 key pair from your SSH public key (default: `~/.ssh/id_rsa.pub`). You can specify a different key by updating `ssh_public_key_path` in `group_vars/all.yml`.

**Security**: The playbook will display the Cockpit URL and credentials at the end. Make sure to change the default password in `group_vars/all.yml` before running!

### Verify Nested Virtualization

SSH into the instance and run:
```bash
# Check if nested virtualization is enabled
cat /sys/module/kvm_intel/parameters/nested  # For Intel CPUs
# or
cat /sys/module/kvm_amd/parameters/nested    # For AMD CPUs

# Should return: Y or 1

# Verify KVM is working
lsmod | grep kvm
virsh capabilities
```

### Create a VM

#### Using virt-install (CLI):
```bash
sudo virt-install \
  --name testvm \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/testvm.qcow2,size=20 \
  --os-variant rhel9 \
  --network network=default \
  --graphics vnc,listen=0.0.0.0 \
  --console pty,target_type=serial \
  --location http://mirror.centos.org/centos/9-stream/BaseOS/x86_64/os/
```

#### Using Cockpit Web Console:
1. Access `https://<instance-public-ip>:9090` (URL displayed at end of playbook)
2. Login with the admin credentials:
   - Username: `admin` (or as configured in `group_vars/all.yml`)
   - Password: As set in `group_vars/all.yml`
3. Navigate to "Virtual Machines"
4. Click "Create VM"

### Manage VMs

#### Using virsh (CLI)
```bash
# List all VMs
sudo virsh list --all

# Start a VM
sudo virsh start <vm-name>

# Stop a VM
sudo virsh shutdown <vm-name>

# Delete a VM
sudo virsh undefine <vm-name>
sudo virsh vol-delete --pool default <vm-name>.qcow2

# Access VM console
sudo virsh console <vm-name>
```

#### Using Redfish API
```bash
# List all systems
curl http://<instance-ip>:8000/redfish/v1/Systems | jq

# Get VM UUID
VM_UUID=$(sudo virsh domuuid <vm-name>)

# Power on
curl -X POST http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "On"}'

# Mount ISO as virtual media
curl -X POST http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID/VirtualMedia/Cd/Actions/VirtualMedia.InsertMedia \
  -H "Content-Type: application/json" \
  -d '{
    "Image": "file:///var/lib/sushy/vmedia/my.iso",
    "Inserted": true,
    "WriteProtected": true
  }'
```

See [SUSHY_REDFISH.md](SUSHY_REDFISH.md) for complete Redfish API documentation.

## Network Configuration

The playbook configures networking as follows:

### Baremetal Bridge

A network bridge named `baremetal` is created using the primary network interface:
- **Bridge Name**: `baremetal`
- **Attached Interface**: Primary NIC (typically `eth0` or `ens5`)
- **IP Configuration**: DHCP (inherits from primary interface)
- **Purpose**: Used by OpenShift and other bare-metal workloads

Check bridge status:
```bash
# View bridge details
ip addr show baremetal
nmcli connection show baremetal

# View bridge connections
bridge link show
```

### Default NAT Network

A default NAT network (`virbr0`) is also configured:
- **Network**: 192.168.122.0/24
- **Gateway**: 192.168.122.1
- **DHCP Range**: 192.168.122.2-254
- **Purpose**: Isolated network for VMs

VMs can use either:
1. **Baremetal bridge** - For direct network access (recommended for OpenShift)
2. **NAT network (virbr0)** - For isolated VMs with NAT

### Network Troubleshooting

```bash
# List all network connections
nmcli connection show

# Restart NetworkManager
sudo systemctl restart NetworkManager

# Check libvirt networks
sudo virsh net-list --all

# View bridge configuration
sudo nmcli connection show baremetal
```

## Storage

### Storage Layout

The playbook creates three EBS volumes for complete storage solution:

**Root Volume** - 500GB (boot disk):
```
/ (root filesystem)
# Operating system and system files
```

**Primary Storage** - 1TB mounted at `/storage`:
```
/storage/
├── vms/         # VM disk images (libvirt default pool)
├── isos/        # ISO images for OS installation
├── vmedia/      # Virtual media for Redfish (ISOs, images)
└── backups/     # VM backups
```

**OpenShift Images** - 500GB mounted at `/var/lib/libvirt/openshift-images`:
```
/var/lib/libvirt/openshift-images/
# Dedicated storage for OpenShift cluster VM images
```

**Total Storage**: 2TB (500GB root + 1TB storage + 500GB OpenShift)

### Configuration

- **Root volume size**: Configure `root_volume_size` in `group_vars/all.yml` (default: 500 GB)
- **Storage volume size**: Configure `storage_volume_size` in `group_vars/all.yml` (default: 1024 GB)
- **OpenShift volume size**: Configure `openshift_volume_size` in `group_vars/all.yml` (default: 500 GB)
- **Volume type**: gp3 (3000 IOPS, 125 MB/s throughput) for all volumes
- **Filesystem**: XFS with noatime for better performance
- **Persistence**: Additional volumes automatically added to `/etc/fstab`
- **Compatibility**: `/var/lib/libvirt/images` symlinked to `/storage/vms`

### Storage Locations

| Purpose | Path | Used By | Size |
|---------|------|---------|------|
| Root/OS | `/` (root filesystem) | Operating System | 500GB |
| VM Disks | `/storage/vms` | libvirt default pool | 1TB |
| ISO Files | `/storage/isos` | Manual storage | 1TB (shared) |
| Virtual Media | `/storage/vmedia` | Sushy Redfish emulator | 1TB (shared) |
| Backups | `/storage/backups` | Manual backups | 1TB (shared) |
| OpenShift VMs | `/var/lib/libvirt/openshift-images` | OpenShift installer | 500GB |

### Checking Storage

```bash
# Check mounted filesystems
df -h /storage /var/lib/libvirt/openshift-images

# Check storage usage
du -sh /storage/*
du -sh /var/lib/libvirt/openshift-images/*

# List VMs in storage pool
sudo virsh vol-list default

# Check all block devices
lsblk
```

## Costs

Using non-bare-metal instances is **much more affordable**! Example pricing (on-demand, us-east-1):

### Recommended Instances:
- `m7i.large`: ~$0.20/hour (~$144/month) - 2 vCPUs, 8GB RAM
- `m7i.xlarge`: ~$0.40/hour (~$288/month) - 4 vCPUs, 16GB RAM
- `m7i.2xlarge`: ~$0.80/hour (~$576/month) - 8 vCPUs, 32GB RAM
- `m6i.2xlarge`: ~$0.38/hour (~$274/month) - 8 vCPUs, 32GB RAM

### Bare Metal (for comparison):
- `m5.metal`: ~$4.60/hour (~$3,300/month) - 96 vCPUs, 384GB RAM

**Cost Savings Tips**:
- Use **Spot Instances** for 60-90% discount (may be interrupted)
- Use **Reserved Instances** for 30-60% discount (1-3 year commitment)
- Start with smaller instances like `m7i.large` for testing

## Cleanup

To destroy all created resources, use the cleanup playbook:

```bash
# Review what will be deleted
cat cleanup.yml

# Run cleanup (requires confirmation)
ansible-playbook cleanup.yml -e confirm_deletion=true
```

See [CLEANUP.md](CLEANUP.md) for detailed cleanup instructions and manual deletion steps.

**Warning**: This will permanently delete:
- EC2 instance
- All EBS volumes (root, storage, openshift-images)
- VPC and networking components
- Security group
- EC2 key pair

## Troubleshooting

### Nested virtualization not enabled
- Ensure you're using a compatible instance type
- Verify with `lscpu | grep Virtualization`

### Cannot connect to Cockpit
- Check security group allows port 9090
- Verify firewall rules: `sudo firewall-cmd --list-all`

### VMs won't start
- Check available resources: `free -h` and `df -h`
- View libvirt logs: `sudo journalctl -u libvirtd`
- Check VM logs: `virsh console <vm-name>`

## References

- [AWS Nested Virtualization](https://aws.amazon.com/blogs/compute/running-hyper-v-on-amazon-ec2-bare-metal-instances/)
- [KVM Documentation](https://www.linux-kvm.org/page/Main_Page)
- [libvirt Documentation](https://libvirt.org/)
