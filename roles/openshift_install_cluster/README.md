# OpenShift Install Cluster Role

This role performs the actual OpenShift cluster installation by running `openshift-install create cluster` in a tmux session and monitoring the progress until completion.

## Requirements

- The `openshift_install` role must be run first to:
  - Create master VMs
  - Generate install-config.yaml
  - Configure DNS and Redfish BMC
- tmux must be installed on the target host
- openshift-install CLI must be available

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp_install_dir` | `/home/ec2-user/openshift-install` | Installation directory containing install-config.yaml |
| `ocp_tmux_session` | `openshift-install` | Tmux session name for the installation |
| `ocp_install_timeout` | `5400` (90 min) | Maximum time to wait for installation in seconds |
| `ocp_poll_interval` | `30` | Polling interval for checking progress in seconds |
| `ocp_log_tail_lines` | `10` | Number of log lines to display during updates |

## What This Role Does

1. **Pre-flight Checks**
   - Verifies install-config.yaml exists
   - Checks if cluster is already installed

2. **Installation**
   - Starts `openshift-install create cluster` in a tmux session
   - Runs as ec2-user in the installation directory
   - Logs all output to `.openshift_install.log`

3. **Progress Monitoring**
   - Polls the tmux session every 30 seconds
   - Displays recent log entries during each check
   - Continues until installation completes or times out

4. **Post-Installation**
   - Extracts kubeadmin credentials
   - Derives API and console URLs
   - Copies kubeconfig to:
     - `/root/.kube/config` (for root user)
     - `/home/ec2-user/.kube/config` (for ec2-user)
   - Saves credentials to `/home/ec2-user/kubeadmin-password`
   - Creates `/home/ec2-user/openshift-cluster-access.txt` with all info

5. **Verification**
   - Tests `oc` command access
   - Gets cluster version
   - Counts nodes
   - Displays complete access information

## Usage

### Standalone Playbook

```yaml
---
- name: Install OpenShift Cluster
  hosts: nested_virt_hosts
  become: true
  roles:
    - openshift_install_cluster
```

### Combined with Preparation

```yaml
---
- name: Prepare and Install OpenShift
  hosts: nested_virt_hosts
  become: true
  roles:
    - openshift_install      # Prepare environment
    - openshift_install_cluster  # Run installation
```

### Run the Playbook

```bash
ansible-playbook install-openshift-cluster.yml
```

## Expected Duration

The installation typically takes **45-60 minutes** and includes:
- Generating ignition configs (2-3 minutes)
- Booting master nodes via Redfish (5-10 minutes)
- Bootstrapping the cluster (20-30 minutes)
- Finalizing installation (10-15 minutes)

## Output

Upon successful completion, you'll receive:

### Credentials
- **Username**: kubeadmin
- **Password**: Displayed in output and saved to files

### URLs
- **API Server**: `https://api.<cluster>.<domain>:6443`
- **Web Console**: `https://console-openshift-console.apps.<cluster>.<domain>`

### Kubeconfig Locations
- `/root/.kube/config` - Root user
- `/home/ec2-user/.kube/config` - EC2 user
- `/home/ec2-user/openshift-install/auth/kubeconfig` - Original

### Access Information File
`/home/ec2-user/openshift-cluster-access.txt` - Contains all URLs, credentials, and commands

## Monitoring Manually

If you need to check on the installation manually:

```bash
# Attach to the tmux session
tmux attach -t openshift-install

# Detach from tmux: Ctrl+B, then D

# View logs
tail -f /home/ec2-user/openshift-install/.openshift_install.log

# Check cluster status (after installation)
oc get nodes
oc get co  # Cluster operators
```

## Troubleshooting

### Installation Timeout
If the role times out but installation is still running:
1. SSH to the EC2 instance
2. Attach to tmux: `tmux attach -t openshift-install`
3. Wait for completion
4. Re-run the role to configure kubeconfig files

### Installation Failed
Check the logs:
```bash
cat /home/ec2-user/openshift-install/.openshift_install.log
```

Common issues:
- DNS not resolving correctly
- Redfish BMC not accessible
- Network connectivity problems
- Insufficient resources

### Re-running Installation
To start over:
```bash
# Remove the installation directory
rm -rf /home/ec2-user/openshift-install

# Re-run the prepare role
ansible-playbook prepare-openshift.yml

# Run the install role again
ansible-playbook install-openshift-cluster.yml
```

## Files Created

- `/home/ec2-user/openshift-cluster-access.txt` - Access information
- `/home/ec2-user/kubeadmin-password` - Admin password
- `/home/ec2-user/.kube/config` - Kubeconfig for ec2-user
- `/root/.kube/config` - Kubeconfig for root
- `/home/ec2-user/openshift-install/.openshift_install.log` - Installation log
- `/home/ec2-user/openshift-install/auth/` - Original auth files

## Dependencies

This role depends on:
- `openshift_install` role (must run first)
- `configure_dns` role (DNS must be configured)
- Sushy-tools/Redfish BMC running
- libvirt with master VMs created
