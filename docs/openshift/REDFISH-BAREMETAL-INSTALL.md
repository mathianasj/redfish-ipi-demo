# OpenShift Baremetal IPI Installation with Redfish

This guide explains how OpenShift Installer Provisioned Infrastructure (IPI) works with Redfish for baremetal installations, and how to manually create an install-config.yaml for real-world baremetal environments.

## Table of Contents

- [Understanding Redfish and OpenShift IPI](#understanding-redfish-and-openshift-ipi)
- [Prerequisites](#prerequisites)
- [Discovering Redfish Endpoints](#discovering-redfish-endpoints)
- [Testing Redfish Connectivity](#testing-redfish-connectivity)
- [Creating install-config.yaml Manually](#creating-install-configyaml-manually)
- [How OpenShift Uses Redfish](#how-openshift-uses-redfish)
- [Real World Considerations](#real-world-considerations)
- [Troubleshooting](#troubleshooting)

## Understanding Redfish and OpenShift IPI

### What is Redfish?

Redfish is an industry-standard RESTful API for managing servers, developed by the DMTF (Distributed Management Task Force). It replaces older protocols like IPMI and provides:

- **RESTful API**: Uses HTTPS and JSON
- **Out-of-band management**: Control servers independently of OS
- **Power management**: Power on/off, reboot servers
- **Virtual media**: Mount ISOs remotely
- **Monitoring**: Temperature, fans, power consumption
- **Inventory**: Hardware details, firmware versions

### What is OpenShift IPI?

**Installer Provisioned Infrastructure (IPI)** means the OpenShift installer manages the entire deployment:

1. **Provisions infrastructure**: Powers on servers, mounts ISOs
2. **Installs OS**: Boots RHCOS (Red Hat CoreOS) via virtual media
3. **Configures cluster**: Sets up control plane and workers
4. **Manages lifecycle**: Handles node scaling, updates

The installer acts as the "infrastructure administrator" using Redfish BMC APIs.

### Common BMC Implementations

Different server vendors implement Redfish in their BMCs:

| Vendor | BMC Name | Redfish Endpoint Example |
|--------|----------|--------------------------|
| Dell | iDRAC | `https://idrac-ip/redfish/v1/` |
| HPE | iLO | `https://ilo-ip/redfish/v1/` |
| Lenovo | XClarity | `https://xcc-ip/redfish/v1/` |
| Cisco | CIMC | `https://cimc-ip/redfish/v1/` |
| Supermicro | BMC | `https://bmc-ip/redfish/v1/` |

## Prerequisites

Before creating your install-config.yaml, gather this information:

### Network Information

- **Machine Network CIDR**: Network where servers are located (e.g., `10.0.10.0/24`)
- **Gateway**: Default gateway for the network
- **DNS Servers**: DNS server IPs
- **API VIP**: Virtual IP for API server (e.g., `10.0.10.5`)
- **Ingress VIP**: Virtual IP for router/ingress (e.g., `10.0.10.6`)

### For Each Server

- **BMC IP Address**: Out-of-band management IP
- **BMC Username/Password**: Credentials for Redfish API
- **Boot MAC Address**: MAC address of the primary NIC (used to identify the correct network interface)
- **System UUID**: Redfish system identifier
- **Boot Device**: Disk to install to (e.g., `/dev/sda`)

**Note**: When using `redfish-virtualmedia://` with `provisioningNetwork: Disabled`, PXE is NOT used. The MAC address identifies which network interface should receive the IP configuration, but boot happens via virtual media (ISO mounting).

### OpenShift Requirements

- **Pull Secret**: From https://console.redhat.com/openshift/install/pull-secret
- **SSH Public Key**: For core user access
- **Cluster Name**: e.g., `ocp`
- **Base Domain**: e.g., `example.com`

## Discovering Redfish Endpoints

### Step 1: Access BMC Web Interface

Most BMCs have a web interface for initial setup:

```
https://<bmc-ip>
```

Log in with default credentials (consult vendor documentation) and:
- Enable Redfish API (usually enabled by default)
- Set a strong password
- Note the Redfish endpoint URL

### Step 2: Test Redfish Root

```bash
# Test basic Redfish access
curl -k -u admin:password https://<bmc-ip>/redfish/v1/

# Pretty print with jq
curl -k -u admin:password https://<bmc-ip>/redfish/v1/ | jq .
```

**Example Response:**
```json
{
  "@odata.context": "/redfish/v1/$metadata#ServiceRoot.ServiceRoot",
  "@odata.id": "/redfish/v1/",
  "@odata.type": "#ServiceRoot.v1_5_0.ServiceRoot",
  "Id": "RootService",
  "Name": "Root Service",
  "RedfishVersion": "1.6.0",
  "UUID": "92384634-2938-2342-1123-123456789012",
  "Systems": {
    "@odata.id": "/redfish/v1/Systems"
  },
  "Chassis": {
    "@odata.id": "/redfish/v1/Chassis"
  },
  "Managers": {
    "@odata.id": "/redfish/v1/Managers"
  }
}
```

### Step 3: Discover Systems

List all compute systems managed by this BMC:

```bash
curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems | jq .
```

**Example Response:**
```json
{
  "@odata.context": "/redfish/v1/$metadata#ComputerSystemCollection.ComputerSystemCollection",
  "@odata.id": "/redfish/v1/Systems",
  "@odata.type": "#ComputerSystemCollection.ComputerSystemCollection",
  "Name": "Computer System Collection",
  "Members": [
    {
      "@odata.id": "/redfish/v1/Systems/System.Embedded.1"
    }
  ],
  "Members@odata.count": 1
}
```

### Step 4: Get System Details

Get details about a specific system:

```bash
curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1 | jq .
```

**Important fields to note:**
- `UUID`: System unique identifier (needed for install-config.yaml)
- `PowerState`: Current power state
- `Boot`: Boot configuration
- `EthernetInterfaces`: Network interfaces

**Find the UUID:**
```bash
curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1 | jq -r '.UUID'
```

### Step 5: Get Network Interfaces

Find the MAC address of the primary boot interface:

```bash
# List network interfaces
curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1/EthernetInterfaces | jq .

# Get specific interface details
curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1/EthernetInterfaces/NIC.Embedded.1 | jq .
```

**Note the MAC address:**
```json
{
  "MACAddress": "d4:ae:52:a1:b2:c3"
}
```

## Testing Redfish Connectivity

Before using in install-config.yaml, test that Redfish virtual media and power management work:

### Test 1: Check Virtual Media Support

```bash
# Check if virtual media is supported
curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1/VirtualMedia | jq .
```

**Should show virtual media endpoints:**
```json
{
  "Members": [
    {
      "@odata.id": "/redfish/v1/Systems/System.Embedded.1/VirtualMedia/CD"
    },
    {
      "@odata.id": "/redfish/v1/Systems/System.Embedded.1/VirtualMedia/RemovableDisk"
    }
  ]
}
```

### Test 2: Power State

```bash
# Get current power state
curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1 | jq '.PowerState'

# Should return: "On" or "Off"
```

### Test 3: Power Management (Optional)

**Warning**: This will power off/on the server!

```bash
# Power off
curl -k -u admin:password -X POST \
  https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "ForceOff"}'

# Power on
curl -k -u admin:password -X POST \
  https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "On"}'
```

### Test 4: Virtual Media Mount (Optional)

Test mounting an ISO:

```bash
# Insert virtual media
curl -k -u admin:password -X POST \
  https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1/VirtualMedia/CD/Actions/VirtualMedia.InsertMedia \
  -H "Content-Type: application/json" \
  -d '{
    "Image": "http://your-web-server/test.iso",
    "Inserted": true,
    "WriteProtected": true
  }'

# Check if mounted
curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1/VirtualMedia/CD | jq '.Inserted'

# Eject virtual media
curl -k -u admin:password -X POST \
  https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1/VirtualMedia/CD/Actions/VirtualMedia.EjectMedia
```

## Creating install-config.yaml Manually

### Step 1: Create Base Configuration

Start with a basic template:

```yaml
apiVersion: v1
baseDomain: example.com
metadata:
  name: ocp
networking:
  networkType: OVNKubernetes
  machineNetwork:
  - cidr: 10.0.10.0/24
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 3
  platform:
    baremetal: {}
platform:
  baremetal:
    provisioningNetwork: Disabled
    apiVIPs:
    - 10.0.10.5
    ingressVIPs:
    - 10.0.10.6
    hosts: []
pullSecret: 'PLACEHOLDER'
sshKey: 'PLACEHOLDER'
```

### Step 2: Add Pull Secret

Replace `PLACEHOLDER` with your actual pull secret from https://console.redhat.com/openshift/install/pull-secret

```yaml
pullSecret: '{"auths":{"cloud.openshift.com":{"auth":"..."},"quay.io":{"auth":"..."},...}}'
```

### Step 3: Add SSH Key

```bash
cat ~/.ssh/id_rsa.pub
```

Replace `PLACEHOLDER`:

```yaml
sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC...'
```

### Step 4: Add Master Hosts

For each master node, add a host entry with Redfish details:

```yaml
platform:
  baremetal:
    provisioningNetwork: Disabled
    apiVIPs:
    - 10.0.10.5
    ingressVIPs:
    - 10.0.10.6
    hosts:
    - name: master-1
      role: master
      bmc:
        address: redfish-virtualmedia://10.0.10.101/redfish/v1/Systems/System.Embedded.1
        username: admin
        password: bmcpassword
        disableCertificateVerification: true
      bootMACAddress: "d4:ae:52:a1:b2:c3"
      rootDeviceHints:
        deviceName: "/dev/sda"
    - name: master-2
      role: master
      bmc:
        address: redfish-virtualmedia://10.0.10.102/redfish/v1/Systems/System.Embedded.1
        username: admin
        password: bmcpassword
        disableCertificateVerification: true
      bootMACAddress: "d4:ae:52:d4:e5:f6"
      rootDeviceHints:
        deviceName: "/dev/sda"
    - name: master-3
      role: master
      bmc:
        address: redfish-virtualmedia://10.0.10.103/redfish/v1/Systems/System.Embedded.1
        username: admin
        password: bmcpassword
        disableCertificateVerification: true
      bootMACAddress: "d4:ae:52:12:34:56"
      rootDeviceHints:
        deviceName: "/dev/sda"
```

### Step 5: Understanding Redfish Address Formats

OpenShift supports two Redfish address formats:

**Standard Redfish** (no virtual media):
```yaml
address: redfish://10.0.10.101/redfish/v1/Systems/System.Embedded.1
```

**Redfish Virtual Media** (recommended):
```yaml
address: redfish-virtualmedia://10.0.10.101/redfish/v1/Systems/System.Embedded.1
```

**Why use redfish-virtualmedia?**
- Mounts RHCOS ISO directly via Redfish
- No PXE infrastructure needed
- More reliable for initial boot
- Supported by most modern BMCs

**Building the address:**
1. Protocol: `redfish-virtualmedia://`
2. BMC IP: `10.0.10.101`
3. System path: `/redfish/v1/Systems/<UUID>`

**Finding the system path:**
```bash
# List systems
curl -k -u admin:password https://10.0.10.101/redfish/v1/Systems | jq -r '.Members[]."@odata.id"'

# Output example:
# /redfish/v1/Systems/System.Embedded.1
```

### Step 6: Root Device Hints

Tell OpenShift which disk to install to. Options:

**By device name** (simple but not portable):
```yaml
rootDeviceHints:
  deviceName: "/dev/sda"
```

**By serial number** (portable across reboots):
```yaml
rootDeviceHints:
  serialNumber: "ABC123XYZ789"
```

**By size** (e.g., smallest disk ≥ 500GB):
```yaml
rootDeviceHints:
  minSizeGigabytes: 500
```

**By WWN** (World Wide Name):
```yaml
rootDeviceHints:
  wwn: "0x5000c500a1b2c3d4"
```

**Find disk details:**
```bash
# On the server (if accessible):
lsblk -d -o NAME,SIZE,SERIAL,WWN

# Via Redfish (if BMC supports storage inventory):
curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1/Storage | jq .
```

### Step 7: Validate the Configuration

Check for common issues:

```bash
# Validate JSON in pull secret
cat install-config.yaml | grep pullSecret | sed "s/pullSecret: '//" | sed "s/'$//" | jq .

# Check YAML syntax
yamllint install-config.yaml

# Verify Redfish endpoints are reachable
for bmc in 10.0.10.101 10.0.10.102 10.0.10.103; do
  echo "Testing $bmc..."
  curl -k -m 5 https://$bmc/redfish/v1/ > /dev/null 2>&1 && echo "✓ OK" || echo "✗ FAILED"
done
```

## How OpenShift Uses Redfish

### Installation Flow

When you run `openshift-install create cluster`, here's what happens:

#### Phase 1: Bootstrap (0-20 minutes)

1. **Installer creates bootstrap VM** locally
2. **Installer powers off baremetal hosts** via Redfish:
   ```
   POST /redfish/v1/Systems/<uuid>/Actions/ComputerSystem.Reset
   {"ResetType": "ForceOff"}
   ```

3. **Installer mounts RHCOS ISO** via Redfish virtual media:
   ```
   POST /redfish/v1/Systems/<uuid>/VirtualMedia/CD/Actions/VirtualMedia.InsertMedia
   {"Image": "http://bootstrap-ip/rhcos-live.iso", "Inserted": true}
   ```

4. **Installer sets boot order** to boot from virtual media:
   ```
   PATCH /redfish/v1/Systems/<uuid>
   {"Boot": {"BootSourceOverrideTarget": "Cd", "BootSourceOverrideEnabled": "Once"}}
   ```

5. **Installer powers on hosts**:
   ```
   POST /redfish/v1/Systems/<uuid>/Actions/ComputerSystem.Reset
   {"ResetType": "On"}
   ```

6. **Hosts boot RHCOS** from ISO, get Ignition config from bootstrap
7. **RHCOS installs to disk** using root device hints
8. **Hosts reboot** and boot from local disk

#### Phase 2: Control Plane Formation (20-40 minutes)

1. **Master nodes join cluster** using bootstrap etcd
2. **Control plane becomes operational**
3. **Machine API starts** and takes over baremetal management
4. **Bootstrap VM is destroyed**

#### Phase 3: Cluster Finalization (40-60 minutes)

1. **Operators deploy** (authentication, console, monitoring, etc.)
2. **Cluster becomes ready**
3. **Installer completes**

### Day 2: Adding Worker Nodes

After installation, you can add worker nodes using BareMetalHost and MachineSet resources.

#### Step 1: Create BMC Credentials Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: worker-1-bmc-secret
  namespace: openshift-machine-api
type: Opaque
stringData:
  username: admin
  password: bmcpassword
```

```bash
oc apply -f worker-1-bmc-secret.yaml
```

#### Step 2: Create BareMetalHost Resource

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-1
  namespace: openshift-machine-api
  labels:
    infraenvs.agent-install.openshift.io: ""
spec:
  online: true
  bmc:
    address: redfish-virtualmedia://10.0.10.104/redfish/v1/Systems/System.Embedded.1
    credentialsName: worker-1-bmc-secret
    disableCertificateVerification: true
  bootMACAddress: "d4:ae:52:11:22:33"
  rootDeviceHints:
    deviceName: "/dev/sda"
```

```bash
oc apply -f worker-1-bmh.yaml
```

**Check BareMetalHost status:**
```bash
oc get baremetalhosts -n openshift-machine-api
```

The host should go through these states:
1. `registering` - BMC credentials validated
2. `inspecting` - Hardware inventory gathered
3. `available` - Ready to be provisioned

#### Step 3: Create MachineSet to Provision Workers

**Important**: Creating a BareMetalHost alone does NOT provision a worker. You must create a MachineSet that references the host.

```yaml
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  name: worker
  namespace: openshift-machine-api
  labels:
    machine.openshift.io/cluster-api-cluster: <cluster-id>
spec:
  replicas: 2
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: <cluster-id>
      machine.openshift.io/cluster-api-machineset: worker
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: <cluster-id>
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: worker
    spec:
      metadata: {}
      providerSpec:
        value:
          apiVersion: baremetal.cluster.k8s.io/v1alpha1
          kind: BareMetalMachineProviderSpec
          image:
            url: <rhcos-image-url>
            checksum: <checksum>
          userData:
            name: worker-user-data
```

**Get cluster ID:**
```bash
oc get -o jsonpath='{.status.infrastructureName}{"\n"}' infrastructure cluster
```

**Get existing MachineSet as template:**
```bash
# If you have existing worker machines from install
oc get machineset -n openshift-machine-api -o yaml

# Or get master machineset as reference
oc get machineset -n openshift-machine-api -o yaml
```

**Create MachineSet:**
```bash
oc apply -f worker-machineset.yaml
```

**Monitor provisioning:**
```bash
# Watch machines being created
oc get machines -n openshift-machine-api -w

# Watch BareMetalHosts being provisioned
oc get baremetalhosts -n openshift-machine-api -w

# Watch nodes joining cluster
oc get nodes -w
```

#### Step 4: Disable Control Plane Scheduling (Optional)

Once you have workers, you can prevent workloads from scheduling on control plane nodes:

```bash
# Mark each master as unschedulable for regular workloads
oc adm cordon master-1
oc adm cordon master-2
oc adm cordon master-3

# Or use a more surgical approach - remove worker role
oc label node master-1 node-role.kubernetes.io/worker-
oc label node master-2 node-role.kubernetes.io/worker-
oc label node master-3 node-role.kubernetes.io/worker-

# Add infra taint to prevent scheduling
oc adm taint nodes master-1 node-role.kubernetes.io/master=:NoSchedule
oc adm taint nodes master-2 node-role.kubernetes.io/master=:NoSchedule
oc adm taint nodes master-3 node-role.kubernetes.io/master=:NoSchedule
```

**Verify:**
```bash
# Check node status
oc get nodes

# Should show:
# master-1   Ready    control-plane,master   ...   (with taints)
# master-2   Ready    control-plane,master   ...   (with taints)
# master-3   Ready    control-plane,master   ...   (with taints)
# worker-1   Ready    worker                 ...
# worker-2   Ready    worker                 ...
```

**Important**: System pods (kube-apiserver, etcd, etc.) use tolerations to run on masters even with taints. User workloads will only schedule on worker nodes.

### How the Bare Metal Operator Works

The **Bare Metal Operator** uses Redfish to:
- Power on/off nodes
- Mount ISOs for provisioning
- Monitor hardware status
- Handle node lifecycle
- Provision/deprovision machines automatically

When you create a MachineSet with replicas > available BareMetalHosts:
1. Operator selects an `available` BareMetalHost
2. Powers off the host via Redfish
3. Mounts RHCOS ISO via Redfish virtual media
4. Powers on the host
5. Host boots RHCOS and joins cluster
6. BareMetalHost state changes to `provisioned`
7. Machine becomes `Running`
8. Node becomes `Ready`

## Real World Considerations

### Security

**Production BMC security:**
- Use TLS certificates (set `disableCertificateVerification: false`)
- Strong passwords (not `admin123`)
- Dedicated management network (isolated VLAN)
- Firewall rules limiting access to Redfish ports (usually 443)
- Regular firmware updates

**Certificate setup:**
```yaml
bmc:
  address: redfish-virtualmedia://bmc.example.com/redfish/v1/Systems/System.Embedded.1
  username: admin
  password: SecurePassword123!
  disableCertificateVerification: false  # Verify certs in production
```

If using self-signed certs, add to install-config.yaml:
```yaml
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  MIIDXTCCAkWgAwIBAgIJAKl...
  -----END CERTIFICATE-----
```

### Network Planning

#### Provisioning Network: Managed vs Disabled

OpenShift baremetal IPI supports two provisioning modes:

**Disabled Mode** (Recommended - used in this guide):
- `provisioningNetwork: Disabled`
- Uses Redfish virtual media to mount ISOs
- No PXE infrastructure required
- Simpler network topology
- Better for environments where virtual media is supported

**Managed Mode** (Legacy/Special cases):
- `provisioningNetwork: Managed`
- Uses PXE boot over a dedicated provisioning network
- Requires DHCP/PXE infrastructure
- More complex network setup
- Used when BMC doesn't support virtual media
- Being deprecated in favor of Disabled mode

**This guide assumes `provisioningNetwork: Disabled`** - all examples use Redfish virtual media, not PXE.

#### Typical baremetal network layout (Disabled mode):

```
┌─────────────────────────────────────────┐
│ Management Network (BMC)                │
│ VLAN 100: 10.0.100.0/24                 │
│ - BMC IPs only                          │
│ - Isolated from production              │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Provisioning Network (NOT USED)         │
│ VLAN 200: 172.22.0.0/24                 │
│ - Only needed if provisioningNetwork:   │
│   Managed (deprecated approach)         │
│ - Uses PXE instead of virtual media     │
│ - This guide uses Disabled mode         │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ Baremetal Network (Servers)             │
│ VLAN 300: 10.0.10.0/24                  │
│ - Server primary interfaces             │
│ - API/Ingress VIPs                      │
│ - Production traffic                    │
└─────────────────────────────────────────┘
```

**DNS Requirements:**

Must resolve before installation:
```
api.ocp.example.com          → 10.0.10.5 (API VIP)
*.apps.ocp.example.com       → 10.0.10.6 (Ingress VIP)
```

### Hardware Requirements

**Minimum per master node:**
- 4 vCPUs (8+ recommended)
- 16 GB RAM (32+ GB recommended)
- 120 GB disk (SSD recommended)
- 1 Gbps NIC (10 Gbps recommended)

**Minimum per worker node:**
- 2 vCPUs (16+ recommended for workloads)
- 8 GB RAM (64+ GB recommended for workloads)
- 120 GB disk
- 1 Gbps NIC

**BMC Requirements:**
- Redfish API support (v1.6+ recommended)
- Virtual media support (for redfish-virtualmedia)
- HTTPS access
- Dedicated management interface

### Vendor-Specific Notes

#### Dell iDRAC

```yaml
bmc:
  address: redfish-virtualmedia://idrac-ip/redfish/v1/Systems/System.Embedded.1
  # System path is always System.Embedded.1 for iDRAC
```

**iDRAC settings:**
- Enable virtual media: iDRAC Settings → Virtual Media → Enabled
- Enable Redfish: iDRAC Settings → Network → Redfish → Enabled

#### HPE iLO

```yaml
bmc:
  address: redfish-virtualmedia://ilo-ip/redfish/v1/Systems/1
  # System path is usually just "1" for iLO
```

**iLO settings:**
- Enable virtual media: iLO Settings → Virtual Media → Enabled
- Ensure license supports virtual media (Standard/Advanced)

#### Lenovo XClarity

```yaml
bmc:
  address: redfish-virtualmedia://xcc-ip/redfish/v1/Systems/1
```

**XClarity notes:**
- Supports Redfish v1.6+
- Virtual media requires Advanced license
- System path may vary by model

#### Supermicro

```yaml
bmc:
  address: redfish-virtualmedia://bmc-ip/redfish/v1/Systems/1
```

**Supermicro notes:**
- Update to latest BMC firmware for best Redfish support
- Virtual media may be called "iKVM" in web interface
- Some models require special firmware for full Redfish support

## Troubleshooting

### Installation Hangs at "Waiting for bootstrap"

**Possible causes:**
- BMC not accessible from installer
- Virtual media not mounting
- Wrong boot MAC address
- Firewall blocking Redfish API

**Debug steps:**

1. **Test Redfish connectivity:**
   ```bash
   curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/<uuid>
   ```

2. **Check BMC can reach installer:**
   - Installer runs an HTTP server for serving ISOs
   - BMC must be able to reach installer's IP

3. **Check boot MAC address:**
   ```bash
   # On the server, check actual MAC
   ip link show
   
   # Compare to install-config.yaml
   grep bootMACAddress install-config.yaml
   ```

4. **Monitor installation:**
   ```bash
   openshift-install wait-for bootstrap-complete --log-level=debug
   ```

### Nodes Don't Boot from ISO

**Possible causes:**
- Virtual media not supported/enabled
- ISO URL not accessible from BMC
- Boot order not set correctly

**Debug steps:**

1. **Verify virtual media endpoint exists:**
   ```bash
   curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/<uuid>/VirtualMedia
   ```

2. **Check if BMC can reach ISO:**
   - ISO is served from installer's IP
   - BMC must have network route to installer

3. **Manually test virtual media:**
   ```bash
   # Mount test ISO
   curl -k -u admin:password -X POST \
     https://<bmc-ip>/redfish/v1/Systems/<uuid>/VirtualMedia/CD/Actions/VirtualMedia.InsertMedia \
     -H "Content-Type: application/json" \
     -d '{"Image": "http://installer-ip:port/rhcos.iso", "Inserted": true}'
   
   # Check if mounted
   curl -k -u admin:password https://<bmc-ip>/redfish/v1/Systems/<uuid>/VirtualMedia/CD | jq '.Inserted'
   ```

### Wrong Disk Selected

**Problem:** OpenShift installs to wrong disk

**Solution:** Use more specific root device hints

```yaml
rootDeviceHints:
  deviceName: "/dev/sda"  # Too generic
```

**Better:**
```yaml
rootDeviceHints:
  serialNumber: "ABC123"  # Specific to one disk
```

**Or:**
```yaml
rootDeviceHints:
  minSizeGigabytes: 500
  maxSizeGigabytes: 1000  # Only disks 500-1000 GB
```

### Authentication Failures

**Problem:** `401 Unauthorized` from Redfish API

**Solutions:**

1. **Verify credentials:**
   ```bash
   curl -k -u admin:wrongpassword https://<bmc-ip>/redfish/v1/
   # Should return 401
   
   curl -k -u admin:correctpassword https://<bmc-ip>/redfish/v1/
   # Should return 200
   ```

2. **Check for special characters** in password:
   - Some special characters need escaping in YAML
   - Use quotes around password if it contains: `:`, `@`, `#`, etc.

3. **Verify account is not locked:**
   - BMCs may lock accounts after failed login attempts
   - Check BMC web interface

### Certificate Issues

**Problem:** Certificate verification failures

**Temporary workaround:**
```yaml
bmc:
  disableCertificateVerification: true
```

**Production solution:**
1. Export BMC certificate
2. Add to install-config.yaml:
   ```yaml
   additionalTrustBundle: |
     -----BEGIN CERTIFICATE-----
     <BMC cert here>
     -----END CERTIFICATE-----
   ```

## Additional Resources

- [OpenShift IPI Baremetal Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal_ipi/ipi-install-overview.html)
- [Redfish Specification](https://www.dmtf.org/standards/redfish)
- [Metal3 Project](https://metal3.io/) - Bare Metal Operator used by OpenShift
- [install-config.yaml Field Reference](INSTALL-CONFIG-GUIDE.md)

## Differences from This Lab

This lab uses **sushy-tools** to emulate Redfish BMC for KVM VMs. In production:

| Lab (sushy-tools) | Production (Real BMC) |
|-------------------|----------------------|
| KVM VMs as "servers" | Physical servers |
| Emulated Redfish | Native Redfish (iDRAC, iLO, etc.) |
| Local virtual media | Remote virtual media over network |
| Single management IP | Separate BMC IPs per server |
| No certificate validation | Should validate TLS certificates |
| Simple network (virbr0) | Complex networks (VLANs, bonds) |

**Key takeaway:** The install-config.yaml format is identical, but production requires:
- Real BMC IPs and credentials
- Network planning (management network, VLANs)
- DNS configuration
- TLS certificates
- More robust hardware
