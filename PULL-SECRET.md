# Red Hat Pull Secret Setup

oc-mirror requires a Red Hat pull secret to authenticate with Red Hat container registries when downloading OpenShift images and operators.

## Getting Your Pull Secret

1. **Log in** to Red Hat Console: https://console.redhat.com/openshift/downloads

2. **Navigate** to the "Downloads" section

3. **Find** "Pull secret" section

4. **Download** the pull secret file

5. **Save** it locally (recommended location: `~/.docker/pull-secret.json`)

## Installing the Pull Secret

### Automatic (Recommended)

The `configure-mirror-registry.yml` playbook automatically copies the pull secret if found locally:

```bash
# Uses default location: ~/.docker/pull-secret.json
ansible-playbook configure-mirror-registry.yml

# Specify custom location
ansible-playbook configure-mirror-registry.yml -e pull_secret_path=~/Downloads/pull-secret.json
```

### Manual Installation

If the playbook couldn't find your pull secret, copy it manually:

```bash
# Get your EC2 instance IP
EC2_IP=$(aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=nested-virt-host" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# Copy to both locations (Docker and Podman use different paths)
scp pull-secret.json ec2-user@${EC2_IP}:~/.docker/config.json
scp pull-secret.json ec2-user@${EC2_IP}:~/.config/containers/auth.json
```

Or directly on the EC2 instance:

```bash
# SSH to instance
ssh ec2-user@<instance-ip>

# Create directories
mkdir -p ~/.docker ~/.config/containers

# Paste your pull secret content
cat > ~/.docker/config.json << 'EOF'
{paste your pull secret JSON here}
EOF

# Copy to podman location
cp ~/.docker/config.json ~/.config/containers/auth.json

# Set permissions
chmod 600 ~/.docker/config.json ~/.config/containers/auth.json
```

## Verifying the Pull Secret

Test authentication to Red Hat registries:

```bash
# SSH to EC2 instance
ssh ec2-user@<instance-ip>

# Test with podman
podman login registry.redhat.io

# Should see: "Login Succeeded!"

# Test pulling an image
podman pull registry.redhat.io/ubi9/ubi:latest
```

## Pull Secret Locations

The pull secret should be installed at both locations:

1. **Docker format:** `/home/ec2-user/.docker/config.json`
   - Used by Docker CLI and some tools
   
2. **Podman format:** `/home/ec2-user/.config/containers/auth.json`
   - Used by Podman, Buildah, Skopeo
   - oc-mirror primarily uses this location

## Troubleshooting

### "unauthorized: authentication required"

This means the pull secret is not found or invalid:

1. Check if pull secret files exist:
   ```bash
   ls -la ~/.docker/config.json ~/.config/containers/auth.json
   ```

2. Verify pull secret content (should be valid JSON):
   ```bash
   cat ~/.docker/config.json | jq .
   ```

3. Check permissions (should be 600):
   ```bash
   ls -la ~/.docker/config.json
   # Should show: -rw------- (600)
   ```

4. Re-download from Red Hat Console if invalid

### "Error: error getting credentials"

The pull secret file may be malformed:

1. Verify it's valid JSON
2. Ensure it contains the `auths` key
3. Re-download from Red Hat Console

### Pull secret expired

Pull secrets don't expire, but your Red Hat account might be deactivated:

1. Log in to https://console.redhat.com
2. Verify your account is active
3. Download a fresh pull secret

## Security Notes

- The pull secret contains authentication tokens - **keep it secure**
- Don't commit it to git repositories
- Set permissions to `600` (owner read/write only)
- Don't share your pull secret with others (they should get their own)

## Format

A valid pull secret looks like this:

```json
{
  "auths": {
    "cloud.openshift.com": {
      "auth": "base64-encoded-credentials",
      "email": "your-email@example.com"
    },
    "quay.io": {
      "auth": "base64-encoded-credentials",
      "email": "your-email@example.com"
    },
    "registry.connect.redhat.com": {
      "auth": "base64-encoded-credentials",
      "email": "your-email@example.com"
    },
    "registry.redhat.io": {
      "auth": "base64-encoded-credentials",
      "email": "your-email@example.com"
    }
  }
}
```

The `auth` values are base64-encoded `username:password` or token strings.
