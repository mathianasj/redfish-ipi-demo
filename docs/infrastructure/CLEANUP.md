# Cleanup Guide - Delete EC2 Instance and Resources

This guide explains how to safely delete the EC2 instance and all associated AWS resources.

## What Gets Deleted

The cleanup playbook will permanently delete:

1. **EC2 Instance** - The nested virtualization host
2. **EBS Volumes**:
   - Root volume (500GB)
   - Storage volume (1TB)
   - OpenShift images volume (500GB)
3. **Networking**:
   - VPC
   - Subnet
   - Route Table
   - Internet Gateway
   - Security Group
4. **SSH Key Pair** - EC2 key pair (your local SSH key is NOT deleted)

## Safety Features

The cleanup playbook has a built-in safety check that requires explicit confirmation before deleting resources.

## Running the Cleanup

### Option 1: Edit the Playbook (Recommended)

1. **Edit `cleanup.yml`**:
   ```yaml
   vars:
     confirm_deletion: true  # Change from false to true
   ```

2. **Run the cleanup**:
   ```bash
   ansible-playbook cleanup.yml
   ```

### Option 2: Use Command-Line Variable

```bash
ansible-playbook cleanup.yml -e confirm_deletion=true
```

### Option 3: Dry Run (Check What Will Be Deleted)

To see what would be deleted without actually deleting:

```bash
# This will fail at the safety check, but shows the instance info
ansible-playbook cleanup.yml --check
```

## Step-by-Step Manual Cleanup

If you prefer to delete resources manually:

### 1. Terminate the EC2 Instance

```bash
# Find the instance
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=nested-virt-host" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text

# Terminate it
aws ec2 terminate-instances \
  --region us-east-2 \
  --instance-ids <instance-id>
```

### 2. Delete EBS Volumes

```bash
# List volumes
aws ec2 describe-volumes \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=nested-virt-host-*" \
  --query 'Volumes[].VolumeId' \
  --output text

# Delete each volume
aws ec2 delete-volume --region us-east-2 --volume-id <volume-id>
```

### 3. Delete Security Group

```bash
# Find security group
aws ec2 describe-security-groups \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=nested-virt-host-sg" \
  --query 'SecurityGroups[].GroupId' \
  --output text

# Delete it
aws ec2 delete-security-group \
  --region us-east-2 \
  --group-id <sg-id>
```

### 4. Delete VPC and Components

```bash
# Find VPC
VPC_ID=$(aws ec2 describe-vpcs \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=nested-virt-host-vpc" \
  --query 'Vpcs[].VpcId' \
  --output text)

# Delete route table
aws ec2 describe-route-tables \
  --region us-east-2 \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=nested-virt-host-rt" \
  --query 'RouteTables[].RouteTableId' \
  --output text | xargs -I {} aws ec2 delete-route-table --region us-east-2 --route-table-id {}

# Delete subnet
aws ec2 describe-subnets \
  --region us-east-2 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].SubnetId' \
  --output text | xargs -I {} aws ec2 delete-subnet --region us-east-2 --subnet-id {}

# Detach and delete internet gateway
IGW_ID=$(aws ec2 describe-internet-gateways \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=nested-virt-host-igw" \
  --query 'InternetGateways[].InternetGatewayId' \
  --output text)

aws ec2 detach-internet-gateway \
  --region us-east-2 \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID

aws ec2 delete-internet-gateway \
  --region us-east-2 \
  --internet-gateway-id $IGW_ID

# Delete VPC
aws ec2 delete-vpc --region us-east-2 --vpc-id $VPC_ID
```

### 5. Delete EC2 Key Pair

```bash
aws ec2 delete-key-pair \
  --region us-east-2 \
  --key-name nested-virt-key
```

## Partial Cleanup

If you only want to delete some resources:

### Delete Only the Instance (Keep Network)

```bash
ansible-playbook cleanup.yml -e confirm_deletion=true --tags instance
```

### Delete Only Volumes

```bash
ansible-playbook cleanup.yml -e confirm_deletion=true --tags volumes
```

### Delete Only Networking

```bash
ansible-playbook cleanup.yml -e confirm_deletion=true --tags network
```

## Verification

After cleanup, verify all resources are deleted:

```bash
# Check for instances
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=nested-virt-host"

# Check for volumes
aws ec2 describe-volumes \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=nested-virt-host-*"

# Check for VPCs
aws ec2 describe-vpcs \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=nested-virt-host-vpc"

# Check for key pairs
aws ec2 describe-key-pairs \
  --region us-east-2 \
  --key-names nested-virt-key
```

## Cost Savings

After cleanup, you will no longer incur charges for:
- EC2 instance compute time (~$7/hour for m8i.16xlarge)
- EBS volume storage (~$0.08/GB-month = ~$160/month for 2TB)
- Data transfer (varies)

**Total savings**: ~$5,000+/month for m8i.16xlarge setup

## Troubleshooting

### "DependencyViolation" Error

If you get dependency errors:

```bash
# Wait a few minutes for resources to fully delete
sleep 60

# Retry the cleanup
ansible-playbook cleanup.yml -e confirm_deletion=true
```

### Security Group Won't Delete

If the security group has dependencies:

```bash
# Check for network interfaces still using it
aws ec2 describe-network-interfaces \
  --region us-east-2 \
  --filters "Name=group-id,Values=<sg-id>"

# Wait for ENIs to be deleted after instance termination
```

### VPC Won't Delete

Ensure all resources in the VPC are deleted first:

```bash
# List all resources in VPC
aws ec2 describe-vpc-attribute \
  --region us-east-2 \
  --vpc-id <vpc-id> \
  --attribute enableDnsSupport

# Check for remaining network interfaces
aws ec2 describe-network-interfaces \
  --region us-east-2 \
  --filters "Name=vpc-id,Values=<vpc-id>"
```

## Important Notes

- **Data Loss**: All data on the EBS volumes will be permanently deleted
- **Backups**: Make sure you have backups of any important data before running cleanup
- **SSH Keys**: Your local SSH private key (~/.ssh/id_rsa_fips) is NOT deleted, only the EC2 key pair
- **Pull Secrets**: Your OpenShift pull secret is only in your local files
- **Irreversible**: This action cannot be undone

## Redeployment

To redeploy after cleanup, simply run the main playbook again:

```bash
ansible-playbook playbook.yml
```

All resources will be recreated from scratch.
