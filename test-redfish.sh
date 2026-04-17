#!/bin/bash
# Simple script to test Redfish API endpoints
# Usage: ./test-redfish.sh <instance-ip>

if [ -z "$1" ]; then
    echo "Usage: $0 <instance-ip>"
    echo "Example: $0 3.145.123.45"
    exit 1
fi

INSTANCE_IP=$1
BASE_URL="http://${INSTANCE_IP}:8000"

echo "=========================================="
echo "Testing Redfish API on ${INSTANCE_IP}"
echo "=========================================="
echo ""

# Test 1: Service Root
echo "1. Testing Service Root..."
echo "   GET ${BASE_URL}/redfish/v1/"
curl -s ${BASE_URL}/redfish/v1/ | jq -r '.Name, .RedfishVersion' 2>/dev/null || curl -s ${BASE_URL}/redfish/v1/
echo ""
echo ""

# Test 2: Systems Collection
echo "2. Listing Systems (VMs)..."
echo "   GET ${BASE_URL}/redfish/v1/Systems"
SYSTEMS=$(curl -s ${BASE_URL}/redfish/v1/Systems)
echo "$SYSTEMS" | jq '.' 2>/dev/null || echo "$SYSTEMS"
echo ""
echo ""

# Test 3: Get first system details
echo "3. Getting first system details..."
FIRST_SYSTEM=$(echo "$SYSTEMS" | jq -r '.Members[0]."@odata.id"' 2>/dev/null)
if [ -n "$FIRST_SYSTEM" ] && [ "$FIRST_SYSTEM" != "null" ]; then
    echo "   GET ${BASE_URL}${FIRST_SYSTEM}"
    SYSTEM_DETAIL=$(curl -s ${BASE_URL}${FIRST_SYSTEM})
    echo "$SYSTEM_DETAIL" | jq -r '"\(.Name): \(.PowerState)"' 2>/dev/null || echo "$SYSTEM_DETAIL"

    # Test 4: Virtual Media
    echo ""
    echo "4. Checking Virtual Media..."
    VMEDIA_URL=$(echo "$SYSTEM_DETAIL" | jq -r '.VirtualMedia."@odata.id"' 2>/dev/null)
    if [ -n "$VMEDIA_URL" ] && [ "$VMEDIA_URL" != "null" ]; then
        echo "   GET ${BASE_URL}${VMEDIA_URL}"
        curl -s ${BASE_URL}${VMEDIA_URL} | jq '.' 2>/dev/null || curl -s ${BASE_URL}${VMEDIA_URL}
    else
        echo "   Virtual Media not available or jq not installed"
    fi
else
    echo "   No systems found. Make sure VMs are created on the host."
    echo ""
    echo "   To create a test VM, SSH to the instance and run:"
    echo "   sudo virt-install --name test-vm --memory 1024 --vcpus 1 \\"
    echo "     --disk path=/var/lib/libvirt/images/test.qcow2,size=10 \\"
    echo "     --os-variant rhel9.0 --network network=default --graphics vnc \\"
    echo "     --noautoconsole --boot uefi"
fi

echo ""
echo "=========================================="
echo "Test complete!"
echo ""
echo "For more examples, see SUSHY_REDFISH.md"
echo "=========================================="
