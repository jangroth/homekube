# Ansible Project for Managing Raspberry Pi Computers

This project is designed to manage three local Raspberry Pi computers using Ansible. It includes an inventory of the devices, playbooks for executing tasks, and roles for organizing tasks and configurations.

## Project Structure

```
ansible-project
├── inventory
│   └── hosts.ini          # Inventory file listing Raspberry Pi devices
├── playbooks
│   ├── site.yml           # Main playbook for executing tasks
│   └── tasks
│       └── common.yml     # Common tasks for all devices
├── roles
│   ├── common
│   │   ├── tasks
│   │   │   └── main.yml    # Entry point for common role tasks
│   │   ├── handlers
│   │   │   └── main.yml    # Handlers for the common role
│   │   ├── templates       # Directory for Jinja2 templates
│   │   ├── files           # Directory for static files
│   │   └── vars
│   │       └── main.yml    # Variables for the common role
├── ansible.cfg             # Ansible configuration file
└── README.md               # Project documentation
```

## Setup Instructions

1. **Install Ansible**: Ensure that Ansible is installed on your control machine. You can install it using pip:
   ```
   pip install ansible
   ```

2. **Configure Inventory**: Edit the `inventory/hosts.ini` file to include the IP addresses or hostnames of your Raspberry Pi devices.

3. **Run the Playbook**: Use the following command to execute the main playbook:
   ```
   ansible-playbook playbooks/site.yml
   ```

## Usage

- Modify the `playbooks/tasks/common.yml` file to add or change tasks that should be executed on all Raspberry Pi devices.
- Use the `roles/common` directory to organize tasks, handlers, templates, and variables related to the common role.

