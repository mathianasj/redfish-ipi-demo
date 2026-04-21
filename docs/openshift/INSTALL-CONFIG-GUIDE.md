# OpenShift install-config.yaml Guide

Comprehensive guide to OpenShift IPI baremetal install-config.yaml configuration for this demo environment.

## Table of Contents

- [Basic Configuration](#basic-configuration)
- [Field Reference](#field-reference)
- [Standard Deployment](#standard-deployment)
- [Disconnected/Mirrored Environment](#disconnectedmirrored-environment)
- [Adding Workers](#adding-workers)
- [Common Scenarios](#common-scenarios)
- [Troubleshooting](#troubleshooting)

## Basic Configuration

The install-config.yaml is consumed by the OpenShift installer. **Always back it up before running the installer!**

```bash
cp ~/openshift-install/install-config.yaml ~/install-config.yaml.backup
```

## Field Reference

### Required Fields

#### `apiVersion`
API version for the config (always `v1`)

```yaml
apiVersion: v1
```

#### `baseDomain`
Base DNS domain for the cluster

```yaml
baseDomain: example.com
```

#### `metadata.name`
Cluster name (combined with baseDomain forms FQDN)

```yaml
metadata:
  name: ocp
```

**Result**: API at `api.ocp.example.com`, apps at `*.apps.ocp.example.com`

#### `networking`
Cluster network configuration

```yaml
networking:
  networkType: OVNKubernetes        # Network plugin (OVNKubernetes or OpenShiftSDN)
  machineNetwork:                   # Physical network where nodes live
  - cidr: 192.168.122.0/24
  clusterNetwork:                   # Pod network
  - cidr: 10.128.0.0/14
    hostPrefix: 23                  # Subnet size for each node (/23 = 512 IPs)
  serviceNetwork:                   # Service network
  - 172.30.0.0/16
```

**Key Points**:
- `machineNetwork` must match your KVM/libvirt network (usually virbr0)
- `clusterNetwork` is for pod-to-pod communication
- `serviceNetwork` is for Kubernetes services
- These three networks must not overlap

#### `compute`
Worker node configuration

```yaml
compute:
- name: worker
  replicas: 0                       # 0 = no workers (compact cluster)
```

**Compact Cluster** (3 masters, 0 workers):
- Masters run workloads
- Minimum resource footprint
- Good for demos/testing

**Standard Cluster** (3 masters + N workers):
```yaml
compute:
- name: worker
  replicas: 2                       # Add 2 workers during install
```

#### `controlPlane`
Master node configuration

```yaml
controlPlane:
  name: master
  replicas: 3                       # Always 3 for HA
  platform:
    baremetal: {}
```

#### `platform.baremetal`
Baremetal platform configuration

```yaml
platform:
  baremetal:
    provisioningNetwork: Disabled   # No provisioning network (use external bridge)
    externalBridge: virbr0          # KVM bridge name
    apiVIPs:                        # Virtual IP for API server
    - 192.168.122.5
    ingressVIPs:                    # Virtual IP for ingress/router
    - 192.168.122.6
    hosts:                          # List of baremetal hosts (see below)
    - name: master-1
      # ... host details
```

**VIP Requirements**:
- Must be on the same network as machines
- Must be outside DHCP range
- Must have DNS A records (or use /etc/hosts)

#### `platform.baremetal.hosts`
Individual host definitions with Redfish BMC

```yaml
hosts:
- name: master-1
  role: master
  bmc:
    address: redfish-virtualmedia://192.168.122.1:8000/redfish/v1/Systems/abc-123-uuid
    username: admin
    password: password
    disableCertificateVerification: true  # Required for self-signed certs
  bootMACAddress: "52:54:00:a1:b2:c3"     # MAC of primary NIC
  rootDeviceHints:
    deviceName: "/dev/vda"                 # Which disk to install to
```

**Redfish Address Format**:
- `redfish://` - Standard Redfish (no virtual media)
- `redfish-virtualmedia://` - Redfish with ISO mounting (required for this demo)
- URL must include full path to system: `/redfish/v1/Systems/<UUID>`

**Finding System UUIDs**:
```bash
# List all systems
curl http://<instance-ip>:8000/redfish/v1/Systems | jq '.Members[]."@odata.id"'

# Get specific system UUID
virsh domuuid ocp-master-1
```

#### `pullSecret`
Red Hat registry authentication (from console.redhat.com)

```yaml
pullSecret: '{"auths":{"cloud.openshift.com":{"auth":"..."},...}}'
```

Download from: https://console.redhat.com/openshift/install/pull-secret

#### `sshKey`
SSH public key for core user access

```yaml
sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC...'
```

```bash
# Get your public key
cat ~/.ssh/id_rsa.pub
```

### Optional Fields

#### `fips`
Enable FIPS 140-2 cryptographic mode

```yaml
fips: true
```

**Note**: FIPS mode cannot be disabled after installation.

#### `additionalTrustBundle`
Custom CA certificates (required for disconnected/mirrored registries)

```yaml
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  MIIDXTCCAkWgAwIBAgIJAKl...
  -----END CERTIFICATE-----
```

#### `imageContentSources`
Mirror registry configuration (for disconnected environments)

```yaml
imageContentSources:
- mirrors:
  - <registry-ip>:8443/openshift/release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - <registry-ip>:8443/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

See [Disconnected Environment Configuration](#disconnectedmirrored-environment) below.

## Standard Deployment

Full example for a compact 3-node cluster:

```yaml
apiVersion: v1
baseDomain: example.com
metadata:
  name: ocp
networking:
  networkType: OVNKubernetes
  machineNetwork:
  - cidr: 192.168.122.0/24
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
    externalBridge: virbr0
    apiVIPs:
    - 192.168.122.5
    ingressVIPs:
    - 192.168.122.6
    hosts:
    - name: master-1
      role: master
      bmc:
        address: redfish-virtualmedia://192.168.122.1:8000/redfish/v1/Systems/abc-123-uuid-1
        username: admin
        password: password
        disableCertificateVerification: true
      bootMACAddress: "52:54:00:a1:b2:c3"
      rootDeviceHints:
        deviceName: "/dev/vda"
    - name: master-2
      role: master
      bmc:
        address: redfish-virtualmedia://192.168.122.1:8000/redfish/v1/Systems/abc-123-uuid-2
        username: admin
        password: password
        disableCertificateVerification: true
      bootMACAddress: "52:54:00:d4:e5:f6"
      rootDeviceHints:
        deviceName: "/dev/vda"
    - name: master-3
      role: master
      bmc:
        address: redfish-virtualmedia://192.168.122.1:8000/redfish/v1/Systems/abc-123-uuid-3
        username: admin
        password: password
        disableCertificateVerification: true
      bootMACAddress: "52:54:00:12:34:56"
      rootDeviceHints:
        deviceName: "/dev/vda"
pullSecret: '{"auths":{"cloud.openshift.com":{"auth":"base64string"},...}}'
sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC...'
```

## Disconnected/Mirrored Environment

For air-gapped installations using a local mirror registry:

```yaml
apiVersion: v1
baseDomain: example.com
metadata:
  name: ocp
networking:
  networkType: OVNKubernetes
  machineNetwork:
  - cidr: 192.168.122.0/24
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
    externalBridge: virbr0
    apiVIPs:
    - 192.168.122.5
    ingressVIPs:
    - 192.168.122.6
    hosts:
    # ... (same as standard deployment)
# Additional configuration for disconnected environment:
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  MIIDXTCCAkWgAwIBAgIJAKl...
  -----END CERTIFICATE-----
imageContentSources:
- mirrors:
  - 3.145.67.89:8443/openshift/release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - 3.145.67.89:8443/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
pullSecret: '{"auths":{"cloud.openshift.com":{"auth":"..."},"3.145.67.89:8443":{"auth":"..."}}}'
sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC...'
```

### Steps for Disconnected Setup

1. **Set up mirror registry**:
   ```bash
   ansible-playbook configure-mirror-registry.yml
   ```

2. **Mirror images**:
   ```bash
   ansible-playbook run-mirror.yml
   ansible-playbook push-to-registry.yml
   ```

3. **Get CA certificate**:
   ```bash
   cat /home/ec2-user/mirror-registry/quay-rootCA/rootCA.pem
   ```

4. **Find imageContentSources**:
   ```bash
   # After mirroring completes
   find /home/ec2-user/mirror -name "*imageContentSourcePolicy.yaml"
   ```

5. **Update pull secret** to include mirror registry:
   ```bash
   # Merge mirror registry auth into pull secret
   podman login <instance-ip>:8443
   cat ~/.docker/config.json  # Contains merged auth
   ```

6. **Add to install-config.yaml**:
   - `additionalTrustBundle`: Paste CA certificate
   - `imageContentSources`: Copy from ICSP file
   - `pullSecret`: Use merged auth from config.json

See [MIRROR-REGISTRY-GUIDE.md](../disconnected/MIRROR-REGISTRY-GUIDE.md) for complete details.

## Adding Workers

### During Installation

Specify worker count in install-config.yaml:

```yaml
compute:
- name: worker
  replicas: 2
```

Then add worker hosts to the platform section:

```yaml
platform:
  baremetal:
    # ... VIPs and master hosts ...
    hosts:
    # ... masters ...
    - name: worker-1
      role: worker
      bmc:
        address: redfish-virtualmedia://192.168.122.1:8000/redfish/v1/Systems/worker-1-uuid
        username: admin
        password: password
        disableCertificateVerification: true
      bootMACAddress: "52:54:00:11:22:33"
      rootDeviceHints:
        deviceName: "/dev/vda"
    - name: worker-2
      role: worker
      bmc:
        address: redfish-virtualmedia://192.168.122.1:8000/redfish/v1/Systems/worker-2-uuid
        username: admin
        password: password
        disableCertificateVerification: true
      bootMACAddress: "52:54:00:44:55:66"
      rootDeviceHints:
        deviceName: "/dev/vda"
```

### After Installation (Day 2)

Use the scale-workers playbook:

```bash
ansible-playbook scale-workers.yml -e worker_count=2
```

This creates BareMetalHost resources that OpenShift provisions automatically.

## Common Scenarios

### Scenario 1: Standard 3-Node Compact Cluster

**Use Case**: Demo, testing, minimal footprint

```yaml
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 3
```

**Resources**: 3 masters (24 vCPUs, 96GB RAM total)

### Scenario 2: Production-Like with Workers

**Use Case**: Realistic workload separation

```yaml
compute:
- name: worker
  replicas: 2
controlPlane:
  name: master
  replicas: 3
```

**Resources**: 3 masters + 2 workers (40 vCPUs, 160GB RAM total)

### Scenario 3: Disconnected Installation

**Use Case**: Air-gapped, no internet access

**Requirements**:
- Local mirror registry
- Mirrored images
- Custom CA certificate
- Updated pull secret

See [Disconnected Environment Configuration](#disconnectedmirrored-environment) above.

### Scenario 4: Different Network Ranges

**Use Case**: Avoid conflicts with existing networks

```yaml
networking:
  machineNetwork:
  - cidr: 10.0.10.0/24              # Custom machine network
  clusterNetwork:
  - cidr: 10.200.0.0/14             # Custom pod network
    hostPrefix: 23
  serviceNetwork:
  - 10.100.0.0/16                   # Custom service network
```

**Remember**: Update DNS and VIPs to match the new network.

## Troubleshooting

### Problem: Install fails with "BMC not accessible"

**Solution**: Verify Redfish connectivity

```bash
# Test Redfish endpoint
curl http://<ip>:8000/redfish/v1/Systems/<uuid>

# Check sushy-tools is running
systemctl status sushy-emulator
```

### Problem: "No route to host" for VIPs

**Solution**: Ensure VIPs are on the same network as machines

```bash
# Check network configuration
virsh net-dumpxml default

# Verify IPs are available
ping 192.168.122.5
ping 192.168.122.6
```

### Problem: Nodes fail to boot from ISO

**Solution**: Verify virtual media support

```bash
# Check Redfish virtual media endpoint
curl http://<ip>:8000/redfish/v1/Systems/<uuid>/VirtualMedia

# Verify sushy-tools config
cat /etc/sushy/sushy-emulator.conf
```

### Problem: "Unable to pull image" errors

**Solution**: Check pull secret

```bash
# Validate pull secret JSON
cat pullsecret.json | jq .

# For mirrored environments, verify registry auth
podman login <mirror-ip>:8443
```

### Problem: install-config.yaml is consumed/deleted

**Solution**: The installer consumes this file - always back it up!

```bash
# Before running installer:
cp install-config.yaml install-config.yaml.backup

# Restore if needed:
cp install-config.yaml.backup install-config.yaml
```

## Additional Resources

- [OpenShift IPI Baremetal Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal_ipi/ipi-install-overview.html)
- [Redfish API Guide](SUSHY_REDFISH.md)
- [Complete Deployment Workflow](COMPLETE_DEPLOYMENT.md)
- [Mirror Registry Setup](../disconnected/MIRROR-REGISTRY-GUIDE.md)
- [Pull Secret Guide](PULL-SECRET.md)

## Examples in This Repository

- `install-config.yaml.example` - Basic example
- `roles/openshift_install/templates/install-config.yaml.j2` - Ansible template with variables
- Generated config: `/home/ec2-user/openshift-install/install-config.yaml` (on EC2 instance)
