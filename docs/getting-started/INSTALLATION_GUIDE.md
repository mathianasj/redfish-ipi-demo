# Complete OpenShift Installation Guide

Step-by-step guide to deploy OpenShift cluster on EC2 with nested virtualization.

## Overview

This guide covers:
1. **Prerequisites** - What you need before starting
2. **Infrastructure Setup** - Deploy EC2 instance with KVM
3. **OpenShift Installation** - Deploy OpenShift cluster
4. **Split-Horizon DNS** - Configure external access
5. **Verification** - Test your cluster

**Total Time**: ~90-120 minutes

## Prerequisites

### 1. Install Required Tools

```bash
# Install AWS CLI
pip install awscli

# Configure AWS credentials
aws configure

# Install Ansible
pip install ansible

# Install required collections
ansible-galaxy collection install -r requirements.yml
```

### 2. Get OpenShift Pull Secret

1. Go to https://console.redhat.com/openshift/install/pull-secret
2. Download your pull secret
3. Save it to the project directory:

```bash
cp ~/Downloads/pull-secret.txt pullsecret.json
```

### 3. Generate SSH Keys (if you don't have them)

```bash
# Generate FIPS-compliant SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_fips

# Set correct permissions
chmod 600 ~/.ssh/id_rsa_fips
chmod 644 ~/.ssh/id_rsa_fips.pub
```

### 4. Configure Variables

Edit `group_vars/all.yml`:

```yaml
# AWS Configuration
aws_region: us-east-2
instance_type: m8i.16xlarge  # Or m7i.16xlarge

# SSH Keys
ssh_public_key_path: "~/.ssh/id_rsa_fips.pub"
ssh_private_key_path: "~/.ssh/id_rsa_fips"

# Security
cockpit_admin_password: "YourSecurePassword123!"  # CHANGE THIS!
```

### 5. Get Route53 Hosted Zone ID (for external DNS)

```bash
# List your Route53 hosted zones
aws route53 list-hosted-zones

# Note the Zone ID for later (e.g., Z1234567890ABC)
```

## Installation Methods

You have two options:

### Option A: One-Command Full Deployment

Everything in one go (infrastructure + OpenShift):

```bash
# Activate virtual environment
source venv/bin/activate

# Option A1: Auto-discover Route53 domain (recommended - requires exactly 1 hosted zone)
ansible-playbook playbook.yml \
  -e install_openshift=true \
  -e use_route53=true

# Option A2: Specific Route53 zone (if you have multiple)
ansible-playbook playbook.yml \
  -e install_openshift=true \
  -e route53_hosted_zone_id=Z1234567890ABC

# Option A3: With custom domain (no Route53 lookup)
ansible-playbook playbook.yml \
  -e install_openshift=true \
  -e ocp_base_domain=mydomain.com

# Option A4: Default example.com domain (testing only)
ansible-playbook playbook.yml -e install_openshift=true
```

**Use this if:**
- ✅ First time setup
- ✅ Want automated end-to-end deployment
- ✅ Can wait 90-120 minutes

### Option B: Step-by-Step Deployment (Recommended)

More control, easier to troubleshoot:

```bash
# Activate virtual environment
source venv/bin/activate

# Step 1: Deploy infrastructure only (20-35 minutes)
ansible-playbook playbook.yml

# Step 2: Install OpenShift (45-60 minutes)
ansible-playbook prepare-and-install-openshift.yml

# Step 3: Configure split-horizon DNS (5 minutes)
ansible-playbook configure-split-horizon-dns.yml \
  -e route53_hosted_zone_id=Z1234567890ABC

# Step 4: Configure external Route53 DNS (2 minutes)
./configure-route53-external.sh Z1234567890ABC
```

**Use this if:**
- ✅ Want to verify each step
- ✅ Need to troubleshoot issues
- ✅ Want to customize between steps

## Step-by-Step Instructions

### Step 1: Deploy Infrastructure (20-35 minutes)

This creates the EC2 instance and configures KVM:

```bash
source venv/bin/activate

# Option 1: Auto-discover Route53 (if you have exactly 1 hosted zone)
ansible-playbook playbook.yml -e use_route53=true

# Option 2: Specific Route53 zone (if you have multiple)
ansible-playbook playbook.yml -e route53_hosted_zone_id=Z1234567890ABC

# Option 3: Custom domain (no Route53)
ansible-playbook playbook.yml -e ocp_base_domain=mydomain.com

# Option 4: Default example.com (testing only)
ansible-playbook playbook.yml
```

**What this does:**
- ✅ Creates VPC and networking
- ✅ Launches EC2 instance (m8i.16xlarge)
- ✅ Configures nested virtualization
- ✅ Installs KVM, libvirt, sushy-tools
- ✅ Sets up internal Bind DNS
- ✅ Creates master VMs (powered off)
- ✅ Generates install-config.yaml

**Output:**
```
PLAY RECAP *************************************************************
localhost                  : ok=45   changed=30   unreachable=0    failed=0
3.145.67.89                : ok=120  changed=85   unreachable=0    failed=0
```

**Verify:**
```bash
# SSH to EC2 instance
ssh ec2-user@<instance-public-ip>

# Check VMs exist (should be 3 masters, powered off)
sudo virsh list --all

# Check sushy is running
curl http://localhost:8000/redfish/v1/Systems

# Exit
exit
```

### Step 2: Install OpenShift (45-60 minutes)

This deploys the OpenShift cluster:

```bash
ansible-playbook prepare-and-install-openshift.yml
```

**What this does:**
- ✅ Discovers and adds DNS records for discovered VIPs
- ✅ Creates install-config.yaml (if not exists)
- ✅ Runs `openshift-install create cluster` in tmux
- ✅ Monitors installation progress
- ✅ Configures cluster access
- ✅ Saves credentials to `~/openshift-cluster-access.txt`

**Progress:**
```
INFO Waiting up to 20m0s for the Kubernetes API at https://api.sno.example.com:6443...
INFO API v1.31.0 up
INFO Waiting up to 40m0s for bootstrapping to complete...
INFO Destroying the bootstrap resources...
INFO Waiting up to 40m0s for the cluster to initialize...
```

**Output:**
```
PLAY RECAP *************************************************************
localhost                  : ok=5    changed=0    unreachable=0    failed=0
3.145.67.89                : ok=35   changed=12   unreachable=0    failed=0
```

**Verify:**
```bash
# SSH to EC2
ssh ec2-user@<instance-public-ip>

# Check cluster access info
cat ~/openshift-cluster-access.txt

# Test cluster access
export KUBECONFIG=~/openshift-install/auth/kubeconfig
oc get nodes
oc get co  # All should be "Available"
```

### Step 3: Configure Split-Horizon DNS (5 minutes)

This sets up internal and proxy configuration:

```bash
# Provide your Route53 zone ID
ansible-playbook configure-split-horizon-dns.yml \
  -e route53_hosted_zone_id=Z1234567890ABC
```

**What this does:**
- ✅ Looks up domain from Route53 zone (e.g., `mydomain.com`)
- ✅ Discovers API and Ingress VIPs from cluster
- ✅ Configures Bind DNS with discovered domain and VIPs
- ✅ Configures HAProxy to proxy EC2 public IP to VIPs
- ✅ Opens firewall ports (6443, 443, 80, 9000)

**Output:**
```
TASK [Display discovered VIPs]
ok: [3.145.67.89] => 
  msg:
  - 'Discovered OpenShift VIPs:'
  - '  API VIP: 192.168.122.10'
  - '  Ingress VIP: 192.168.122.11'
```

**Verify:**
```bash
# Test internal DNS
ssh ec2-user@<instance-ip>
dig api.sno.mydomain.com  # Should return 192.168.122.10
dig console.apps.sno.mydomain.com  # Should return 192.168.122.11

# Test HAProxy
curl -k https://localhost:6443/healthz  # Should return "ok"

# Check HAProxy stats
curl http://localhost:9000/stats
```

### Step 4: Configure External Route53 DNS (2 minutes)

This makes your cluster accessible from the internet:

```bash
# Using helper script (automatic)
./configure-route53-external.sh Z1234567890ABC

# Or manually
EC2_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=nested-virt-host" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

ansible-playbook configure-dns-route53.yml \
  -e route53_hosted_zone_id=Z1234567890ABC \
  -e api_vip=$EC2_IP \
  -e ingress_vip=$EC2_IP
```

**What this does:**
- ✅ Gets EC2 public IP automatically
- ✅ Discovers domain from Route53 zone
- ✅ Creates Route53 A records:
  - `api.sno.mydomain.com` → EC2 public IP
  - `*.apps.sno.mydomain.com` → EC2 public IP

**Verify (wait 60 seconds for DNS propagation):**
```bash
# From your laptop
dig api.sno.mydomain.com  # Should return EC2 public IP

curl -k https://api.sno.mydomain.com:6443/healthz  # Should return "ok"
```

## Access Your Cluster

### From External (Your Laptop)

```bash
# Get kubeconfig from EC2
ssh ec2-user@<instance-ip> cat ~/openshift-install/auth/kubeconfig > ~/kubeconfig-ocp

# Set environment variable
export KUBECONFIG=~/kubeconfig-ocp

# Test access
oc get nodes
oc get co

# Get console URL and credentials
ssh ec2-user@<instance-ip> cat ~/openshift-cluster-access.txt
```

### Access Web Console

```bash
# Get credentials
ssh ec2-user@<instance-ip> cat ~/openshift-cluster-access.txt

# Open in browser (using external DNS)
https://console-openshift-console.apps.sno.mydomain.com

# Login with:
# Username: kubeadmin
# Password: (from cluster-access.txt)
```

## Verification Checklist

### ✅ Infrastructure

```bash
# EC2 instance running
aws ec2 describe-instances --filters "Name=tag:Name,Values=nested-virt-host"

# SSH access works
ssh ec2-user@<instance-ip> uptime
```

### ✅ OpenShift Cluster

```bash
ssh ec2-user@<instance-ip>

# All nodes ready
oc get nodes
# NAME                         STATUS   ROLES                  AGE   VERSION
# master-0.sno.mydomain.com    Ready    control-plane,master   1h    v1.31.0
# master-1.sno.mydomain.com    Ready    control-plane,master   1h    v1.31.0
# master-2.sno.mydomain.com    Ready    control-plane,master   1h    v1.31.0

# All operators available
oc get co
# NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED
# authentication                             4.17.0    True        False         False
# cloud-credential                           4.17.0    True        False         False
# cluster-autoscaler                         4.17.0    True        False         False
# ...all should be True/False/False
```

### ✅ Internal DNS (Bind)

```bash
ssh ec2-user@<instance-ip>

# DNS resolution
dig api.sno.mydomain.com
# Should return: 192.168.122.10

dig console.apps.sno.mydomain.com
# Should return: 192.168.122.11

# DNS server running
sudo systemctl status named
```

### ✅ HAProxy Reverse Proxy

```bash
ssh ec2-user@<instance-ip>

# HAProxy running
sudo systemctl status haproxy

# Ports listening
sudo ss -tlnp | grep haproxy
# Should show: :6443, :443, :80, :9000

# Test proxy
curl -k https://localhost:6443/healthz
# Should return: ok

# View stats
curl http://localhost:9000/stats
```

### ✅ External Route53 DNS

```bash
# From your laptop
dig api.sno.mydomain.com
# Should return: <EC2 public IP>

dig console.apps.sno.mydomain.com
# Should return: <EC2 public IP>
```

### ✅ External Access

```bash
# From your laptop
curl -k https://api.sno.mydomain.com:6443/healthz
# Should return: ok

# Test console
curl -k https://console-openshift-console.apps.sno.mydomain.com
# Should return HTML
```

## Common Issues

### Issue: EC2 Instance Creation Fails

```
Error: UnauthorizedOperation: You are not authorized to perform this operation
```

**Solution:**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify permissions (need EC2, VPC permissions)
```

### Issue: OpenShift Install Hangs

```
INFO Waiting up to 20m0s for the Kubernetes API...
```

**Solution:**
```bash
# SSH to EC2
ssh ec2-user@<instance-ip>

# Check VMs are powered on
sudo virsh list

# Check VIP is reachable
ping 192.168.122.10

# Check DNS
dig api.sno.example.com

# View installer logs
tail -f ~/openshift-install/.openshift_install.log
```

### Issue: DNS Not Resolving

**Internal DNS:**
```bash
ssh ec2-user@<instance-ip>

# Check named
sudo systemctl status named
sudo journalctl -u named -f

# Test resolution
dig @localhost api.sno.mydomain.com
```

**External DNS:**
```bash
# Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id Z1234567890ABC

# Wait for propagation (up to 60 seconds)
dig api.sno.mydomain.com
```

### Issue: HAProxy Connection Refused

```bash
ssh ec2-user@<instance-ip>

# Check HAProxy
sudo systemctl status haproxy
sudo journalctl -u haproxy -n 50

# Check firewall
sudo firewall-cmd --list-all

# Test backend directly
curl -k https://192.168.122.10:6443/healthz
```

## Next Steps

### Add Worker Nodes

```bash
ansible-playbook scale-workers.yml -e worker_count=2
```

### Set Up Monitoring

```bash
# Enable cluster monitoring
oc create -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF
```

### Configure Authentication

```bash
# Set up htpasswd identity provider
htpasswd -c -B -b users.htpasswd admin password123
oc create secret generic htpass-secret \
  --from-file=htpasswd=users.htpasswd -n openshift-config

oc apply -f - <<EOF
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: my_htpasswd_provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
EOF
```

## Cleanup

### Option 1: Destroy OpenShift Only (Keep Infrastructure)

Use this to reinstall OpenShift without rebuilding AWS infrastructure:

```bash
# Destroy cluster, keep EC2 instance
ansible-playbook destroy-openshift-cluster.yml -e confirm_destroy=true

# Then reinstall OpenShift
ansible-playbook playbook.yml \
  -e install_openshift=true \
  -e route53_hosted_zone_id=Z1234567890ABC
```

**What this removes:**
- ✓ OpenShift cluster (all nodes, services, data)
- ✓ Master VMs
- ✓ Installation directory and credentials

**What this keeps:**
- ✓ EC2 instance
- ✓ AWS infrastructure (VPC, networking)
- ✓ DNS server (bind)
- ✓ Redfish BMC (sushy-tools)

### Option 2: Delete Everything (Full Cleanup)

Removes all AWS resources:

```bash
# Delete everything
ansible-playbook cleanup.yml -e confirm_deletion=true
```

**What this removes:**
- ✓ EC2 instance
- ✓ All EBS volumes
- ✓ VPC, subnets, security groups
- ✓ Everything

### Option 3: Manual Cluster Destruction

```bash
# SSH to EC2
ssh ec2-user@<instance-ip>

# Destroy OpenShift cluster
cd ~/openshift-install
./openshift-install destroy cluster --dir .
```

## Cost Optimization

### Use Spot Instances

Edit `group_vars/all.yml`:
```yaml
use_spot_instance: true
spot_max_price: "1.50"  # m8i.16xlarge on-demand is ~$3.50/hr
```

### Stop Instance When Not Using

```bash
# Stop instance (retains all data)
ansible-playbook stop-instance.yml

# Start again later
ansible-playbook start-instance.yml
```

### Use Smaller Instance for Testing

Edit `group_vars/all.yml`:
```yaml
instance_type: m7i.8xlarge  # 16 cores, 128GB RAM (~$1.60/hr)
cpu_core_count: 16
```

## Reference

- [Complete Deployment Guide](../openshift/COMPLETE_DEPLOYMENT.md)
- [Split-Horizon DNS Guide](../infrastructure/SPLIT_HORIZON_DNS.md)
- [DNS Comparison](../infrastructure/DNS_COMPARISON.md)
- [Troubleshooting](../troubleshooting/)

## Support

For issues or questions:
1. Check [Troubleshooting guides](../troubleshooting/)
2. Review [OpenShift documentation](https://docs.openshift.com/)
3. Open issue at https://github.com/mathianasj/redfish-ipi-demo/issues
