# Complete OpenShift Deployment on AWS EC2

This guide covers the end-to-end deployment of OpenShift on AWS EC2 using nested virtualization.

## Overview

The main `playbook.yml` now performs a complete deployment in 5 phases:

### Phase 1: AWS Infrastructure (5-10 minutes)
- Create VPC and networking components
- Launch EC2 instance with nested virtualization support
- Configure security groups and SSH access

### Phase 2: Virtualization Setup (10-15 minutes)
- Install KVM and libvirt packages
- Configure networking bridges
- Setup Redfish BMC using sushy-tools
- Install Cockpit web console
- Install OpenShift CLI tools

### Phase 3: DNS Configuration (2-3 minutes)
- Install and configure BIND DNS server
- Create DNS zones for OpenShift
- Configure DNS records for API and apps

### Phase 4: OpenShift Preparation (5-10 minutes)
- Create 3 master VMs (8 vCPUs, 32GB RAM, 120GB disk each)
- Generate install-config.yaml
- Configure network settings and VIPs
- Setup Redfish BMC access for VMs

### Phase 5: OpenShift Installation (45-60 minutes)
- Run openshift-install in a tmux session
- Monitor progress with real-time updates
- Configure kubeconfig files for root and ec2-user
- Save credentials and access URLs

**Total Time: 60-90 minutes**

## Prerequisites

### Local Machine
- Ansible 2.9 or higher
- AWS CLI configured with credentials
- SSH key pair (`~/.ssh/id_rsa_fips` and `~/.ssh/id_rsa_fips.pub`)
- Red Hat pull secret saved to `pullsecret.json`

### AWS Account
- Sufficient quota for m8i.16xlarge instances
- Access to RHEL 9 AMI

## Complete Deployment

### Single Command Deployment

Run the entire deployment from start to finish:

```bash
ansible-playbook playbook.yml
```

This will execute all 5 phases automatically.

### Selective Phase Execution

You can also run specific phases by creating a playbook that includes only the plays you need, or by using the `--start-at-task` flag:

```bash
# Start from DNS configuration (Phase 3)
ansible-playbook playbook.yml --start-at-task="Configure DNS server for OpenShift"

# Start from OpenShift preparation (Phase 4)
ansible-playbook playbook.yml --start-at-task="Prepare OpenShift installation"

# Start from OpenShift installation (Phase 5)
ansible-playbook playbook.yml --start-at-task="Install OpenShift cluster"
```

### Alternative: Individual Playbooks

If you prefer to run phases separately:

```bash
# Phase 1 & 2: AWS and Virtualization
ansible-playbook playbook.yml --tags never  # Run first 2 phases

# Phase 3: DNS
ansible-playbook configure-dns.yml

# Phase 4: Prepare OpenShift
ansible-playbook prepare-openshift.yml

# Phase 5: Install OpenShift
ansible-playbook install-openshift-cluster.yml
```

## Monitoring the Installation

### During Phase 5 (Installation)

The playbook monitors the installation automatically, showing progress updates every 30 seconds:

```
Installation in progress... (checked at 14:23:15)
Recent log entries:
  INFO Waiting for bootstrap to complete...
  INFO Bootstrap node responding...
```

### Manual Monitoring

You can disconnect from the playbook and monitor manually:

```bash
# SSH to the EC2 instance
ssh ec2-user@<EC2_PUBLIC_IP>

# Attach to the tmux session
tmux attach -t openshift-install

# View installation logs
tail -f ~/openshift-install/.openshift_install.log

# Detach from tmux: Ctrl+B, then D
```

## After Installation

### Access Information

All access details are saved to: `/home/ec2-user/openshift-cluster-access.txt`

```bash
ssh ec2-user@<EC2_PUBLIC_IP>
cat ~/openshift-cluster-access.txt
```

### Web Console Access

```
URL: https://console-openshift-console.apps.<cluster>.<domain>
Username: kubeadmin
Password: <displayed in output>
```

### CLI Access

Kubeconfig is automatically installed for both users:

```bash
# As ec2-user
oc get nodes
oc get clusterversion
oc get co  # Cluster operators

# As root
sudo -i
oc get nodes
```

### Files Created

| File | Description |
|------|-------------|
| `/home/ec2-user/openshift-cluster-access.txt` | Complete access information |
| `/home/ec2-user/kubeadmin-password` | Admin password |
| `/home/ec2-user/.kube/config` | Kubeconfig for ec2-user |
| `/root/.kube/config` | Kubeconfig for root |
| `/home/ec2-user/install-config.yaml.backup` | Backup of install config |
| `/home/ec2-user/openshift-install/network-config.txt` | Network configuration details |
| `/home/ec2-user/openshift-install/.openshift_install.log` | Installation log |

## Troubleshooting

### Phase 1 Failures
**EC2 instance won't launch**
- Check AWS quota for m8i.16xlarge instances
- Verify RHEL 9 AMI ID is correct for your region
- Check subnet availability in different AZs

### Phase 2 Failures
**Virtualization packages fail to install**
- Verify RHEL subscription is active
- Check network connectivity to package repositories
- Ensure sufficient disk space

### Phase 3 Failures
**DNS queries not resolving**
- Check named service status: `systemctl status named`
- Verify zone files: `named-checkzone example.com /var/named/example.com.zone`
- Test DNS: `dig @localhost api.ocp.example.com`

### Phase 4 Failures
**VMs fail to create**
- Check libvirt is running: `systemctl status libvirtd`
- Verify available disk space: `df -h`
- Check virsh network: `virsh net-list`

### Phase 5 Failures
**Installation timeout**
- SSH to instance and check tmux: `tmux attach -t openshift-install`
- Review logs: `tail -100 ~/openshift-install/.openshift_install.log`
- Check VM status: `virsh list --all`
- Verify Redfish BMC: `curl http://localhost:8000/redfish/v1/Systems`

**Installation errors**
Common issues:
- DNS not resolving from VMs
- Redfish BMC not accessible
- Network connectivity problems
- Insufficient resources

## Re-running Installation

### Clean Start
To completely start over:

```bash
# Destroy the EC2 instance
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>

# Re-run the complete deployment
ansible-playbook playbook.yml
```

### Restart from Phase 4
To keep the infrastructure but rebuild OpenShift:

```bash
# SSH to instance
ssh ec2-user@<EC2_PUBLIC_IP>

# Remove installation directory
rm -rf ~/openshift-install

# Destroy VMs
sudo virsh destroy ocp-master-1 || true
sudo virsh destroy ocp-master-2 || true
sudo virsh destroy ocp-master-3 || true
sudo virsh undefine ocp-master-1 || true
sudo virsh undefine ocp-master-2 || true
sudo virsh undefine ocp-master-3 || true

# Exit and re-run from Phase 4
exit
ansible-playbook playbook.yml --start-at-task="Prepare OpenShift installation"
```

## Customization

### Variables

Edit `playbook.yml` to customize:

```yaml
# AWS Configuration
aws_region: us-east-2
instance_type: m8i.16xlarge
instance_name: nested-virt-host

# DNS Configuration (in DNS play)
dns_domain: example.com

# OpenShift Configuration (in Prepare play)
ocp_cluster_name: ocp
ocp_base_domain: example.com
```

### Instance Type

The default `m8i.16xlarge` provides:
- 64 vCPUs (32 cores with hyperthreading)
- 128 GB RAM (actual is ~247 GB)
- Supports nested virtualization

Other compatible instances:
- `m7i.16xlarge` - Similar specs, slightly older generation
- `m7i.24xlarge` - More resources (48 cores, 192 GB RAM)
- `m8i.24xlarge` - More resources (48 cores, 192 GB RAM)

### VM Resources

Default VM allocation (configured in `roles/openshift_install/tasks/main.yml`):

```yaml
virt-install \
  --memory 32768   # 32 GB per VM (OpenShift recommended minimum)
  --vcpus 8        # 8 vCPUs per VM
  --disk size=120  # 120 GB per VM
```

**Total allocation:** 3 VMs × 32 GB = 96 GB (leaves plenty for host OS)

**Note:** The m8i.16xlarge actually has ~247 GB of RAM, so memory is not a concern.

## Cost Optimization

### Run Time Costs
- m8i.16xlarge: ~$4.03/hour (us-east-2, on-demand)
- Installation time: ~1-1.5 hours
- Testing/demo time: varies

**Estimated cost for deployment: $4-6**

### Stopping the Instance
After deployment, you can stop (not terminate) the instance to save costs:

```bash
aws ec2 stop-instances --instance-ids <INSTANCE_ID>
```

Stopped instances only incur EBS storage costs (~$0.10/GB/month).

### Starting Again
```bash
aws ec2 start-instances --instance-ids <INSTANCE_ID>
```

Note: Public IP will change unless you use an Elastic IP.

## Next Steps

After successful deployment:

1. **Explore the Web Console**
   - Navigate through the console
   - Review cluster operators
   - Check node status

2. **Deploy Sample Applications**
   ```bash
   oc new-app https://github.com/sclorg/nodejs-ex
   ```

3. **Create Users and Projects**
   ```bash
   oc create project myproject
   ```

4. **Configure Storage**
   - Review storage classes
   - Create persistent volumes

5. **Monitor Cluster**
   - Check cluster metrics
   - Review alerts

## Support

For issues or questions:
- Check logs in `/home/ec2-user/openshift-install/.openshift_install.log`
- Review network configuration in `~/openshift-install/network-config.txt`
- Consult OpenShift documentation: https://docs.openshift.com
