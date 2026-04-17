# KVM Nested Virtualization Fix

## Problem
OCP master VMs running on EC2 instance were pausing with KVM hardware error `0x80000021` (invalid VMCS). This error occurs when nested guests attempt to use VMX (Intel VT-x) virtualization features that aren't properly supported in the nested virtualization environment.

## Root Cause
The EC2 instance (L1 hypervisor) had nested virtualization enabled in the KVM module (`nested=Y`), which exposed VMX capability to the OCP master VMs (L2 guests). When RHCOS or processes inside the masters attempted to use VMX features, it triggered KVM hardware errors because true nested virtualization (L3) isn't reliably supported.

## Solution (Two-Layer Defense)

### Layer 1: Disable Nested Virt at EC2 Instance (L1 Hypervisor)
**Primary fix** - Prevents OCP masters from seeing VMX capability at all.

**Configuration:**
- KVM module parameter: `nested=0`
- Location: `/etc/modprobe.d/kvm-nested.conf`
- Effect: OCP master VMs do not see VMX/SVM CPU flags

**Verification:**
```bash
cat /sys/module/kvm_intel/parameters/nested
# Should show: N
```

**Applied in:**
- `playbook.yml` lines 991-1013 (during initial EC2 setup)
- `disable-nested-virt-ec2.yml` (standalone fix playbook)

### Layer 2: Explicit VMX Disable in VM CPU Config
**Belt-and-suspenders** - Even if nested were enabled, VMs explicitly have VMX disabled.

**CPU Configuration:**
```xml
<cpu mode="custom" match="exact" check="none">
  <model fallback="allow">Skylake-Server-IBRS</model>
  <feature policy="disable" name="vmx"/>
</cpu>
```

**Applied to:**
- OCP master VMs (3 nodes)
- Worker VMs (scale-up)

**Files updated:**
- `roles/openshift_install/tasks/main.yml` lines 279-398 (master VM creation + CPU fix)
- `roles/scale_workers/tasks/scale_up.yml` lines 17-53 (worker VM creation + CPU fix)
- `fix-ocp-masters-cpu-final.yml` (standalone fix for existing VMs)

## CPU Model Choice: Skylake-Server-IBRS

**Why Skylake-Server-IBRS?**
- Modern enough for RHCOS (RHEL 9 CoreOS) requirements
- Widely supported features without nested virtualization
- IBRS variant includes security mitigations
- Stable in nested environments

**Rejected alternatives:**
- `host-passthrough` → Auto-expands to GraniteRapids with vmx=on
- `host-model` → Same auto-expansion issue
- `qemu64` → Too basic, caused kernel panic
- `Nehalem-IBRS` → Missing features, VMs paused
- `Westmere-IBRS` → Missing features, VMs paused

## Implementation Details

### Initial Setup (playbook.yml)
1. Load KVM module
2. Unload kvm_intel module
3. Reload kvm_intel with `nested=0`
4. Create `/etc/modprobe.d/kvm-nested.conf` for persistence
5. Verify nested=N

### VM Creation (openshift_install role)
1. Create VMs with `--cpu Skylake-Server-IBRS`
2. Export VM XML to temp file
3. Remove auto-generated CPU section
4. Inject custom CPU config with VMX disabled
5. Apply via `virsh define`
6. Verify in dumped XML

### Worker Scale-Up (scale_workers role)
Same process as master VM creation, applied to each new worker node.

## Verification Steps

### Check EC2 Instance (L1)
```bash
# Should show: N
cat /sys/module/kvm_intel/parameters/nested

# Verify persistence
cat /etc/modprobe.d/kvm-nested.conf
```

### Check VM Config
```bash
# Should show: <feature policy='disable' name='vmx'/>
sudo virsh dumpxml ocp-master-1 | grep vmx

# Full CPU section
sudo virsh dumpxml ocp-master-1 | grep -A 5 '<cpu'
```

### Monitor Stability
```bash
# Watch for 60+ seconds
watch -n 5 'sudo virsh list | grep ocp-master'

# Check for paused state
sudo virsh list --all | grep paused
```

## Testing Results
- ✅ All 3 OCP masters stable for 60+ seconds after fix
- ✅ No KVM error 0x80000021 in logs
- ✅ VMX feature correctly disabled in VM XML
- ✅ Nested parameter shows 'N' on EC2 instance

## Files Modified

1. **playbook.yml**
   - Added KVM nested=0 configuration during setup
   - Updated status display messages

2. **roles/openshift_install/tasks/main.yml**
   - Changed CPU from host-passthrough to Skylake-Server-IBRS
   - Added post-creation CPU fix tasks for all 3 masters
   - Updated VM specs display

3. **roles/scale_workers/tasks/scale_up.yml**
   - Changed CPU from host-passthrough to Skylake-Server-IBRS
   - Added post-creation CPU fix task for workers

4. **New standalone playbooks:**
   - `disable-nested-virt-ec2.yml` - Fix running EC2 instance
   - `fix-ocp-masters-cpu-final.yml` - Fix existing master VMs

## Maintenance Notes

- **Reboot persistence:** KVM nested=0 persists via `/etc/modprobe.d/kvm-nested.conf`
- **New VMs:** Automatically get correct CPU config via updated playbooks
- **Existing VMs:** Use `fix-ocp-masters-cpu-final.yml` to apply fix
- **Sushy-tools:** No impact, continues to work with nested=0

## References

- KVM error 0x80000021: Invalid VMCS (Virtual Machine Control Structure)
- Intel VMX: Virtual Machine Extensions for hardware virtualization
- Nested virtualization: L1 (EC2) → L2 (OCP masters) → L3 (not supported)
- RHCOS requirements: Modern x86_64 CPU with typical server features

## Date Applied
2026-04-17

## Status
✅ Fixed and verified stable
