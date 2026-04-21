# OpenShift IPI Baremetal Demo with Redfish

This repository provides an automated lab environment for demonstrating **OpenShift Installer Provisioned Infrastructure (IPI)** installations using **Redfish** and **virtual media** - simulating a real baremetal deployment on AWS EC2 with nested virtualization.

## Purpose

Demonstrate how OpenShift IPI installation works with baremetal infrastructure by:
- Creating "virtual baremetal" nodes (KVM VMs on EC2)
- Exposing them via **Redfish API** using **sushy-tools** (Redfish BMC emulator)
- Using **virtual media** to mount ISOs and provision nodes
- Running OpenShift IPI installer to provision the cluster using Redfish

This allows you to demonstrate and test OpenShift baremetal IPI workflows without needing physical servers or expensive bare-metal cloud instances.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ AWS EC2 Instance (m8i.16xlarge)                         │
│ RHEL 9 with nested virtualization                       │
│                                                           │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Sushy-tools (Redfish BMC Emulator)                 │ │
│  │ Port 8000: http://<ip>:8000/redfish/v1/           │ │
│  │ - Presents KVM VMs as "baremetal" nodes            │ │
│  │ - Supports virtual media (ISO mounting)            │ │
│  │ - Provides power management                        │ │
│  └────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌────────────────────────────────────────────────────┐ │
│  │ KVM Virtual Machines (Masters/Workers)             │ │
│  │ - ocp-master-1, ocp-master-2, ocp-master-3        │ │
│  │ - ocp-worker-1, ocp-worker-2, ...                 │ │
│  │ - Exposed via Redfish API                          │ │
│  └────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌────────────────────────────────────────────────────┐ │
│  │ VyOS Router (optional)                             │ │
│  │ - Network isolation and routing                    │ │
│  └────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────── ┘

OpenShift IPI Installer → Redfish API → Sushy → KVM VMs
                        (virtual media)
```

## Features

### OpenShift IPI Capabilities
- ✅ **Full IPI installation** - OpenShift installer manages the entire deployment
- ✅ **Redfish virtual media** - ISOs mounted to boot RHCOS
- ✅ **BMC simulation** - Sushy-tools emulates Redfish BMC
- ✅ **Baremetal simulation** - KVM VMs act as physical servers
- ✅ **Worker scaling** - Add/remove workers via BareMetalHost resources
- ✅ **Agent-based installer** - Pre-provision VMs, then run installer

### Infrastructure Components
- **Nested Virtualization** - KVM on EC2 (no bare-metal instance required!)
- **Redfish API** - Industry-standard baremetal management
- **Virtual Media** - Mount ISOs via Redfish for OS installation
- **Network Isolation** - VyOS router for realistic networking
- **DNS** - BIND DNS for OpenShift cluster resolution
- **Storage** - 2TB total (500GB root + 1TB storage + 500GB OpenShift)
- **Web Console** - Cockpit for VM management

## Quick Start

### 1. Prerequisites

```bash
# Clone the repository
git clone https://github.com/mathianasj/redfish-ipi-demo.git
cd redfish-ipi-demo

# Install Python dependencies
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Install Ansible collections
ansible-galaxy collection install -r requirements.yml

# Configure AWS credentials
aws configure
```

### 2. Configure Variables

Edit `group_vars/all.yml`:
```yaml
# AWS Configuration
aws_region: us-east-2
instance_type: m8i.16xlarge  # 32 cores, 64 threads, 128GB RAM

# SSH Keys
ssh_public_key_path: "~/.ssh/id_rsa_fips.pub"
ssh_private_key_path: "~/.ssh/id_rsa_fips"

# Security
cockpit_admin_password: "YourSecurePassword123!"  # CHANGE THIS!

# OpenShift
ocp_cluster_name: ocp
ocp_base_domain: example.com
```

Add your OpenShift pull secret:
```bash
# Download from https://console.redhat.com/openshift/install/pull-secret
cp pullsecret.json.example pullsecret.json
# Edit pullsecret.json with your actual pull secret
```

### 3. Deploy Complete Environment

```bash
# Deploy EC2 instance with nested virt + OpenShift cluster
ansible-playbook playbook.yml
```

This automated playbook will:
1. ✅ Create AWS infrastructure (VPC, subnets, EC2 instance)
2. ✅ Configure nested virtualization and KVM
3. ✅ Install and configure Sushy Redfish emulator
4. ✅ Set up DNS for OpenShift
5. ✅ Create master VMs (3 nodes)
6. ✅ Generate install-config.yaml
7. ✅ Run OpenShift IPI installer
8. ✅ Configure cluster access

**Time**: ~60-90 minutes total

### 4. Access Your Cluster

After installation completes:

```bash
# SSH to EC2 instance
ssh ec2-user@<instance-ip>

# Get cluster credentials
cat ~/openshift-cluster-access.txt

# Access web console (requires noVNC)
# The playbook exposes a noVNC web endpoint at:
#   https://<instance-ip>:6081/vnc.html
# 
# Example: https://3.145.67.89:6081/vnc.html
# Password: redhat123 (default)
# 
# Firefox will auto-launch to the OpenShift console with credentials pre-filled
# See VNC_ACCESS_GUIDE.md for detailed instructions

# Use CLI (from EC2 instance)
export KUBECONFIG=~/openshift-install/auth/kubeconfig
oc get nodes
oc get co  # Check cluster operators
```

## Individual Components

### Deploy Infrastructure Only

```bash
# Just create EC2 + KVM + Sushy (no OpenShift)
ansible-playbook playbook.yml --tags infrastructure
```

### Install VyOS Router

```bash
# Deploy VyOS for network management
ansible-playbook install-vyos.yml
```

Features:
- Automated installation from ISO
- Dynamic network configuration
- Static IP assignment
- SSH enabled
- Persistent configuration

### Scale Workers

```bash
# Add workers to existing cluster
ansible-playbook scale-workers.yml -e worker_count=2
```

This will:
- Create additional worker VMs
- Expose them via Redfish
- Create BareMetalHost manifests
- Let OpenShift provision them automatically

### Mirror OpenShift Images

For disconnected/air-gapped environments:

```bash
# Step 1: Install mirror registry
ansible-playbook configure-mirror-registry.yml

# Step 2: Download images (50-80 GB, 45-90 minutes on EC2)
ansible-playbook run-mirror.yml

# Step 3: Push to registry
ansible-playbook push-to-registry.yml

# Test first with minimal config (10-15 GB, 10-20 minutes)
ansible-playbook run-mirror.yml -e mirror_config=minimal
```

This provides:
- Local mirror registry (Quay)
- oc-mirror v2 tool
- Automated download workflow
- Automated push workflow
- Access at: https://<instance-ip>:8443

See [MIRROR-REGISTRY-GUIDE.md](MIRROR-REGISTRY-GUIDE.md) for complete details.

## How OpenShift IPI Works with Redfish

### Installation Flow

1. **Preparation**
   - Create master VMs (powered off)
   - Get VM UUIDs from libvirt
   - Configure Redfish URLs in install-config.yaml

2. **Bootstrap**
   ```yaml
   platform:
     baremetal:
       apiVIPs: [192.168.122.10]
       ingressVIPs: [192.168.122.11]
       hosts:
         - name: master-1
           role: master
           bmc:
             address: redfish-virtualmedia://192.168.122.1:8000/redfish/v1/Systems/<uuid>
             username: admin
             password: password
           bootMACAddress: "52:54:00:xx:xx:xx"
   ```

3. **IPI Installer Actions**
   - Uses Redfish API to power on VMs
   - Mounts RHCOS ISO via virtual media
   - Boots nodes from ISO
   - Installs RHCOS to disk
   - Configures networking
   - Joins cluster

4. **Day 2 Operations**
   - Create BareMetalHost resources
   - Kubernetes manages baremetal nodes
   - Scale workers up/down dynamically

### Redfish API Examples

```bash
# List all "baremetal" nodes
curl http://<instance-ip>:8000/redfish/v1/Systems | jq

# Get node details
curl http://<instance-ip>:8000/redfish/v1/Systems/<uuid> | jq

# Power on node
curl -X POST http://<instance-ip>:8000/redfish/v1/Systems/<uuid>/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "On"}'

# Mount ISO via virtual media
curl -X POST http://<instance-ip>:8000/redfish/v1/Systems/<uuid>/VirtualMedia/Cd/Actions/VirtualMedia.InsertMedia \
  -H "Content-Type: application/json" \
  -d '{"Image": "file:///storage/vmedia/rhcos.iso", "Inserted": true}'
```

See [SUSHY_REDFISH.md](SUSHY_REDFISH.md) for complete API documentation.

## AWS Instance Types

This lab uses **m8i.16xlarge** by default (32 cores, 128GB RAM) but works on any Nitro instance supporting nested virtualization:

### Recommended Options

| Instance | vCPUs | RAM | Cost/hr | Use Case |
|----------|-------|-----|---------|----------|
| m8i.16xlarge | 64 | 128GB | ~$3.50 | **Full OpenShift cluster** (recommended) |
| m7i.8xlarge | 32 | 128GB | ~$1.60 | 3 masters + 2 workers |
| m7i.4xlarge | 16 | 64GB | ~$0.80 | Minimal cluster (3 masters only) |
| m6i.4xlarge | 16 | 64GB | ~$0.76 | Budget option |

### Nested Virtualization Support

All modern AWS Nitro instances support nested virtualization - **no bare-metal required**!

- M7i, M6i, M8i families
- C7i, C6i families  
- R7i, R6i families
- And many more...

See [INSTANCE_TYPES.md](INSTANCE_TYPES.md) for complete list and pricing.

## Storage Configuration

**Total Storage**: 2TB across 3 volumes

| Volume | Size | Mount | Purpose |
|--------|------|-------|---------|
| Root | 500GB | `/` | Operating system |
| Storage | 1TB | `/storage` | VM disks, ISOs, virtual media |
| OpenShift | 500GB | `/var/lib/libvirt/openshift-images` | OpenShift VM images |

```
/storage/
├── vms/         # VM disk images (QCOW2)
├── isos/        # ISO files (RHCOS, etc.)
├── vmedia/      # Virtual media for Redfish
└── backups/     # VM backups
```

## Network Configuration

### Default libvirt Network

```
Network: 192.168.122.0/24
Gateway: 192.168.122.1
DHCP: 192.168.122.100-254
Static: 192.168.122.2-99 (for OpenShift)
```

### Baremetal Bridge

EC2 primary interface is bridged for direct network access:
- Bridge: `baremetal`
- Used by: OpenShift cluster VMs
- Access: Direct network connectivity

### VyOS Router (Optional)

For network isolation and advanced routing:
- IP: 192.168.122.10/24
- Gateway: 192.168.122.1
- Access: `ssh vyos@192.168.122.10`

## Documentation

### 📘 Getting Started
- **[Quick Start Guide](docs/getting-started/QUICK_START.md)** - Fast deployment walkthrough
- **[Quick Reference](docs/getting-started/QUICK_REFERENCE.md)** - Common commands and operations

### 🏗️ Infrastructure Setup
- **[Instance Types](docs/infrastructure/INSTANCE_TYPES.md)** - AWS instance comparison and recommendations
- **[RHEL Setup](docs/infrastructure/RHEL_SETUP.md)** - RHEL 9 configuration and preparation
- **[Networking](docs/infrastructure/NETWORKING.md)** - Network architecture and configuration
- **[DNS Setup](docs/infrastructure/DNS_SETUP.md)** - DNS configuration for OpenShift
- **[Cleanup](docs/infrastructure/CLEANUP.md)** - Resource deletion and teardown
- **[Instance Management](docs/infrastructure/INSTANCE-MANAGEMENT-README.md)** - EC2 instance lifecycle

### 🔴 OpenShift Deployment
- **[Complete Deployment](docs/openshift/COMPLETE_DEPLOYMENT.md)** - End-to-end deployment workflow
- **[Redfish Baremetal Install Guide](docs/openshift/REDFISH-BAREMETAL-INSTALL.md)** - Manual install-config.yaml creation and real-world Redfish
- **[install-config.yaml Guide](docs/openshift/INSTALL-CONFIG-GUIDE.md)** - Field reference and configuration examples
- **[Redfish/BMC Guide](docs/openshift/SUSHY_REDFISH.md)** - Redfish API integration and usage
- **[Pull Secret Setup](docs/openshift/PULL-SECRET.md)** - Red Hat pull secret configuration

### 🔌 Disconnected/Air-Gapped Environments
- **[Mirror Registry Guide](docs/disconnected/MIRROR-REGISTRY-GUIDE.md)** - Complete mirror registry setup and workflow
- **[Mirror Timing & Sizing](docs/disconnected/OC-MIRROR-TIMING.md)** - Download estimates and best practices

### 🔧 Troubleshooting
- **[KVM Nested Virtualization Fix](docs/troubleshooting/KVM_NESTED_VIRT_FIX.md)** - Resolve nested virt issues
- **[VM Paused Troubleshooting](docs/troubleshooting/VM_PAUSED_TROUBLESHOOTING.md)** - Fix VM stability problems
- **[CPU Options](docs/troubleshooting/CPU_OPTIONS.md)** - CPU configuration and tuning
- **[KVM Error Prevention](docs/troubleshooting/KVM_ERROR_PREVENTION.md)** - Prevent common KVM errors
- **[Nested Virt Detection](docs/troubleshooting/NESTED-VIRT-DETECTION.md)** - Verify nested virtualization
- **[Memory Changes Revert](docs/troubleshooting/REVERT_MEMORY_CHANGES.md)** - Undo memory configuration changes

### 🚀 Advanced Topics
- **[VNC Access Guide](docs/advanced/VNC_ACCESS_GUIDE.md)** - Remote desktop and console access
- **[VyOS VM Guide](docs/advanced/VYOS_VM_GUIDE.md)** - VyOS router deployment and configuration
- **[Dynamic Inventory](docs/advanced/README-INVENTORY.md)** - Ansible dynamic inventory for EC2

## Cost Estimation

**On-Demand Pricing** (us-east-2):

| Duration | m8i.16xlarge | m7i.8xlarge | m6i.4xlarge |
|----------|--------------|-------------|-------------|
| 1 hour | $3.50 | $1.60 | $0.76 |
| 8 hours | $28 | $13 | $6 |
| 1 month | $2,520 | $1,152 | $547 |

**Cost Savings**:
- ✅ **Spot instances**: 60-90% discount (may be interrupted)
- ✅ **Stop when not in use**: Only pay for storage (~$50/month)
- ✅ **Smaller instances**: Use m6i.4xlarge for demos

## Use Cases

### 1. Sales Demonstrations
- Show OpenShift IPI installation process
- Demonstrate Redfish integration
- Exhibit cluster scaling
- No physical hardware required

### 2. Customer Training
- Hands-on IPI installation practice
- Redfish API interaction
- BareMetalHost management
- Troubleshooting workflows

### 3. Development & Testing
- Test IPI installation procedures
- Validate automation scripts
- Development environment for baremetal features
- CI/CD pipeline testing

### 4. Partner Enablement
- Train partners on OpenShift IPI
- Demonstrate Redfish capabilities
- Practice deployment procedures
- Pre-sales technical validation

## Cleanup

```bash
# Delete all AWS resources
ansible-playbook cleanup.yml -e confirm_deletion=true
```

**Warning**: Deletes:
- EC2 instance
- All EBS volumes (and data!)
- VPC and networking
- Security groups
- SSH key pair

See [CLEANUP.md](CLEANUP.md) for details.

## Troubleshooting

### OpenShift Installation Fails

```bash
# Check installer logs
ssh ec2-user@<instance-ip>
cd ~/openshift-install
./openshift-install wait-for bootstrap-complete --log-level=debug

# Check Redfish connectivity
curl http://<instance-ip>:8000/redfish/v1/Systems
```

### VMs Won't Boot

```bash
# Check VM state
sudo virsh list --all

# Check Redfish status
curl http://<instance-ip>:8000/redfish/v1/Systems/<uuid>

# View VM console
sudo virsh console ocp-master-1
```

### Nested Virtualization Issues

See [KVM_NESTED_VIRT_FIX.md](KVM_NESTED_VIRT_FIX.md) for:
- KVM hardware errors
- VM pausing issues
- CPU configuration problems

## Security Notes

⚠️ **This is a LAB/DEMO environment** - not for production!

- Default passwords in documentation are examples - **change them**!
- Security groups allow wide access - **restrict in production**
- No TLS for Redfish API - **use HTTPS in production**
- Pull secret contains credentials - **never commit to git**

The repository `.gitignore` protects:
- `pullsecret.json`
- SSH keys
- AWS credentials
- ISO files and VM images

## Contributing

This is a demonstration environment for OpenShift IPI with Redfish. Contributions welcome for:
- Additional network configurations
- Alternative OpenShift deployment methods
- Documentation improvements
- Troubleshooting guides

## License

See repository license file.

## References

- [OpenShift IPI Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal_ipi/ipi-install-overview.html)
- [Redfish Specification](https://www.dmtf.org/standards/redfish)
- [Sushy-tools Documentation](https://docs.openstack.org/sushy-tools/latest/)
- [AWS Nested Virtualization](https://aws.amazon.com/ec2/instance-types/)
- [KVM Documentation](https://www.linux-kvm.org/)
