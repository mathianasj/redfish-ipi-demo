#!/bin/bash
# Verify which instance types actually support nested virtualization
# by attempting a dry-run with CPU options

set -e

REGION="${1:-us-east-2}"
INSTANCE_TYPE="$2"

if [ -z "$INSTANCE_TYPE" ]; then
    echo "Usage: $0 [region] <instance-type>"
    echo "Example: $0 us-east-2 m5.xlarge"
    exit 1
fi

# Use a dummy AMI ID (won't actually launch due to dry-run)
AMI_ID="ami-0c55b159cbfafe1f0"

# Try to do a dry-run with CPU options to see if instance supports nested virt
echo "Testing $INSTANCE_TYPE in $REGION..."

if aws ec2 run-instances \
    --region "$REGION" \
    --instance-type "$INSTANCE_TYPE" \
    --image-id "$AMI_ID" \
    --dry-run \
    --cpu-options CoreCount=1,ThreadsPerCore=1 \
    2>&1 | grep -q "does not support the nested-virtualization CPU option"; then
    echo "❌ $INSTANCE_TYPE DOES NOT support nested virtualization"
    exit 1
else
    echo "✓ $INSTANCE_TYPE supports nested virtualization"
    exit 0
fi
