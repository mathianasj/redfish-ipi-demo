# AWS Instance Types Supporting Nested Virtualization

This document lists AWS instance types that support nested virtualization using the newer Nitro hypervisor capabilities (no bare metal required).

## Recommended Instance Types (Best Value)

### General Purpose - M8i Family (8th Gen Intel - Granite Rapids)

| Instance Type | vCPUs | Cores | Memory | Price/Hour (us-east-1) | Best For |
|--------------|-------|-------|---------|------------------------|----------|
| m8i.large | 2 | 1 | 8 GB | ~$0.22 | Testing, small VMs |
| m8i.xlarge | 4 | 2 | 16 GB | $0.44 | Development, 2-3 VMs |
| m8i.2xlarge | 8 | 4 | 32 GB | $0.88 | Production, 4-6 VMs |
| m8i.4xlarge | 16 | 8 | 64 GB | $1.77 | Multiple VMs |
| m8i.8xlarge | 32 | 16 | 128 GB | $3.53 | Heavy workloads |
| m8i.16xlarge | 64 | 32 | 256 GB | $7.06 | Very heavy workloads |

### General Purpose - M7i Family (7th Gen Intel)
| Instance Type | vCPUs | Cores | Memory | Price/Hour (us-east-1) | Best For |
|--------------|-------|-------|---------|------------------------|----------|
| m7i.large | 2 | 1 | 8 GB | ~$0.20 | Testing, small VMs |
| m7i.xlarge | 4 | 2 | 16 GB | $0.40 | Development, 2-3 VMs |
| m7i.2xlarge | 8 | 4 | 32 GB | $0.80 | Production, 4-6 VMs |
| m7i.4xlarge | 16 | 8 | 64 GB | $1.61 | Multiple VMs |
| m7i.8xlarge | 32 | 16 | 128 GB | $3.22 | Heavy workloads |

### General Purpose - M6i Family (6th Gen Intel)
| Instance Type | vCPUs | Memory | Price/Hour (us-east-1) | Best For |
|--------------|-------|---------|------------------------|----------|
| m6i.large | 2 | 8 GB | ~$0.19 | Testing, small VMs |
| m6i.xlarge | 4 | 16 GB | $0.38 | Development, 2-3 VMs |
| m6i.2xlarge | 8 | 32 GB | $0.77 | Production, 4-6 VMs |
| m6i.4xlarge | 16 | 64 GB | $1.54 | Multiple VMs |

### Compute Optimized - C7i Family (7th Gen Intel)
| Instance Type | vCPUs | Memory | Price/Hour (us-east-1) | Best For |
|--------------|-------|---------|------------------------|----------|
| c7i.large | 2 | 4 GB | ~$0.18 | CPU-intensive VMs |
| c7i.xlarge | 4 | 8 GB | $0.36 | Compute workloads |
| c7i.2xlarge | 8 | 16 GB | $0.71 | High CPU needs |
| c7i.4xlarge | 16 | 32 GB | $1.43 | Heavy compute |

### AMD-Based - M7a Family (7th Gen AMD)
| Instance Type | vCPUs | Memory | Price/Hour (us-east-1) | Best For |
|--------------|-------|---------|------------------------|----------|
| m7a.large | 2 | 8 GB | ~$0.17 | Cost-effective testing |
| m7a.xlarge | 4 | 16 GB | $0.35 | Budget-friendly dev |
| m7a.2xlarge | 8 | 32 GB | $0.69 | Lower cost production |

## Memory Optimized Instances

### R7i Family (7th Gen Intel)
| Instance Type | vCPUs | Memory | Price/Hour (us-east-1) | Best For |
|--------------|-------|---------|------------------------|----------|
| r7i.large | 2 | 16 GB | ~$0.25 | Memory-intensive VMs |
| r7i.xlarge | 4 | 32 GB | $0.50 | Database VMs |
| r7i.2xlarge | 8 | 64 GB | $1.01 | Large databases |
| r7i.4xlarge | 16 | 128 GB | $2.02 | Memory-heavy workloads |

## Cost Comparison

### Monthly Costs (24/7 on-demand, us-east-1)
- **m7i.large**: ~$144/month (2 vCPU, 8 GB)
- **m7i.xlarge**: ~$288/month (4 vCPU, 16 GB)
- **m7i.2xlarge**: ~$576/month (8 vCPU, 32 GB) ⭐ **Default/Recommended**
- **m6i.2xlarge**: ~$554/month (8 vCPU, 32 GB)
- **m5.metal**: ~$3,312/month (96 vCPU, 384 GB)

### Savings Options
1. **Spot Instances**: 60-90% discount (may be interrupted)
   - Example: m7i.2xlarge spot: ~$0.24/hour (~$173/month)
   
2. **Reserved Instances** (1-year):
   - 30-40% discount with upfront payment
   - Example: m7i.2xlarge RI: ~$0.48/hour (~$346/month)

3. **Savings Plans** (1-year):
   - Flexible compute savings: 20-30% discount
   - More flexibility than Reserved Instances

## How to Enable Nested Virtualization

These instance types **automatically support** nested virtualization on AWS with no special configuration needed. The playbook will:
1. Launch the instance
2. Install KVM/QEMU
3. Verify nested virtualization is enabled
4. Configure libvirt for VM management

## Verification

After launching an instance, verify nested virtualization is enabled:

```bash
# For Intel CPUs
cat /sys/module/kvm_intel/parameters/nested
# Should return: Y or 1

# For AMD CPUs  
cat /sys/module/kvm_amd/parameters/nested
# Should return: 1

# Check CPU flags
grep -E 'vmx|svm' /proc/cpuinfo
```

## Choosing the Right Instance Type

### For Testing/Learning:
- **m7i.large** or **m7a.large**: Lowest cost, good for 1-2 small VMs

### For Development:
- **m7i.xlarge** or **m6i.xlarge**: Good balance for 2-4 VMs

### For Production:
- **m7i.2xlarge** or **m6i.2xlarge**: Recommended default, handles 4-8 VMs

### For Compute-Intensive VMs:
- **c7i.2xlarge** or **c7i.4xlarge**: More CPU, less memory

### For Memory-Intensive VMs:
- **r7i.2xlarge** or **r7i.4xlarge**: More memory per vCPU

### For Budget Constraints:
- **m7a.*** (AMD-based): 10-15% cheaper than Intel equivalents
- **Spot Instances**: Use for non-critical workloads

## Regional Availability

Not all instance types are available in all regions. Check availability:

```bash
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters Name=instance-type,Values=m7i.2xlarge \
  --region us-east-1
```

## Additional Resources

- [AWS Nested Virtualization Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html)
- [AWS Pricing Calculator](https://calculator.aws/)
- [AWS Instance Type Explorer](https://aws.amazon.com/ec2/instance-types/)
