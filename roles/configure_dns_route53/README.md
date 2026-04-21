# Configure DNS with Route53

This role configures DNS records in AWS Route53 for OpenShift cluster deployment as an alternative to running a local bind DNS server.

## Requirements

- AWS credentials configured (via environment variables, AWS CLI profile, or IAM role)
- Ansible collection: `amazon.aws` (included in requirements.yml)
- A Route53 hosted zone (can be created automatically)

## Role Variables

### Required Variables

- `dns_domain`: The domain name for DNS records (e.g., `example.com`)
- `cluster_name`: OpenShift cluster name (e.g., `sno`)
- `api_vip`: IP address for the API endpoint (e.g., `192.168.122.10`)
- `ingress_vip`: IP address for ingress/apps wildcard (e.g., `192.168.122.11`)

### Optional Variables (choose one)

- `route53_hosted_zone_id`: Existing hosted zone ID to use (e.g., `Z1234567890ABC`)
  - **Read-only lookup** - will verify zone exists, not modify it
  - Use this when you already have a Route53 hosted zone
- `route53_domain_name`: Domain name to use (e.g., `example.com`)
  - Will lookup existing zone or create new one if needed
  - Use this when you want the role to manage the zone

### Other Optional Variables

- `route53_record_ttl`: TTL for DNS records in seconds (default: `300`)
- `route53_wait_for_propagation`: Wait for DNS propagation (default: `true`)
- `route53_propagation_wait`: Seconds to wait for propagation (default: `30`)
- `route53_verify_dns`: Verify DNS resolution after creation (default: `false`)
- `aws_region`: AWS region for API calls (default: `us-east-1`)

## Usage

### Option 1: Use Existing Hosted Zone

If you already have a Route53 hosted zone:

```yaml
- hosts: localhost
  roles:
    - role: configure_dns_route53
      vars:
        route53_hosted_zone_id: Z1234567890ABC
        dns_domain: example.com
        cluster_name: sno
        api_vip: 192.168.122.10
        ingress_vip: 192.168.122.11
```

### Option 2: Create New Hosted Zone

To create a new hosted zone:

```yaml
- hosts: localhost
  roles:
    - role: configure_dns_route53
      vars:
        route53_domain_name: example.com
        cluster_name: sno
        api_vip: 192.168.122.10
        ingress_vip: 192.168.122.11
```

## DNS Records Created

This role creates the following DNS records:

- `api.{cluster_name}.{dns_domain}` → A record pointing to `api_vip`
- `*.apps.{cluster_name}.{dns_domain}` → A record pointing to `ingress_vip`

## AWS Credentials

The role requires AWS credentials with the following permissions:

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

You can provide credentials via:

1. **Environment variables**:
   ```bash
   export AWS_ACCESS_KEY_ID=your_access_key
   export AWS_SECRET_ACCESS_KEY=your_secret_key
   export AWS_REGION=us-east-1
   ```

2. **AWS CLI profile**:
   ```bash
   export AWS_PROFILE=your_profile
   ```

3. **IAM role** (if running on EC2):
   - Attach an IAM role with Route53 permissions to your EC2 instance

## Example Playbook

See `configure-dns-route53.yml` for a complete example.

## Important Notes

1. **Public IPs**: If `api_vip` and `ingress_vip` are private IPs (like `192.168.x.x`), Route53 records will still be created, but they won't be resolvable from the public internet. This is fine for internal/VPN-only access.

2. **Name Servers**: If you created a new hosted zone, you'll need to update your domain registrar with the Route53 name servers shown in the playbook output.

3. **DNS Propagation**: DNS changes typically propagate within 60 seconds, but can take longer depending on TTL values.

4. **Split-Horizon DNS**: If you need different IPs for internal vs external access, consider:
   - Using bind for internal DNS
   - Using Route53 for external DNS with public IPs
   - Setting up VPN for access to private IPs

## Comparison with Bind

| Feature | Bind (Local DNS) | Route53 |
|---------|------------------|---------|
| Setup | Requires BIND server on EC2 | No local server needed |
| Management | Manual zone file edits | AWS console/API/Terraform |
| Cost | Free (uses EC2 resources) | $0.50/zone/month + queries |
| Scope | Internal network only | Can be public or private |
| Propagation | Immediate | ~60 seconds |
| Dependencies | Requires running EC2 instance | Cloud-based, always available |
| Best for | Lab/demo environments | Production environments |

## License

Apache 2.0
