# Split-Horizon DNS Architecture for OpenShift

Complete guide to setting up split-horizon DNS with external Route53, internal Bind, and HAProxy reverse proxy.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ External Users (Internet)                                       │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ DNS Query: api.sno.example.com
                 ↓
┌─────────────────────────────────────────────────────────────────┐
│ Route53 (External DNS)                                          │
│ api.sno.example.com → 3.145.67.89 (EC2 Public IP)              │
│ *.apps.sno.example.com → 3.145.67.89 (EC2 Public IP)           │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ HTTPS to 3.145.67.89:6443
                 ↓
┌─────────────────────────────────────────────────────────────────┐
│ EC2 Instance (3.145.67.89)                                      │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ HAProxy (Reverse Proxy)                                  │  │
│  │ :6443 → 192.168.122.10:6443 (API)                       │  │
│  │ :443  → 192.168.122.11:443  (Apps HTTPS)                │  │
│  │ :80   → 192.168.122.11:80   (Apps HTTP)                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Bind DNS (Internal DNS for VMs)                          │  │
│  │ api.sno.example.com → 192.168.122.10                     │  │
│  │ *.apps.sno.example.com → 192.168.122.11                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ OpenShift Cluster (KVM VMs)                              │  │
│  │ API VIP: 192.168.122.10                                  │  │
│  │ Ingress VIP: 192.168.122.11                              │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Why Split-Horizon DNS?

### Problem

OpenShift cluster runs on private IPs (192.168.122.x) inside EC2 instance:
- ❌ Not accessible from internet
- ✅ Fast internal VM-to-VM communication
- ✅ No public IP costs per VM

### Solution: Split-Horizon DNS

**Different DNS answers based on where you ask from:**

| Client Location | DNS Server | API Answer | Result |
|----------------|------------|------------|---------|
| **Internal VMs** | Bind (local) | 192.168.122.10 | Direct connection (fast) |
| **External users** | Route53 (cloud) | 3.145.67.89 | Via HAProxy (proxied) |

### Benefits

✅ **Internal VMs**: Fast direct access (no proxy overhead)  
✅ **External users**: Access via single public IP  
✅ **Cost**: Only one public IP needed (EC2 instance)  
✅ **Security**: Private IPs not exposed to internet  
✅ **Flexibility**: Same DNS names work everywhere  

## Components

### 1. Internal Bind DNS (Port 53)

**Purpose**: Resolve DNS for VMs inside EC2 instance  
**Listeners**: 127.0.0.1, EC2 private IP  
**Records**:
- `api.sno.example.com` → `192.168.122.10` (API VIP)
- `*.apps.sno.example.com` → `192.168.122.11` (Ingress VIP)

**Used by**: OpenShift VMs, EC2 instance itself

### 2. HAProxy Reverse Proxy

**Purpose**: Proxy external traffic from EC2 public IP to internal VIPs  
**Listeners**:
- `:6443` → `192.168.122.10:6443` (API)
- `:443` → `192.168.122.11:443` (HTTPS)
- `:80` → `192.168.122.11:80` (HTTP)

**Mode**: TCP passthrough (no SSL termination)

### 3. External Route53 DNS

**Purpose**: Resolve DNS for external users  
**Records**:
- `api.sno.example.com` → `3.145.67.89` (EC2 public IP)
- `*.apps.sno.example.com` → `3.145.67.89` (EC2 public IP)

**Used by**: External users, your laptop

## Complete Setup Workflow

### Prerequisites

1. ✅ OpenShift cluster installed
2. ✅ EC2 instance has public IP
3. ✅ Route53 hosted zone exists
4. ✅ AWS credentials configured

### Step 1: Install OpenShift (if not already done)

```bash
ansible-playbook prepare-and-install-openshift.yml
```

This creates the cluster with private VIPs.

### Step 2: Configure Split-Horizon DNS (Internal)

```bash
# Provide Route53 zone ID - domain is auto-discovered
ansible-playbook configure-split-horizon-dns.yml \
  -e route53_hosted_zone_id=Z1234567890ABC
```

This playbook:
1. ✅ **Discovers DNS domain** from Route53 hosted zone
2. ✅ **Discovers VIPs** from running cluster (no manual config!)
3. ✅ Configures **Bind DNS** with discovered domain and VIPs
4. ✅ Configures **HAProxy** to proxy to discovered VIPs
5. ✅ Saves configuration summary

**What it discovers:**
- DNS Domain from: Route53 zone lookup (e.g., `mydomain.com`)
- API VIP from: `oc get infrastructure cluster`
- Ingress VIP from: Router service or install-config

### Step 3: Configure Route53 External DNS

Get your EC2 public IP:

```bash
# Option 1: AWS CLI
EC2_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=nested-virt-host" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# Option 2: From EC2 instance
EC2_IP=$(ssh ec2-user@<instance> curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
```

Configure Route53:

```bash
ansible-playbook configure-dns-route53.yml \
  -e route53_hosted_zone_id=Z1234567890ABC \
  -e dns_domain=example.com \
  -e cluster_name=sno \
  -e api_vip=$EC2_IP \
  -e ingress_vip=$EC2_IP
```

**Important**: For Route53, both `api_vip` and `ingress_vip` = EC2 public IP!

### Step 4: Verify Setup

#### Test Internal DNS (from EC2 instance)

```bash
ssh ec2-user@<ec2-public-ip>

# Test Bind DNS
dig api.sno.example.com
# Should return: 192.168.122.10

dig console.apps.sno.example.com
# Should return: 192.168.122.11

# Test direct access
curl -k https://192.168.122.10:6443/healthz
# Should return: ok
```

#### Test HAProxy (from EC2 instance)

```bash
# Test via HAProxy on localhost
curl -k https://localhost:6443/healthz
# Should return: ok

curl http://localhost

# Check HAProxy stats
curl http://localhost:9000/stats
```

#### Test External DNS (from your laptop)

```bash
# Test Route53 DNS
dig api.sno.example.com
# Should return: 3.145.67.89 (EC2 public IP)

dig console.apps.sno.example.com
# Should return: 3.145.67.89 (EC2 public IP)

# Test access via HAProxy
curl -k https://api.sno.example.com:6443/healthz
# Should return: ok

curl -k https://console.apps.sno.example.com
# Should load OpenShift console
```

## Traffic Flow Examples

### Example 1: Internal VM Accesses API

```
OpenShift VM
  ↓ DNS query: api.sno.example.com
Bind DNS
  ↓ Returns: 192.168.122.10
OpenShift VM
  ↓ HTTPS to 192.168.122.10:6443
OpenShift API VIP
  ✓ Direct connection (no proxy)
```

**Latency**: <1ms (VM to VM)

### Example 2: External User Accesses API

```
External User
  ↓ DNS query: api.sno.example.com
Route53
  ↓ Returns: 3.145.67.89 (EC2 public IP)
External User
  ↓ HTTPS to 3.145.67.89:6443
HAProxy on EC2
  ↓ Proxy to 192.168.122.10:6443
OpenShift API VIP
  ✓ Proxied connection
```

**Latency**: ~20-50ms (internet + proxy)

### Example 3: External User Accesses Console

```
External User
  ↓ DNS query: console-openshift-console.apps.sno.example.com
Route53
  ↓ Returns: 3.145.67.89 (EC2 public IP)
External User
  ↓ HTTPS to 3.145.67.89:443
HAProxy on EC2
  ↓ TCP passthrough to 192.168.122.11:443
OpenShift Ingress VIP
  ↓ Routes to console pod
Console Pod
  ✓ Console loads
```

## Configuration Files

### Bind DNS

**Location**: `/etc/named.conf`, `/var/named/example.com.zone`

```bind
; Forward zone
api.sno             IN  A       192.168.122.10
*.apps.sno          IN  A       192.168.122.11
```

### HAProxy

**Location**: `/etc/haproxy/haproxy.cfg`

```
frontend api_frontend
    bind *:6443
    default_backend api_backend

backend api_backend
    server api 192.168.122.10:6443 check
```

### Route53

**Records**:
```
api.sno.example.com        A    3.145.67.89
*.apps.sno.example.com     A    3.145.67.89
```

## Firewall Ports

### EC2 Security Group

Must allow inbound:
- **22/tcp**: SSH
- **6443/tcp**: OpenShift API
- **443/tcp**: HTTPS (apps)
- **80/tcp**: HTTP (apps)
- **9000/tcp**: HAProxy stats (optional)

### EC2 Instance Firewall (firewalld)

Automatically configured by playbooks:
- ✅ DNS (53/tcp, 53/udp)
- ✅ API (6443/tcp)
- ✅ HTTP (80/tcp)
- ✅ HTTPS (443/tcp)
- ✅ HAProxy stats (9000/tcp)

## VIP Discovery

The HAProxy role automatically discovers VIPs:

### API VIP Discovery

```bash
oc get infrastructure cluster \
  -o jsonpath='{.status.apiServerInternalURL}' \
  | sed 's|https://||' | cut -d: -f1
```

Example output: `192.168.122.10`

### Ingress VIP Discovery

Tries in order:
1. `oc get service router-default -n openshift-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`
2. `oc get service router-default -n openshift-ingress -o jsonpath='{.spec.clusterIP}'`
3. Parse from `install-config.yaml`

Example output: `192.168.122.11`

## Troubleshooting

### DNS Not Resolving Correctly

**Symptom**: Wrong IP returned

```bash
# Check which DNS server you're using
cat /etc/resolv.conf

# Test specific DNS server
dig @127.0.0.1 api.sno.example.com     # Bind
dig @8.8.8.8 api.sno.example.com       # Route53

# Expected results:
# Bind → 192.168.122.10
# Route53 → 3.145.67.89
```

### HAProxy Connection Refused

**Symptom**: Cannot connect to EC2 public IP

```bash
# 1. Check HAProxy is running
ssh ec2-user@<ec2-ip>
sudo systemctl status haproxy

# 2. Check HAProxy is listening
sudo ss -tlnp | grep haproxy
# Should show :6443, :443, :80

# 3. Test backend from EC2
curl -k https://192.168.122.10:6443/healthz

# 4. Check firewall
sudo firewall-cmd --list-all
```

### VIP Discovery Failed

**Symptom**: Error discovering VIPs

```bash
# Manually check cluster
export KUBECONFIG=~/openshift-install/auth/kubeconfig

# Get API VIP
oc get infrastructure cluster -o yaml

# Get Ingress VIP
oc get service router-default -n openshift-ingress

# Check install-config
cat ~/openshift-install/install-config.yaml
```

### External Access Works, Internal Doesn't

**Symptom**: Can access from internet but not from VMs

```bash
# Check Bind DNS on EC2
ssh ec2-user@<ec2-ip>
sudo systemctl status named

# Test Bind resolution
dig @localhost api.sno.example.com

# Check VM DNS configuration
# On VM:
cat /etc/resolv.conf
# Should have: nameserver 192.168.122.1 or nameserver <ec2-private-ip>
```

### Internal Access Works, External Doesn't

**Symptom**: VMs can access, internet cannot

```bash
# 1. Check AWS Security Group
aws ec2 describe-security-groups --group-ids <sg-id>
# Must allow ports 6443, 443, 80

# 2. Check Route53 DNS
dig api.sno.example.com
# Should return EC2 public IP, not private IP

# 3. Test HAProxy from EC2
ssh ec2-user@<ec2-ip>
curl -k https://localhost:6443/healthz
```

## Security Considerations

### Public Exposure

✅ **Exposed to internet**:
- HAProxy on ports 6443, 443, 80
- HAProxy stats on port 9000 (optional, can disable)

❌ **NOT exposed**:
- OpenShift VMs (private IPs only)
- Bind DNS (internal only)
- OpenShift API directly (via HAProxy only)

### Best Practices

1. **Change HAProxy stats password**:
   ```bash
   ansible-playbook configure-haproxy-proxy.yml \
     -e haproxy_stats_password="SecurePassword123"
   ```

2. **Restrict SSH access** in AWS Security Group

3. **Use strong pull secret** for OpenShift

4. **Enable AWS GuardDuty** for threat detection

5. **Monitor HAProxy logs**:
   ```bash
   sudo journalctl -u haproxy -f
   ```

## Performance Optimization

### HAProxy Tuning

For high traffic, edit `/etc/haproxy/haproxy.cfg`:

```
global
    maxconn     20000

defaults
    timeout client  10m
    timeout server  10m
```

Then restart:
```bash
sudo systemctl restart haproxy
```

### DNS Caching

Internal VMs benefit from Bind caching:
- First query: ~5ms
- Cached query: <1ms

### Connection Pooling

HAProxy maintains connection pools to backends:
- Reduces connection overhead
- Better performance for high request rates

## Cost Analysis

### With Split-Horizon (This Setup)

- EC2 Instance: $3.50/hour (m8i.16xlarge)
- EC2 Public IP: $0.00 (included)
- Route53 Hosted Zone: $0.50/month
- Route53 Queries: $0.40 per million
- **Total**: ~$2,520/month + Route53

### Without Split-Horizon (All Public IPs)

- EC2 Instance: $3.50/hour
- EC2 Public IP: $0.00
- Additional Public IPs: $3.65/month each × 6 = $21.90/month
- Route53 Hosted Zone: $0.50/month
- **Total**: ~$2,542/month + Route53

**Savings**: $22/month + simplified architecture

## Comparison with Other Solutions

| Approach | Pros | Cons |
|----------|------|------|
| **Split-Horizon (This)** | ✅ Single public IP<br>✅ Fast internal access<br>✅ Cost effective | ⚠️ HAProxy SPOF<br>⚠️ More complex setup |
| **All Public IPs** | ✅ Simple<br>✅ No proxy | ❌ Multiple public IPs<br>❌ Higher cost<br>❌ More attack surface |
| **VPN Only** | ✅ Very secure<br>✅ No public exposure | ❌ VPN required<br>❌ Not internet-accessible |
| **Load Balancer** | ✅ High availability<br>✅ Auto-scaling | ❌ Expensive<br>❌ Overkill for demo |

## Migration Paths

### From Bind-Only to Split-Horizon

If you started with just Bind:

```bash
# 1. Verify OpenShift is running
oc get nodes

# 2. Add HAProxy
ansible-playbook configure-haproxy-proxy.yml

# 3. Add Route53
ansible-playbook configure-dns-route53.yml \
  -e api_vip=<EC2_PUBLIC_IP> \
  -e ingress_vip=<EC2_PUBLIC_IP>
```

### From Split-Horizon to VPN

If you want to remove public access:

```bash
# 1. Remove Route53 records
aws route53 change-resource-record-sets --delete ...

# 2. Stop HAProxy
sudo systemctl stop haproxy
sudo systemctl disable haproxy

# 3. Update security group (remove 6443, 443, 80)

# 4. Set up VPN (OpenVPN, WireGuard, etc.)
```

## References

- [HAProxy Documentation](http://www.haproxy.org/)
- [OpenShift DNS Requirements](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal.html#installation-dns-user-infra_installing-bare-metal)
- [Route53 Documentation](https://docs.aws.amazon.com/route53/)
- [Split-Horizon DNS](https://en.wikipedia.org/wiki/Split-horizon_DNS)
