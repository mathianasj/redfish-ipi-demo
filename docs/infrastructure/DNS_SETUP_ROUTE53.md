# DNS Setup with AWS Route53

This guide explains how to configure DNS for OpenShift using AWS Route53 instead of a local bind DNS server.

## Overview

Route53 provides a managed DNS service that can be used as an alternative to running bind on the EC2 instance. This is useful when:

- You want managed DNS without maintaining a bind server
- You need DNS records accessible outside the EC2 instance
- You prefer infrastructure-as-code DNS management
- You're running in a production environment

## Route53 vs Bind Comparison

| Feature | Bind (Local DNS) | Route53 |
|---------|------------------|---------|
| **Setup** | Requires bind server on EC2 | No local server needed |
| **Management** | Manual zone file edits | AWS console/API/Ansible |
| **Cost** | Free (uses EC2 resources) | $0.50/zone/month + queries |
| **Scope** | Internal network only | Public or private |
| **Propagation** | Immediate | ~60 seconds |
| **Dependencies** | Requires running EC2 | Cloud-based, always available |
| **Best for** | Lab/demo environments | Production environments |
| **Public Access** | Requires port forwarding | Native with public IPs |

## Prerequisites

### 1. AWS Credentials

You need AWS credentials with Route53 permissions. Choose one method:

#### Option A: Environment Variables

```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_REGION=us-east-1
```

#### Option B: AWS CLI Profile

```bash
export AWS_PROFILE=your_profile
```

#### Option C: IAM Role (if running on EC2)

Attach an IAM role to your EC2 instance with this policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:GetHostedZone",
        "route53:ListHostedZones",
        "route53:CreateHostedZone",
        "route53:ChangeResourceRecordSets",
        "route53:GetChange",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "*"
    }
  ]
}
```

### 2. Domain Name

You need either:
- **An existing Route53 hosted zone** - provide the zone ID (read-only lookup)
- **A domain name** - the playbook will lookup or create the hosted zone as needed

## Running the Route53 Configuration

### Basic Usage

```bash
# Activate virtual environment
source venv/bin/activate

# Run Route53 DNS configuration
ansible-playbook configure-dns-route53.yml
```

### Override Variables

```bash
# With zone ID (domain auto-discovered)
ansible-playbook configure-dns-route53.yml \
  -e route53_hosted_zone_id=Z1234567890ABC \
  -e cluster_name=prod \
  -e api_vip=192.168.122.20 \
  -e ingress_vip=192.168.122.21

# Or manually specify domain to create/lookup zone
ansible-playbook configure-dns-route53.yml \
  -e route53_domain_name=mydomain.com \
  -e cluster_name=prod \
  -e api_vip=192.168.122.20 \
  -e ingress_vip=192.168.122.21
```

### Use Existing Hosted Zone

If you already have a Route53 hosted zone (recommended):

```bash
# Domain is automatically discovered from the zone
ansible-playbook configure-dns-route53.yml \
  -e route53_hosted_zone_id=Z1234567890ABC \
  -e cluster_name=sno \
  -e api_vip=192.168.122.10 \
  -e ingress_vip=192.168.122.11
```

**Note:** 
- This performs a read-only lookup of your existing zone and adds DNS records
- The `dns_domain` is automatically discovered from the zone (e.g., if your zone is for `mydomain.com`, that will be used)
- It will NOT modify the zone itself, only add DNS records

## Configuration Variables

Edit `configure-dns-route53.yml` or use command-line variables:

```yaml
vars:
  # DNS configuration
  dns_domain: example.com          # Your domain
  cluster_name: sno                # OpenShift cluster name
  api_vip: 192.168.122.10         # API endpoint IP
  ingress_vip: 192.168.122.11     # Ingress/apps wildcard IP
  
  # Route53 - Option 1: Use existing hosted zone
  route53_hosted_zone_id: Z1234567890ABC
  
  # Route53 - Option 2: Create new hosted zone
  # route53_domain_name: example.com
  
  # Route53 settings
  route53_record_ttl: 300                    # DNS TTL in seconds
  route53_wait_for_propagation: true         # Wait for DNS to propagate
  route53_propagation_wait: 30               # Seconds to wait
  
  # AWS region
  aws_region: us-east-1
```

## DNS Records Created

The playbook creates these DNS records in Route53:

| Record | Type | Value | Purpose |
|--------|------|-------|---------|
| `api.sno.example.com` | A | 192.168.122.10 | OpenShift API endpoint |
| `*.apps.sno.example.com` | A | 192.168.122.11 | Wildcard for all apps/routes |

All app routes will resolve to the ingress VIP:
- `console-openshift-console.apps.sno.example.com` → 192.168.122.11
- `oauth-openshift.apps.sno.example.com` → 192.168.122.11
- `myapp.apps.sno.example.com` → 192.168.122.11

## Important: Public vs Private IPs

### Private IPs (192.168.x.x, 10.x.x.x)

If your `api_vip` and `ingress_vip` are private IPs (which is common for this setup):

✅ **Pros:**
- Route53 records are created successfully
- DNS works from anywhere (names resolve to IPs)

⚠️ **Cons:**
- IPs only reachable from inside your network
- Public internet users can resolve names but can't reach the IPs

**Solution:** Use one of these approaches:

1. **VPN Access**: Set up VPN to access the private network
2. **Hybrid DNS**: 
   - Use Route53 for external DNS (with public IPs)
   - Use bind for internal DNS (with private IPs)
3. **Public IPs**: Use public IPs for `api_vip` and `ingress_vip`

### Public IPs

If you use public IPs (e.g., EC2 Elastic IPs):

✅ **Pros:**
- Accessible from anywhere on the internet
- Works seamlessly with Route53

⚠️ **Cons:**
- Requires proper security groups and firewall rules
- May incur additional AWS costs

## Testing DNS

### Check Hosted Zone

```bash
# List your hosted zones
aws route53 list-hosted-zones

# Get zone details
aws route53 get-hosted-zone --id Z1234567890ABC

# List records in zone
aws route53 list-resource-record-sets --hosted-zone-id Z1234567890ABC
```

### Test DNS Resolution

```bash
# Wait a minute for DNS propagation, then test
dig api.sno.example.com
dig console.apps.sno.example.com
dig test.apps.sno.example.com

# Should all return the correct IPs

# Or use nslookup
nslookup api.sno.example.com
nslookup console.apps.sno.example.com
```

### Verify from Different Locations

```bash
# Test from different DNS servers
dig @8.8.8.8 api.sno.example.com
dig @1.1.1.1 api.sno.example.com

# Test from different geographic locations
# Use online tools like:
# - https://www.whatsmydns.net
# - https://dnschecker.org
```

## New Hosted Zone Setup

If the playbook created a new hosted zone, you need to update your domain registrar:

### 1. Get Name Servers

The playbook output shows the Route53 name servers. You can also get them with:

```bash
aws route53 get-hosted-zone --id Z1234567890ABC
```

Example output:
```
ns-1234.awsdns-12.org
ns-5678.awsdns-56.com
ns-9012.awsdns-90.net
ns-3456.awsdns-34.co.uk
```

### 2. Update Domain Registrar

Log into your domain registrar (e.g., GoDaddy, Namecheap, Google Domains) and:

1. Find DNS settings for your domain
2. Replace the current name servers with Route53 name servers
3. Save changes

⏱️ **Note:** DNS delegation can take 24-48 hours to propagate globally.

### 3. Verify Delegation

```bash
# Check if delegation is working
dig NS example.com

# Should show Route53 name servers
```

## Using with OpenShift

### Update install-config.yaml

Since Route53 DNS is publicly resolvable, you don't need special DNS configuration in `install-config.yaml` unless you want to override defaults:

```yaml
# OpenShift will use public DNS automatically
# No special dns-resolver config needed if using public DNS

# For private IPs, you might still want to configure DNS
networkConfig:
  dns-resolver:
    config:
      server:
      - 8.8.8.8
      - 1.1.1.1
```

### Using Both Route53 and Bind

You can use both for split-horizon DNS:

1. **Route53**: Public DNS with public IPs (external access)
2. **Bind**: Private DNS with private IPs (internal access)

This allows:
- External users access via Route53 (public IPs)
- Internal VMs access via bind (private IPs, faster, no internet dependency)

## Managing DNS Records

### Add Additional Records

Use Ansible to add more records:

```yaml
- name: Add additional DNS record
  amazon.aws.route53:
    state: present
    zone: Z1234567890ABC
    record: myapp.example.com
    type: A
    ttl: 300
    value: 192.168.122.50
```

Or use AWS CLI:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch file://change-batch.json
```

### Update Records

Re-run the playbook with different IPs:

```bash
ansible-playbook configure-dns-route53.yml \
  -e api_vip=192.168.122.20 \
  -e ingress_vip=192.168.122.21
```

The `overwrite: yes` parameter ensures records are updated.

### Delete Records

Set `state: absent` in Ansible or use AWS CLI:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch '{
    "Changes": [{
      "Action": "DELETE",
      "ResourceRecordSet": {
        "Name": "api.sno.example.com",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "192.168.122.10"}]
      }
    }]
  }'
```

## Multiple Clusters

To support multiple OpenShift clusters in the same domain:

```bash
# Cluster 1 (sno)
ansible-playbook configure-dns-route53.yml \
  -e cluster_name=sno \
  -e api_vip=192.168.122.10 \
  -e ingress_vip=192.168.122.11

# Cluster 2 (prod)
ansible-playbook configure-dns-route53.yml \
  -e cluster_name=prod \
  -e api_vip=192.168.122.20 \
  -e ingress_vip=192.168.122.21

# Cluster 3 (dev)
ansible-playbook configure-dns-route53.yml \
  -e cluster_name=dev \
  -e api_vip=192.168.122.30 \
  -e ingress_vip=192.168.122.31
```

This creates:
- `api.sno.example.com` → 192.168.122.10
- `*.apps.sno.example.com` → 192.168.122.11
- `api.prod.example.com` → 192.168.122.20
- `*.apps.prod.example.com` → 192.168.122.21
- `api.dev.example.com` → 192.168.122.30
- `*.apps.dev.example.com` → 192.168.122.31

## Costs

Route53 pricing (as of 2024):

- **Hosted Zone**: $0.50 per zone per month
- **Queries**: $0.40 per million queries for first billion
- **Health Checks**: Additional cost if using health checks

For a demo/lab environment:
- 1 hosted zone: $0.50/month
- Estimated queries: ~100K/month: ~$0.04/month
- **Total**: ~$0.54/month

## Troubleshooting

### Credentials Not Found

```bash
# Check AWS credentials
aws sts get-caller-identity

# If not configured, set up credentials
aws configure
```

### Hosted Zone Not Found

```bash
# List all hosted zones
aws route53 list-hosted-zones

# Check specific zone
aws route53 get-hosted-zone --id Z1234567890ABC
```

### DNS Not Resolving

```bash
# Check if records exist
aws route53 list-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --query "ResourceRecordSets[?Name=='api.sno.example.com.']"

# Check DNS propagation status
dig api.sno.example.com +trace

# Try different DNS servers
dig @8.8.8.8 api.sno.example.com
dig @ns1.awsdns.com api.sno.example.com
```

### Playbook Fails with Permission Error

Ensure your AWS credentials have the required Route53 permissions (see Prerequisites section).

### DNS Takes Too Long to Propagate

Reduce TTL values:

```bash
ansible-playbook configure-dns-route53.yml \
  -e route53_record_ttl=60
```

Note: Lower TTL = faster updates but more DNS queries = slightly higher cost.

## Cleaning Up

### Delete DNS Records Only

```bash
# Use AWS CLI to delete specific records
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch file://delete-records.json
```

### Delete Entire Hosted Zone

⚠️ **Warning**: This deletes all records in the zone!

```bash
# First, delete all non-default records
# Then delete the hosted zone
aws route53 delete-hosted-zone --id Z1234567890ABC
```

Or use Ansible:

```yaml
- name: Delete hosted zone
  amazon.aws.route53_zone:
    zone: example.com
    state: absent
```

## Migration from Bind to Route53

To migrate from bind to Route53:

1. **Export existing bind records**:
   ```bash
   ssh ec2-user@instance
   sudo cat /var/named/example.com.zone
   ```

2. **Create Route53 records** for each A record:
   ```bash
   ansible-playbook configure-dns-route53.yml
   ```

3. **Test Route53 DNS** before switching:
   ```bash
   dig @ns1.awsdns.com api.sno.example.com
   ```

4. **Update domain registrar** with Route53 name servers

5. **Wait for propagation** (24-48 hours)

6. **Verify everything works** from multiple locations

7. **Stop bind server** (optional):
   ```bash
   ssh ec2-user@instance
   sudo systemctl stop named
   sudo systemctl disable named
   ```

## Best Practices

1. **Use Low TTL During Testing**: Set `route53_record_ttl: 60` for faster updates
2. **Increase TTL in Production**: Use `route53_record_ttl: 3600` to reduce query costs
3. **Tag Resources**: Add tags to hosted zones for easier management
4. **Monitor Costs**: Check AWS billing dashboard regularly
5. **Backup Records**: Export records before making major changes
6. **Use Infrastructure as Code**: Store Route53 configuration in version control

## References

- [AWS Route53 Documentation](https://docs.aws.amazon.com/route53/)
- [OpenShift DNS Requirements](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal.html#installation-dns-user-infra_installing-bare-metal)
- [Ansible route53 Module](https://docs.ansible.com/ansible/latest/collections/amazon/aws/route53_module.html)
- [Route53 Pricing](https://aws.amazon.com/route53/pricing/)
