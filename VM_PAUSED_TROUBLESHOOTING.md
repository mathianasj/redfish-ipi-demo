# Troubleshooting Paused VMs

## ⚠️ Important: Check the Real Cause First!

**Don't assume it's memory!** The most common cause of VM pausing on nested virtualization is actually **KVM hardware errors**, not memory issues.

### Quick Diagnosis

```bash
# Check QEMU logs for the actual error
sudo tail -50 /var/log/libvirt/qemu/ocp-master-2.log | grep -i "kvm\|error"

# Check libvirt logs
sudo journalctl -u libvirtd -n 50 | grep -i "ocp-master-2\|error"

# Check memory (to rule it out)
free -h

# Check for OOM events (to rule it out)
sudo journalctl -k | grep -i oom
```

### Most Likely: KVM Hardware Error

If you see `KVM: entry failed, hardware error 0x80000021`, this is **NOT a memory issue**.

**Quick Fix:**
```bash
# Force reset the VM (resume won't work)
sudo virsh destroy ocp-master-2

# Start it fresh
sudo virsh start ocp-master-2

# If it happens again, see "KVM Hardware Error" section below
```

## Common Causes

### 1. KVM Hardware Error (Most Common on Nested Virt)

**Symptoms:**
- VM pauses during operation
- QEMU log shows: `KVM: entry failed, hardware error 0x80000021`
- Libvirt log shows: `unable to execute QEMU command 'cont': Resetting the Virtual Machine is required`
- Host has plenty of free memory

**Fix:**
See the dedicated section "KVM Hardware Error Fix" below.

### 2. Out of Memory (Less Common)

## KVM Hardware Error Fix

### Understanding the Error

**Error Code:** `KVM: entry failed, hardware error 0x80000021`

**What it means:** The guest VM entered a CPU state that nested KVM cannot handle. This is a limitation of nested virtualization, not a bug in your setup.

**Why it happens:**
- RHCOS (Red Hat CoreOS) uses certain CPU instructions
- Nested virtualization has limitations on what CPU states it can emulate
- The guest OS enters "big real mode" or other states incompatible with nested VT

### Solution: Force Reset and CPU Configuration

**Automated Fix:**
```bash
ansible-playbook fix-kvm-hardware-error.yml
```

**Manual Fix:**
```bash
# 1. Force stop the paused VM (resume won't work!)
sudo virsh destroy ocp-master-2

# 2. Update CPU configuration for better compatibility
sudo virt-xml ocp-master-2 --edit --cpu host-passthrough,cache.mode=passthrough

# 3. Configure auto-restart on crashes
sudo virt-xml ocp-master-2 --edit --events on_crash=restart

# 4. Start the VM
sudo virsh start ocp-master-2

# 5. Monitor to ensure it stays running
watch 'sudo virsh list --all'
```

### If It Keeps Pausing

If the VM continues to pause with KVM errors:

**Option 1: Try different CPU model**
```bash
sudo virsh destroy ocp-master-2
sudo virt-xml ocp-master-2 --edit --cpu host-model
sudo virsh start ocp-master-2
```

**Option 2: Disable problematic CPU features**
```bash
sudo virsh destroy ocp-master-2
sudo virt-xml ocp-master-2 --edit --cpu host-passthrough
sudo virt-xml ocp-master-2 --edit --cpu clearxml,+feature policy=disable,name=vmx
sudo virsh start ocp-master-2
```

**Option 3: Simplify CPU topology**
```bash
sudo virsh destroy ocp-master-2
sudo virt-xml ocp-master-2 --edit --vcpus 8,sockets=1,cores=8,threads=1
sudo virsh start ocp-master-2
```

### During OpenShift Installation

If the VM pauses during OpenShift installation:

1. **Immediately resume it:**
   ```bash
   sudo virsh destroy ocp-master-2
   sudo virsh start ocp-master-2
   ```

2. **The installation should continue** - OpenShift is resilient to temporary node issues

3. **Monitor the installation:**
   ```bash
   # Watch VMs
   watch 'sudo virsh list --all'
   
   # Watch installation progress
   tail -f ~/openshift-install/.openshift_install.log
   ```

4. **If it pauses again repeatedly:**
   - This indicates fundamental incompatibility
   - Consider reducing to 2 master nodes or SNO (Single Node OpenShift)
   - May need to use different instance type or run on bare metal

### 1. Out of Memory (Less Common on m8i.16xlarge)

**Symptoms:**
- VM pauses during boot or operation
- Host memory is critically low
- OOM killer events in logs

**Check:**
```bash
# Check host memory
free -h

# Check for OOM events
sudo journalctl -k | grep -i "out of memory\|oom"

# Check total VM memory allocation
sudo virsh list --all --name | while read vm; do
  if [ ! -z "$vm" ]; then
    echo -n "$vm: "
    sudo virsh dominfo "$vm" | grep "Max memory"
  fi
done
```

**Fix:**
Reduce VM memory allocation. Each master VM is allocated 32GB by default. On m8i.16xlarge (128GB RAM), running 3x VMs (96GB) plus host OS leaves little margin.

**Option A: Reduce memory per VM (recommended)**
```bash
# Stop the VM
sudo virsh destroy ocp-master-2

# Reduce memory to 24GB
sudo virt-xml ocp-master-2 --edit --memory 24576,maxmemory=24576

# Start the VM
sudo virsh start ocp-master-2
```

Do this for all 3 master VMs:
```bash
for vm in ocp-master-1 ocp-master-2 ocp-master-3; do
  sudo virsh destroy $vm
  sudo virt-xml $vm --edit --memory 24576,maxmemory=24576
  sudo virsh start $vm
  sleep 5
done
```

**Option B: Reduce to 2 master nodes**

OpenShift can run with 3 compact nodes (masters that also run workloads), but you can also run with just 1 for SNO (Single Node OpenShift) if needed.

### 2. Disk Space Full

**Check:**
```bash
# Check disk space
df -h

# Check VM disk usage
sudo virsh pool-list --all
sudo virsh vol-list default
```

**Fix:**
```bash
# Clean up space
sudo dnf clean all
sudo journalctl --vacuum-time=1d

# Remove old VM images if any
sudo virsh vol-delete --pool default <old-vol-name>
```

### 3. I/O Errors

**Check:**
```bash
# Check for I/O errors
sudo journalctl -k | grep -i "i/o error\|disk error"

# Check disk health
sudo smartctl -a /dev/nvme0n1  # or appropriate disk
```

### 4. CPU Oversubscription

**Check:**
```bash
# Check CPU usage
top
htop  # if installed

# Check VM vCPU allocation
sudo virsh vcpucount ocp-master-2
```

**Fix:**
Reduce vCPUs if needed:
```bash
sudo virsh destroy ocp-master-2
sudo virt-xml ocp-master-2 --edit --vcpus 6,maxvcpus=6
sudo virsh start ocp-master-2
```

## Automated Troubleshooting

Run the troubleshooting playbook:

```bash
ansible-playbook troubleshoot-paused-vm.yml
```

This will:
- Check VM states
- Review libvirt and QEMU logs
- Check host resources (memory, disk, CPU)
- Look for OOM events
- Check for I/O errors
- Attempt automatic fixes

## Preventing VM Pauses

### 1. Configure VM to Restart on Errors

Instead of pausing, configure VMs to restart:

```bash
sudo virsh destroy ocp-master-2
sudo virt-xml ocp-master-2 --edit --events on_crash=restart,on_reboot=restart
sudo virsh start ocp-master-2
```

### 2. Enable Memory Ballooning

Allow dynamic memory adjustment:

```bash
sudo virsh destroy ocp-master-2
sudo virt-xml ocp-master-2 --edit --memory 24576,currentMemory=20480,maxmemory=24576
sudo virsh start ocp-master-2
```

### 3. Set Resource Limits

Configure host-level limits to prevent OOM:

Edit `/etc/security/limits.conf`:
```
* soft memlock unlimited
* hard memlock unlimited
```

### 4. Adjust Kernel Parameters

For better memory management:

```bash
# Reduce swappiness
sudo sysctl vm.swappiness=10

# Make permanent
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

## Monitoring VM Health

### Continuous Monitoring

```bash
# Watch VM states
watch 'sudo virsh list --all'

# Monitor memory
watch 'free -h'

# Monitor specific VM
watch 'sudo virsh dominfo ocp-master-2'
```

### Check Logs in Real-Time

```bash
# Libvirt logs
sudo journalctl -u libvirtd -f

# QEMU logs for specific VM
sudo tail -f /var/log/libvirt/qemu/ocp-master-2.log

# Kernel messages
sudo journalctl -k -f
```

## Recommended VM Configuration for m8i.16xlarge

The m8i.16xlarge has:
- 64 vCPUs (32 physical cores with hyperthreading)
- 128 GB RAM

**Default allocation per master VM:**
- **Memory:** 32 GB (OpenShift recommended minimum)
- **vCPUs:** 8
- **Disk:** 120 GB

This provides:
- 3 VMs: 96 GB total
- 32 GB free for host OS
- Sufficient for production-like environments

**Note:** The default 32GB allocation is correct and appropriate. Only reduce if you're running additional workloads on the host.

## Recovery Procedures

### If VM Won't Resume

```bash
# Force stop
sudo virsh destroy ocp-master-2

# Start fresh
sudo virsh start ocp-master-2

# Monitor
sudo virsh console ocp-master-2
# Press Ctrl+] to exit console
```

### If VM Keeps Pausing

```bash
# Check what's consuming memory
sudo ps aux --sort=-%mem | head -20

# Check VM actual memory usage
sudo virsh dommemstat ocp-master-2

# Consider reducing memory permanently
sudo virsh destroy ocp-master-2
sudo virt-xml ocp-master-2 --edit --memory 20480,maxmemory=20480
sudo virsh start ocp-master-2
```

### If During OpenShift Installation

The OpenShift installer expects VMs to be running. If they keep pausing:

1. **Reduce VM memory before installation:**
   ```bash
   for vm in ocp-master-1 ocp-master-2 ocp-master-3; do
     sudo virsh destroy $vm
     sudo virt-xml $vm --edit --memory 24576,maxmemory=24576
     sudo virsh start $vm
   done
   ```

2. **Monitor during installation:**
   ```bash
   # In one terminal
   watch 'sudo virsh list --all'
   
   # In another terminal
   watch 'free -h'
   ```

3. **If VM pauses during install:**
   ```bash
   # Resume immediately
   sudo virsh resume ocp-master-2
   
   # Installation should continue
   ```

## Advanced Diagnostics

### Memory Pressure

```bash
# Check memory pressure
cat /proc/pressure/memory

# Check for swapping
vmstat 1 10

# Check huge pages
cat /proc/meminfo | grep -i huge
```

### Detailed VM Memory

```bash
# Memory statistics
sudo virsh dommemstat ocp-master-2

# Memory balloon info
sudo virsh domstats ocp-master-2 --balloon

# Memory details
sudo virsh dominfo ocp-master-2 | grep -i memory
```

### QEMU Process Info

```bash
# Find QEMU process
ps aux | grep qemu | grep ocp-master-2

# Check process memory
sudo pmap -x $(pgrep -f "qemu.*ocp-master-2") | tail -1
```

## Quick Reference Commands

```bash
# Resume all paused VMs
for vm in $(sudo virsh list --all --name); do
  if [ "$(sudo virsh domstate $vm)" = "paused" ]; then
    echo "Resuming $vm..."
    sudo virsh resume $vm
  fi
done

# Check all VM states
sudo virsh list --all

# Get memory stats for all VMs
for vm in $(sudo virsh list --name); do
  echo "=== $vm ==="
  sudo virsh dommemstat $vm 2>/dev/null || echo "Not running"
done

# Monitor for pauses
while true; do
  date
  sudo virsh list --all | grep paused && echo "PAUSED VM DETECTED!"
  sleep 5
done
```

## Prevention in Future Deployments

When creating VMs in the future, use these settings:

```bash
virt-install \
  --name ocp-master-1 \
  --memory 24576 \        # Reduced from 32768
  --vcpus 8 \
  --disk size=120,format=qcow2,bus=virtio \
  --network bridge=virbr0,mac=... \
  --boot uefi,network \
  --graphics vnc \
  --noautoconsole \
  --os-variant rhel9.0 \
  --noreboot \
  --events on_crash=restart  # Auto-restart instead of pause
```
