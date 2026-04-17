---
# Configure VNC GUI Role

Sets up noVNC web-based remote desktop access on the EC2 instance with a graphical desktop environment. Access the desktop directly from your web browser - no VNC client needed!

## Overview

This role provides:

- **Desktop Environment**: Installs GNOME desktop
- **VNC Server**: Configures TigerVNC server (localhost only)
- **noVNC**: Web-based VNC client accessible via browser
- **HTTP & HTTPS Access**: Both encrypted and unencrypted web access
- **Self-signed SSL**: Auto-generated SSL certificate for HTTPS
- **Network Access**: Opens firewall and updates AWS security group
- **OpenShift Integration**: 
  - Trusts OpenShift CA certificate in both system and Firefox
  - Auto-launches Firefox to console
  - Pre-saves kubeadmin credentials in Firefox password manager
  - Zero-click demo experience!
- **Auto-start**: VNC starts automatically on reboot via cron

## Requirements

- EC2 instance running RHEL 9 or compatible
- AWS credentials configured for security group updates
- Sufficient disk space for desktop environment (~2-3 GB)
- OpenShift cluster installed (optional, for CA cert trust)

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `vnc_password` | redhat123 | VNC connection password |
| `vnc_port` | 5901 | VNC server port (localhost only) |
| `vnc_user` | ec2-user | User running VNC server |
| `vnc_display` | 1 | VNC display number (:1) |
| `novnc_http_port` | 6080 | HTTP web access port |
| `novnc_https_port` | 6081 | HTTPS web access port |
| `novnc_install_dir` | /opt/novnc | noVNC installation directory |
| `novnc_ssl_cert_dir` | /etc/novnc/ssl | SSL certificate directory |
| `desktop_environment` | xfce | Desktop to install (xfce or gnome) |
| `aws_region` | us-east-2 | AWS region for security group |
| `instance_name` | nested-virt-host | EC2 instance name tag |
| `vnc_firewall_zone` | public | Firewalld zone |

## Usage

### Basic Setup

```bash
# Set up noVNC with XFCE desktop (recommended)
ansible-playbook setup-vnc-gui.yml

# Set up with GNOME desktop
ansible-playbook setup-vnc-gui.yml -e desktop_environment=gnome

# Custom VNC password
ansible-playbook setup-vnc-gui.yml -e vnc_password=MySecurePassword123

# Custom ports
ansible-playbook setup-vnc-gui.yml -e novnc_http_port=8080 -e novnc_https_port=8443
```

### Accessing the Desktop

**No VNC client needed - just use your web browser!**

**Option 1: HTTPS (Recommended)**

```
https://<EC2_PUBLIC_IP>:6081/vnc.html
```

- Encrypted connection
- Accept self-signed certificate warning
- Enter VNC password when prompted

**Option 2: HTTP**

```
http://<EC2_PUBLIC_IP>:6080/vnc.html
```

- Unencrypted connection
- Simpler (no certificate warning)
- Enter VNC password when prompted

### Accessing OpenShift Console

**Firefox auto-launches to the OpenShift console!**

When you connect to the desktop via browser:

1. You'll see the GNOME desktop in your browser
2. Wait 15-20 seconds for GNOME to fully load
3. **Firefox automatically opens** to the OpenShift console
4. **OpenShift CA certificate is trusted** - no warnings!
5. **Credentials are auto-filled** - just click "Log In"!

If OpenShift wasn't installed when VNC was configured, Firefox won't auto-launch. You can manually open Firefox and browse to the console.

### How It Works

The role automatically:
- Detects the OpenShift console URL
- Extracts the kubeadmin password
- Creates a Firefox profile with autoconfig enabled
- Imports the OpenShift CA certificate into Firefox's certificate database (cert9.db)
- Configures Firefox autoconfig to inject credentials into the login form
- Uses Firefox's `autoconfig.js` mechanism to auto-fill username and password fields

**Technical Details:**
- Firefox autoconfig (`/usr/lib64/firefox/firefox.cfg`) runs JavaScript on page load
- Detects OpenShift OAuth login pages by domain
- Automatically fills `username` and `password` fields
- Dispatches input events to trigger form validation
- Works without browser extensions or password manager

**Result:** Zero-click demo experience - just open noVNC, Firefox auto-launches, credentials auto-fill, click "Log In"!

## What It Does

### 1. Desktop Environment Installation

**XFCE (Default)**:
- Lightweight and fast
- Good for remote browser access
- Uses ~1.5 GB disk space

**GNOME**:
- Full-featured desktop
- More resource intensive
- Uses ~2.5 GB disk space

### 2. VNC Server Configuration

VNC server runs on **localhost only** (more secure):
```
127.0.0.1:5901
```

Only accessible through noVNC web proxy.

```
/home/ec2-user/.vnc/
├── config          # VNC settings (localhost=yes)
├── passwd          # Encrypted VNC password
└── xstartup        # Desktop startup script
```

Systemd service: `vncserver@1.service`

### 3. noVNC Installation

noVNC provides browser-based VNC access:

**Components**:
- noVNC HTML5 client (cloned from GitHub)
- websockify proxy (installed via pip)
- Two systemd services:
  - `novnc-http.service` - HTTP on port 6080
  - `novnc-https.service` - HTTPS on port 6081

**Installation**:
```
/opt/novnc/                 # noVNC files
/etc/novnc/ssl/            # SSL certificates
  ├── novnc.crt            # Certificate
  ├── novnc.key            # Private key
  └── novnc.pem            # Combined (for websockify)
```

### 4. Network Configuration

**Firewalld**:
```bash
# Opens HTTP and HTTPS ports
firewall-cmd --zone=public --add-port=6080/tcp --permanent
firewall-cmd --zone=public --add-port=6081/tcp --permanent
```

**AWS Security Group**:
- Adds inbound rule for port 6080 (HTTP)
- Adds inbound rule for port 6081 (HTTPS)
- Allows access from 0.0.0.0/0 (anywhere)

VNC port 5901 is NOT exposed - only accessible via localhost.

### 5. SSL Certificate

Self-signed certificate auto-generated:
- 3072-bit RSA key
- Valid for 10 years
- Subject CN set to EC2 public IP

**Browser warning**: You'll need to accept the self-signed certificate warning when using HTTPS.

### 6. OpenShift CA Certificate

Extracts CA from kubeconfig and installs to:
```
/etc/pki/ca-trust/source/anchors/openshift-ca.crt
```

Then runs `update-ca-trust` to add to system trust store.

This allows:
- Firefox to trust OpenShift console
- curl/wget to access OpenShift APIs
- No certificate warnings in browser

## Web Browser Access

### Supported Browsers

- Google Chrome / Chromium
- Mozilla Firefox
- Microsoft Edge
- Safari
- Any modern HTML5-capable browser

### Features

- **Full desktop** rendered in browser
- **Clipboard integration** (copy/paste)
- **Keyboard support** (including special keys)
- **Mouse support** (full cursor control)
- **Fullscreen mode** available
- **Scaling options** (fit to window, remote resizing)
- **Touch support** on tablets/phones

### noVNC Controls

When connected, look for the noVNC toolbar (left side of screen):

- **Settings**: Configure display, quality, compression
- **Clipboard**: Transfer text between local and remote
- **Fullscreen**: Toggle fullscreen mode
- **Scaling**: Fit window or native resolution
- **Disconnect**: Close VNC session

## Management Commands

### noVNC Services

```bash
# Check HTTP service
sudo systemctl status novnc-http.service

# Check HTTPS service
sudo systemctl status novnc-https.service

# Restart services
sudo systemctl restart novnc-http.service
sudo systemctl restart novnc-https.service

# View logs
sudo journalctl -u novnc-http.service -f
sudo journalctl -u novnc-https.service -f
```

### VNC Service

```bash
# Check VNC status
ps aux | grep Xvnc

# Start VNC manually
~/start-vnc.sh

# Kill VNC session
vncserver -kill :99

# View VNC logs
cat ~/.vnc/*.log
```

### Manual Control

```bash
# List VNC sessions
vncserver -list

# Kill VNC session
vncserver -kill :1

# Start VNC session (localhost only)
vncserver :1 -geometry 1920x1080 -localhost yes
```

### Change VNC Password

```bash
# As ec2-user
vncpasswd

# Restart services
sudo systemctl restart vncserver@1.service
sudo systemctl restart novnc-http.service
sudo systemctl restart novnc-https.service
```

## Troubleshooting

### Can't Access Web Page

**Check services are running:**
```bash
sudo systemctl status novnc-http.service
sudo systemctl status novnc-https.service
sudo systemctl status vncserver@1.service
```

**Check ports are listening:**
```bash
sudo netstat -tlnp | grep -E '6080|6081'
```

**Check firewall:**
```bash
sudo firewall-cmd --list-ports | grep -E '6080|6081'
```

**Check security group:**
- AWS Console -> EC2 -> Security Groups
- Verify inbound rules for ports 6080 and 6081

**Test connectivity:**
```bash
curl http://<EC2_PUBLIC_IP>:6080/
curl -k https://<EC2_PUBLIC_IP>:6081/
```

### Black/Gray Screen in Browser

**Check VNC is running:**
```bash
sudo systemctl status vncserver@1.service
```

**Check websockify connection:**
```bash
sudo journalctl -u novnc-http.service -n 50
```

**Restart all services:**
```bash
sudo systemctl restart vncserver@1.service
sudo systemctl restart novnc-http.service
sudo systemctl restart novnc-https.service
```

### Connection Refused

**Verify VNC on localhost:**
```bash
# Should show VNC listening on 127.0.0.1:5901
sudo netstat -tlnp | grep 5901
```

**Check websockify proxy:**
```bash
ps aux | grep websockify
```

### SSL Certificate Issues

**Regenerate certificate:**
```bash
sudo rm -rf /etc/novnc/ssl/*
sudo openssl req -x509 -nodes -newkey rsa:3072 \
  -keyout /etc/novnc/ssl/novnc.key \
  -out /etc/novnc/ssl/novnc.crt -days 3650 \
  -subj "/C=US/ST=State/L=City/O=Org/CN=$(hostname -I | awk '{print $1}')"
sudo cat /etc/novnc/ssl/novnc.crt /etc/novnc/ssl/novnc.key > /etc/novnc/ssl/novnc.pem
sudo chmod 600 /etc/novnc/ssl/novnc.pem
sudo systemctl restart novnc-https.service
```

### Performance Issues

**Use HTTP instead of HTTPS:**
- HTTP has slightly less overhead
- HTTPS encrypts all desktop traffic

**Reduce desktop complexity:**
```bash
# Use XFCE instead of GNOME
ansible-playbook setup-vnc-gui.yml -e desktop_environment=xfce
```

**Adjust noVNC quality:**
- In noVNC interface: Settings -> Quality
- Reduce compression quality for faster performance
- Use "Low Quality" for slow connections

**Lower screen resolution:**
Edit `/home/ec2-user/.vnc/config`:
```
geometry=1280x720
```

### OpenShift Certificate Not Trusted

**Check certificate installed:**
```bash
ls -l /etc/pki/ca-trust/source/anchors/openshift-ca.crt
```

**Check Firefox certificate database:**
```bash
certutil -L -d sql:/home/ec2-user/.mozilla/firefox/vnc.default
```

**Manually update system trust:**
```bash
sudo update-ca-trust
```

**Restart Firefox:**
Close and reopen Firefox in the VNC desktop session.

### Credentials Not Auto-Filling

**Check Firefox autoconfig files:**
```bash
ls -l /usr/lib64/firefox/defaults/pref/autoconfig.js
ls -l /usr/lib64/firefox/firefox.cfg
```

**Verify autoconfig content:**
```bash
cat /usr/lib64/firefox/firefox.cfg | grep -A 5 "USERNAME\|PASSWORD"
```

**Test manually:**
1. Open Firefox developer console (F12)
2. Navigate to OpenShift console login page
3. Check console for any JavaScript errors
4. Verify username and password fields are filled

**If still not working:**
- Ensure you're on the correct login page (OAuth login screen)
- Check that Firefox profile is being used: `firefox --profile /home/ec2-user/.mozilla/firefox/vnc.default`
- Restart VNC session to reload Firefox with new config

**Enable auto-submit:**
Edit `/usr/lib64/firefox/firefox.cfg` and uncomment the auto-submit section to have Firefox automatically click the login button.

## Security Considerations

### VNC Password

Default password is `redhat123` - **change this for production**:

```bash
# During playbook run
ansible-playbook setup-vnc-gui.yml -e vnc_password=YourStrongPassword

# Or manually
vncpasswd
sudo systemctl restart vncserver@1.service
sudo systemctl restart novnc-http.service
sudo systemctl restart novnc-https.service
```

### Network Exposure

noVNC is exposed to 0.0.0.0/0 (internet) by default.

**Security improvements:**

**1. Use HTTPS only (disable HTTP)**

```bash
sudo systemctl stop novnc-http.service
sudo systemctl disable novnc-http.service
sudo firewall-cmd --remove-port=6080/tcp --permanent
sudo firewall-cmd --reload
```

**2. Restrict source IP in security group**

Modify AWS security group to only allow your IP:
- Change 0.0.0.0/0 to YOUR_IP/32

**3. Use SSH tunnel**

Forward noVNC through SSH (no security group changes needed):
```bash
ssh -L 6081:localhost:6081 ec2-user@<EC2_IP> -i ~/.ssh/id_rsa_fips
# Access via: https://localhost:6081/vnc.html
```

**4. VPN/Bastion**

- Set up VPN to AWS VPC
- Remove public noVNC access
- Access through VPN

### Encryption

- **HTTP**: Unencrypted (all desktop traffic visible)
- **HTTPS**: Encrypted with self-signed certificate (safe from eavesdropping)

**Recommendation**: Use HTTPS or SSH tunnel for production.

### VNC Localhost Only

VNC server binds to localhost only (`-localhost yes`):
- Cannot be accessed directly from internet
- Only accessible through noVNC proxy
- More secure than exposing VNC directly

## Resource Usage

### XFCE Desktop
- **RAM**: ~500 MB idle, ~1 GB active
- **Disk**: ~1.5 GB
- **CPU**: Low impact

### GNOME Desktop
- **RAM**: ~1.5 GB idle, ~2.5 GB active
- **Disk**: ~2.5 GB
- **CPU**: Moderate impact

### noVNC Services
- **RAM**: ~50 MB per websockify instance (HTTP + HTTPS = ~100 MB)
- **Network**: ~1-5 Mbps depending on activity
- **CPU**: Low impact

### Browser Experience

- **Chrome/Firefox**: Best performance
- **Safari**: Good performance
- **Mobile browsers**: Works but limited on small screens

## HTTP vs HTTPS

| Feature | HTTP | HTTPS |
|---------|------|-------|
| Port | 6080 | 6081 |
| Encryption | None | TLS/SSL |
| Certificate | N/A | Self-signed |
| Browser warning | No | Yes (accept certificate) |
| Performance | Slightly faster | Slight overhead |
| Security | Unencrypted | Encrypted |
| Best for | Lab/testing | Production |

## Advanced Configuration

### Custom Screen Resolution

Edit `/home/ec2-user/.vnc/config`:
```
geometry=2560x1440
```

Restart services:
```bash
sudo systemctl restart vncserver@1.service
```

### Custom SSL Certificate

Replace self-signed with your own:

```bash
# Copy your certificate and key
sudo cp mycert.crt /etc/novnc/ssl/novnc.crt
sudo cp mykey.key /etc/novnc/ssl/novnc.key

# Create combined PEM
sudo cat /etc/novnc/ssl/novnc.crt /etc/novnc/ssl/novnc.key > /etc/novnc/ssl/novnc.pem
sudo chmod 600 /etc/novnc/ssl/novnc.pem

# Restart HTTPS service
sudo systemctl restart novnc-https.service
```

### Custom noVNC Branding

Edit noVNC HTML files in `/opt/novnc/`:
```bash
sudo vim /opt/novnc/vnc.html
```

### Multiple VNC Sessions

```bash
# Start second VNC session
vncserver :2

# Create additional noVNC service
sudo cp /etc/systemd/system/novnc-http.service /etc/systemd/system/novnc-http2.service
# Edit to use port 6082 and localhost:5902

sudo systemctl start novnc-http2.service
```

## Uninstallation

To remove noVNC, VNC, and desktop:

```bash
# Stop services
sudo systemctl stop novnc-http.service novnc-https.service vncserver@1.service
sudo systemctl disable novnc-http.service novnc-https.service vncserver@1.service

# Remove packages
sudo dnf remove -y tigervnc-server @Xfce
sudo pip3 uninstall -y websockify

# Remove files
sudo rm -rf /opt/novnc
sudo rm -rf /etc/novnc
sudo rm -rf ~/.vnc
sudo rm /etc/systemd/system/vncserver@.service
sudo rm /etc/systemd/system/novnc-http.service
sudo rm /etc/systemd/system/novnc-https.service
sudo systemctl daemon-reload

# Remove firewall rules
sudo firewall-cmd --remove-port=6080/tcp --permanent
sudo firewall-cmd --remove-port=6081/tcp --permanent
sudo firewall-cmd --reload

# Remove security group rules (manual via AWS console)
```

## Benefits Over Traditional VNC

| Feature | Traditional VNC | noVNC (This Setup) |
|---------|-----------------|-------------------|
| Client required | Yes (TigerVNC, RealVNC) | No (web browser) |
| Platform | Windows/Mac/Linux apps | Any device with browser |
| Mobile access | Limited apps | Full browser support |
| Encryption | SSH tunnel needed | Built-in HTTPS |
| Firewall | Often blocked | HTTP/HTTPS usually allowed |
| Setup | Install client software | Just click URL |
| Updates | Client updates needed | Always latest (server-side) |

## See Also

- OpenShift console documentation
- noVNC project: https://github.com/novnc/noVNC
- websockify project: https://github.com/novnc/websockify
- XFCE desktop user guide
- TLS/SSL certificate management
