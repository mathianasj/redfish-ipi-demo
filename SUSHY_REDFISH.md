# Sushy Redfish Emulator Configuration

This playbook installs and configures [Sushy-tools](https://docs.openstack.org/sushy-tools/latest/), a Redfish BMC emulator that provides a Redfish API for managing libvirt virtual machines with virtual media support.

## What is Sushy?

Sushy-tools emulates a Redfish-compliant Baseboard Management Controller (BMC) for virtual machines. This allows you to:
- Manage VMs using standard Redfish API calls
- Mount ISO images as virtual media (virtual CD/DVD)
- Control power state (power on/off/reset)
- Configure boot devices and boot order
- Use the same tools and workflows as physical bare-metal servers

## Redfish Endpoints

After deployment, Sushy exposes the following Redfish endpoints:

### Base URL
```
http://<instance-public-ip>:8000/redfish/v1/
```

### Common Endpoints
- **Service Root**: `http://<ip>:8000/redfish/v1/`
- **Systems Collection**: `http://<ip>:8000/redfish/v1/Systems`
- **Specific System**: `http://<ip>:8000/redfish/v1/Systems/<vm-uuid>`
- **Virtual Media**: `http://<ip>:8000/redfish/v1/Systems/<vm-uuid>/VirtualMedia`

## Configuration

Sushy is configured via `/etc/sushy/sushy-emulator.conf`:

```python
SUSHY_EMULATOR_LISTEN_IP = '0.0.0.0'
SUSHY_EMULATOR_LISTEN_PORT = 8000
SUSHY_EMULATOR_LIBVIRT_URI = 'qemu:///system'
SUSHY_EMULATOR_VMEDIA_DEVICES = {
    'Cd': {
        'Name': 'Virtual CD',
        'MediaTypes': ['CD', 'DVD']
    },
    'Floppy': {
        'Name': 'Virtual Floppy',
        'MediaTypes': ['Floppy', 'USBStick']
    }
}
SUSHY_EMULATOR_STORAGE_BACKEND = '/var/lib/sushy/vmedia'
```

## Service Management

Sushy runs as a systemd service:

```bash
# Check status
sudo systemctl status sushy-emulator

# Restart service
sudo systemctl restart sushy-emulator

# View logs
sudo journalctl -u sushy-emulator -f

# Check if service is listening
sudo ss -tlnp | grep 8000
```

## Usage Examples

### 1. List All Systems (VMs)

```bash
curl http://<instance-ip>:8000/redfish/v1/Systems | jq
```

**Example Response:**
```json
{
  "@odata.type": "#ComputerSystemCollection.ComputerSystemCollection",
  "Name": "Computer System Collection",
  "Members@odata.count": 2,
  "Members": [
    {
      "@odata.id": "/redfish/v1/Systems/vm1"
    },
    {
      "@odata.id": "/redfish/v1/Systems/vm2"
    }
  ]
}
```

### 2. Get System Details

```bash
# Get VM UUID
VM_UUID=$(sudo virsh domuuid <vm-name>)

# Get system info
curl http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID | jq
```

### 3. Power Control

```bash
VM_UUID=$(sudo virsh domuuid <vm-name>)

# Power On
curl -X POST http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "On"}'

# Power Off (graceful)
curl -X POST http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "GracefulShutdown"}'

# Force Power Off
curl -X POST http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "ForceOff"}'

# Reboot
curl -X POST http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "ForceRestart"}'
```

### 4. Virtual Media - Mount ISO

```bash
VM_UUID=$(sudo virsh domuuid <vm-name>)

# First, download an ISO to the vmedia directory
sudo wget -O /var/lib/sushy/vmedia/rhel9.iso \
  https://example.com/path/to/rhel-9.0-x86_64-dvd.iso

# Get virtual media collection
curl http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID/VirtualMedia | jq

# Insert virtual media (CD)
curl -X POST http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID/VirtualMedia/Cd/Actions/VirtualMedia.InsertMedia \
  -H "Content-Type: application/json" \
  -d '{
    "Image": "file:///var/lib/sushy/vmedia/rhel9.iso",
    "Inserted": true,
    "WriteProtected": true
  }'

# Check virtual media status
curl http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID/VirtualMedia/Cd | jq

# Eject virtual media
curl -X POST http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID/VirtualMedia/Cd/Actions/VirtualMedia.EjectMedia \
  -H "Content-Type: application/json" \
  -d '{}'
```

### 5. Set Boot Device

```bash
VM_UUID=$(sudo virsh domuuid <vm-name>)

# Boot from CD once
curl -X PATCH http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID \
  -H "Content-Type: application/json" \
  -d '{
    "Boot": {
      "BootSourceOverrideEnabled": "Once",
      "BootSourceOverrideTarget": "Cd"
    }
  }'

# Boot from hard disk (default)
curl -X PATCH http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID \
  -H "Content-Type: application/json" \
  -d '{
    "Boot": {
      "BootSourceOverrideEnabled": "Continuous",
      "BootSourceOverrideTarget": "Hdd"
    }
  }'

# Boot from network (PXE)
curl -X PATCH http://<instance-ip>:8000/redfish/v1/Systems/$VM_UUID \
  -H "Content-Type: application/json" \
  -d '{
    "Boot": {
      "BootSourceOverrideEnabled": "Once",
      "BootSourceOverrideTarget": "Pxe"
    }
  }'
```

## Complete Workflow: Install OS via Virtual Media

Here's a complete example of installing RHEL 9 on a VM using Redfish virtual media:

```bash
#!/bin/bash

REDFISH_URL="http://<instance-ip>:8000"
VM_NAME="rhel9-vm"
ISO_URL="https://example.com/rhel-9.0-x86_64-dvd.iso"

# 1. Create VM
sudo virt-install \
  --name $VM_NAME \
  --memory 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/${VM_NAME}.qcow2,size=40,format=qcow2 \
  --network network=default \
  --graphics vnc,listen=0.0.0.0 \
  --os-variant rhel9.0 \
  --noautoconsole \
  --boot uefi

# Wait for VM to be created
sleep 5

# Get VM UUID
VM_UUID=$(sudo virsh domuuid $VM_NAME)
echo "VM UUID: $VM_UUID"

# 2. Download ISO to vmedia directory
sudo wget -O /var/lib/sushy/vmedia/rhel9.iso $ISO_URL

# 3. Power off VM (if running)
curl -X POST $REDFISH_URL/redfish/v1/Systems/$VM_UUID/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "ForceOff"}'

sleep 5

# 4. Insert virtual CD
curl -X POST $REDFISH_URL/redfish/v1/Systems/$VM_UUID/VirtualMedia/Cd/Actions/VirtualMedia.InsertMedia \
  -H "Content-Type: application/json" \
  -d '{
    "Image": "file:///var/lib/sushy/vmedia/rhel9.iso",
    "Inserted": true,
    "WriteProtected": true
  }'

# 5. Set boot to CD once
curl -X PATCH $REDFISH_URL/redfish/v1/Systems/$VM_UUID \
  -H "Content-Type: application/json" \
  -d '{
    "Boot": {
      "BootSourceOverrideEnabled": "Once",
      "BootSourceOverrideTarget": "Cd"
    }
  }'

# 6. Power on VM
curl -X POST $REDFISH_URL/redfish/v1/Systems/$VM_UUID/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "On"}'

echo "VM is booting from ISO. Connect to console:"
echo "sudo virsh console $VM_NAME"
```

## Using Python Redfish Library

Install the Redfish Python client:
```bash
pip install redfish
```

Example Python script:
```python
#!/usr/bin/env python3
import redfish

# Connect to Redfish service
REDFISH_HOST = "http://<instance-ip>:8000"
client = redfish.redfish_client(base_url=REDFISH_HOST)
client.login()

# Get systems
systems = client.get("/redfish/v1/Systems")
print("Systems:", systems.dict)

# Get first system
system_url = systems.dict['Members'][0]['@odata.id']
system = client.get(system_url)
print(f"System: {system.dict['Name']}")
print(f"Power State: {system.dict['PowerState']}")

# Power on
reset_action = system.dict['Actions']['#ComputerSystem.Reset']
client.post(reset_action['target'], body={'ResetType': 'On'})

client.logout()
```

## Integration with Bare Metal Provisioning

Sushy is commonly used with:
- **OpenStack Ironic**: Bare metal provisioning
- **Metal3**: Kubernetes bare metal operator
- **RedHat OpenShift**: Bare metal IPI deployments

This setup allows you to test bare-metal provisioning workflows in a virtualized environment.

## Troubleshooting

### Sushy service won't start
```bash
# Check logs
sudo journalctl -u sushy-emulator -n 50

# Verify libvirt is running
sudo systemctl status libvirtd

# Test config
sudo sushy-emulator --config /etc/sushy/sushy-emulator.conf
```

### Cannot access Redfish API
```bash
# Check if service is listening
sudo ss -tlnp | grep 8000

# Check firewall
sudo firewall-cmd --list-ports

# Add port if missing
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --reload

# Test locally
curl http://localhost:8000/redfish/v1/
```

### Virtual media not working
```bash
# Check vmedia directory permissions
ls -la /var/lib/sushy/vmedia/

# Verify ISO file exists
sudo ls -lh /var/lib/sushy/vmedia/

# Check SELinux (if enabled)
sudo setenforce 0  # Temporarily disable for testing
```

### VM UUID not found
```bash
# List all VMs and UUIDs
sudo virsh list --all --uuid --name

# Get specific VM UUID
sudo virsh domuuid <vm-name>
```

## Security Considerations

### Production Deployment
The default configuration uses HTTP without authentication. For production:

1. **Enable SSL/TLS**:
   ```python
   SUSHY_EMULATOR_SSL_CERT = '/path/to/cert.pem'
   SUSHY_EMULATOR_SSL_KEY = '/path/to/key.pem'
   ```

2. **Add Authentication**: Use a reverse proxy (nginx/Apache) with authentication

3. **Restrict Access**: Update security group to limit source IPs

4. **Use Firewall Rules**: 
   ```bash
   sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" port port="8000" protocol="tcp" accept'
   sudo firewall-cmd --reload
   ```

## Additional Resources

- [Sushy-tools Documentation](https://docs.openstack.org/sushy-tools/latest/)
- [Redfish API Specification](https://www.dmtf.org/standards/redfish)
- [OpenStack Ironic](https://docs.openstack.org/ironic/latest/)
- [Virtual Media Redfish Schema](https://redfish.dmtf.org/schemas/VirtualMedia.json)
