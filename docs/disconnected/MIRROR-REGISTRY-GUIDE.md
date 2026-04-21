# OpenShift Mirror Registry Guide

This guide covers the complete workflow for setting up and using a local OpenShift mirror registry for disconnected environments.

## Overview

The mirroring workflow has two main phases:

1. **Download Phase**: Use `oc-mirror` to download images from Red Hat registries to disk
2. **Upload Phase**: Push the downloaded images from disk to your local mirror registry

## Architecture

```
Red Hat Registries → oc-mirror → Disk → oc-mirror → Local Mirror Registry
(registry.redhat.io)   (download)  (file://)  (upload)  (Quay on EC2)
```

## Components

### oc-mirror v2
- Tool for mirroring OpenShift images
- Downloads images to disk in disconnected scenarios
- Can push images from disk to a registry
- Location: `/usr/local/bin/oc-mirror`

### Mirror Registry (Quay)
- Local container registry for hosting mirrored images
- Based on Red Hat Quay
- Runs as containers via Podman
- Default URL: `https://<instance-ip>:8443`

## Installation

Run the configure-mirror-registry playbook:

```bash
ansible-playbook configure-mirror-registry.yml
```

This installs:
- oc-mirror v2
- mirror-registry tool
- Quay-based container registry
- Configures firewall and certificates

## Automated Workflow (Recommended)

Use the provided Ansible playbooks for a fully automated mirroring process:

### Step 1: Download Images

```bash
# Test with minimal config first (10-15 GB)
ansible-playbook run-mirror.yml -e mirror_config=minimal

# Or full mirror (50-80 GB)
ansible-playbook run-mirror.yml
```

This playbook:
- Validates prerequisites (registry running, oc-mirror installed)
- Copies config file to EC2 instance
- Starts download in tmux session 'mirror'
- Provides monitoring instructions

### Step 2: Push to Registry

After download completes:

```bash
ansible-playbook push-to-registry.yml
```

This playbook:
- Trusts the registry CA certificate
- Logs into the mirror registry
- Pushes images from disk to registry
- Starts push in tmux session 'push'

### Monitor Progress

```bash
# Attach to download session
ssh ec2-user@<instance-ip>
tmux attach -t mirror

# Attach to push session
tmux attach -t push

# Or check logs
tail -f /home/ec2-user/mirror/download.log
tail -f /home/ec2-user/mirror/push.log
```

## Manual Workflow

For manual control or troubleshooting, use these commands directly:

### Step 1: Download Images (Internet Required)

Download OpenShift images to disk:

```bash
# SSH to EC2 instance
ssh ec2-user@<instance-ip>

# Start tmux (recommended for long-running downloads)
tmux new -s mirror

# Create output directory
mkdir -p /home/ec2-user/mirror

# Download images (50-80 GB, 45-90 minutes on EC2)
oc-mirror --v2 --config=imageset-config-4.20.yaml file:///home/ec2-user/mirror

# Monitor progress in another terminal
watch -n 30 'du -sh /home/ec2-user/mirror'
```

**Output:**
- Downloaded images: `/home/ec2-user/mirror/v2/`
- Pinned config: `/home/ec2-user/mirror/isc_pinned_<timestamp>.yaml`
- Metadata: `/home/ec2-user/mirror/artifacts/`

### Step 2: Trust Registry CA Certificate

The mirror registry uses self-signed certificates. Trust them:

```bash
# Copy CA certificate to system trust store
sudo cp /home/ec2-user/mirror-registry/quay-rootCA/rootCA.pem \
  /etc/pki/ca-trust/source/anchors/mirror-registry-ca.crt

# Update system CA trust
sudo update-ca-trust

# Verify
ls -la /etc/pki/ca-trust/source/anchors/mirror-registry-ca.crt
```

### Step 3: Login to Mirror Registry

Authenticate with the local registry:

```bash
# Login with default credentials
podman login -u admin -p admin123 <instance-ip>:8443

# Verify login
podman login <instance-ip>:8443 --get-login
```

**Default Credentials:**
- Username: `admin`
- Password: `admin123`
- URL: `https://<instance-ip>:8443`

### Step 4: Push Images to Mirror Registry

Upload the downloaded images to the local registry:

```bash
# Push from disk to registry
oc-mirror --v2 \
  --from=file:///home/ec2-user/mirror \
  docker://<instance-ip>:8443

# This will:
# 1. Read images from disk (/home/ec2-user/mirror)
# 2. Push them to the local registry (<instance-ip>:8443)
# 3. Create ImageContentSourcePolicy and CatalogSource configs
```

**Output:**
- Images pushed to: `https://<instance-ip>:8443`
- Cluster configs: Look for ICSP and CatalogSource YAML files

### Step 5: Access Mirror Registry Web UI

Open your browser:

1. Navigate to: `https://<instance-ip>:8443`
2. Accept the self-signed certificate warning
3. Login with:
   - Username: `admin`
   - Password: `admin123`
4. Browse repositories and images

## Mirror Registry Management

### Check Registry Status

```bash
# Check if Quay is running
podman ps | grep quay

# Should show containers:
# - quay-app
# - quay-postgres
# - quay-redis
```

### View Registry Logs

```bash
# Get Quay container ID
podman ps | grep quay-app

# View logs
podman logs -f <container-id>

# Or use mirror-registry tool
cd /home/ec2-user/mirror-registry
/usr/local/bin/mirror-registry --help
```

### Restart Registry

```bash
# Stop registry
podman stop $(podman ps | grep quay | awk '{print $1}')

# Start registry (it will auto-restart via systemd)
# Or use mirror-registry tool:
cd /home/ec2-user/mirror-registry
/usr/local/bin/mirror-registry start
```

### Change Registry Password

```bash
# Access Quay web UI
# Go to: https://<instance-ip>:8443
# Login as admin
# Navigate to: Account Settings → Change Password
```

## Using Mirrored Images in OpenShift

### Option 1: ImageContentSourcePolicy (ICSP)

After mirroring, oc-mirror creates ICSP configuration:

```bash
# Find the ICSP file
find /home/ec2-user/mirror -name "*imageContentSourcePolicy.yaml"

# Apply to running cluster
oc apply -f <icsp-file>

# Nodes will reboot to apply changes
```

### Option 2: install-config.yaml

For new installations, add to install-config.yaml:

```yaml
imageContentSources:
- mirrors:
  - <instance-ip>:8443/openshift/release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - <instance-ip>:8443/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

### Option 3: CatalogSource

For operator catalogs:

```bash
# Find CatalogSource file
find /home/ec2-user/mirror -name "*catalogSource.yaml"

# Apply to cluster
oc apply -f <catalogsource-file>
```

## Storage Management

### Mirror Registry Storage

Default location: `/home/ec2-user/mirror-registry/`

```bash
# Check registry storage usage
du -sh /home/ec2-user/mirror-registry

# Storage breakdown
du -h --max-depth=1 /home/ec2-user/mirror-registry
```

### Downloaded Images Storage

Default location: `/home/ec2-user/mirror/`

```bash
# Check downloaded images size
du -sh /home/ec2-user/mirror

# After pushing to registry, you can delete downloads:
rm -rf /home/ec2-user/mirror
```

## Troubleshooting

### Registry Not Accessible

**Problem:** Can't access `https://<instance-ip>:8443`

**Solutions:**
1. Check firewall:
   ```bash
   sudo firewall-cmd --list-ports
   # Should show: 8443/tcp
   ```

2. Check containers running:
   ```bash
   podman ps | grep quay
   ```

3. Check registry logs:
   ```bash
   podman logs $(podman ps | grep quay-app | awk '{print $1}')
   ```

### Certificate Trust Issues

**Problem:** `x509: certificate signed by unknown authority`

**Solution:**
```bash
# Trust the CA certificate
sudo cp /home/ec2-user/mirror-registry/quay-rootCA/rootCA.pem \
  /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust

# Verify
openssl s_client -connect <instance-ip>:8443 -CApath /etc/pki/tls/certs
```

### Login Failures

**Problem:** `podman login` fails

**Solutions:**
1. Verify credentials (default: admin/admin123)
2. Check registry is running
3. Try without TLS verification (testing only):
   ```bash
   podman login --tls-verify=false <instance-ip>:8443
   ```

### Out of Disk Space

**Problem:** Mirror fails with "no space left on device"

**Solutions:**
1. Check available space:
   ```bash
   df -h /home/ec2-user
   ```

2. Move to /storage if needed:
   ```bash
   mkdir -p /storage/mirror-registry
   # Re-run mirror-registry install with new path
   ```

3. Clean up old downloads:
   ```bash
   rm -rf /home/ec2-user/mirror/oc-mirror-workspace/tmp
   ```

### Push Fails

**Problem:** oc-mirror push to registry fails

**Solutions:**
1. Ensure you're logged in:
   ```bash
   podman login <instance-ip>:8443
   ```

2. Verify CA trust is configured

3. Check registry disk space

4. Try pushing a single image manually:
   ```bash
   podman pull registry.access.redhat.com/ubi9/ubi:latest
   podman tag ubi9/ubi:latest <instance-ip>:8443/test/ubi:latest
   podman push <instance-ip>:8443/test/ubi:latest
   ```

## Security Considerations

### Default Password

⚠️ **Change the default password immediately in production!**

Default credentials are:
- Username: `admin`
- Password: `admin123`

Change via:
- Web UI: Account Settings → Change Password
- Or recreate with custom password in install command

### Self-Signed Certificates

The registry uses self-signed certificates by default.

For production:
1. Generate proper certificates from your CA
2. Replace certificates in `/home/ec2-user/mirror-registry/quay-config/`
3. Restart registry

### Network Security

- Registry runs on port 8443 (HTTPS)
- Firewall configured to allow external access
- Consider restricting access to specific IP ranges:
  ```bash
  sudo firewall-cmd --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" port port="8443" protocol="tcp" accept'
  ```

## Performance Tips

### Faster Mirroring

1. **Run on EC2 instance** - Better bandwidth to Red Hat registries
2. **Use tmux** - Detach and let it run
3. **Test with minimal config first** - Verify workflow before full mirror
4. **Use fast storage** - SSD/NVMe preferred

### Registry Performance

1. **Adequate resources** - Ensure enough CPU/RAM for Quay
2. **Fast disk** - Use SSD for registry storage
3. **Monitor containers**:
   ```bash
   podman stats
   ```

## Backup and Recovery

### Backup Registry Data

```bash
# Stop registry
podman stop $(podman ps | grep quay | awk '{print $1}')

# Backup registry directory
tar -czf mirror-registry-backup-$(date +%Y%m%d).tar.gz \
  /home/ec2-user/mirror-registry

# Start registry
podman start $(podman ps -a | grep quay | awk '{print $1}')
```

### Restore Registry

```bash
# Stop registry
podman stop $(podman ps | grep quay | awk '{print $1}')

# Restore from backup
tar -xzf mirror-registry-backup-20260420.tar.gz -C /home/ec2-user/

# Start registry
podman start $(podman ps -a | grep quay | awk '{print $1}')
```

## Additional Resources

- [oc-mirror Documentation](https://docs.openshift.com/container-platform/4.20/installing/disconnected_install/installing-mirroring-disconnected-v2.html)
- [Mirror Registry Documentation](https://docs.openshift.com/container-platform/4.20/installing/disconnected_install/installing-mirroring-creating-registry.html)
- [Red Hat Quay Documentation](https://access.redhat.com/documentation/en-us/red_hat_quay)
- [OC-MIRROR-TIMING.md](OC-MIRROR-TIMING.md) - Download timing and sizing guide

## Summary Checklist

- [ ] Install oc-mirror and mirror-registry
- [ ] Download images with oc-mirror (to disk)
- [ ] Trust registry CA certificate
- [ ] Login to mirror registry
- [ ] Push images from disk to registry
- [ ] Access registry web UI
- [ ] Create ICSP/CatalogSource for cluster
- [ ] Test pulling images from mirror registry
- [ ] Change default password
- [ ] Backup registry configuration
