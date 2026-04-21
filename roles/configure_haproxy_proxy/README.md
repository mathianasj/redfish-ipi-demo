# HAProxy Reverse Proxy for OpenShift

This role configures HAProxy on the EC2 instance to act as a reverse proxy/passthrough for OpenShift cluster traffic.

## Purpose

Enables external access to OpenShift cluster running on private IPs by:
- Proxying API traffic (port 6443) to internal API VIP
- Proxying HTTPS traffic (port 443) to internal ingress VIP
- Proxying HTTP traffic (port 80) to internal ingress VIP

**Important:** This role **automatically discovers** the API and Ingress VIPs from the running OpenShift cluster. You do not need to specify them.

## Architecture

```
Internet
    ↓
EC2 Public IP (HAProxy)
    ├─ Port 6443 → [Discovered API VIP]:6443 (OpenShift API)
    ├─ Port 443  → [Discovered Ingress VIP]:443  (OpenShift Apps HTTPS)
    └─ Port 80   → [Discovered Ingress VIP]:80   (OpenShift Apps HTTP)
```

## Split-Horizon DNS Setup

This role is designed to work with split-horizon DNS:

**External DNS (Route53):**
- `api.sno.example.com` → EC2 Public IP
- `*.apps.sno.example.com` → EC2 Public IP

**Internal DNS (Bind):**
- `api.sno.example.com` → [Discovered API VIP]
- `*.apps.sno.example.com` → [Discovered Ingress VIP]

**Traffic Flow:**
1. External user queries Route53 → gets EC2 public IP
2. Connects to EC2 public IP:6443
3. HAProxy proxies to internal API VIP:6443
4. Internal VMs query Bind → get private IPs directly

## Prerequisites

- OpenShift cluster must be installed and running
- Kubeconfig must exist at `~/openshift-install/auth/kubeconfig`
- `oc` CLI must be installed and in PATH

## Role Variables

### Optional Variables

- `openshift_install_dir`: Directory containing OpenShift installation (default: `~/openshift-install`)
- `haproxy_stats_enabled`: Enable HAProxy statistics page (default: `true`)
- `haproxy_stats_user`: Stats page username (default: `admin`)
- `haproxy_stats_password`: Stats page password (default: `admin`)
- `haproxy_stats_port`: Stats page port (default: `9000`)

### Discovered Variables (Read from Cluster)

The role automatically discovers these from the running cluster:
- `openshift_api_ip`: API VIP (discovered from cluster infrastructure)
- `openshift_ingress_ip`: Ingress VIP (discovered from router service)

## How VIP Discovery Works

The role uses these methods to discover VIPs:

1. **API VIP**: Reads from `oc get infrastructure cluster`
2. **Ingress VIP**: Tries in order:
   - Router service LoadBalancer IP
   - Router service ClusterIP
   - Install-config.yaml ingressVIPs field

## Usage

### Basic Usage

```yaml
- hosts: nested_virt_hosts
  become: true
  roles:
    - role: configure_haproxy_proxy
```

VIPs are automatically discovered - no configuration needed!

### Custom OpenShift Directory

```yaml
- hosts: nested_virt_hosts
  become: true
  roles:
    - role: configure_haproxy_proxy
      vars:
        openshift_install_dir: /opt/openshift
```

### Custom Stats Password

```yaml
- hosts: nested_virt_hosts
  become: true
  roles:
    - role: configure_haproxy_proxy
      vars:
        haproxy_stats_password: "SecurePassword123"
```

## Ports Opened

This role opens the following firewall ports:

- **6443/tcp**: OpenShift API
- **443/tcp**: HTTPS (apps/routes)
- **80/tcp**: HTTP (apps/routes)
- **9000/tcp**: HAProxy statistics (optional)

## HAProxy Configuration

The HAProxy configuration uses:
- **Mode: TCP** - Pure TCP passthrough (no SSL termination)
- **SNI Inspection** - For HTTPS traffic routing
- **Health Checks** - Monitors backend availability
- **Round Robin** - Load balancing (if multiple backends added)

## Testing

### Test API Access

```bash
# From external machine
curl -k https://<ec2-public-ip>:6443/healthz

# Should return: ok
```

### Test Apps Access

```bash
# HTTP
curl http://<ec2-public-ip>

# HTTPS
curl -k https://<ec2-public-ip>
```

### View HAProxy Stats

```
http://<ec2-public-ip>:9000/stats
Username: admin
Password: admin (or custom password)
```

### Check HAProxy Status

```bash
ssh ec2-user@<ec2-public-ip>

# Check service
sudo systemctl status haproxy

# View logs
sudo journalctl -u haproxy -f

# Test configuration
sudo haproxy -f /etc/haproxy/haproxy.cfg -c

# View current connections
echo "show stat" | sudo socat stdio /var/lib/haproxy/stats
```

## Security Considerations

1. **Firewall**: Only required ports are opened
2. **SELinux**: Configured to allow HAProxy connections
3. **Stats Password**: Change default stats password in production
4. **SSL/TLS**: HAProxy does pure TCP passthrough - OpenShift handles SSL
5. **AWS Security Groups**: Ensure security group allows ports 80, 443, 6443

## Troubleshooting

### Cluster Not Found

```
Error: OpenShift cluster not found
```

**Solution**: Ensure OpenShift is installed first:
```bash
ansible-playbook prepare-and-install-openshift.yml
```

### VIP Discovery Failed

```
Error: Failed to discover API VIP
```

**Solution**: Check cluster status:
```bash
export KUBECONFIG=~/openshift-install/auth/kubeconfig
oc get infrastructure cluster
oc get service router-default -n openshift-ingress
```

### HAProxy Won't Start

```bash
# Check configuration syntax
sudo haproxy -f /etc/haproxy/haproxy.cfg -c

# Check SELinux denials
sudo ausearch -m avc -ts recent | grep haproxy

# Check logs
sudo journalctl -u haproxy -n 50
```

### Connection Refused

```bash
# Verify discovered IPs are reachable
ping <api-vip>
ping <ingress-vip>

# Test backend directly from EC2
curl -k https://<api-vip>:6443/healthz
curl -k https://<ingress-vip>

# Check HAProxy stats
curl http://localhost:9000/stats
```

### Firewall Issues

```bash
# Check firewall rules
sudo firewall-cmd --list-all

# Verify ports are listening
sudo ss -tlnp | grep haproxy

# Test from external
telnet <ec2-public-ip> 6443
telnet <ec2-public-ip> 443
```

## Performance Tuning

For high-traffic scenarios, adjust in `/etc/haproxy/haproxy.cfg`:

```
global
    maxconn     10000  # Increase max connections

defaults
    timeout client  5m   # Increase timeouts for long-running connections
    timeout server  5m
```

## Integration with DNS

This role works with the split-horizon DNS setup:

1. **Install OpenShift cluster first**:
   ```bash
   ansible-playbook prepare-and-install-openshift.yml
   ```

2. **Configure internal Bind DNS** (with discovered VIPs):
   ```bash
   ansible-playbook configure-dns.yml
   ```

3. **Configure HAProxy proxy** (VIPs auto-discovered):
   ```bash
   ansible-playbook configure-haproxy-proxy.yml
   ```

4. **Get EC2 public IP**:
   ```bash
   EC2_PUBLIC_IP=$(aws ec2 describe-instances \
     --filters "Name=tag:Name,Values=nested-virt-host" \
     --query 'Reservations[0].Instances[0].PublicIpAddress' \
     --output text)
   ```

5. **Configure external Route53 DNS** (pointing to EC2 public IP):
   ```bash
   ansible-playbook configure-dns-route53.yml \
     -e route53_hosted_zone_id=Z1234567890ABC \
     -e api_vip=$EC2_PUBLIC_IP \
     -e ingress_vip=$EC2_PUBLIC_IP
   ```

Note: For Route53, both api_vip and ingress_vip should be the **EC2 public IP**, not the internal OpenShift VIPs.

## Example: Complete Split-Horizon Setup

```bash
# 1. Install OpenShift
ansible-playbook prepare-and-install-openshift.yml

# 2. Configure internal DNS (uses discovered VIPs)
ansible-playbook configure-dns.yml

# 3. Configure HAProxy (discovers VIPs from cluster)
ansible-playbook configure-haproxy-proxy.yml

# 4. Get EC2 public IP
EC2_IP=$(ssh ec2-user@<instance> curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# 5. Configure external DNS (points to EC2 public IP)
ansible-playbook configure-dns-route53.yml \
  -e route53_hosted_zone_id=Z1234567890ABC \
  -e api_vip=$EC2_IP \
  -e ingress_vip=$EC2_IP
```

Now you have:
- **Internal clients** → Bind DNS → Direct to OpenShift VIPs (fast, no proxy)
- **External clients** → Route53 → EC2 public IP → HAProxy → OpenShift VIPs

## References

- [HAProxy Documentation](http://www.haproxy.org/docs.html)
- [OpenShift Load Balancing](https://docs.openshift.com/container-platform/latest/installing/installing_bare_metal/installing-bare-metal.html#installation-load-balancing-user-infra_installing-bare-metal)
- [HAProxy TCP Mode](http://cbonte.github.io/haproxy-dconv/2.4/configuration.html#mode)
