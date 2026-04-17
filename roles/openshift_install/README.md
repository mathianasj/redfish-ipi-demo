# OpenShift Install Role

This Ansible role prepares an OpenShift install-config.yaml for a compact 3-node cluster deployment using Redfish virtual media.

## Features

✅ **Automatic VM Creation**: Creates 3 master node VMs (8 vCPUs, 32GB RAM, 120GB disk each)  
✅ **Dynamic IP Discovery**: Automatically finds available IPs from the virbr0 network  
✅ **DHCP-Safe**: Only uses static IPs outside the DHCP range  
✅ **MAC Generation**: Generates random MAC addresses for master nodes  
✅ **Network Detection**: Discovers network CIDR, gateway, and configuration from libvirt  
✅ **Redfish Integration**: Configures Sushy emulator BMC URLs with proper UUIDs  
✅ **Reference Documentation**: Creates a network-config.txt file with all IP/MAC mappings  

## Prerequisites

1. **Pull Secret**: Download your pull secret from https://console.redhat.com/openshift/install/pull-secret
   - Save it as `pullsecret.json` in the project root directory
   - This file is excluded from git via `.gitignore`

2. **SSH Key**: Ensure your SSH public key exists at `~/.ssh/id_rsa_fips.pub`

3. **EC2 Instance**: A running EC2 instance with:
   - KVM/libvirt installed and configured
   - Sushy emulator running on port 8000
   - virbr0 network configured (default libvirt network)
   - At least 5 available static IPs outside the DHCP range

## How It Works

The role automatically:

1. **Discovers the virbr0 network configuration**:
   - Network CIDR and netmask
   - Gateway address
   - DHCP range (start and end)

2. **Finds available IPs**:
   - Scans for IPs outside the DHCP range
   - Checks for currently used IPs
   - Reserves 5 consecutive available IPs for:
     - API VIP
     - Ingress VIP
     - Master node 1
     - Master node 2
     - Master node 3

3. **Generates MAC addresses**:
   - Creates random MAC addresses with the libvirt prefix (52:54:00:xx:xx:xx)
   - Ensures uniqueness for each master node

4. **Creates configuration files**:
   - `install-config.yaml`: OpenShift installer configuration
   - `network-config.txt`: Reference document with all IP/MAC mappings

## Variables

Only these variables can be customized (see `defaults/main.yml`):

- `ocp_cluster_name`: Cluster name (default: `ocp`)
- `ocp_base_domain`: Base domain (default: `example.com`)

All network configuration (IPs, MACs, gateways, etc.) is automatically discovered.

## Usage

### Basic Usage

```bash
# 1. Create your pull secret file
cp pullsecret.json.example pullsecret.json
# Edit pullsecret.json with your actual Red Hat pull secret

# 2. Run the prepare playbook
ansible-playbook prepare-openshift-install.yml
```

### Custom Cluster Name/Domain

Override variables in your playbook:

```yaml
- name: Prepare OpenShift installation configuration
  hosts: target_hosts
  become: false
  gather_facts: true
  vars:
    ocp_cluster_name: production
    ocp_base_domain: openshift.lab.example.com
  roles:
    - openshift_install
```

## Output

The role creates two files in `/home/ec2-user/openshift-install/`:

1. **install-config.yaml**: OpenShift installer configuration with:
   - Pull secret injected
   - SSH key injected
   - Dynamically assigned IPs and MACs
   - Redfish BMC addresses pointing to Sushy emulator

2. **network-config.txt**: Reference document showing:
   - All assigned IPs
   - Generated MAC addresses
   - System IDs for libvirt domains
   - BMC URLs

## Next Steps

After running the role, VMs are created and ready. Here's what to do next:

1. **Review the configuration**:
   ```bash
   ssh ec2-user@<instance-ip>
   cat ~/openshift-install/network-config.txt
   virsh list --all  # Verify VMs are created
   ```

2. **Backup install-config.yaml** (it gets consumed by the installer):
   ```bash
   cp ~/openshift-install/install-config.yaml ~/install-config.yaml.backup
   ```

3. **Set up DNS** (if using real domain):
   - Point `api.<cluster>.<domain>` to the API VIP
   - Point `*.apps.<cluster>.<domain>` to the Ingress VIP
   - For testing with example.com, DNS is handled locally

4. **Run the OpenShift installer**:
   ```bash
   cd ~/openshift-install
   openshift-install create cluster --log-level=info
   ```

The installer will:
- Boot each VM via Redfish virtual media
- Install RHCOS (Red Hat CoreOS) on each master node
- Bootstrap the cluster
- Configure the control plane
- Take approximately 45-60 minutes to complete

## Example Output

```
Master Nodes:
  Master-1: 192.168.122.5 (52:54:00:a1:b2:c3)
  Master-2: 192.168.122.6 (52:54:00:d4:e5:f6)
  Master-3: 192.168.122.7 (52:54:00:12:34:56)

Virtual IPs:
  API VIP: 192.168.122.3
  Ingress VIP: 192.168.122.4
```

## Troubleshooting

**Not enough available IPs**: The role needs 5 consecutive IPs outside the DHCP range. Check your virbr0 network configuration:
```bash
virsh net-dumpxml default
```

**MAC address conflicts**: The role generates random MACs. If you get conflicts, re-run the playbook to generate new ones.

## Notes

- The install-config.yaml contains secrets (pull secret, SSH key) - don't commit it
- Back up install-config.yaml before running the installer (it gets consumed)
- The Redfish system IDs in the config are based on expected libvirt domain names
- MAC addresses must match exactly when you create the VMs
