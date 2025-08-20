#!/bin/bash

# Install required Ansible collections for GitOps setup

echo "Installing Ansible collections..."
ansible-galaxy collection install -r requirements.yml

echo "Installation complete!"
echo ""
echo "You can now run the GitOps playbook:"
echo "  ansible-playbook 05-setup-gitops.yml"
