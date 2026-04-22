# virbr0 NO-CARRIER / State DOWN Issue

## Problem

OpenShift installation fails with error:
```
platform.baremetal.externalBridge: Invalid value: "virbr0": could not find interface "virbr0"
```

Checking the interface shows:
```bash
$ ip link show virbr0
virbr0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN
```

Key indicators:
- `NO-CARRIER` - No link/carrier detected
- `state DOWN` - Interface is down (not ready)

## Root Cause

**This happens when the virbr0-keepalive VM is not running.**

The virbr0 network bridge requires at least one active VM attached to it to have carrier/link.
Without an active VM, the kernel marks the interface as NO-CARRIER even though it's UP.

The virbr0-keepalive VM is a minimal VM that exists solely to keep virbr0 in an UP state.

## Diagnosis

Check if virbr0-keepalive VM is running:
```bash
sudo virsh list --all | grep virbr0-keepalive
```

Expected output (GOOD):
```
 1    virbr0-keepalive   running
```

Bad output:
```
 -    virbr0-keepalive   shut off
```

Check virbr0 interface state:
```bash
ip link show virbr0
```

Expected output (GOOD):
```
virbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP
          ^^^^^ Has carrier                        ^^^^^ Interface UP
```

Bad output (NO CARRIER):
```
virbr0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 state DOWN
          ^^^^^^^^^^ No carrier detected           ^^^^ Interface DOWN
```

## Fix

### Quick Fix - Start the VM

```bash
# Start virbr0-keepalive VM
sudo virsh start virbr0-keepalive

# Wait a few seconds for interface to come up
sleep 3

# Verify virbr0 is now UP
ip link show virbr0
# Should show: state UP (not DOWN)
```

### Ensure Autostart

Make sure the VM starts automatically on boot:

```bash
# Enable autostart
sudo virsh autostart virbr0-keepalive

# Verify autostart is enabled
sudo virsh dominfo virbr0-keepalive | grep Autostart
# Should show: Autostart:      enable
```

### If VM Won't Start

```bash
# Check VM status
sudo virsh dominfo virbr0-keepalive

# Try to start it
sudo virsh start virbr0-keepalive

# If it fails, check logs
sudo virsh dumpxml virbr0-keepalive

# If VM is broken, you may need to recreate it
# (See playbook.yml for VM creation steps)
```

## Prevention

The playbook includes pre-flight checks to ensure virbr0-keepalive is running before OpenShift installation:

**In `prepare-and-install-openshift.yml`** (lines 75-122):
```yaml
pre_tasks:
  - name: Check if virbr0-keepalive VM exists
  - name: Check if virbr0-keepalive VM is running
  - name: Start virbr0-keepalive VM if not running
  - name: Ensure virbr0-keepalive VM is set to autostart
  - name: Wait for virbr0 to come up
  - name: Verify virbr0 is UP
  - name: Fail if virbr0 is not UP
```

**In `playbook.yml`** (creates virbr0-keepalive during initial setup):
```yaml
- name: Create minimal VM to keep virbr0 network active
- name: Set dummy VM to autostart on boot
```

## Why This Happens

Linux kernel network bridges (like virbr0) go into NO-CARRIER state when they have no active ports/members:

1. **No VMs running** → No vnet interfaces attached to virbr0
2. **No vnet interfaces** → Bridge has no carrier
3. **No carrier** → Interface state = DOWN
4. **Interface DOWN** → OpenShift installer validation fails

The virbr0-keepalive VM provides a persistent vnet interface so virbr0 always has carrier.

## OpenShift Install Validation

The OpenShift installer (`openshift-install create cluster`) validates the `externalBridge` interface **before** starting installation:

```
Generating Platform Provisioning Check...
platform.baremetal.externalBridge: Invalid value: "virbr0": could not find interface "virbr0", valid interfaces are baremetal
```

The installer checks:
- ✅ Interface exists
- ✅ Interface is UP (state UP, not DOWN)
- ✅ Interface is a bridge
- ❌ FAILS if interface is DOWN or NO-CARRIER

## Related Files

- `playbook.yml` - Creates virbr0-keepalive VM (lines 1100-1150)
- `prepare-and-install-openshift.yml` - Pre-flight virbr0 checks (lines 75-122)
- `docs/troubleshooting/KVM_NESTED_VIRT_FIX.md` - Related VM issues

## Common Scenarios

### Scenario 1: Fresh EC2 Instance Boot
After EC2 instance reboot, virbr0-keepalive must start automatically:
- ✅ **GOOD**: Autostart enabled → VM starts → virbr0 UP
- ❌ **BAD**: Autostart disabled → VM stopped → virbr0 DOWN

### Scenario 2: During OpenShift Installation
If keepalive VM stops mid-installation:
- virbr0 goes DOWN → Installation fails
- Fix: Start VM, restart installation

### Scenario 3: After Cluster Destruction
After running `destroy-openshift-cluster.yml`:
- ✅ virbr0-keepalive VM is preserved (not destroyed)
- virbr0 stays UP, ready for reinstall

## Verification Commands

```bash
# Full diagnostic
echo "=== virbr0-keepalive VM Status ==="
sudo virsh list --all | grep virbr0

echo -e "\n=== virbr0 Interface Status ==="
ip link show virbr0

echo -e "\n=== Autostart Status ==="
sudo virsh dominfo virbr0-keepalive | grep Autostart

echo -e "\n=== Network Interfaces on virbr0 ==="
sudo virsh domiflist virbr0-keepalive

echo -e "\n=== default Network Status ==="
sudo virsh net-info default
```

## Summary

**Problem**: virbr0 NO-CARRIER / state DOWN  
**Cause**: virbr0-keepalive VM not running  
**Fix**: `sudo virsh start virbr0-keepalive`  
**Prevention**: Enable autostart on virbr0-keepalive VM
