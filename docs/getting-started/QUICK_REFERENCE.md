# Quick Reference Guide

## One-Command Deployment

```bash
ansible-playbook playbook.yml
```

**Time:** 60-90 minutes  
**Result:** Complete OpenShift cluster ready to use

## Phase Overview

| Phase | Duration | Description |
|-------|----------|-------------|
| 1. AWS Infrastructure | 5-10 min | Create EC2 instance with VPC |
| 2. Virtualization Setup | 10-15 min | Install KVM, libvirt, Redfish |
| 3. DNS Configuration | 2-3 min | Setup BIND DNS server |
| 4. OpenShift Preparation | 5-10 min | Create VMs and config |
| 5. OpenShift Installation | 45-60 min | Install and configure cluster |

## Individual Playbooks

```bash
# DNS only (Phase 3)
ansible-playbook configure-dns.yml

# Prepare OpenShift only (Phase 4)
ansible-playbook prepare-openshift.yml

# Install OpenShift only (Phase 5)
ansible-playbook install-openshift-cluster.yml

# Prepare + Install (Phases 4-5)
ansible-playbook prepare-and-install-openshift.yml
```

## Common Commands

### Check Installation Progress

```bash
# SSH to instance
ssh ec2-user@<EC2_IP>

# Attach to installation
tmux attach -t openshift-install

# View logs
tail -f ~/openshift-install/.openshift_install.log

# Detach from tmux
# Press: Ctrl+B, then D
```

### Access Cluster

```bash
# View access information
cat ~/openshift-cluster-access.txt

# Check nodes
oc get nodes

# Check cluster operators
oc get co

# Check all pods
oc get pods -A
```

### Web Console

```
URL: https://console-openshift-console.apps.ocp.example.com
Username: kubeadmin
Password: (check ~/kubeadmin-password)
```

## File Locations

| File | Path |
|------|------|
| Access info | `/home/ec2-user/openshift-cluster-access.txt` |
| Admin password | `/home/ec2-user/kubeadmin-password` |
| Kubeconfig (ec2-user) | `/home/ec2-user/.kube/config` |
| Kubeconfig (root) | `/root/.kube/config` |
| Install config backup | `/home/ec2-user/install-config.yaml.backup` |
| Network config | `/home/ec2-user/openshift-install/network-config.txt` |
| Install log | `/home/ec2-user/openshift-install/.openshift_install.log` |

## Troubleshooting Quick Checks

```bash
# Check named service
systemctl status named

# Test DNS
dig @localhost api.ocp.example.com

# Check libvirt
systemctl status libvirtd
virsh list --all

# Check Redfish BMC
systemctl status sushy-emulator
curl http://localhost:8000/redfish/v1/Systems

# Check VM network
virsh net-list
virsh net-dhcp-leases default
```

## Clean Up

### Remove OpenShift (keep infrastructure)

```bash
ssh ec2-user@<EC2_IP>
rm -rf ~/openshift-install
sudo virsh destroy ocp-master-1 ocp-master-2 ocp-master-3
sudo virsh undefine ocp-master-1 ocp-master-2 ocp-master-3
```

### Destroy Everything

```bash
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>
```

## Cost Management

```bash
# Stop instance (saves compute cost)
aws ec2 stop-instances --instance-ids <INSTANCE_ID>

# Start instance (IP will change)
aws ec2 start-instances --instance-ids <INSTANCE_ID>

# Get new IP
aws ec2 describe-instances --instance-ids <INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].PublicIpAddress'
```

## Variables

Edit `playbook.yml` for customization:

```yaml
# AWS
aws_region: us-east-2
instance_type: m8i.16xlarge

# DNS
dns_domain: example.com

# OpenShift
ocp_cluster_name: ocp
ocp_base_domain: example.com
```

## Estimated Costs

- **m8i.16xlarge:** ~$4/hour
- **Complete deployment:** $4-6
- **Testing (4 hours):** ~$16
- **Stopped instance:** ~$0.10/GB/month (storage only)

## Support Files

- `COMPLETE_DEPLOYMENT.md` - Full deployment guide
- `README.md` - Project overview
- `roles/*/README.md` - Individual role documentation
