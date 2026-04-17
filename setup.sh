#!/bin/bash
set -e

VENV_DIR="venv"

echo "=================================================="
echo "EC2 Nested Virtualization Setup"
echo "=================================================="

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required but not installed."
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
else
    echo "Virtual environment already exists in $VENV_DIR"
fi

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install Python dependencies
echo "Installing Python dependencies..."
pip install -r requirements.txt

# Install Ansible collections
echo "Installing Ansible collections..."
ansible-galaxy collection install -r requirements.yml

echo ""
echo "=================================================="
echo "Setup complete!"
echo "=================================================="
echo ""
echo "🎉 Virtual environment created and activated!"
echo ""
echo "To activate the virtual environment in your current shell:"
echo "   source venv/bin/activate"
echo ""
echo "To deactivate when done:"
echo "   deactivate"
echo ""
echo "Next steps:"
echo "1. Ensure you have an SSH key pair generated:"
echo "   If not: ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa"
echo "2. Configure your AWS credentials (aws configure)"
echo "3. IMPORTANT: Update group_vars/all.yml with your settings:"
echo "   - cockpit_admin_password: CHANGE THIS to a secure password!"
echo "   - ssh_public_key_path: Path to your SSH public key (default: ~/.ssh/id_rsa.pub)"
echo "   - aws_region: Your preferred region (default: us-east-2)"
echo "   - instance_type: Choose based on budget (see INSTANCE_TYPES.md)"
echo "4. Activate the virtual environment:"
echo "   source venv/bin/activate"
echo "5. Run: ansible-playbook playbook.yml"
echo ""
echo "💰 Cost Information:"
echo "   Default instance (m7i.16xlarge): ~\$6.45/hour (~\$4,644/month)"
echo "   For testing, consider m7i.large: ~\$0.20/hour (~\$144/month)"
echo "   See INSTANCE_TYPES.md for all options and pricing"
echo ""
echo "💡 Tip: Use spot instances for 60-90% savings!"
echo ""
