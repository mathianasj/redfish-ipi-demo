# Documentation Index

Complete documentation for the OpenShift IPI Baremetal Demo with Redfish on AWS EC2.

## Quick Navigation

### 🚀 New Users Start Here

1. **[Quick Start Guide](getting-started/QUICK_START.md)** - Get up and running fast
2. **[Instance Types](infrastructure/INSTANCE_TYPES.md)** - Choose your AWS instance
3. **[Complete Deployment](openshift/COMPLETE_DEPLOYMENT.md)** - Full deployment walkthrough

### 📋 By Topic

#### Getting Started
| Document | Description |
|----------|-------------|
| [Quick Start](getting-started/QUICK_START.md) | Fast deployment walkthrough |
| [Quick Reference](getting-started/QUICK_REFERENCE.md) | Common commands and operations |

#### Infrastructure Setup
| Document | Description |
|----------|-------------|
| [Instance Types](infrastructure/INSTANCE_TYPES.md) | AWS instance comparison and recommendations |
| [RHEL Setup](infrastructure/RHEL_SETUP.md) | RHEL 9 configuration and preparation |
| [Networking](infrastructure/NETWORKING.md) | Network architecture and configuration |
| [DNS Setup](infrastructure/DNS_SETUP.md) | DNS configuration for OpenShift |
| [Cleanup](infrastructure/CLEANUP.md) | Resource deletion and teardown |
| [Instance Management](infrastructure/INSTANCE-MANAGEMENT-README.md) | EC2 instance lifecycle management |

#### OpenShift Deployment
| Document | Description |
|----------|-------------|
| [Complete Deployment](openshift/COMPLETE_DEPLOYMENT.md) | End-to-end deployment workflow |
| [install-config.yaml Guide](openshift/INSTALL-CONFIG-GUIDE.md) | **NEW** - Field reference and configuration examples |
| [Redfish/BMC Guide](openshift/SUSHY_REDFISH.md) | Redfish API integration and usage |
| [Pull Secret Setup](openshift/PULL-SECRET.md) | Red Hat pull secret configuration |

#### Disconnected/Air-Gapped Environments
| Document | Description |
|----------|-------------|
| [Mirror Registry Guide](disconnected/MIRROR-REGISTRY-GUIDE.md) | Complete mirror registry setup and workflow |
| [Mirror Timing & Sizing](disconnected/OC-MIRROR-TIMING.md) | Download estimates and best practices |

#### Troubleshooting
| Document | Description |
|----------|-------------|
| [KVM Nested Virtualization Fix](troubleshooting/KVM_NESTED_VIRT_FIX.md) | Resolve nested virt issues |
| [VM Paused Troubleshooting](troubleshooting/VM_PAUSED_TROUBLESHOOTING.md) | Fix VM stability problems |
| [CPU Options](troubleshooting/CPU_OPTIONS.md) | CPU configuration and tuning |
| [KVM Error Prevention](troubleshooting/KVM_ERROR_PREVENTION.md) | Prevent common KVM errors |
| [Nested Virt Detection](troubleshooting/NESTED-VIRT-DETECTION.md) | Verify nested virtualization support |
| [Memory Changes Revert](troubleshooting/REVERT_MEMORY_CHANGES.md) | Undo memory configuration changes |

#### Advanced Topics
| Document | Description |
|----------|-------------|
| [VNC Access Guide](advanced/VNC_ACCESS_GUIDE.md) | Remote desktop and console access |
| [VyOS VM Guide](advanced/VYOS_VM_GUIDE.md) | VyOS router deployment and configuration |
| [Dynamic Inventory](advanced/README-INVENTORY.md) | Ansible dynamic inventory for EC2 |

## Common Workflows

### First-Time Setup
1. [Quick Start](getting-started/QUICK_START.md) - Overview
2. [Instance Types](infrastructure/INSTANCE_TYPES.md) - Choose EC2 instance
3. [Complete Deployment](openshift/COMPLETE_DEPLOYMENT.md) - Run deployment
4. [VNC Access](advanced/VNC_ACCESS_GUIDE.md) - Access consoles

### OpenShift Installation
1. [Pull Secret Setup](openshift/PULL-SECRET.md) - Get Red Hat credentials
2. [install-config.yaml Guide](openshift/INSTALL-CONFIG-GUIDE.md) - Configure installation
3. [Complete Deployment](openshift/COMPLETE_DEPLOYMENT.md) - Execute installation

### Disconnected Environment
1. [Mirror Registry Guide](disconnected/MIRROR-REGISTRY-GUIDE.md) - Setup registry
2. [Mirror Timing](disconnected/OC-MIRROR-TIMING.md) - Plan mirror download
3. [install-config.yaml Guide](openshift/INSTALL-CONFIG-GUIDE.md#disconnectedmirrored-environment) - Configure for disconnected
4. [Pull Secret Setup](openshift/PULL-SECRET.md) - Add mirror registry auth

### Troubleshooting Common Issues
- **VM won't start**: [KVM Nested Virt Fix](troubleshooting/KVM_NESTED_VIRT_FIX.md)
- **VM keeps pausing**: [VM Paused Troubleshooting](troubleshooting/VM_PAUSED_TROUBLESHOOTING.md)
- **CPU errors**: [CPU Options](troubleshooting/CPU_OPTIONS.md)
- **Can't access console**: [VNC Access Guide](advanced/VNC_ACCESS_GUIDE.md)

### Cleanup and Management
- **Delete resources**: [Cleanup Guide](infrastructure/CLEANUP.md)
- **Manage instance**: [Instance Management](infrastructure/INSTANCE-MANAGEMENT-README.md)

## Quick Reference Cards

### Essential Commands
See [Quick Reference](getting-started/QUICK_REFERENCE.md) for comprehensive command list.

### Network Configuration
See [Networking Guide](infrastructure/NETWORKING.md) for network architecture.

### Redfish API
See [Redfish/BMC Guide](openshift/SUSHY_REDFISH.md) for API examples.

## Documentation Structure

```
docs/
├── README.md (this file)
├── getting-started/      # First-time user guides
├── infrastructure/       # AWS and system setup
├── openshift/           # OpenShift deployment
├── disconnected/        # Air-gapped environments
├── troubleshooting/     # Problem resolution
└── advanced/            # Advanced configurations
```

## Contributing to Documentation

When adding new documentation:

1. **Place in appropriate category**:
   - Getting started guides → `getting-started/`
   - AWS/infrastructure setup → `infrastructure/`
   - OpenShift-specific → `openshift/`
   - Disconnected/mirror → `disconnected/`
   - Problem fixes → `troubleshooting/`
   - Advanced features → `advanced/`

2. **Update this index** with new document

3. **Link from main README** if relevant to quick start

4. **Use consistent formatting**:
   - Clear headings
   - Code blocks with syntax highlighting
   - Step-by-step instructions
   - Example outputs

## Need Help?

- **General questions**: Start with [Quick Start](getting-started/QUICK_START.md)
- **Installation issues**: Check [Troubleshooting](#troubleshooting-common-issues)
- **Configuration questions**: See [install-config.yaml Guide](openshift/INSTALL-CONFIG-GUIDE.md)
- **Feature requests/bugs**: https://github.com/mathianasj/redfish-ipi-demo/issues
