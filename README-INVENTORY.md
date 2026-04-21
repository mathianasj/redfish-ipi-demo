# Dynamic Inventory for EC2 Instance

This repository uses dynamic inventory to automatically discover the EC2 instance created by the main playbook.

## How It Works

The `inventory-ec2.yml` playbook automatically finds your running EC2 instance and adds it to the `nested_virt_hosts` group.

## Usage

### Standalone Playbooks

Most standalone playbooks automatically import `inventory-ec2.yml`:

```bash
# These automatically discover the EC2 instance
ansible-playbook configure-mirror-registry.yml
ansible-playbook setup-vnc-gui.yml
ansible-playbook scale-workers.yml
```

### Override Region

If your EC2 instance is in a different region:

```bash
ansible-playbook configure-mirror-registry.yml -e aws_region=us-east-1
```

### Override SSH Key

If you use a different SSH key:

```bash
ansible-playbook configure-mirror-registry.yml -e ssh_private_key_path=~/.ssh/my-key
```

### Test Dynamic Inventory

To test the inventory discovery:

```bash
ansible-playbook inventory-ec2.yml
```

This will:
- Search for the EC2 instance in the specified region
- Display instance details
- Add it to the `nested_virt_hosts` group

## Default Values

The inventory discovery uses these defaults:

```yaml
aws_region: us-east-2
instance_name: nested-virt-host
ssh_private_key_path: ~/.ssh/id_rsa_fips
```

All can be overridden with `-e` flags.

## No Static Inventory File

This repository **does not use** a static inventory file (`inventory`, `hosts.ini`, etc.). 

Instead, playbooks use one of these methods:

1. **Import inventory-ec2.yml** - Recommended for new playbooks
   ```yaml
   - import_playbook: inventory-ec2.yml
   ```

2. **Inline discovery** - Some older playbooks have inline discovery logic
   ```yaml
   - name: Find EC2 instance
     hosts: localhost
     tasks:
       - amazon.aws.ec2_instance_info: ...
       - add_host: ...
   ```

## Troubleshooting

### "No running EC2 instance found"

Your instance either:
- Doesn't exist (create with `ansible-playbook playbook.yml`)
- Is stopped (start with `ansible-playbook start-instance.yml`)
- Is in a different region (override with `-e aws_region=<region>`)

### "Unable to parse inventory"

This warning can be ignored if you're not using a static inventory file. The playbooks use dynamic inventory instead.

### "Could not match supplied host pattern, ignoring: nested_virt_hosts"

This means the playbook ran before the inventory was discovered. Make sure:
- The playbook imports `inventory-ec2.yml` first
- OR the playbook has its own discovery logic
- Your EC2 instance is running

## Creating a Static Inventory (Optional)

If you prefer a static inventory file, create `inventory`:

```ini
[nested_virt_hosts]
1.2.3.4 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/id_rsa_fips
```

Then use it:
```bash
ansible-playbook -i inventory configure-mirror-registry.yml
```

However, dynamic inventory is recommended as it automatically adapts when you recreate the instance.
