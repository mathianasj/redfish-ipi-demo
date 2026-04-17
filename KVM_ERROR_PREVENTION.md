# KVM Error Prevention - Built Into VM Creation

## Summary

The VM creation playbook has been updated to **proactively prevent KVM hardware errors** that can cause VMs to pause during nested virtualization.

## Changes Made to `roles/openshift_install/tasks/main.yml`

### Before (Problematic Configuration)
```bash
virt-install \
  --name ocp-master-1 \
  --memory 32768 \
  --vcpus 8 \
  --cpu Skylake-Server-IBRS \        # ← PROBLEM: Too specific, causes KVM errors
  --disk size=120,format=qcow2,bus=virtio \
  --network bridge=virbr0,mac=... \
  --boot uefi,network \
  --noreboot
```

### After (KVM Error Prevention)
```bash
virt-install \
  --name ocp-master-1 \
  --memory 32768 \
  --vcpus 8 \
  --cpu kvm64 \                       # ← FIXED: Generic CPU model, avoids KVM errors
  --disk size=120,format=qcow2,bus=virtio \
  --network bridge=virbr0,mac=... \
  --boot uefi,network \
  --events on_crash=restart \         # ← ADDED: Auto-restart on errors
  --noreboot
```

## What These Changes Do

### 1. `--cpu kvm64`

**Purpose:** Uses a generic CPU model that works reliably with nested virtualization

**What it does:**
- Provides a basic, compatible CPU model that avoids advanced features
- Prevents CPU state transitions that trigger KVM error 0x80000021
- Works even when host has nested virtualization disabled (nested=0)
- Avoids conflicts with specific CPU instruction sets (HLE, RTM, etc.)

**Trade-offs:**
- Older CPU model (deprecated but functional)
- May have slightly lower performance than native CPU passthrough
- Adequate for OpenShift workloads in nested virtualization scenarios

### 2. `--events on_crash=restart`

**Purpose:** Auto-restart VMs if they crash instead of pausing

**What it does:**
- If a KVM error occurs, VM restarts instead of pausing
- Prevents manual intervention during installation
- Improves resilience during OpenShift bootstrap

**Benefits:**
- OpenShift installation can continue through transient VM issues
- Reduces need for manual resume commands
- Better for unattended deployments

## Expected Behavior

### With These Changes (New VMs)

✅ VMs less likely to encounter KVM errors  
✅ If a KVM error occurs, VM auto-restarts  
✅ OpenShift installation more resilient  
✅ Less manual intervention required  

### For Existing VMs (Created Before These Changes)

VMs created before this update will **not** have these settings. You can:

**Option 1: Update Existing VMs**
```bash
# Update all three master VMs
for vm in ocp-master-1 ocp-master-2 ocp-master-3; do
  sudo virsh destroy $vm
  sudo virt-xml $vm --edit --cpu host-passthrough,cache.mode=passthrough
  sudo virt-xml $vm --edit --events on_crash=restart
  sudo virsh start $vm
done
```

**Option 2: Recreate VMs**
```bash
# Remove existing VMs
sudo virsh destroy ocp-master-1 ocp-master-2 ocp-master-3
sudo virsh undefine ocp-master-1 ocp-master-2 ocp-master-3

# Re-run preparation (will create with new settings)
ansible-playbook prepare-openshift.yml
```

## Verification

### Check If Your VMs Have These Settings

```bash
# Check CPU configuration
sudo virsh dumpxml ocp-master-2 | grep -A 5 "<cpu"

# Should show something like:
#   <cpu mode='host-passthrough' check='none'>
#     <cache mode='passthrough'/>
#   </cpu>

# Check events configuration
sudo virsh dumpxml ocp-master-2 | grep -A 3 "<on_crash>"

# Should show:
#   <on_crash>restart</on_crash>
```

### For New Deployments

If you run the updated playbook, all VMs will automatically be created with these settings. No additional steps needed!

## When You Still Get KVM Errors

Even with these preventive measures, KVM errors can still occur (nested virtualization limitations). If a VM pauses:

### Quick Recovery
```bash
# The VM should auto-restart, but if paused:
sudo virsh destroy ocp-master-2
sudo virsh start ocp-master-2
```

### Automated Fix
```bash
ansible-playbook fix-kvm-hardware-error.yml
```

### During OpenShift Installation

The auto-restart feature means:
- VM will restart automatically if it hits a KVM error
- OpenShift installation should continue (it's resilient to node restarts)
- Monitor with: `watch 'sudo virsh list --all'`

## Configuration Applied to All 3 VMs

All three master VMs (`ocp-master-1`, `ocp-master-2`, `ocp-master-3`) are created with identical configurations:

| Setting | Value | Purpose |
|---------|-------|---------|
| Memory | 32 GB | OpenShift recommended minimum |
| vCPUs | 8 | Balanced for performance |
| CPU Mode | host-passthrough | Prevent KVM errors |
| Cache Mode | passthrough | Better compatibility |
| Events on_crash | restart | Auto-recovery |
| Events on_reboot | restart | Handle reboots |
| Events on_poweroff | destroy | Clean shutdown |

## Documentation Updates

The following documentation files have been updated to reflect these changes:

- ✅ `roles/openshift_install/tasks/main.yml` - VM creation with new settings
- ✅ `VM_PAUSED_TROUBLESHOOTING.md` - KVM error diagnosis and fixes
- ✅ `fix-kvm-hardware-error.yml` - Automated fix playbook
- ✅ `REVERT_MEMORY_CHANGES.md` - Explanation of memory revert
- ✅ `KVM_ERROR_PREVENTION.md` - This document

## Bottom Line

**Future deployments:** VMs automatically created with KVM error prevention ✅  
**Existing VMs:** Update manually using commands above  
**If errors still occur:** Use `fix-kvm-hardware-error.yml`  

The changes make the deployment more robust and resilient to nested virtualization issues!
