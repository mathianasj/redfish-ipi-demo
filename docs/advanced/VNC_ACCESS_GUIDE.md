# noVNC Web-Based GUI Access Guide

Quick guide for accessing the EC2 instance desktop via web browser - **no VNC client needed!**

## Setup

Run once to install and configure noVNC web access:

```bash
ansible-playbook setup-vnc-gui.yml
```

Custom options:
```bash
# Use GNOME instead of XFCE
ansible-playbook setup-vnc-gui.yml -e desktop_environment=gnome

# Custom VNC password
ansible-playbook setup-vnc-gui.yml -e vnc_password=MySecurePassword

# Custom ports
ansible-playbook setup-vnc-gui.yml -e novnc_http_port=8080 -e novnc_https_port=8443
```

## Accessing the Desktop

### Get Your EC2 Public IP

```bash
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=nested-virt-host" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text
```

### Option 1: HTTPS Access (Recommended)

**Open in your browser:**
```
https://<EC2_PUBLIC_IP>:6081/vnc.html
```

**Steps:**
1. You'll see a certificate warning (self-signed cert)
2. Accept the warning and proceed
3. Click "Connect" button in noVNC interface
4. Enter VNC password: `redhat123` (or your custom password)
5. You'll see the desktop in your browser!

**Benefits:**
- Encrypted connection
- Secure traffic
- Works on any modern browser

### Option 2: HTTP Access

**Open in your browser:**
```
http://<EC2_PUBLIC_IP>:6080/vnc.html
```

**Steps:**
1. Click "Connect" button
2. Enter VNC password: `redhat123`
3. Desktop appears in browser

**Benefits:**
- No certificate warning
- Simpler access
- Good for lab/testing

**Warning:** Unencrypted - don't use for sensitive data over untrusted networks.

## Quick Access URLs

After setup completes, you can bookmark these:

```
HTTP:  http://<EC2_PUBLIC_IP>:6080/vnc.html
HTTPS: https://<EC2_PUBLIC_IP>:6081/vnc.html
```

## Using OpenShift Console in noVNC

Once connected to desktop in your browser:

1. **Open Firefox** (pre-installed in the desktop)

2. **Get OpenShift Console URL:**
   - Open Terminal in the desktop
   - Run: `oc whoami --show-console`
   - Or just browse to: `https://console-openshift-console.apps.ocp.example.com`

3. **Login:**
   - **No certificate warnings** - CA is already trusted!
   - Username: `kubeadmin`
   - Password: Get from installation output or:
     ```bash
     cat ~/openshift-install/auth/kubeadmin-password
     ```

4. **Access OpenShift** web console directly in the remote desktop!

## noVNC Interface Features

When connected, you'll see noVNC controls on the left sidebar:

### Controls

- **Gear Icon (Settings)**:
  - Adjust image quality
  - Change compression
  - Configure scaling
  - Clipboard settings

- **Clipboard Icon**:
  - Transfer text between local and remote
  - Copy from your computer, paste in desktop
  - Copy from desktop, paste on your computer

- **Fullscreen Icon**:
  - Toggle fullscreen mode
  - Press ESC to exit fullscreen

- **Scaling Icon**:
  - Remote Resizing: Desktop follows browser window
  - Local Scaling: Fit desktop to browser window
  - Remote + Local: Combination of both

- **Keyboard Icon**:
  - Send special keys (Ctrl+Alt+Del, etc.)
  - Extra keys for special functions

- **Disconnect**:
  - Close VNC session (desktop keeps running)

### Keyboard Shortcuts

- **Ctrl+Alt+Shift**: Show noVNC menu
- **Tab**: Send Tab to desktop (not browser)
- **Special keys**: Use keyboard icon for Ctrl+Alt+Del, etc.

## Supported Browsers

Works on **any modern browser**:

- ✅ Google Chrome / Chromium (recommended)
- ✅ Mozilla Firefox (recommended)
- ✅ Microsoft Edge
- ✅ Safari
- ✅ Mobile browsers (Chrome, Safari on iOS/Android)
- ✅ Any HTML5-capable browser

**No installation needed** - just open the URL!

## Mobile Access

Yes, it works on phones and tablets!

**iOS (iPhone/iPad):**
```
Safari: https://<EC2_IP>:6081/vnc.html
```

**Android:**
```
Chrome: https://<EC2_IP>:6081/vnc.html
```

**Tips:**
- Use landscape orientation for better view
- Pinch to zoom
- Touch gestures for mouse
- Virtual keyboard pops up automatically

## Troubleshooting

### Can't Access Web Page

**1. Check services:**
```bash
ssh ec2-user@<EC2_IP> -i ~/.ssh/id_rsa_fips
sudo systemctl status novnc-http.service
sudo systemctl status novnc-https.service
```

**2. Restart services:**
```bash
sudo systemctl restart novnc-http.service
sudo systemctl restart novnc-https.service
sudo systemctl restart vncserver@1.service
```

**3. Check firewall:**
```bash
sudo firewall-cmd --list-ports | grep -E '6080|6081'
```

**4. Check security group:**
- AWS Console → EC2 → Security Groups
- Verify inbound rules for ports 6080 and 6081

### Black/Gray Screen

**Restart all services:**
```bash
ssh ec2-user@<EC2_IP> -i ~/.ssh/id_rsa_fips
sudo systemctl restart vncserver@1.service
sudo systemctl restart novnc-http.service
sudo systemctl restart novnc-https.service
```

### Certificate Warning (HTTPS)

**This is expected!**

The certificate is self-signed. You need to accept it:

- **Chrome**: Click "Advanced" → "Proceed to <IP> (unsafe)"
- **Firefox**: Click "Advanced" → "Accept the Risk and Continue"
- **Safari**: Click "Show Details" → "visit this website"
- **Edge**: Click "Advanced" → "Continue to <IP> (unsafe)"

This is safe - you're connecting to your own EC2 instance.

### Slow Performance

**1. Use HTTP instead of HTTPS:**
- Slightly faster (no encryption overhead)
- Good for lab use

**2. Adjust quality in noVNC:**
- Click Settings (gear icon)
- Reduce "Compression level"
- Set "Quality" to lower value

**3. Lower screen resolution:**
```bash
ssh ec2-user@<EC2_IP> -i ~/.ssh/id_rsa_fips
echo "geometry=1280x720" >> ~/.vnc/config
sudo systemctl restart vncserver@1.service
```

**4. Use XFCE instead of GNOME:**
```bash
ansible-playbook setup-vnc-gui.yml -e desktop_environment=xfce
```

### Password Prompt Keeps Appearing

**Change password:**
```bash
ssh ec2-user@<EC2_IP> -i ~/.ssh/id_rsa_fips
vncpasswd
# Enter new password twice
sudo systemctl restart vncserver@1.service
sudo systemctl restart novnc-http.service
sudo systemctl restart novnc-https.service
```

## Security Tips

### Change Default Password

```bash
ssh ec2-user@<EC2_IP> -i ~/.ssh/id_rsa_fips
vncpasswd
# Enter new password
sudo systemctl restart vncserver@1.service
sudo systemctl restart novnc-http.service
sudo systemctl restart novnc-https.service
```

Or set during playbook run:
```bash
ansible-playbook setup-vnc-gui.yml -e vnc_password=MyNewPassword
```

### Use HTTPS Only

Disable HTTP for better security:
```bash
ssh ec2-user@<EC2_IP> -i ~/.ssh/id_rsa_fips
sudo systemctl stop novnc-http.service
sudo systemctl disable novnc-http.service
```

### Restrict IP Access

Edit AWS security group to only allow your IP address:
- Change source from `0.0.0.0/0` to `YOUR_IP/32`

### SSH Tunnel (Most Secure)

Forward noVNC through SSH:
```bash
ssh -L 6081:localhost:6081 ec2-user@<EC2_IP> -i ~/.ssh/id_rsa_fips

# Then browse to:
https://localhost:6081/vnc.html
```

Benefits:
- No public noVNC ports needed
- All traffic through SSH tunnel
- Maximum security

## Management Commands

```bash
# SSH into EC2 instance
ssh ec2-user@<EC2_IP> -i ~/.ssh/id_rsa_fips

# Check all services
sudo systemctl status vncserver@1.service
sudo systemctl status novnc-http.service
sudo systemctl status novnc-https.service

# Restart everything
sudo systemctl restart vncserver@1.service
sudo systemctl restart novnc-http.service
sudo systemctl restart novnc-https.service

# View logs
sudo journalctl -u novnc-http.service -f
sudo journalctl -u novnc-https.service -f
sudo journalctl -u vncserver@1.service -f

# Check what's listening
sudo netstat -tlnp | grep -E '6080|6081|5901'
```

## Features

- ✅ **No VNC client needed** - just a web browser
- ✅ **Works everywhere** - desktop, laptop, tablet, phone
- ✅ **Copy/paste** between local and remote
- ✅ **Fullscreen mode** for immersive experience
- ✅ **Encrypted HTTPS** option
- ✅ **OpenShift console access** with trusted certificates
- ✅ **Auto-start** on boot
- ✅ **Responsive** - adapts to browser window size

## What You Can Do

- ✅ Access OpenShift console in Firefox (no cert warnings!)
- ✅ Run OpenShift CLI commands in terminal
- ✅ Monitor VMs with virt-manager (if installed)
- ✅ Browse files with GUI file manager
- ✅ Open multiple terminal windows
- ✅ Copy/paste between local and remote desktop
- ✅ Access from anywhere with internet
- ✅ Use any device (desktop, laptop, tablet, phone)

## Quick Reference Card

```
╔═══════════════════════════════════════════════════════╗
║ noVNC Quick Reference                                 ║
╠═══════════════════════════════════════════════════════╣
║ HTTP Port:          6080                              ║
║ HTTPS Port:         6081                              ║
║ VNC Password:       redhat123                         ║
║ Desktop:            XFCE                              ║
║ Resolution:         1920x1080                         ║
╠═══════════════════════════════════════════════════════╣
║ Access URLs:                                          ║
║   HTTP:   http://<EC2_IP>:6080/vnc.html               ║
║   HTTPS:  https://<EC2_IP>:6081/vnc.html              ║
╠═══════════════════════════════════════════════════════╣
║ Connection:                                           ║
║   1. Open URL in browser                              ║
║   2. Accept certificate (HTTPS only)                  ║
║   3. Click "Connect"                                  ║
║   4. Enter password: redhat123                        ║
║   5. Desktop appears!                                 ║
╠═══════════════════════════════════════════════════════╣
║ Services:                                             ║
║   VNC:         sudo systemctl restart vncserver@1     ║
║   noVNC HTTP:  sudo systemctl restart novnc-http      ║
║   noVNC HTTPS: sudo systemctl restart novnc-https     ║
╠═══════════════════════════════════════════════════════╣
║ OpenShift Console:                                    ║
║   URL:     oc whoami --show-console                   ║
║   User:    kubeadmin                                  ║
║   CA:      Trusted (no warnings)                      ║
╠═══════════════════════════════════════════════════════╣
║ Browsers:                                             ║
║   ✅ Chrome/Chromium (recommended)                     ║
║   ✅ Firefox (recommended)                             ║
║   ✅ Safari, Edge, mobile browsers                     ║
║   ✅ Any HTML5 browser                                 ║
╚═══════════════════════════════════════════════════════╝
```

## Common Use Cases

### 1. Quick OpenShift Console Check

```
1. Open: https://<EC2_IP>:6081/vnc.html
2. Connect with password
3. Open Firefox in desktop
4. Browse to OpenShift console
5. No certificate warnings!
```

### 2. Run OpenShift Commands

```
1. Connect to noVNC desktop
2. Open Terminal
3. Run: oc get nodes
4. Run: oc get pods -A
```

### 3. Monitor VM Status

```
1. Connect to noVNC desktop
2. Open Terminal
3. Run: sudo virsh list --all
4. Run: watch 'sudo virsh list --all'
```

### 4. File Management

```
1. Connect to noVNC desktop
2. Open File Manager
3. Browse, copy, move files with GUI
4. Copy/paste file paths
```

### 5. Mobile Monitoring

```
1. Open browser on phone/tablet
2. Browse to HTTPS URL
3. Accept certificate
4. Connect
5. Monitor from anywhere!
```

## Pro Tips

1. **Bookmark the URLs** - save HTTP and HTTPS links for quick access

2. **Use HTTPS in production** - always use encrypted connection for security

3. **Fullscreen for immersive experience** - click fullscreen icon in noVNC

4. **Clipboard for copy/paste** - use clipboard icon to transfer text

5. **Adjust quality for slow connections** - Settings → reduce quality/compression

6. **Multiple tabs** - open multiple browser tabs for different views

7. **Mobile landscape mode** - rotate phone/tablet for better view

8. **SSH tunnel for maximum security** - forward through SSH when possible

## Comparison: Traditional VNC vs noVNC

| Feature | Traditional VNC | noVNC (This Setup) |
|---------|-----------------|-------------------|
| Client | Need VNC app | Just web browser |
| Installation | Install software | Nothing to install |
| Mobile | Limited apps | Any mobile browser |
| Encryption | Need SSH tunnel | Built-in HTTPS |
| Accessibility | Desktop/laptop only | Any device with browser |
| Setup | Configure client | Just click URL |
| Updates | Update client | Always latest |
| Firewall | Often blocked | HTTP/HTTPS allowed |

## Next Steps

After connecting:

1. **Explore the desktop** - XFCE/GNOME interface
2. **Open Firefox** - browse OpenShift console
3. **Open Terminal** - run `oc` commands
4. **Customize** - adjust settings, resolution, quality
5. **Bookmark** - save URLs for quick access

Enjoy web-based desktop access to your OpenShift environment!
