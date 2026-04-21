# DNS Setup for OpenShift

This guide explains how to configure DNS for OpenShift Single Node (SNO) deployment.

## Overview

The DNS playbook configures a BIND DNS server on the EC2 instance with:
- **Domain**: example.com
- **Cluster**: sno
- **API VIP**: 192.168.122.10 (api.sno.example.com)
- **Ingress VIP**: 192.168.122.11 (*.apps.sno.example.com)

### What the Playbook Does

1. **Installs BIND DNS server** - Sets up named service with recursive DNS support
2. **Creates DNS zone files** - Forward and reverse zones for example.com
3. **Configures the instance to use itself for DNS** - Sets the EC2 instance to use 127.0.0.1 as its primary DNS server
4. **Opens firewall** - Allows DNS traffic (port 53)
5. **Tests configuration** - Verifies DNS resolution works

After running this playbook, the EC2 instance will:
- Run a DNS server accessible at its IP address
- Use itself (localhost) for all DNS lookups
- Forward unknown queries to 8.8.8.8/8.8.4.4

## Running the DNS Configuration

### Prerequisites

1. EC2 instance must be deployed and running
2. SSH access to the instance
3. Ansible inventory configured

### Deploy DNS

```bash
# Activate virtual environment
source venv/bin/activate

# Run DNS configuration playbook
# The playbook automatically finds the EC2 instance
ansible-playbook configure-dns.yml
```

The playbook will:
1. Search for the EC2 instance by name (default: `nested-virt-host`)
2. Add it to the inventory dynamically
3. Configure DNS on the instance

**Note**: The playbook uses the same variables as the main deployment:
- `aws_region` (default: us-east-2)
- `instance_name` (default: nested-virt-host)
- `ssh_private_key_path` (default: ~/.ssh/id_rsa_fips)

To override these values:

```bash
ansible-playbook configure-dns.yml \
  -e aws_region=us-west-2 \
  -e instance_name=my-instance \
  -e ssh_private_key_path=~/.ssh/my-key
```

### Configuration Variables

#### First Play (Find EC2 Instance)

Edit `configure-dns.yml` or use command-line variables:

```yaml
vars:
  aws_region: us-east-2                    # AWS region
  instance_name: nested-virt-host          # EC2 instance name
  ssh_private_key_path: "~/.ssh/id_rsa_fips"  # SSH key
```

#### Second Play (DNS Configuration)

Edit the DNS settings in `configure-dns.yml`:

```yaml
vars:
  dns_domain: example.com        # Your domain
  cluster_name: sno              # OpenShift cluster name
  api_vip: 192.168.122.10       # API endpoint IP
  ingress_vip: 192.168.122.11   # Ingress/apps wildcard IP
  dns_forwarders:               # Upstream DNS servers
    - 8.8.8.8
    - 8.8.4.4
```

#### Override from Command Line

```bash
ansible-playbook configure-dns.yml \
  -e aws_region=us-west-2 \
  -e instance_name=my-custom-host \
  -e dns_domain=mydomain.com \
  -e cluster_name=prod
```

## DNS Records Created

### A Records

| Record | IP | Purpose |
|--------|-----|---------|
| `api.sno.example.com` | 192.168.122.10 | OpenShift API endpoint |
| `*.apps.sno.example.com` | 192.168.122.11 | Wildcard for all apps/routes |

This means all app routes resolve to the ingress VIP:
- `console-openshift-console.apps.sno.example.com` → 192.168.122.11
- `oauth-openshift.apps.sno.example.com` → 192.168.122.11
- `myapp.apps.sno.example.com` → 192.168.122.11

### PTR Records (Reverse DNS)

| IP | Record |
|----|--------|
| 192.168.122.10 | api.sno.example.com |
| 192.168.122.11 | apps.sno.example.com |

### NS Record

- `ns1.example.com` → EC2 instance public IP

## Testing DNS

### From the EC2 Instance

The instance is configured to use itself (127.0.0.1) for DNS, so you can query without specifying a server:

```bash
ssh ec2-user@<instance-ip>

# Test API record (uses localhost DNS automatically)
dig api.sno.example.com

# Test wildcard apps record
dig console.apps.sno.example.com
dig test.apps.sno.example.com

# You can also explicitly query localhost
dig @localhost api.sno.example.com

# Test reverse DNS
dig -x 192.168.122.10
dig -x 192.168.122.11

# Verify resolv.conf uses localhost
cat /etc/resolv.conf
# Should show: nameserver 127.0.0.1

# Check DNS server status
sudo systemctl status named

# View DNS logs
sudo journalctl -u named -f
```

### From Your Local Machine

```bash
# Test using the EC2 DNS server
dig @<instance-public-ip> api.sno.example.com
dig @<instance-public-ip> console.apps.sno.example.com

# Use nslookup
nslookup api.sno.example.com <instance-public-ip>
```

### From VMs Inside the Network

```bash
# On a VM, test DNS resolution
dig api.sno.example.com
dig console.apps.sno.example.com

# Test with curl
curl -k https://api.sno.example.com:6443
```

## Configuring VMs to Use This DNS

### DNS Server IP Address

The DNS server IP depends on which network your VMs are using:

- **VMs on baremetal bridge**: Use the EC2 instance's VPC IP (e.g., `10.0.1.236`)
  - This is for OpenShift nodes and VMs with direct network access
  - Check with: `ip addr show baremetal` on the EC2 instance
  
- **VMs on NAT network (virbr0)**: Use `192.168.122.1`
  - This is the libvirt default network gateway
  - Only works for isolated VMs on the NAT network

### Option 1: Static Configuration in VM

For VMs on the **baremetal bridge** (recommended for OpenShift):

```bash
# Get the EC2 instance IP first
ip addr show baremetal
# Use the IP shown (e.g., 10.0.1.236)

# On the VM, add to /etc/resolv.conf:
nameserver 10.0.1.236  # EC2 instance IP on baremetal bridge
search example.com
```

For VMs on the **NAT network**:

```bash
nameserver 192.168.122.1  # Gateway IP on NAT network
search example.com
```

### Option 2: Configure in install-config.yaml

For OpenShift on the baremetal bridge, use in `networkConfig`:

```yaml
dns-resolver:
  config:
    server:
    - 10.0.1.236  # EC2 instance IP (check with: ip addr show baremetal)
```

**Important**: Replace `10.0.1.236` with your actual EC2 instance IP on the baremetal bridge.

### Option 3: DHCP Configuration

Update libvirt network to use this DNS:

```bash
sudo virsh net-edit default
```

Add DNS forwarder:
```xml
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <dns forwardPlainNames='yes'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
```

Restart the network:
```bash
sudo virsh net-destroy default
sudo virsh net-start default
```

## DNS Configuration Files

### Main Configuration
- **File**: `/etc/named.conf`
- **Purpose**: Main BIND configuration

### Zone Files
- **Forward Zone**: `/var/named/example.com.zone`
- **Reverse Zone**: `/var/named/122.168.192.in-addr.arpa.zone`

### View Zone Files

```bash
# View forward zone
sudo cat /var/named/example.com.zone

# View reverse zone
sudo cat /var/named/122.168.192.in-addr.arpa.zone

# Check configuration syntax
sudo named-checkconf /etc/named.conf

# Check zone file syntax
sudo named-checkzone example.com /var/named/example.com.zone
```

## Adding Additional DNS Records

### Edit Zone File

```bash
ssh ec2-user@<instance-ip>

# Edit the zone file
sudo vim /var/named/example.com.zone
```

### Add Records

```bind
; Add additional A records
node1           IN  A       192.168.122.20
node2           IN  A       192.168.122.21

; Add CNAME records
www             IN  CNAME   node1
```

### Reload DNS

```bash
# Update serial number in zone file first!
# Change the serial in SOA record (e.g., increment by 1)

# Check zone syntax
sudo named-checkzone example.com /var/named/example.com.zone

# Reload named
sudo systemctl reload named

# Or use rndc
sudo rndc reload
```

## Troubleshooting

### DNS Service Won't Start

```bash
# Check configuration syntax
sudo named-checkconf /etc/named.conf

# Check zone file syntax
sudo named-checkzone example.com /var/named/example.com.zone

# Check logs
sudo journalctl -u named -n 50

# Check SELinux
sudo ausearch -m avc -ts recent
```

### DNS Not Resolving

```bash
# Check if named is running
sudo systemctl status named

# Check if listening on port 53
sudo ss -tulnp | grep :53

# Check firewall
sudo firewall-cmd --list-services | grep dns

# Test locally
dig @localhost api.sno.example.com

# Check zone is loaded
sudo rndc status
```

### Firewall Issues

```bash
# Add DNS service to firewall
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --reload

# Or add port directly
sudo firewall-cmd --permanent --add-port=53/tcp
sudo firewall-cmd --permanent --add-port=53/udp
sudo firewall-cmd --reload
```

### SELinux Issues

```bash
# Check for denials
sudo ausearch -m avc -ts recent | grep named

# Restore proper context
sudo restorecon -rv /var/named

# If needed, set to permissive for testing
sudo setenforce 0
```

## Using with OpenShift

### Update install-config.yaml

Ensure DNS servers point to your DNS server in the `networkConfig`:

```yaml
networkConfig:
  interfaces:
  - name: eth0
    type: ethernet
    state: up
    mac-address: "52:54:00:XX:XX:XX"
    ipv4:
      enabled: true
      address:
      - ip: 192.168.122.10
        prefix-length: 24
      dhcp: false
  dns-resolver:
    config:
      server:
      - 192.168.122.1  # DNS server (EC2 instance on libvirt network)
      - 8.8.8.8        # Fallback
  routes:
    config:
    - destination: 0.0.0.0/0
      next-hop-address: 192.168.122.1
      next-hop-interface: eth0
```

### Verify DNS Before Install

Before running OpenShift installer, verify DNS works:

```bash
# From VM network
dig @192.168.122.1 api.sno.example.com
dig @192.168.122.1 console.apps.sno.example.com
dig @192.168.122.1 test.apps.sno.example.com

# All should return the correct IPs
```

## DNS for Multiple Clusters

To support multiple OpenShift clusters, add more records:

```bash
# Edit zone file
sudo vim /var/named/example.com.zone
```

Add:
```bind
; Cluster 1 (sno)
api.sno                     IN  A       192.168.122.10
*.apps.sno                  IN  A       192.168.122.11

; Cluster 2 (prod)
api.prod                    IN  A       192.168.122.20
*.apps.prod                 IN  A       192.168.122.21

; Cluster 3 (dev)
api.dev                     IN  A       192.168.122.30
*.apps.dev                  IN  A       192.168.122.31
```

Reload:
```bash
sudo systemctl reload named
```

## External DNS Access

If you want to access OpenShift from outside the EC2 instance:

### Option 1: Port Forwarding via SSH

```bash
# Forward API port
ssh -L 6443:192.168.122.10:6443 ec2-user@<instance-ip>

# Forward HTTPS for apps
ssh -L 443:192.168.122.11:443 ec2-user@<instance-ip>

# Update /etc/hosts locally
echo "127.0.0.1 api.sno.example.com" | sudo tee -a /etc/hosts
echo "127.0.0.1 console-openshift-console.apps.sno.example.com" | sudo tee -a /etc/hosts
```

### Option 2: VPN/Bastion

Set up a VPN or bastion host to access the private network directly.

## Cleaning Up DNS

To remove DNS configuration:

```bash
ssh ec2-user@<instance-ip>

# Stop and disable named
sudo systemctl stop named
sudo systemctl disable named

# Remove configuration
sudo rm -f /etc/named.conf
sudo rm -rf /var/named/*.zone

# Remove firewall rule
sudo firewall-cmd --permanent --remove-service=dns
sudo firewall-cmd --reload
```

## References

- [BIND Documentation](https://bind9.readthedocs.io/)
- [OpenShift DNS Requirements](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal.html#installation-dns-user-infra_installing-bare-metal)
- [RHEL DNS Configuration](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_networking_infrastructure_services/assembly_setting-up-and-configuring-a-bind-dns-server_networking-infrastructure-services)
