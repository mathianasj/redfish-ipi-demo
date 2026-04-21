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

For each master node, add a host entry with Redfish details.

#### Understanding Virtual IPs (VIPs)

Before configuring hosts, you need to assign two virtual IP addresses:

**apiVIPs** - API Server Virtual IP:
- Used for Kubernetes API server access
- Must resolve to: `api.<cluster-name>.<base-domain>`
- Example: `api.ocp.example.com` → `10.0.10.5`
- Used by: `oc` CLI, kubectl, automation tools

**ingressVIPs** - Ingress/Router Virtual IP:
- Used for application ingress (routes)
- Must resolve to: `*.apps.<cluster-name>.<base-domain>`
- Example: `*.apps.ocp.example.com` → `10.0.10.6`
- Used by: Web console, application routes

**CRITICAL Requirements:**
- ✅ Both VIPs **MUST** be within the `machineNetwork` CIDR (e.g., `10.0.10.0/24`)
- ✅ VIPs **MUST** be outside DHCP range (use static allocation range)
- ✅ VIPs **MUST** be unused IPs (not assigned to any host)
- ✅ VIPs **MUST** have DNS A records
- ✅ VIPs **MUST** be reachable from all cluster nodes

**Example Network Planning:**
```
machineNetwork: 10.0.10.0/24
Gateway:        10.0.10.1
DHCP Range:     10.0.10.100 - 10.0.10.200
Static Range:   10.0.10.2 - 10.0.10.99

Assigned IPs:
- API VIP:      10.0.10.5  (static, in machineNetwork)
- Ingress VIP:  10.0.10.6  (static, in machineNetwork)
- Master-1:     10.0.10.10 (static, in machineNetwork)
- Master-2:     10.0.10.11 (static, in machineNetwork)
- Master-3:     10.0.10.12 (static, in machineNetwork)
```

#### Host Configuration with Static IPs

**Option 1: DHCP-based (simpler, recommended for testing)**

Let nodes get IPs via DHCP, identify by MAC address:

```yaml
platform:
  baremetal:
    provisioningNetwork: Disabled
    apiVIPs:
    - 10.0.10.5                     # API server VIP (must be in machineNetwork)
    ingressVIPs:
    - 10.0.10.6                     # Ingress/router VIP (must be in machineNetwork)
    hosts:
    - name: master-1
      role: master
      bmc:
        address: redfish-virtualmedia://10.0.10.101/redfish/v1/Systems/System.Embedded.1
        username: admin
        password: bmcpassword
        disableCertificateVerification: true
      bootMACAddress: "d4:ae:52:a1:b2:c3"    # Primary NIC MAC
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

**Option 2: Static IP Assignment (production, more control)**

Assign specific static IPs to each master node:

```yaml
platform:
  baremetal:
    provisioningNetwork: Disabled
    apiVIPs:
    - 10.0.10.5                     # API VIP (in machineNetwork CIDR)
    ingressVIPs:
    - 10.0.10.6                     # Ingress VIP (in machineNetwork CIDR)
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
      # Static IP configuration
      networkConfig:
        interfaces:
        - name: eno1                 # Interface name (adjust to your hardware)
          type: ethernet
          state: up
          mac-address: "d4:ae:52:a1:b2:c3"
          ipv4:
            enabled: true
            address:
            - ip: 10.0.10.10         # Static IP (in machineNetwork CIDR)
              prefix-length: 24
            dhcp: false
          ipv6:
            enabled: false
        dns-resolver:
          config:
            server:
            - 10.0.10.1              # DNS server
        routes:
          config:
          - destination: 0.0.0.0/0
            next-hop-address: 10.0.10.1
            next-hop-interface: eno1
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
      networkConfig:
        interfaces:
        - name: eno1
          type: ethernet
          state: up
          mac-address: "d4:ae:52:d4:e5:f6"
          ipv4:
            enabled: true
            address:
            - ip: 10.0.10.11         # Static IP (in machineNetwork CIDR)
              prefix-length: 24
            dhcp: false
          ipv6:
            enabled: false
        dns-resolver:
          config:
            server:
            - 10.0.10.1
        routes:
          config:
          - destination: 0.0.0.0/0
            next-hop-address: 10.0.10.1
            next-hop-interface: eno1
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
      networkConfig:
        interfaces:
        - name: eno1
          type: ethernet
          state: up
          mac-address: "d4:ae:52:12:34:56"
          ipv4:
            enabled: true
            address:
            - ip: 10.0.10.12         # Static IP (in machineNetwork CIDR)
              prefix-length: 24
            dhcp: false
          ipv6:
            enabled: false
        dns-resolver:
          config:
            server:
            - 10.0.10.1
        routes:
          config:
          - destination: 0.0.0.0/0
            next-hop-address: 10.0.10.1
            next-hop-interface: eno1
```

**When to use static IPs:**
- Production deployments
- No DHCP server available
- Need predictable IP assignments
- Strict network policies

**When to use DHCP:**
- Lab/testing environments
- DHCP reservations configured by MAC
- Simpler configuration

**Important notes for static IPs:**
- Interface name (`eno1`, `ens192`, etc.) must match your hardware
- Find interface name from BMC console or server documentation
- All IPs must be in the `machineNetwork` CIDR range
- VIPs and host IPs must not conflict

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

## Running the Installation

Now that you have a complete install-config.yaml, follow these steps to install OpenShift.

### Step 1: Create Installation Directory

```bash
# Create a directory for installation files
mkdir ~/openshift-install-dir
cd ~/openshift-install-dir
```

### Step 2: Place install-config.yaml

```bash
# Copy your install-config.yaml to the installation directory
cp /path/to/install-config.yaml ~/openshift-install-dir/
```

### Step 3: Backup install-config.yaml

**CRITICAL**: The installer consumes (deletes) the install-config.yaml file during installation!

```bash
# Always create a backup
cp install-config.yaml install-config.yaml.backup
```

### Step 4: Download OpenShift Installer

```bash
# Download the installer for your version
# Replace with the version matching your mirrored images
VERSION=4.20.0

# Download installer
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${VERSION}/openshift-install-linux.tar.gz

# Extract
tar -xzf openshift-install-linux.tar.gz

# Make executable
chmod +x openshift-install

# Verify version
./openshift-install version
```

### Step 5: Verify DNS is Configured

**Before running the installer**, ensure DNS is working:

```bash
# Test API VIP resolution
nslookup api.ocp.example.com
# Should return: 10.0.10.5

# Test wildcard apps resolution
nslookup test.apps.ocp.example.com
# Should return: 10.0.10.6
```

**CRITICAL: If DNS is not configured, the installation will fail.**

RHCOS nodes are immutable and cannot have /etc/hosts modified. You **MUST** configure proper DNS before installation:

1. **Create DNS A records:**
   ```
   api.ocp.example.com          IN  A  10.0.10.5
   *.apps.ocp.example.com       IN  A  10.0.10.6
   ```

2. **Or use dnsmasq for testing:**
   ```bash
   # On a DNS server or your workstation (if acting as DNS)
   echo "address=/api.ocp.example.com/10.0.10.5" >> /etc/dnsmasq.d/openshift.conf
   echo "address=/apps.ocp.example.com/10.0.10.6" >> /etc/dnsmasq.d/openshift.conf
   systemctl restart dnsmasq
   ```

3. **Verify DNS works from installer machine:**
   ```bash
   nslookup api.ocp.example.com
   nslookup test.apps.ocp.example.com
   # Both should resolve correctly
   ```

### Step 6: Start the Installation

```bash
# Run the installer
./openshift-install create cluster --dir=. --log-level=info

# For more verbose output
./openshift-install create cluster --dir=. --log-level=debug
```

**What happens next:**
1. Installer validates install-config.yaml
2. Generates manifests and ignition configs
3. Creates temporary bootstrap VM
4. Contacts BMCs via Redfish
5. Powers off baremetal hosts
6. Mounts RHCOS ISO via virtual media
7. Powers on hosts
8. Monitors bootstrap process

### Step 7: Monitor Installation Progress

**In the same terminal**, you'll see output like:

```
INFO Consuming Install Config from target directory
INFO Obtaining RHCOS image file from 'https://...'
INFO Creating infrastructure resources...
INFO Waiting up to 20m0s for the Kubernetes API at https://api.ocp.example.com:6443...
INFO API v1.29.0 up
INFO Waiting up to 30m0s for bootstrapping to complete...
INFO Destroying the bootstrap resources...
INFO Waiting up to 40m0s for the cluster at https://api.ocp.example.com:6443 to initialize...
INFO Waiting up to 10m0s for the openshift-console route to be created...
INFO Install complete!
```

**In another terminal**, monitor BMC activity:

```bash
# Watch Redfish power states
while true; do
  echo "=== Power States at $(date) ==="
  for bmc in 10.0.10.101 10.0.10.102 10.0.10.103; do
    state=$(curl -sk -u admin:password https://$bmc/redfish/v1/Systems/System.Embedded.1 | jq -r '.PowerState')
    echo "$bmc: $state"
  done
  sleep 30
done
```

**Monitor via BMC console** (optional):
- Access BMC web interface
- Open virtual console (iKVM, HTML5 console)
- Watch RHCOS boot and installation

### Step 8: Installation Complete

When installation finishes (typically 45-60 minutes), you'll see:

```
INFO Install complete!
INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/root/openshift-install-dir/auth/kubeconfig'
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.ocp.example.com
INFO Login to the console with user: "kubeadmin", and password: "xxxxx-xxxxx-xxxxx-xxxxx"
```

**Important files created:**
```
openshift-install-dir/
├── auth/
│   ├── kubeconfig          # Admin kubeconfig
│   └── kubeadmin-password  # Web console password
├── metadata.json           # Cluster metadata
└── .openshift_install.log  # Full installation log
```

### Step 9: Export Kubeconfig

```bash
# Export kubeconfig for CLI access
export KUBECONFIG=~/openshift-install-dir/auth/kubeconfig

# Verify access
oc whoami
# Should show: system:admin

# Check cluster version
oc get clusterversion

# Check nodes
oc get nodes
```

**Expected output:**
```
NAME       STATUS   ROLES                  AGE   VERSION
master-1   Ready    control-plane,master   45m   v1.29.0+xxxxx
master-2   Ready    control-plane,master   45m   v1.29.0+xxxxx
master-3   Ready    control-plane,master   45m   v1.29.0+xxxxx
```

### Step 10: Access Web Console

**Get console URL and credentials:**

```bash
# Console URL
echo "Console: https://console-openshift-console.apps.ocp.example.com"

# Get kubeadmin password
cat ~/openshift-install-dir/auth/kubeadmin-password
```

**Access the console:**

1. Open browser to: `https://console-openshift-console.apps.ocp.example.com`
2. Accept certificate warning (self-signed cert for apps wildcard)
3. Click "kubeadmin" login
4. Username: `kubeadmin`
5. Password: (from kubeadmin-password file)

**Alternative - Get password via CLI:**
```bash
# One-liner to open console with password
PASSWORD=$(cat ~/openshift-install-dir/auth/kubeadmin-password)
echo "Username: kubeadmin"
echo "Password: $PASSWORD"
echo "URL: https://console-openshift-console.apps.ocp.example.com"
```

### Step 11: Verify Cluster Health

```bash
# Check all nodes are ready
oc get nodes

# Check cluster operators
oc get co
# All should show AVAILABLE=True, PROGRESSING=False, DEGRADED=False

# Check cluster version
oc get clusterversion
# Should show desired version and PROGRESSING=False

# Check pods in critical namespaces
oc get pods -n openshift-kube-apiserver
oc get pods -n openshift-etcd
oc get pods -n openshift-console
```

### Step 12: Create Regular Admin User (Optional)

The `kubeadmin` user is temporary. Create a permanent admin:

```bash
# Create htpasswd file
htpasswd -c -B -b users.htpasswd admin 'YourPassword123!'

# Create secret
oc create secret generic htpass-secret \
  --from-file=htpasswd=users.htpasswd \
  -n openshift-config

# Create OAuth config
cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: htpasswd_provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
EOF

# Give admin user cluster-admin role
oc adm policy add-cluster-role-to-user cluster-admin admin

# Wait for authentication operator to reconcile
oc get pods -n openshift-authentication -w
# Wait for pods to restart

# Test new user login
oc login -u admin -p YourPassword123! https://api.ocp.example.com:6443
```

**Now you can delete kubeadmin:**
```bash
oc delete secrets kubeadmin -n kube-system
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

After the initial cluster installation completes with 3 control plane nodes, you can add worker nodes to handle application workloads.

**Prerequisites:**
- Cluster installed and accessible
- Additional physical servers with BMC/Redfish access
- Kubeconfig exported: `export KUBECONFIG=~/openshift-install-dir/auth/kubeconfig`

**Overview of the process:**
1. Create BMC credential secrets for each worker
2. Create BareMetalHost resources (registers servers with Metal3)
3. Create/update MachineSet (triggers actual provisioning)
4. Monitor as workers are provisioned and join cluster
5. (Optional) Disable scheduling on control plane nodes

**Time**: 15-30 minutes per worker (provisioning happens in parallel)

Let's walk through adding 2 worker nodes.

#### Step 1: Create BMC Credentials Secret

For each worker, create a secret with BMC credentials:

**Create worker-1-bmc-secret.yaml:**

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

**Apply the secret:**
```bash
oc apply -f worker-1-bmc-secret.yaml
```

**Repeat for worker-2:**
```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: worker-2-bmc-secret
  namespace: openshift-machine-api
type: Opaque
stringData:
  username: admin
  password: bmcpassword
EOF
```

**Verify secrets:**
```bash
oc get secrets -n openshift-machine-api | grep bmc-secret
```

#### Step 2: Create BareMetalHost Resources

**Before creating BareMetalHost**, gather this information for each worker:
- BMC IP address
- Redfish System UUID (from `curl https://<bmc-ip>/redfish/v1/Systems`)
- Boot MAC address (from server or BMC interface list)
- Root device hint (disk to install to)

**Create worker-1-bmh.yaml:**
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

**Apply worker-1:**
```bash
oc apply -f worker-1-bmh.yaml
```

**Create and apply worker-2:**
```bash
cat <<EOF | oc apply -f -
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-2
  namespace: openshift-machine-api
  labels:
    infraenvs.agent-install.openshift.io: ""
spec:
  online: true
  bmc:
    address: redfish-virtualmedia://10.0.10.105/redfish/v1/Systems/System.Embedded.1
    credentialsName: worker-2-bmc-secret
    disableCertificateVerification: true
  bootMACAddress: "d4:ae:52:44:55:66"
  rootDeviceHints:
    deviceName: "/dev/sda"
EOF
```

**Check BareMetalHost status:**
```bash
# List all BareMetalHosts
oc get baremetalhosts -n openshift-machine-api

# Watch status changes
oc get baremetalhosts -n openshift-machine-api -w

# Get detailed info for a specific host
oc describe baremetalhost worker-1 -n openshift-machine-api
```

**Expected progression:**
```
NAME       STATUS       PROVISIONING STATUS   CONSUMER   BMC                 HARDWARE PROFILE
worker-1   OK           inspecting                       redfish-virtualmedia://...
worker-2   OK           inspecting                       redfish-virtualmedia://...
```

After inspection completes (5-10 minutes):
```
NAME       STATUS       PROVISIONING STATUS   CONSUMER   BMC                 HARDWARE PROFILE
worker-1   OK           available                        redfish-virtualmedia://...   unknown
worker-2   OK           available                        redfish-virtualmedia://...   unknown
```

**Troubleshooting:**
- If stuck in `registering`: Check BMC credentials and network connectivity
- If stuck in `inspecting`: Check BMC virtual media support
- If status shows errors: `oc describe baremetalhost worker-1 -n openshift-machine-api`

#### Step 3: Create MachineSet to Provision Workers

**CRITICAL**: Creating a BareMetalHost alone does NOT provision a worker. The BareMetalHost registers the hardware, but you need a MachineSet to actually provision and join workers to the cluster.

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
          apiVersion: machine.openshift.io/v1beta1
          kind: BareMetalMachineProviderSpec
          userData:
            name: worker-user-data
```

**Note**: The RHCOS image is automatically managed by the cluster's release payload. You don't need to specify image URL or checksum.

**Step 3a: Get Your Cluster ID**

```bash
# Get cluster infrastructure name (used as cluster ID)
CLUSTER_ID=$(oc get -o jsonpath='{.status.infrastructureName}{"\n"}' infrastructure cluster)
echo "Cluster ID: $CLUSTER_ID"

# Example output: ocp-gkw4z
```

**Step 3b: Create the MachineSet**

Replace `<cluster-id>` in the YAML above with your actual cluster ID, or create it with sed:

```bash
# Save the MachineSet template
cat <<EOF > worker-machineset.yaml
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  name: worker
  namespace: openshift-machine-api
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
spec:
  replicas: 2
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: worker
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: worker
    spec:
      metadata: {}
      providerSpec:
        value:
          apiVersion: machine.openshift.io/v1beta1
          kind: BareMetalMachineProviderSpec
          userData:
            name: worker-user-data
EOF

# Review the file
cat worker-machineset.yaml
```

**Alternative - Use existing MachineSet as template (if available):**
```bash
# Check if any MachineSet already exists
oc get machineset -n openshift-machine-api

# If exists, use as template
oc get machineset -n openshift-machine-api -o yaml | head -100 > worker-machineset-template.yaml
# Edit template and apply
```

**Step 3c: Apply the MachineSet**

```bash
oc apply -f worker-machineset.yaml
```

**Verify MachineSet created:**
```bash
oc get machineset -n openshift-machine-api

# Should show:
# NAME     DESIRED   CURRENT   READY   AVAILABLE   AGE
# worker   2         0         0       0           5s
```

#### Step 4: Monitor Worker Provisioning

**Watch the entire provisioning process:**

**Terminal 1 - Watch Machines:**
```bash
oc get machines -n openshift-machine-api -w
```

**Terminal 2 - Watch BareMetalHosts:**
```bash
oc get baremetalhosts -n openshift-machine-api -w
```

**Terminal 3 - Watch Nodes:**
```bash
oc get nodes -w
```

**What you'll see:**

1. **Machines created** (immediate):
   ```
   NAME                   PHASE      TYPE   REGION   ZONE   AGE
   worker-xxxxx-yyyyy     Pending                            5s
   worker-xxxxx-zzzzz     Pending                            5s
   ```

2. **BareMetalHosts claim** (30 seconds):
   ```
   NAME       STATUS   STATE          CONSUMER               BMC
   worker-1   OK       provisioning   worker-xxxxx-yyyyy     redfish-virtualmedia://...
   worker-2   OK       provisioning   worker-xxxxx-zzzzz     redfish-virtualmedia://...
   ```

3. **Provisioning starts** (1-2 minutes):
   - Hosts power off
   - ISO mounts via Redfish
   - Hosts power on and boot RHCOS

4. **Nodes appear** (10-15 minutes):
   ```
   NAME       STATUS     ROLES    AGE   VERSION
   master-1   Ready      master   2h    v1.29.0
   master-2   Ready      master   2h    v1.29.0
   master-3   Ready      master   2h    v1.29.0
   worker-1   NotReady   worker   30s   v1.29.0
   worker-2   NotReady   worker   30s   v1.29.0
   ```

5. **Nodes become Ready** (5 minutes):
   ```
   worker-1   Ready      worker   5m    v1.29.0
   worker-2   Ready      worker   5m    v1.29.0
   ```

**Check progress with single commands:**
```bash
# Overview
echo "=== MachineSet ===" && oc get machineset -n openshift-machine-api && \
echo "=== Machines ===" && oc get machines -n openshift-machine-api && \
echo "=== BareMetalHosts ===" && oc get baremetalhosts -n openshift-machine-api && \
echo "=== Nodes ===" && oc get nodes

# Detailed view of a specific BareMetalHost
oc describe baremetalhost worker-1 -n openshift-machine-api

# Check provisioning logs
oc logs -n openshift-machine-api -l baremetal.openshift.io/cluster-baremetal-operator=metal3-state
```

**Troubleshooting:**
- **Machine stuck in Pending**: Check BareMetalHost is in `available` state
- **Host stuck in provisioning**: Check Redfish connectivity, view BMC console
- **Node stuck in NotReady**: Check node logs with `oc debug node/worker-1`

**Total time**: 15-30 minutes per worker from MachineSet creation to Ready

#### Step 5: Disable Control Plane Scheduling (Optional but Recommended)

**When to do this**: Once all workers are `Ready` and you want to dedicate control plane nodes to cluster management only.

**Why**: In production, you typically don't want user workloads on control plane nodes. This reserves masters for:
- Kubernetes control plane (API server, controller manager, scheduler)
- etcd database
- Cluster operators

**Execute these commands once workers are Ready:**

**Method 1: Taint masters (Recommended)**

Add a taint that prevents scheduling on masters:

```bash
# Add NoSchedule taint to all masters
for node in $(oc get nodes -l node-role.kubernetes.io/master -o name); do
  oc adm taint node ${node#node/} node-role.kubernetes.io/master=:NoSchedule
done
```

**Verify taints applied:**
```bash
oc get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

**Method 2: Cordon masters**

Mark masters as unschedulable (simpler but less flexible):

```bash
# Cordon all master nodes
for node in $(oc get nodes -l node-role.kubernetes.io/master -o name); do
  oc adm cordon ${node#node/}
done
```

**Verify cordoned:**
```bash
oc get nodes
# Masters should show "Ready,SchedulingDisabled"
```

**Method 3: Remove worker label (if present)**

If masters have both master and worker roles:

```bash
# Check if masters have worker role
oc get nodes -l node-role.kubernetes.io/master

# Remove worker role from masters
for node in $(oc get nodes -l node-role.kubernetes.io/master -o name); do
  oc label ${node} node-role.kubernetes.io/worker-
done
```

**Recommended approach**: Use Method 1 (taints) as it's the standard Kubernetes way and most flexible.

**Verify final node configuration:**
```bash
oc get nodes -o wide

# Expected output:
# NAME       STATUS   ROLES                  AGE   VERSION
# master-1   Ready    control-plane,master   2h    v1.29.0+xxx
# master-2   Ready    control-plane,master   2h    v1.29.0+xxx
# master-3   Ready    control-plane,master   2h    v1.29.0+xxx
# worker-1   Ready    worker                 30m   v1.29.0+xxx
# worker-2   Ready    worker                 30m   v1.29.0+xxx
```

**Test scheduling:**
```bash
# Create a test pod
oc run test-pod --image=registry.access.redhat.com/ubi9/ubi:latest --command -- sleep 3600

# Check where it was scheduled (should be on a worker)
oc get pod test-pod -o wide

# Clean up
oc delete pod test-pod
```

**Important notes:**
- System pods (kube-apiserver, etcd, etc.) use tolerations and will still run on masters
- User workloads will only schedule on worker nodes
- You can reverse this with: `oc adm taint nodes <master> node-role.kubernetes.io/master:NoSchedule-`

**Your cluster is now fully configured with dedicated control plane and worker nodes!**

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
