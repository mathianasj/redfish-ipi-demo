#!/bin/bash
# Test script to verify nested virtualization detection

REGION="${1:-us-east-2}"
TEST_TYPE="${2:-m8i.16xlarge}"

echo "Testing nested virtualization detection for $TEST_TYPE in $REGION"
echo "========================================================================"

# Get full instance type details
echo ""
echo "Full instance type details:"
aws ec2 describe-instance-types \
  --region "$REGION" \
  --instance-types "$TEST_TYPE" \
  --output json | jq '.InstanceTypes[0] | {
    InstanceType,
    ProcessorInfo: {
      SupportedFeatures: .ProcessorInfo.SupportedFeatures
    }
  }'

echo ""
echo "========================================================================"
echo "Checking for nested virtualization indicators:"
echo ""

# Check for various nested virt indicators
echo "1. Checking ProcessorInfo.SupportedFeatures:"
aws ec2 describe-instance-types \
  --region "$REGION" \
  --instance-types "$TEST_TYPE" \
  --query 'InstanceTypes[0].ProcessorInfo.SupportedFeatures' \
  --output json

echo ""
echo "2. Known nested virt instance families (m5+, m6+, m7+, m8+, c5+, r5+, etc.):"
if [[ "$TEST_TYPE" =~ ^(m[5-9]|c[5-9]|r[5-9]|t3) ]]; then
  echo "   ✓ Instance family supports nested virtualization"
else
  echo "   ✗ Instance family may not support nested virtualization"
fi

echo ""
echo "3. Test with known nested virt instance types:"
echo "   Testing: m8i.16xlarge, m7i.16xlarge, m6i.16xlarge, c7i.16xlarge"
aws ec2 describe-instance-types \
  --region "$REGION" \
  --instance-types m8i.16xlarge m7i.16xlarge m6i.16xlarge c7i.16xlarge \
  --query 'InstanceTypes[].[InstanceType, ProcessorInfo.SupportedFeatures]' \
  --output json | jq -r '.[] | @json'

echo ""
echo "========================================================================"
echo "Recommended filter query:"
echo ""
echo "For instances with amd-sev-snp or intel-tdx (confidential computing features):"
echo 'jq ".InstanceTypes[] | select(.ProcessorInfo.SupportedFeatures // [] | contains([\"amd-sev-snp\"]) or contains([\"intel-tdx\"]))"'
echo ""
echo "Or use instance family pattern matching for known nested virt families:"
echo 'jq ".InstanceTypes[] | select(.InstanceType | test(\"^(m5|m6|m7|m8|c5|c6|c7|r5|r6|r7|t3)\"))"'
