# Display Cluster Access Role

This Ansible role retrieves and displays EC2 instance connection information and OpenShift cluster access details (if installed).

## Description

The role:
- **Always displays:**
  - EC2 instance public IP
  - SSH access command
  - Cockpit web console (if running)
  - Redfish API (Sushy emulator, if running)
  - noVNC web GUI (if configured)
  - VM management commands

- **Optionally displays (if OpenShift is installed):**
  - Cluster name, version, node count
  - API server and console URLs
  - kubeadmin credentials
  - Kubeconfig locations
  - Quick oc commands

## Requirements

- EC2 instance must be running
- OpenShift cluster installation is **optional**
- If OpenShift is installed, `oc` CLI should be available

## Dependencies

None

## Example Usage

### Standalone Playbook

```bash
ansible-playbook show-cluster-access.yml
```

### In Main Playbook

```yaml
- name: Show cluster access info
  hosts: nested_virt_hosts
  become: true
  
  roles:
    - display_cluster_access
```

## What Gets Displayed

### Always Displayed (Instance Connection Info)

- **EC2 Instance**
  - Public IP address
  - SSH access command

- **Web Consoles** (if services are running)
  - Cockpit (https://IP:9090)
  - noVNC HTTP (http://IP:6080)
  - noVNC HTTPS (https://IP:6081)

- **APIs**
  - Redfish/Sushy emulator (http://IP:8000)

- **VM Management**
  - virsh commands
  - VNC console access

### Optionally Displayed (Only if OpenShift is Installed)

- **Cluster Information**
  - Name, version, node count
  - Degraded operator count

- **Access URLs**
  - API Server URL
  - Web Console URL

- **Credentials**
  - kubeadmin username and password
  - File locations

- **Kubeconfig Locations**
  - Root user, EC2 user, original paths

- **Quick Commands**
  - oc commands
  - Web console login steps

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp_install_dir` | `/home/ec2-user/ocp-install` | OpenShift installation directory |

## When to Use

Use this playbook when you need to:
- Get SSH access to the EC2 instance
- Find Cockpit or noVNC URLs
- Retrieve OpenShift cluster credentials (if installed)
- Share access information with team members
- Verify what services are running
- Get console URLs and passwords
- Check cluster status quickly

## Troubleshooting

### OpenShift Shows "NOT installed yet"

This is normal if you haven't installed OpenShift. The playbook will still show instance connection details.

To install OpenShift:
```bash
ansible-playbook playbook.yml -e install_openshift=true
```

### No Cockpit or noVNC URLs Shown

These services are optional. If not shown, the services aren't running.

- Cockpit is installed by default in the main playbook
- noVNC requires running: `ansible-playbook setup-vnc-gui.yml`

### "Unable to fetch - cluster may still be installing"

The cluster is still installing. Wait a few minutes and try again.

### "Degraded Operators: X"

Some cluster operators are not healthy. Check with:
```bash
ssh ec2-user@<instance-ip>
oc get co
```

## Output Examples

### Example 1: OpenShift Not Installed Yet

```
==========================================
EC2 Instance Connection Information
==========================================

Instance IP: 3.144.254.35

SSH Access:
  ssh ec2-user@3.144.254.35

Cockpit Web Console:
  URL: https://3.144.254.35:9090
  Username: admin (or ec2-user)
  Note: Accept self-signed certificate warning

Redfish API (Sushy Emulator):
  URL: http://3.144.254.35:8000/redfish/v1/
  Systems: http://3.144.254.35:8000/redfish/v1/Systems

VM Management:
  List VMs: ssh ec2-user@3.144.254.35 'sudo virsh list --all'
  VNC Console: VMs accessible via noVNC (if configured)

==========================================

==========================================
OpenShift Status
==========================================

✗ OpenShift cluster is NOT installed yet

To install OpenShift:
  ansible-playbook playbook.yml -e install_openshift=true

Or check installation status:
  ssh ec2-user@3.144.254.35
  cat ~/ocp-install/.openshift_install.log

==========================================
```

### Example 2: OpenShift Installed

```
==========================================
EC2 Instance Connection Information
==========================================

Instance IP: 3.144.254.35

SSH Access:
  ssh ec2-user@3.144.254.35

Cockpit Web Console:
  URL: https://3.144.254.35:9090
  Username: admin (or ec2-user)
  Note: Accept self-signed certificate warning

Redfish API (Sushy Emulator):
  URL: http://3.144.254.35:8000/redfish/v1/
  Systems: http://3.144.254.35:8000/redfish/v1/Systems

noVNC Web GUI (HTTPS):
  URL: https://3.144.254.35:6081/vnc.html
  Note: Accept self-signed certificate warning

VM Management:
  List VMs: ssh ec2-user@3.144.254.35 'sudo virsh list --all'
  VNC Console: VMs accessible via noVNC (if configured)

==========================================

==========================================
OpenShift Cluster Access Information
==========================================

Cluster Information:
  Name: ocp
  Version: 4.20.1
  Nodes: 3
  Degraded Operators: 0

Access URLs:
  API Server: https://api.ocp.example.com:6443
  Web Console: https://console-openshift-console.apps.ocp.example.com

Credentials:
  Username: kubeadmin
  Password: XXXXX-XXXXX-XXXXX-XXXXX
  (Also saved to: /home/ec2-user/kubeadmin-password)

Kubeconfig Location:
  Root user: /root/.kube/config
  EC2 user: /home/ec2-user/.kube/config
  Original: /home/ec2-user/ocp-install/auth/kubeconfig

Command Line Access:
  SSH to instance: ssh ec2-user@3.144.254.35
  Run oc commands: oc get nodes
  Check cluster: oc get clusterversion
  View all resources: oc get all -A
  Check operators: oc get co

Web Console Access:
  1. Open browser to: https://console-openshift-console.apps.ocp.example.com
  2. Login with username: kubeadmin
  3. Login with password: XXXXX-XXXXX-XXXXX-XXXXX

Saved Access Information:
  File: /home/ec2-user/openshift-cluster-access.txt
  View: ssh ec2-user@3.144.254.35 'cat ~/openshift-cluster-access.txt'

==========================================
```

## License

MIT

## Author

Created for OpenShift IPI baremetal demo environment
