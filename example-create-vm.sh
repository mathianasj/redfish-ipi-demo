#!/bin/bash
# Example script to create a VM on the nested virtualization host
# Run this on the EC2 instance after setup

set -e

VM_NAME="${1:-testvm}"
VM_RAM="${2:-4096}"
VM_CPUS="${3:-2}"
VM_DISK_SIZE="${4:-20}"

echo "Creating VM: $VM_NAME"
echo "  RAM: ${VM_RAM}MB"
echo "  CPUs: $VM_CPUS"
echo "  Disk: ${VM_DISK_SIZE}GB"

sudo virt-install \
  --name "$VM_NAME" \
  --ram "$VM_RAM" \
  --vcpus "$VM_CPUS" \
  --disk path=/storage/vms/${VM_NAME}.qcow2,size="$VM_DISK_SIZE",format=qcow2 \
  --os-variant generic \
  --network network=default \
  --graphics vnc,listen=0.0.0.0 \
  --console pty,target_type=serial \
  --cdrom /storage/isos/your-iso.iso  # Place ISOs in /storage/isos/

echo ""
echo "VM created successfully!"
echo "To access the VM:"
echo "  - Console: virsh console $VM_NAME"
echo "  - VNC: Connect to $(hostname -I | awk '{print $1}'):5900"
echo "  - List VMs: virsh list --all"
echo "  - Start VM: virsh start $VM_NAME"
echo "  - Stop VM: virsh shutdown $VM_NAME"
echo ""
echo "Storage locations:"
echo "  - VM disk: /storage/vms/${VM_NAME}.qcow2"
echo "  - ISOs: /storage/isos/"
echo "  - Virtual media: /storage/vmedia/"
