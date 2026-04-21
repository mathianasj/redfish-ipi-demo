# Quick Start Guide

## Deploy

```bash
# 1. Setup dependencies
./setup.sh

# 2. Activate virtual environment
source venv/bin/activate

# 3. Configure settings
vim group_vars/all.yml
# - Update ssh_public_key_path
# - Update cockpit_admin_password
# - Update aws_region if needed

# 4. Deploy!
ansible-playbook playbook.yml
```

## Access

After deployment completes, you'll see:

```
Cockpit Web Console:
  URL: https://<public-ip>:9090
  Username: admin
  Password: <your-password>

Redfish API (Sushy):
  URL: http://<public-ip>:8000/redfish/v1/

SSH Access:
  ssh ec2-user@<public-ip>
```

## Configure DNS (Optional for OpenShift)

```bash
# Activate virtual environment
source venv/bin/activate

# Configure DNS for OpenShift (automatically finds instance)
ansible-playbook configure-dns.yml

# This creates:
# - api.sno.example.com → 192.168.122.10
# - *.apps.sno.example.com → 192.168.122.11

# Test DNS
ssh ec2-user@<public-ip>
dig @localhost api.sno.example.com
```

See [../infrastructure/DNS_SETUP.md](../infrastructure/DNS_SETUP.md) for details.

## Common Tasks

### Create a VM

```bash
ssh ec2-user@<public-ip>

# Option 1: VM on baremetal bridge (direct network access - recommended for OpenShift)
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

# Option 2: VM on NAT network (isolated)
sudo virt-install \
  --name myvm-nat \
  --memory 4096 \
  --vcpus 2 \
  --disk path=/storage/vms/myvm-nat.qcow2,size=40 \
  --network network=default \
  --os-variant rhel9.0 \
  --boot uefi \
  --graphics vnc \
  --noautoconsole

# List VMs
sudo virsh list --all

# Start VM
sudo virsh start myvm

# Console access
sudo virsh console myvm

# Check bridge
ip addr show baremetal
```

See [../infrastructure/NETWORKING.md](../infrastructure/NETWORKING.md) for network details.

### Use Redfish Virtual Media

```bash
# Get VM UUID
VM_UUID=$(sudo virsh domuuid myvm)

# Mount ISO
curl -X POST http://<public-ip>:8000/redfish/v1/Systems/$VM_UUID/VirtualMedia/Cd/Actions/VirtualMedia.InsertMedia \
  -H "Content-Type: application/json" \
  -d '{
    "Image": "file:///storage/vmedia/rhel9.iso",
    "Inserted": true,
    "WriteProtected": true
  }'

# Power on via Redfish
curl -X POST http://<public-ip>:8000/redfish/v1/Systems/$VM_UUID/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "On"}'
```

### Check Storage

```bash
# Check disk usage
df -h

# Storage layout
lsblk

# Check libvirt storage
sudo virsh pool-list
sudo virsh vol-list default
```

## Cleanup

```bash
# Delete everything
ansible-playbook cleanup.yml -e confirm_deletion=true
```

See [../infrastructure/CLEANUP.md](../infrastructure/CLEANUP.md) for details.

## Troubleshooting

### Can't connect to Cockpit

```bash
# Check service
sudo systemctl status cockpit.socket

# Check firewall
sudo firewall-cmd --list-services
```

### Redfish not working

```bash
# Check Sushy service
sudo systemctl status sushy-emulator

# Check logs
sudo journalctl -u sushy-emulator -f
```

### VM won't start

```bash
# Check logs
sudo journalctl -u libvirtd -f

# Check VM definition
sudo virsh dumpxml <vm-name>

# Check resources
free -h
df -h /storage
```

### Bridge issues

```bash
# Check bridge
ip addr show baremetal
nmcli connection show baremetal

# Restart bridge
sudo nmcli connection down baremetal
sudo nmcli connection up baremetal
```

## Files Overview

| File | Purpose |
|------|---------|
| `playbook.yml` | Main deployment playbook |
| `cleanup.yml` | Delete all resources |
| `group_vars/all.yml` | Configuration variables |
| `openshift-sno-install-config.yaml` | OpenShift install config |
| `README.md` | Full documentation |
| `../infrastructure/CLEANUP.md` | Cleanup guide |
| `RHEL_SETUP.md` | RHEL 9 specific info |
| `SUSHY_REDFISH.md` | Redfish API guide |
| `CPU_OPTIONS.md` | CPU configuration guide |
| `INSTANCE_TYPES.md` | Instance type comparison |

## Costs

**Default m8i.16xlarge setup:**
- Instance: ~$7/hour (~$5,040/month)
- Storage: ~$160/month (2TB EBS)
- **Total**: ~$5,200/month

Use spot instances for 60-90% savings!

## Resources

- [Deploy Playbook](playbook.yml)
- [Cleanup Playbook](cleanup.yml)
- [Configuration](group_vars/all.yml)
- [Full Documentation](../../README.md)
