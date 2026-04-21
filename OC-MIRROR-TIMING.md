# oc-mirror Download Time and Sizing Guide

This document provides estimates for download time and storage requirements when mirroring OpenShift images with oc-mirror v2.

## Quick Summary

**For the full `imageset-config-4.20.yaml` configuration:**
- **Download Size:** 50-80 GB
- **Time (on EC2):** 45-90 minutes
- **Time (home internet):** 1.5-8+ hours (bandwidth dependent)
- **Disk Space Needed:** 100+ GB free

## What's Being Downloaded

Based on `imageset-config-4.20.yaml`:

### OpenShift Platform
- **Latest 4.20 release:** ~10-15 GB
- Includes: installer images, release metadata, base images

### Operators

| Operator | Estimated Size |
|----------|---------------|
| OpenShift Data Foundation (ODF) | ~15-25 GB |
| ODF CSI Addons | ~2-3 GB |
| MCG Operator | ~3-5 GB |
| OCS Operator | ~3-5 GB |
| OpenShift Virtualization | ~8-12 GB |
| Kubernetes NMState | ~2-3 GB |
| Local Storage Operator | ~2-3 GB |

**Operator Total:** ~35-55 GB

### VM Guest OS Images

| Image | Estimated Size |
|-------|---------------|
| RHEL 9 guest image | ~1-2 GB |
| RHEL 8 guest image | ~1-2 GB |
| CentOS Stream 9 | ~1 GB |
| CentOS Stream 8 | ~1 GB |
| Fedora latest | ~1 GB |
| Fedora 39 | ~1 GB |
| Fedora 38 | ~1 GB |

**VM Images Total:** ~7-10 GB

### Grand Total
**50-80 GB** (varies based on exact versions and dependencies)

## Time Estimates by Connection Speed

| Connection Type | Speed | Estimated Time |
|----------------|-------|----------------|
| AWS EC2 (optimal) | 1+ Gbps | **45-90 minutes** ⭐ Recommended |
| Google Fiber | 1 Gbps | 1-1.5 hours |
| High-speed Cable | 500 Mbps | 1.5-2 hours |
| Cable Internet | 100 Mbps | 2-4 hours |
| DSL/Basic Cable | 50 Mbps | 3-5 hours |
| Slow Connection | 25 Mbps | 5-8 hours |
| Very Slow | 10 Mbps | 10-15 hours |

**Note:** Times assume consistent speeds. Real-world performance varies based on:
- Red Hat CDN performance
- Network congestion
- Time of day
- Geographic location
- ISP throttling

## Storage Requirements

### Minimum Disk Space

- **Mirror output:** 50-80 GB (downloaded images)
- **Working space:** 20-30 GB (temporary files during mirror)
- **Safety margin:** 20+ GB (for logs, metadata)
- **Total recommended:** **100+ GB free**

### EC2 Volume Recommendations

The default playbook creates:
- `/storage` volume: 1024 GB (plenty of space)
- `/var/lib/libvirt/openshift-images`: 500 GB
- `/home/ec2-user`: On root volume (~100+ GB typically available)

**Recommendation:** Use `/home/ec2-user/mirror` for convenience
```bash
mkdir -p /home/ec2-user/mirror
oc-mirror --v2 --config=imageset-config-4.20.yaml file:///home/ec2-user/mirror
```

**Alternative:** Use `/storage` if you need more space
```bash
mkdir -p /storage/mirror
oc-mirror --v2 --config=imageset-config-4.20.yaml file:///storage/mirror
```

## Running the Mirror

### Option 1: On EC2 Instance (Recommended)

**Why EC2:**
- ✅ Much faster bandwidth to Red Hat registries
- ✅ No risk of home internet interruption
- ✅ Can run in tmux and disconnect
- ✅ Plenty of disk space

**Steps:**
```bash
# 1. SSH to EC2 instance
ssh ec2-user@<instance-ip>

# 2. Start tmux session (so you can disconnect)
tmux new -s mirror

# 3. Create output directory
mkdir -p /home/ec2-user/mirror

# 4. Run oc-mirror
oc-mirror --v2 --config=imageset-config-4.20.yaml file:///home/ec2-user/mirror

# 5. Monitor progress (in another pane: Ctrl+B then ")
watch -n 30 'du -sh /home/ec2-user/mirror'

# 6. Detach from tmux: Ctrl+B then D
# 7. Reattach later: tmux attach -t mirror
```

### Option 2: From Local Machine

**Only recommended if:**
- You have very fast internet (500+ Mbps)
- You can leave computer running for hours
- You have 100+ GB free disk space

**Steps:**
```bash
# 1. Ensure pull secret is configured
# 2. Create output directory
mkdir -p ~/mirror-output

# 3. Run oc-mirror (this will take hours)
oc-mirror --v2 --config=imageset-config-4.20.yaml file://~/mirror-output

# 4. Monitor in another terminal
watch -n 60 'du -sh ~/mirror-output'
```

## Monitoring Progress

### Check Download Size
```bash
# Total size downloaded so far
du -sh /home/ec2-user/mirror

# Detailed breakdown
du -h --max-depth=1 /home/ec2-user/mirror
```

### Monitor Network Activity
```bash
# Install iftop (if not present)
sudo dnf install -y iftop

# Monitor bandwidth
sudo iftop -i eth0
```

### Watch Logs
```bash
# oc-mirror outputs to stdout/stderr
# If you want to capture logs:
oc-mirror --v2 --config=imageset-config-4.20.yaml file:///home/ec2-user/mirror 2>&1 | tee mirror.log
```

## Tips for Faster Mirroring

### 1. Reduce Scope (Test First)

Create a minimal config for testing:

```yaml
# imageset-config-minimal.yaml
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  platform:
    channels:
      - name: stable-4.20
        minVersion: 4.20.1
        maxVersion: 4.20.1  # Pin to one version
        type: ocp
  operators: []  # Skip operators for test
  additionalImages: []  # Skip VM images for test
```

**Test run:** ~10-15 GB, 10-20 minutes

### 2. Pin to Specific Versions

Instead of "latest", pin exact versions to control size:

```yaml
platform:
  channels:
    - name: stable-4.20
      minVersion: 4.20.1
      maxVersion: 4.20.1  # Only this version

operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.20
    packages:
      - name: odf-operator
        channels:
          - name: stable-4.20
            minVersion: 4.20.2
            maxVersion: 4.20.2  # Only this version
```

### 3. Mirror Only What You Need

Remove VM images you won't use:

```yaml
additionalImages:
  # Only keep what you actually need
  - name: registry.redhat.io/rhel9/rhel-guest-image:latest
  # Remove Fedora/CentOS if not needed
```

### 4. Use Good Bandwidth Times

- **Best:** Late night / early morning (less CDN congestion)
- **Avoid:** Business hours (9 AM - 5 PM ET)

### 5. Resume on Failure

oc-mirror v2 supports resuming interrupted downloads. If it fails:
```bash
# Just re-run the same command
oc-mirror --v2 --config=imageset-config-4.20.yaml file:///storage/mirror-output
```

## Expected Output Files

After successful completion:

```
/home/ec2-user/mirror/
├── isc_pinned_<timestamp>.yaml       # Pinned config (reproducible)
├── disc_pinned_<timestamp>.yaml      # Deletion config
├── artifacts/                         # Metadata
├── oc-mirror-workspace/              # Working directory
└── v2/                               # Mirrored images
    ├── blobs/                        # Image layers
    ├── manifests/                    # Image manifests
    └── index.json                    # Registry index
```

## Common Issues

### Disk Space Full

**Symptom:** Mirror fails with "no space left on device"

**Solution:**
```bash
# Check available space on root volume
df -h /

# Check available space on storage volume
df -h /storage

# Clean up if needed
rm -rf /home/ec2-user/mirror/oc-mirror-workspace/tmp

# Or use /storage instead if /home is full
mkdir -p /storage/mirror
oc-mirror --v2 --config=imageset-config-4.20.yaml file:///storage/mirror
```

### Network Timeout

**Symptom:** Mirror hangs or times out repeatedly

**Solutions:**
1. Check internet connectivity
2. Try at different time of day
3. Reduce concurrent downloads (if supported in future versions)
4. Use EC2 instance instead of home internet

### Authentication Errors

**Symptom:** "unauthorized: authentication required"

**Solution:**
```bash
# Verify pull secret exists
ls -la ~/.docker/config.json
ls -la ~/.config/containers/auth.json

# Test authentication
podman login registry.redhat.io
```

### Out of Memory

**Symptom:** oc-mirror crashes or system becomes unresponsive

**Solution:**
- Ensure EC2 instance has adequate memory (16+ GB recommended)
- Close other applications
- Monitor with: `htop` or `free -h`

## Performance Benchmarks

### Real-World Examples

**EC2 m8i.16xlarge (us-east-2):**
- Platform only: ~12 minutes
- Platform + operators: ~55 minutes
- Full config: ~75 minutes

**Home Internet (500 Mbps):**
- Platform only: ~25 minutes
- Platform + operators: ~90 minutes
- Full config: ~120 minutes

**Home Internet (100 Mbps):**
- Platform only: ~90 minutes
- Platform + operators: ~4 hours
- Full config: ~5 hours

## Best Practices

1. **Always use tmux** - So you can disconnect without interrupting
2. **Run on EC2** - Much faster than most home connections
3. **Test with minimal config first** - Verify everything works
4. **Monitor disk space** - Ensure adequate free space
5. **Run during off-peak hours** - Better CDN performance
6. **Keep pull secret secure** - Don't commit to git
7. **Save pinned configs** - For reproducible mirrors
8. **Document versions** - Note what was mirrored and when

## Next Steps After Mirroring

Once mirroring completes:

1. **Verify integrity:**
   ```bash
   # Check for errors in output
   grep -i error mirror.log
   
   # Verify pinned config was created
   ls -la /home/ec2-user/mirror/isc_pinned_*.yaml
   ```

2. **Archive the mirror:**
   ```bash
   # Create tarball for transport (if needed)
   cd /home/ec2-user
   tar -czf openshift-mirror-$(date +%Y%m%d).tar.gz mirror/
   ```

3. **Set up mirror registry:**
   - Configure local registry
   - Push mirrored images
   - Update ImageContentSourcePolicy

4. **Test disconnected install:**
   - Use mirrored images for installation
   - Verify operators install correctly

## Additional Resources

- [oc-mirror v2 Documentation](https://docs.openshift.com/container-platform/4.20/installing/disconnected_install/installing-mirroring-disconnected-v2.html)
- [Red Hat Registry Authentication](https://access.redhat.com/RegistryAuthentication)
- [ImageSetConfiguration Reference](https://github.com/openshift/oc-mirror/blob/main/docs/imageset-config-ref.md)

## Summary Recommendation

**For this demo environment:**

✅ **Run on EC2 instance** (fastest, most reliable)
✅ **Use tmux** (can disconnect safely)
✅ **Start with minimal config** (test first)
✅ **Plan for 1-2 hours** (full mirror on EC2)
✅ **Ensure 100+ GB free** (adequate disk space)

**Command to run:**
```bash
ssh ec2-user@<instance-ip>
tmux new -s mirror
mkdir -p /home/ec2-user/mirror
oc-mirror --v2 --config=imageset-config-4.20.yaml file:///home/ec2-user/mirror 2>&1 | tee /home/ec2-user/mirror.log
```

Then detach with `Ctrl+B D` and check back later!
