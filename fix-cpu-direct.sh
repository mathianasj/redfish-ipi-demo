#!/bin/bash
# Direct CPU configuration fix via XML manipulation

MASTERS="ocp-master-1 ocp-master-2 ocp-master-3"

echo "============================================"
echo "Fixing CPU Configuration for All Masters"
echo "============================================"
echo ""

for VM in $MASTERS; do
    echo "Processing $VM..."

    # Stop VM
    sudo virsh destroy $VM 2>/dev/null || true
    sleep 1

    # Dump current XML
    sudo virsh dumpxml $VM > /tmp/${VM}-original.xml

    # Create new CPU configuration
    # Replace host-passthrough with host-model and remove incompatible attributes
    sudo sed -i '/<cpu mode=.*host-passthrough/,/<\/cpu>/c\  <cpu mode="host-model" check="none">\
  <\/cpu>' /tmp/${VM}-original.xml

    # Undefine the VM
    sudo virsh undefine $VM

    # Redefine with new XML
    sudo virsh define /tmp/${VM}-original.xml

    # Disable nested virt features
    sudo virt-xml $VM --edit --cpu feature policy=disable,name=vmx 2>/dev/null || true
    sudo virt-xml $VM --edit --cpu feature policy=disable,name=svm 2>/dev/null || true

    # Set crash behavior to restart
    sudo virt-xml $VM --edit --events on_crash=restart 2>/dev/null || true

    echo "✓ $VM configured"
    echo ""
done

echo "Starting VMs..."
echo ""

for VM in $MASTERS; do
    echo "Starting $VM..."
    sudo virsh start $VM
    sleep 3
done

echo ""
echo "Monitoring for 30 seconds..."
echo ""

for i in {1..6}; do
    echo "Check $i/6:"
    for VM in $MASTERS; do
        STATE=$(sudo virsh domstate $VM)
        printf "  %-15s %s\n" "$VM:" "$STATE"
    done
    echo ""
    sleep 5
done

echo "============================================"
echo "Done!"
echo "============================================"
