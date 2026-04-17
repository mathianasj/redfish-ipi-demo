# CPU Options for EC2 Instance Types

This document provides CPU configuration options for different EC2 instance types to optimize nested virtualization.

## What are CPU Options?

CPU options allow you to specify:
- **Core Count**: Number of CPU cores to activate
- **Threads Per Core**: 1 (disable hyperthreading) or 2 (enable hyperthreading)

For nested virtualization, **hyperthreading should be enabled** (`threads_per_core: 2`) to provide better performance for guest VMs.

## CPU Options by Instance Type

### M8i Family (8th Gen Intel - Granite Rapids)

| Instance Type | Default vCPUs | Core Count | Threads Per Core | Total vCPUs |
|--------------|---------------|------------|------------------|-------------|
| m8i.large | 2 | 1 | 2 | 2 |
| m8i.xlarge | 4 | 2 | 2 | 4 |
| m8i.2xlarge | 8 | 4 | 2 | 8 |
| m8i.4xlarge | 16 | 8 | 2 | 16 |
| m8i.8xlarge | 32 | 16 | 2 | 32 |
| m8i.16xlarge | 64 | 32 | 2 | 64 |
| m8i.24xlarge | 96 | 48 | 2 | 96 |
| m8i.32xlarge | 128 | 64 | 2 | 128 |

### M7i Family (7th Gen Intel - Sapphire Rapids)

| Instance Type | Default vCPUs | Core Count | Threads Per Core | Total vCPUs |
|--------------|---------------|------------|------------------|-------------|
| m7i.large | 2 | 1 | 2 | 2 |
| m7i.xlarge | 4 | 2 | 2 | 4 |
| m7i.2xlarge | 8 | 4 | 2 | 8 |
| m7i.4xlarge | 16 | 8 | 2 | 16 |
| m7i.8xlarge | 32 | 16 | 2 | 32 |
| m7i.16xlarge | 64 | 32 | 2 | 64 |
| m7i.24xlarge | 96 | 48 | 2 | 96 |

### M6i Family (6th Gen Intel - Ice Lake)

| Instance Type | Default vCPUs | Core Count | Threads Per Core | Total vCPUs |
|--------------|---------------|------------|------------------|-------------|
| m6i.large | 2 | 1 | 2 | 2 |
| m6i.xlarge | 4 | 2 | 2 | 4 |
| m6i.2xlarge | 8 | 4 | 2 | 8 |
| m6i.4xlarge | 16 | 8 | 2 | 16 |
| m6i.8xlarge | 32 | 16 | 2 | 32 |
| m6i.16xlarge | 64 | 32 | 2 | 64 |

### C7i Family (7th Gen Intel Compute Optimized)

| Instance Type | Default vCPUs | Core Count | Threads Per Core | Total vCPUs |
|--------------|---------------|------------|------------------|-------------|
| c7i.large | 2 | 1 | 2 | 2 |
| c7i.xlarge | 4 | 2 | 2 | 4 |
| c7i.2xlarge | 8 | 4 | 2 | 8 |
| c7i.4xlarge | 16 | 8 | 2 | 16 |
| c7i.8xlarge | 32 | 16 | 2 | 32 |
| c7i.16xlarge | 64 | 32 | 2 | 64 |

### R7i Family (7th Gen Intel Memory Optimized)

| Instance Type | Default vCPUs | Core Count | Threads Per Core | Total vCPUs |
|--------------|---------------|------------|------------------|-------------|
| r7i.large | 2 | 1 | 2 | 2 |
| r7i.xlarge | 4 | 2 | 2 | 4 |
| r7i.2xlarge | 8 | 4 | 2 | 8 |
| r7i.4xlarge | 16 | 8 | 2 | 16 |
| r7i.8xlarge | 32 | 16 | 2 | 32 |
| r7i.16xlarge | 64 | 32 | 2 | 64 |

## Configuration in Playbook

### Update `group_vars/all.yml`

```yaml
# For m8i.16xlarge
instance_type: m8i.16xlarge
cpu_core_count: 32
cpu_threads_per_core: 2

# For m7i.2xlarge
instance_type: m7i.2xlarge
cpu_core_count: 4
cpu_threads_per_core: 2

# For m6i.4xlarge
instance_type: m6i.4xlarge
cpu_core_count: 8
cpu_threads_per_core: 2
```

### Playbook Implementation

The playbook automatically uses these values:

```yaml
cpu_options:
  core_count: "{{ cpu_core_count }}"
  threads_per_core: "{{ cpu_threads_per_core }}"
```

## Nested Virtualization Requirements

For optimal nested virtualization:

1. **Enable Hyperthreading**: Always use `threads_per_core: 2`
2. **Use Full Core Count**: Don't reduce cores unless needed for cost optimization
3. **Verify CPU Flags**: After instance launch, verify VMX/SVM flags are present

### Verification Commands

After the instance is running:

```bash
# Check for Intel VT-x (vmx) or AMD-V (svm)
grep -E '(vmx|svm)' /proc/cpuinfo

# Check CPU topology
lscpu

# Verify nested virtualization is enabled
cat /sys/module/kvm_intel/parameters/nested  # Intel
cat /sys/module/kvm_amd/parameters/nested     # AMD
```

## Custom CPU Configurations

### Disable Hyperthreading (Not Recommended for Nested Virt)

```yaml
cpu_core_count: 32
cpu_threads_per_core: 1  # Disables hyperthreading
# Results in 32 vCPUs instead of 64
```

### Reduce Core Count (Cost Optimization)

You can reduce the number of cores to lower costs:

```yaml
# m8i.16xlarge normally has 32 cores
instance_type: m8i.16xlarge
cpu_core_count: 16  # Use only 16 cores
cpu_threads_per_core: 2
# Results in 32 vCPUs instead of 64
```

**Note**: Reducing cores may reduce performance but also reduces costs proportionally in some cases.

## Performance Considerations

### Best Performance
- **Hyperthreading Enabled**: `threads_per_core: 2`
- **Full Core Count**: Use all available cores
- **Example**: m8i.16xlarge with 32 cores, 2 threads = 64 vCPUs

### Balanced Performance/Cost
- **Hyperthreading Enabled**: `threads_per_core: 2`
- **Reduced Core Count**: Use 50-75% of cores
- **Example**: m8i.16xlarge with 20 cores, 2 threads = 40 vCPUs

### Maximum Density (Not Recommended)
- **Hyperthreading Disabled**: `threads_per_core: 1`
- **Full Core Count**: Use all cores
- **Example**: m8i.16xlarge with 32 cores, 1 thread = 32 vCPUs
- **Note**: Lower performance for virtualization workloads

## AMD Instances (M7a, C7a, R7a)

AMD instances work similarly but use AMD-V (SVM) instead of Intel VT-x (VMX):

### M7a Family (7th Gen AMD - Genoa)

| Instance Type | Default vCPUs | Core Count | Threads Per Core |
|--------------|---------------|------------|------------------|
| m7a.large | 2 | 1 | 2 |
| m7a.xlarge | 4 | 2 | 2 |
| m7a.2xlarge | 8 | 4 | 2 |
| m7a.4xlarge | 16 | 8 | 2 |
| m7a.8xlarge | 32 | 16 | 2 |
| m7a.16xlarge | 64 | 32 | 2 |

Configuration is the same:
```yaml
instance_type: m7a.16xlarge
cpu_core_count: 32
cpu_threads_per_core: 2
```

## Quick Reference Table

| Instance Size | Core Count | Threads Per Core | Total vCPUs | Use Case |
|--------------|------------|------------------|-------------|----------|
| *.large | 1 | 2 | 2 | Testing, 1-2 VMs |
| *.xlarge | 2 | 2 | 4 | Development, 2-3 VMs |
| *.2xlarge | 4 | 2 | 8 | Small production, 4-6 VMs |
| *.4xlarge | 8 | 2 | 16 | Medium production, 8-12 VMs |
| *.8xlarge | 16 | 2 | 32 | Large production, 16-24 VMs |
| *.16xlarge | 32 | 2 | 64 | Heavy workloads, 32+ VMs |

## Troubleshooting

### CPU Options Not Applied

Check if your instance type supports CPU options:
```bash
aws ec2 describe-instance-types \
  --instance-types m8i.16xlarge \
  --query 'InstanceTypes[0].VCpuInfo' \
  --region us-east-2
```

### Nested Virtualization Not Working

1. Verify CPU flags:
   ```bash
   grep -E '(vmx|svm)' /proc/cpuinfo | wc -l
   # Should match your vCPU count
   ```

2. Check KVM module:
   ```bash
   lsmod | grep kvm
   cat /sys/module/kvm_intel/parameters/nested
   ```

3. Verify instance type supports nested virtualization (Nitro-based)

### Performance Issues

If VMs are slow:
1. Ensure hyperthreading is enabled (`threads_per_core: 2`)
2. Verify you're using enough cores for your workload
3. Check if host is overcommitted (too many VMs)
4. Consider using a larger instance type

## References

- [AWS EC2 CPU Options](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-optimize-cpu.html)
- [AWS Instance Types](https://aws.amazon.com/ec2/instance-types/)
- [Nested Virtualization on AWS](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html)
