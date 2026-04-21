#!/bin/bash
# Helper script to configure Route53 external DNS with EC2 public IP
# Usage: ./configure-route53-external.sh <route53-zone-id>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Route53 hosted zone ID required${NC}"
    echo ""
    echo "Usage: $0 <route53-zone-id> [options]"
    echo ""
    echo "Examples:"
    echo "  $0 Z1234567890ABC"
    echo "  $0 Z1234567890ABC -e dns_domain=mydomain.com"
    echo "  $0 Z1234567890ABC -e cluster_name=prod"
    echo ""
    echo "To find your hosted zone ID:"
    echo "  aws route53 list-hosted-zones"
    exit 1
fi

ZONE_ID=$1
shift  # Remove first argument, keep rest for ansible

# Default values
AWS_REGION=${AWS_REGION:-us-east-2}
INSTANCE_NAME=${INSTANCE_NAME:-nested-virt-host}
CLUSTER_NAME=${CLUSTER_NAME:-sno}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Route53 External DNS Configuration${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get EC2 public IP
echo -e "${YELLOW}Finding EC2 instance...${NC}"
EC2_PUBLIC_IP=$(aws ec2 describe-instances \
  --region $AWS_REGION \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text 2>/dev/null)

if [ -z "$EC2_PUBLIC_IP" ] || [ "$EC2_PUBLIC_IP" == "None" ]; then
    echo -e "${RED}Error: Could not find running EC2 instance with name: $INSTANCE_NAME${NC}"
    echo ""
    echo "Available instances:"
    aws ec2 describe-instances \
      --region $AWS_REGION \
      --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress]' \
      --output table
    exit 1
fi

echo -e "${GREEN}✓ Found EC2 instance${NC}"
echo -e "  Instance Name: $INSTANCE_NAME"
echo -e "  Public IP: $EC2_PUBLIC_IP"
echo ""

# Verify Route53 zone exists and get domain name
echo -e "${YELLOW}Verifying Route53 hosted zone...${NC}"
ZONE_NAME=$(aws route53 get-hosted-zone --id $ZONE_ID --query 'HostedZone.Name' --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Could not find hosted zone: $ZONE_ID${NC}"
    echo ""
    echo "Available hosted zones:"
    aws route53 list-hosted-zones --query 'HostedZones[].[Id,Name]' --output table
    exit 1
fi

# Remove trailing dot from zone name
DNS_DOMAIN=${ZONE_NAME%.}

echo -e "${GREEN}✓ Found Route53 hosted zone${NC}"
echo -e "  Zone ID: $ZONE_ID"
echo -e "  Zone Name: $ZONE_NAME"
echo -e "  DNS Domain: $DNS_DOMAIN"
echo ""

# Show configuration
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  DNS Domain: $DNS_DOMAIN"
echo -e "  Cluster Name: $CLUSTER_NAME"
echo -e "  API VIP: $EC2_PUBLIC_IP (EC2 public IP)"
echo -e "  Ingress VIP: $EC2_PUBLIC_IP (EC2 public IP)"
echo ""

# Confirm
read -p "Continue with this configuration? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${GREEN}Configuring Route53 external DNS...${NC}"
echo ""

# Run ansible playbook
ansible-playbook configure-dns-route53.yml \
  -e route53_hosted_zone_id=$ZONE_ID \
  -e dns_domain=$DNS_DOMAIN \
  -e cluster_name=$CLUSTER_NAME \
  -e api_vip=$EC2_PUBLIC_IP \
  -e ingress_vip=$EC2_PUBLIC_IP \
  "$@"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Route53 Configuration Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "DNS Records Created:"
    echo -e "  api.$CLUSTER_NAME.$DNS_DOMAIN → $EC2_PUBLIC_IP"
    echo -e "  *.apps.$CLUSTER_NAME.$DNS_DOMAIN → $EC2_PUBLIC_IP"
    echo ""
    echo -e "Test external access (wait ~60 seconds for DNS propagation):"
    echo -e "  ${YELLOW}curl -k https://api.$CLUSTER_NAME.$DNS_DOMAIN:6443/healthz${NC}"
    echo -e "  ${YELLOW}curl -k https://console-openshift-console.apps.$CLUSTER_NAME.$DNS_DOMAIN${NC}"
    echo ""
else
    echo ""
    echo -e "${RED}Error: Configuration failed${NC}"
    exit 1
fi
