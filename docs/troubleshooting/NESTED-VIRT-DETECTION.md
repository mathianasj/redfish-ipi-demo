# Nested Virtualization Detection

## Overview

The playbooks now use AWS EC2 API to dynamically detect nested virtualization support rather than relying on a hardcoded list of instance families.

## Detection Methods

### Primary Method: AWS API Features

The playbooks query `ProcessorInfo.SupportedFeatures` to check for:
- `amd-sev-snp` - AMD Secure Encrypted Virtualization
- `intel-tdx` - Intel Trust Domain Extensions

These features indicate confidential computing support, which typically correlates with nested virtualization capabilities.

### Fallback Method: Instance Family Pattern

If AWS API features aren't conclusive, the playbooks check instance family patterns:
- **m-series:** m5, m5a, m5n, m5zn, m6i, m6a, m6in, m6idn, m7i, m7a, m8i, m8a
- **c-series:** c5, c5a, c5n, c6i, c6a, c6in, c6id, c7i, c7a, c8
- **r-series:** r5, r5a, r5n, r6i, r6a, r6in, r6idn, r7i, r7a, r7iz, r8
- **t-series:** t3, t3a

## Implementation

### In query_nested_virt_batch.yml

```bash
aws ec2 describe-instance-types \
  --region us-east-2 \
  --instance-types [batch] \
  --output json

# Then filter with jq:
jq '.InstanceTypes[] |
  select(.ProcessorInfo.SupportedFeatures // [] | contains(["amd-sev-snp"]) or
         .ProcessorInfo.SupportedFeatures // [] | contains(["intel-tdx"]) or
         (.InstanceType | test("^(m5|m6|m7|m8|c5|c6|c7|r5|r6|r7|t3)")))'
```

### Files Updated

1. **find-available-instance-types.yml**
   - Removed hardcoded `supported_families` variable
   - Now uses `query_nested_virt_batch.yml` for dynamic detection

2. **find-alternative-instance-types.yml**
   - Removed hardcoded `supported_families` variable
   - Now uses `query_nested_virt_batch.yml` for dynamic detection

3. **query_nested_virt_batch.yml** (new)
   - Queries AWS API in batches of 100
   - Filters for nested virtualization support using both methods
   - Returns only supported instance types

4. **test-nested-virt-detection.sh** (new)
   - Diagnostic script to verify detection logic
   - Shows AWS API response for any instance type
   - Useful for troubleshooting

## Why This Matters

### Before (Hardcoded List)
- ❌ Required manual updates when new instance families launched
- ❌ Could miss new instance types with nested virt support
- ❌ Could include unsupported types if AWS changed specs
- ✅ Fast - no extra API calls needed

### After (AWS API Detection)
- ✅ Automatically discovers new instance types
- ✅ Always accurate based on current AWS specs
- ✅ Adapts to AWS changes without playbook updates
- ✅ Uses official AWS metadata
- ⚠️ Slightly slower due to additional API queries (batched for efficiency)

## Testing Your Current Instance

To verify your current instance supports nested virtualization:

```bash
# Check m8i.16xlarge in us-east-2
./test-nested-virt-detection.sh us-east-2 m8i.16xlarge
```

You should see:
- ProcessorInfo.SupportedFeatures listed (may include amd-sev-snp or intel-tdx)
- Instance family pattern match confirmation
- Comparison with other known nested virt instance types

## API Query Optimization

To avoid AWS API rate limits and reduce query time:
- Queries run in batches of 100 instance types max
- Results are cached within a single playbook run
- Only queries instance types available in target availability zone
- Filters out bare metal instances before capacity testing

## Example Output

```
Querying batch 1: instances 1 to 100
Batch 1: Found 42 instance types with nested virtualization support

Querying batch 2: instances 101 to 200
Batch 2: Found 38 instance types with nested virtualization support
```

## Troubleshooting

### "No instance types found with nested virtualization"

This is unlikely but could happen if:
1. The AWS API response format changed
2. The availability zone has no modern instance types
3. Network/API issues preventing query

**Solution:** Check the raw API response:
```bash
aws ec2 describe-instance-types \
  --region us-east-2 \
  --instance-types m8i.16xlarge \
  --query 'InstanceTypes[0].ProcessorInfo.SupportedFeatures'
```

### Instance type shows as "not supported" but should be

The detection combines AWS API features with pattern matching. If an instance is incorrectly filtered:

1. Run the test script to see what AWS reports
2. Check if it matches the family pattern
3. May need to add the family pattern if it's a new series

### Queries are slow

Batching reduces this, but with 500+ instance types in a zone:
- Each batch of 100 takes ~1-2 seconds
- Consider reducing `max_types_to_test` in find-available-instance-types.yml
- Focus on specific instance families if you know what you want

## Future Improvements

Potential enhancements:
1. Cache API results to file for faster re-runs
2. Add user override to specify exact instance types to test
3. Parallel batch queries (careful of rate limits)
4. Filter by processor generation or other criteria
