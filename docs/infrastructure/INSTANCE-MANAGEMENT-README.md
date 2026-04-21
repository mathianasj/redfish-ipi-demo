# EC2 Instance Management Playbooks

This directory contains Ansible playbooks for managing EC2 instances with capacity-aware operations.

## Playbooks Overview

### 1. Main Instance Provisioning
- **playbook.yml** - Creates and configures the EC2 instance with nested virtualization

### 2. Instance Lifecycle Management
- **start-instance.yml** - Start instance with retry logic for capacity issues
- **stop-instance.yml** - Stop the instance
- **modify-instance-type.yml** - Change instance type (requires stopped instance)

### 3. Capacity Planning
- **find-alternative-instance-types.yml** - Find instance types that meet requirements (doesn't validate capacity)
- **validate-instance-capacity.yml** - Test specific instance types for actual capacity
- **find-available-instance-types.yml** - **RECOMMENDED** - Find AND validate instance types with actual capacity

## Common Workflows

### When You Get InsufficientInstanceCapacity Errors

If your instance won't start due to capacity issues:

#### Option 1: Quick - Find and Switch to Available Instance Type

```bash
# 1. Find instance types with actual available capacity
ansible-playbook find-available-instance-types.yml

# 2. Review the results in instance-capacity-report.txt
cat instance-capacity-report.txt

# 3. Stop the instance
ansible-playbook stop-instance.yml

# 4. Modify to use an available instance type
ansible-playbook modify-instance-type.yml --extra-vars "new_instance_type=m7i.16xlarge"

# 5. Start the instance
ansible-playbook start-instance.yml
```

#### Option 2: Detailed - Test Specific Instance Types

```bash
# 1. Find all possible alternatives (not validated for capacity)
ansible-playbook find-alternative-instance-types.yml

# 2. Review alternatives
cat alternative-instance-types.txt

# 3. Test specific types for actual capacity
ansible-playbook validate-instance-capacity.yml

# 4. Review capacity validation results
cat capacity-validation-results.txt

# 5. Stop, modify, and start (as shown in Option 1)
```

### Starting Instance with Auto-Retry

The start-instance.yml playbook includes exponential backoff retry logic:

```bash
ansible-playbook start-instance.yml
```

Features:
- Retries up to 10 times by default
- Exponential backoff: 5s → 7.5s → 11s → 16s → 24s → 36s → 54s → ... → 300s max
- Automatically detects when instance remains in "stopped" state

### Changing Instance Type

```bash
# 1. Stop the instance first
ansible-playbook stop-instance.yml

# 2. Modify to new type
ansible-playbook modify-instance-type.yml --extra-vars "new_instance_type=m7i.24xlarge"

# 3. Start it back up
ansible-playbook start-instance.yml
```

## Playbook Details

### find-available-instance-types.yml (RECOMMENDED)

Searches for instance types that:
- Support nested virtualization
- Are NOT bare metal
- Have at least the same CPU and RAM as current instance
- Are available in the same availability zone
- **Actually have capacity right now** (validated via AWS API dry-run)

**Configuration:**
- `max_types_to_test: 15` - How many instance types to test (higher = slower but more thorough)
- `supported_families` - Instance families known to support nested virtualization

**Output:**
- Console output with available instance types
- `instance-capacity-report.txt` - Detailed report

### start-instance.yml

Starts stopped instance with intelligent retry logic for capacity issues.

**Configuration:**
- `max_retries: 10` - Maximum retry attempts
- `initial_delay: 5` - Starting delay in seconds
- `max_delay: 300` - Maximum delay between retries (5 minutes)
- `backoff_multiplier: 1.5` - Exponential growth factor

### validate-instance-capacity.yml

Tests specific instance types for actual capacity availability.

**Usage:**
```bash
# Uses instance types from alternative-instance-types.txt
ansible-playbook validate-instance-capacity.yml

# Or specify types manually
ansible-playbook validate-instance-capacity.yml \
  --extra-vars "test_instance_types=['m7i.16xlarge','m6i.16xlarge','r7i.16xlarge']"
```

**Configuration:**
- `max_types_to_test: 10` - Limit how many to test from file

## Understanding Capacity Issues

### Why Capacity Issues Happen

AWS has finite capacity in each availability zone. Large instance types (especially newer generations) may experience temporary capacity constraints during:
- Peak usage times
- After new instance launches or maintenance
- In specific availability zones

### What the Playbooks Do

1. **find-available-instance-types.yml** - Uses `run-instances --dry-run` to check if AWS would allow launching each instance type right now
2. **start-instance.yml** - Detects when instance stays in "stopped" state and retries with backoff
3. **validate-instance-capacity.yml** - Tests a list of instance types to see which have capacity

### Best Practices

1. **Use find-available-instance-types.yml first** - It finds AND validates in one step
2. **Test multiple instance families** - Don't rely on a single family (m8i, m7i, m6i, etc.)
3. **Consider slightly smaller instances** - Often have better availability
4. **Retry during off-peak hours** - Capacity changes frequently
5. **Update playbook.yml** - After finding a good alternative, update the default instance_type

## Instance Type Selection Criteria

All playbooks filter for instance types that:
- ✅ Support nested virtualization (verified via AWS API)
- ✅ Are NOT bare metal (excludes *.metal instances)
- ✅ Meet or exceed current vCPU count
- ✅ Meet or exceed current memory
- ✅ Are available in your availability zone

### Nested Virtualization Detection

The playbooks use AWS EC2 API to detect nested virtualization support through:

1. **ProcessorInfo.SupportedFeatures** - Checks for `amd-sev-snp` or `intel-tdx` features
2. **Instance family pattern** - Fallback check for known families (m5+, m6+, m7+, m8+, c5+, c6+, c7+, r5+, r6+, r7+, t3+)

This ensures only instance types with actual nested virtualization support are suggested, rather than relying on a static hardcoded list.

### Testing Nested Virtualization Detection

You can verify how the playbooks detect nested virtualization:

```bash
./test-nested-virt-detection.sh us-east-2 m8i.16xlarge
```  

## Utility Scripts

### test-nested-virt-detection.sh

Diagnostic script to verify how nested virtualization is detected for instance types:

```bash
# Test current instance type
./test-nested-virt-detection.sh us-east-2 m8i.16xlarge

# Test alternative
./test-nested-virt-detection.sh us-east-2 m7i.16xlarge
```

Shows:
- ProcessorInfo.SupportedFeatures from AWS API
- Whether instance family is known to support nested virt
- Comparison with other known nested virt instance types

## Troubleshooting

### "No instance types with available capacity found"

- Capacity changes frequently - try again in 5-10 minutes
- Try a different availability zone
- Consider slightly smaller instance types
- Check if you can use a different region

### "Instance must be stopped before modifying"

Run `ansible-playbook stop-instance.yml` first.

### "List length for parameter InstanceTypes cannot exceed 100 items"

The playbooks handle this automatically by batching requests. If you see this error, a playbook may need updating.

### Start command succeeds but instance stays stopped

This is the InsufficientInstanceCapacity issue. Use find-available-instance-types.yml to find an alternative.

## Files Generated

- `alternative-instance-types.txt` - All suitable instance types (not capacity-validated)
- `capacity-validation-results.txt` - Results from validate-instance-capacity.yml
- `instance-capacity-report.txt` - Results from find-available-instance-types.yml (recommended)

## Quick Reference

```bash
# Find what's actually available NOW
ansible-playbook find-available-instance-types.yml

# Start with retry logic
ansible-playbook start-instance.yml

# Stop instance
ansible-playbook stop-instance.yml

# Change instance type
ansible-playbook modify-instance-type.yml --extra-vars "new_instance_type=TYPE"

# Create new instance
ansible-playbook playbook.yml
```
