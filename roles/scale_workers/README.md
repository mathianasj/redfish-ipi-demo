---
# Scale Workers Role

Dynamically scale OpenShift worker nodes up or down by managing VMs and BareMetalHost resources.

## Overview

This role provides intelligent worker node scaling for OpenShift clusters running on nested virtualization. It:

- **Scales Up**: Creates VMs and registers them as BareMetalHosts in OpenShift
- **Scales Down**: Safely deprovisions BareMetalHosts, waits for completion, then removes VMs
- **Auto-detects**: Reads cluster name and base domain from the running OpenShift cluster
- **State Tracking**: Maintains a state file to track worker configuration
- **Idempotent**: Can be run multiple times safely

## Requirements

- OpenShift cluster installed and running
- `oc` CLI configured with cluster access
- Kubeconfig at `/home/ec2-user/.kube/config` or `~/.kube/config`
- Sushy-tools Redfish BMC emulator running
- Libvirt/KVM configured

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `worker_count` | 0 | Desired number of worker nodes |
| `worker_vm_memory` | 16384 | Memory per worker in MB (16 GB) |
| `worker_vm_vcpus` | 4 | vCPUs per worker |
| `worker_vm_disk_size` | 120 | Disk size per worker in GB |
| `worker_name_prefix` | ocp-worker | Prefix for worker VM names |
| `worker_network_bridge` | virbr0 | Network bridge for workers |
| `worker_state_file` | /home/ec2-user/openshift-workers-state.json | State tracking file |
| `deprovision_timeout` | 600 | Timeout for deprovisioning (seconds) |
| `deprovision_poll_interval` | 10 | Polling interval for deprovision status |

## Usage

### Basic Usage

```bash
# Add 2 workers
ansible-playbook scale-workers.yml -e worker_count=2

# Add 3 workers (scale up from 2 to 3)
ansible-playbook scale-workers.yml -e worker_count=3

# Remove workers (scale down from 3 to 1)
ansible-playbook scale-workers.yml -e worker_count=1

# Remove all workers
ansible-playbook scale-workers.yml -e worker_count=0
```

### Custom Worker Specifications

```bash
# Add 2 workers with custom specs
ansible-playbook scale-workers.yml \
  -e worker_count=2 \
  -e worker_vm_memory=32768 \
  -e worker_vm_vcpus=8 \
  -e worker_vm_disk_size=200
```

### Check Current State

```bash
# Just show current worker count (don't change anything)
ansible-playbook scale-workers.yml

# Or check the state file directly
ssh ec2-user@<EC2_IP>
cat ~/openshift-workers-state.json
```

## How It Works

### Scale Up Flow

1. **Detect Cluster Info**: Reads cluster name and domain from OpenShift
2. **Calculate Workers to Add**: Compares current vs desired count
3. **For Each New Worker**:
   - Generate unique worker name (e.g., `ocp-worker-1`)
   - Generate random MAC address
   - Create VM with `virt-install`
   - Get VM UUID from libvirt
   - Create BareMetalHost manifest with:
     - Worker name
     - MAC address
     - BMC address: `redfish-virtualmedia://<ec2-ip>:8000/redfish/v1/Systems/<uuid>`
   - Apply BareMetalHost to cluster
   - Wait for discovery (state: available)
   - Track worker in state file

4. **OpenShift Auto-Provisioning**: Once BareMetalHost is available, OpenShift's machine-api will automatically provision it as a worker node

### Scale Down Flow

1. **Identify Workers to Remove**: Takes workers from the end of the list
2. **For Each Worker to Remove**:
   - Check current BareMetalHost state
   - If provisioned, set `spec.online: false` to deprovision
   - **Wait for deprovisioning to complete** (critical!)
   - Poll every 10 seconds (configurable)
   - Only proceed when state is `available` or `ready`
   - Delete BareMetalHost resource from cluster
   - Destroy VM in libvirt
   - Undefine VM
   - Remove disk image
   - Remove from state tracking

3. **Safety**: Will not remove VM until BareMetalHost is safely deprovisioned

## State File

The role maintains a state file at `/home/ec2-user/openshift-workers-state.json`:

```json
{
  "last_updated": "2026-04-16T15:30:00Z",
  "cluster_name": "ocp",
  "base_domain": "example.com",
  "worker_count": 2,
  "workers": [
    {
      "name": "ocp-worker-1",
      "number": 1,
      "uuid": "abc-123-def-456",
      "mac": "52:54:00:12:34:56",
      "bmc_address": "redfish-virtualmedia://10.0.3.178:8000/redfish/v1/Systems/abc-123-def-456",
      "created": "2026-04-16T14:00:00Z",
      "memory_mb": 16384,
      "vcpus": 4,
      "disk_gb": 120
    },
    {
      "name": "ocp-worker-2",
      "number": 2,
      "uuid": "xyz-789-uvw-012",
      "mac": "52:54:00:ab:cd:ef",
      "bmc_address": "redfish-virtualmedia://10.0.3.178:8000/redfish/v1/Systems/xyz-789-uvw-012",
      "created": "2026-04-16T15:00:00Z",
      "memory_mb": 16384,
      "vcpus": 4,
      "disk_gb": 120
    }
  ]
}
```

## Monitoring

### Watch Worker Provisioning

```bash
# Watch BareMetalHosts
watch 'oc get baremetalhosts -n openshift-machine-api'

# Watch nodes
watch 'oc get nodes'

# Watch VMs
watch 'sudo virsh list --all | grep worker'
```

### Check BareMetalHost Status

```bash
# Get all BareMetalHosts
oc get baremetalhosts -n openshift-machine-api

# Get details for specific worker
oc describe baremetalhost ocp-worker-1 -n openshift-machine-api

# Check provisioning state
oc get baremetalhost ocp-worker-1 -n openshift-machine-api -o jsonpath='{.status.provisioning.state}'
```

### Common States

| State | Meaning |
|-------|---------|
| `registering` | Initial state, being discovered |
| `inspecting` | Hardware inspection in progress |
| `available` | Ready to be provisioned |
| `provisioning` | Being provisioned by OpenShift |
| `provisioned` | Successfully provisioned as a node |
| `deprovisioning` | Being deprovisioned |
| `ready` | Deprovisioned and ready |

## Troubleshooting

### Worker VM Created But Not Discovered

**Check BareMetalHost:**
```bash
oc get baremetalhost ocp-worker-1 -n openshift-machine-api -o yaml
```

**Common issues:**
- BMC address incorrect
- BMC credentials wrong
- Sushy-tools not running: `systemctl status sushy-emulator`
- Network connectivity to BMC

**Verify BMC access:**
```bash
curl http://<ec2-ip>:8000/redfish/v1/Systems/<vm-uuid>
```

### Worker Stuck in Provisioning

**Check logs:**
```bash
# Metal3 logs
oc logs -n openshift-machine-api -l baremetal.openshift.io/cluster-baremetal-operator=metal3-state

# Ironic logs
oc logs -n openshift-machine-api -l app=metal3-ironic
```

**Check VM console:**
```bash
sudo virsh console ocp-worker-1
# Press Ctrl+] to exit
```

### Scale Down Timeout

If deprovisioning times out:

1. **Check current state:**
   ```bash
   oc get baremetalhost ocp-worker-1 -n openshift-machine-api -o jsonpath='{.status.provisioning.state}'
   ```

2. **Force delete if stuck:**
   ```bash
   # Last resort - not recommended
   oc delete baremetalhost ocp-worker-1 -n openshift-machine-api --force --grace-period=0
   ```

3. **Manually remove VM:**
   ```bash
   sudo virsh destroy ocp-worker-1
   sudo virsh undefine ocp-worker-1 --nvram
   ```

### State File Corruption

If state file is corrupted or lost:

1. **Recreate from cluster:**
   ```bash
   # List current BareMetalHosts
   oc get baremetalhosts -n openshift-machine-api -l node-role.kubernetes.io/worker

   # List current VMs
   sudo virsh list --all | grep worker
   ```

2. **Manually rebuild state file** with correct worker information

## Resource Requirements

### Per Worker Node

- **Memory**: 16 GB (default, configurable)
- **CPU**: 4 vCPUs (default, configurable)
- **Disk**: 120 GB (default, configurable)
- **Network**: DHCP on virbr0 bridge

### Host Requirements

For `n` workers on m8i.16xlarge (247 GB RAM, 64 vCPUs):

| Workers | Total RAM Used | RAM Available | Total vCPUs |
|---------|---------------|---------------|-------------|
| 0 | 96 GB (masters) | 151 GB | 24 |
| 2 | 128 GB | 119 GB | 32 |
| 4 | 160 GB | 87 GB | 40 |
| 6 | 192 GB | 55 GB | 48 |

**Recommendation**: Max 4-6 workers on m8i.16xlarge

## Integration with Other Roles

This role works with:
- **openshift_install**: Uses same network and Redfish BMC
- **configure_dns**: Workers get DHCP IPs, DNS still works
- **openshift_install_cluster**: Adds workers after cluster installation

## Examples

### Example 1: Add Workers After Installation

```bash
# After OpenShift is installed
ansible-playbook scale-workers.yml -e worker_count=2
```

### Example 2: Scale Gradually

```bash
# Add 1 worker
ansible-playbook scale-workers.yml -e worker_count=1

# Wait for it to provision, then add another
ansible-playbook scale-workers.yml -e worker_count=2
```

### Example 3: Testing Scaling

```bash
# Add 3 workers
ansible-playbook scale-workers.yml -e worker_count=3

# Watch them provision
watch 'oc get baremetalhosts -n openshift-machine-api'

# Scale down to 1
ansible-playbook scale-workers.yml -e worker_count=1
```

### Example 4: Remove All Workers

```bash
ansible-playbook scale-workers.yml -e worker_count=0
```

## BareMetalHost Template

The role uses this template for creating BareMetalHosts:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: ocp-worker-1
  namespace: openshift-machine-api
  labels:
    node-role.kubernetes.io/worker: ""
spec:
  online: true
  bootMACAddress: 52:54:00:12:34:56
  bmc:
    address: redfish-virtualmedia://10.0.3.178:8000/redfish/v1/Systems/<uuid>
    credentialsName: ocp-worker-1-bmc-secret
    disableCertificateVerification: true
  automatedCleaningMode: disabled
```

## Safety Features

1. **Deprovisioning Wait**: Always waits for BareMetalHost to deprovision before removing VM
2. **State Tracking**: Maintains accurate state of all workers
3. **Idempotent**: Safe to run multiple times
4. **Auto-detection**: No hardcoded cluster names
5. **Graceful Timeout**: Configurable timeout for deprovisioning
6. **Warning Messages**: Warns if removing BMH in unexpected state

## Limitations

1. **DHCP Only**: Workers use DHCP (no static IPs)
2. **Sequential Removal**: Workers removed from end of list
3. **Manual MachineSet**: Does not create MachineSet (BareMetalHost only)
4. **No Auto-approval**: CSRs may need manual approval for workers

## Future Enhancements

Potential improvements:
- Auto-approve CSRs for worker nodes
- Create MachineSet in addition to BareMetalHost
- Support for different worker profiles (memory, CPU)
- Drain nodes before deprovisioning
- Parallel worker creation

## See Also

- `fix-kvm-hardware-error.yml` - Fix paused worker VMs
- `VM_PAUSED_TROUBLESHOOTING.md` - VM troubleshooting
- OpenShift bare metal documentation
