# Configure Mirror Registry Role

This Ansible role downloads and installs the oc-mirror v2 tool for mirroring OpenShift Container Platform images and operators to disconnected environments.

## Description

The role:
- Downloads oc-mirror v2 from the official OpenShift mirror site
- Extracts and installs it to `/usr/local/bin/oc-mirror`
- Configures PATH for the ec2-user
- Verifies the installation

## Requirements

- Internet connectivity to download from mirror.openshift.com
- sudo/root privileges (to install to /usr/local/bin)
- **Red Hat pull secret** - Required for authenticating to Red Hat registries
  - Download from: https://console.redhat.com/openshift/downloads
  - Save as `pullsecret.json` in the playbook directory

## Pull Secret Setup

The role automatically copies your pull secret from the playbook directory to the EC2 instance.

**Required location:** `pullsecret.json` (in the same directory as the playbook)

**Steps:**
1. Download from https://console.redhat.com/openshift/downloads
2. Save it as `pullsecret.json` in the repository root directory
3. Run the playbook

The pull secret is copied to:
- `/home/ec2-user/.docker/config.json` (Docker/Podman standard location)
- `/home/ec2-user/.config/containers/auth.json` (Podman XDG location)

If the pull secret is not found, the playbook will fail with instructions.

## Dependencies

None

## Example Usage

### Standalone Playbook

```bash
ansible-playbook configure-mirror-registry.yml
```

### In Main Playbook

```yaml
- name: Configure mirror registry tools
  hosts: nested_virt_hosts
  become: true
  
  roles:
    - configure_mirror_registry
```

### Manual Role Invocation

```yaml
- hosts: servers
  become: true
  roles:
    - role: configure_mirror_registry
```

## What Gets Installed

- **oc-mirror** - Latest version from OpenShift 4.20 release channel
  - Location: `/usr/local/bin/oc-mirror`
- **podman** - Container runtime for pulling/pushing images
- **skopeo** - Container image manipulation tool
- **Pull secret** - Red Hat registry authentication
  - `/home/ec2-user/.docker/config.json`
  - `/home/ec2-user/.config/containers/auth.json`

## After Installation

Once installed, you can use oc-mirror v2 with your ImageSetConfiguration:

```bash
# Mirror OpenShift images and operators (note: --v2 flag required)
mkdir -p /home/ec2-user/mirror
oc-mirror --v2 --config=imageset-config-4.20.yaml file:///home/ec2-user/mirror

# Check version
oc-mirror version

# View help
oc-mirror --help

# View v2-specific help
oc-mirror --v2 --help
```

**Important:** The `--v2` flag is required to use oc-mirror v2 features and the v2alpha1 ImageSetConfiguration format. Without this flag, oc-mirror runs in v1 compatibility mode.

## Before Mirroring - Read This!

⚠️ **Mirroring takes significant time and bandwidth!**

**Expected for full `imageset-config-4.20.yaml`:**
- Download size: 50-80 GB
- Time on EC2: 45-90 minutes
- Time on home internet: 1.5-8+ hours
- Disk space needed: 100+ GB free

**See [OC-MIRROR-TIMING.md](../OC-MIRROR-TIMING.md) for:**
- Detailed size breakdowns
- Time estimates by connection speed
- Best practices and tips
- How to reduce download size
- Monitoring and troubleshooting

**Test first with minimal config:**
```bash
mkdir -p /home/ec2-user/mirror-test
oc-mirror --v2 --config=imageset-config-minimal.yaml file:///home/ec2-user/mirror-test
# Only ~10-15 GB, 10-20 minutes
```

## ImageSetConfiguration

The repository includes a sample configuration file `imageset-config-4.20.yaml` that mirrors:
- OpenShift 4.20 (latest stable release)
- OpenShift Data Foundation operators
- OpenShift Virtualization operators
- Local Storage operator
- VM guest OS images (RHEL, CentOS, Fedora)

## Variables

None - the role expects `pullsecret.json` in the playbook directory and uses hardcoded paths for the latest 4.20 release.

## License

MIT

## Author

Created for OpenShift IPI baremetal demo environment
