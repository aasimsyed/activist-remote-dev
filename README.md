# Activist Development Environment

## Overview

The Activist Development Environment is a custom-built remote development solution designed to provide a cost-effective and efficient alternative to local Docker development and cloud-based development environments like GitHub Codespaces. Recognizing the resource-intensive nature of local Docker Desktop development and the higher costs associated with cloud-based alternatives, this project was created to offer a streamlined, remote development experience.

This environment leverages DigitalOcean droplets as remote development servers, managed through a combination of Terraform for infrastructure provisioning and Ansible for configuration management. The system is designed to be lightweight, secure, and easily reproducible, while maintaining the flexibility needed for modern web application development.

Key features of the environment include:

- Automated setup of remote development servers
- Secure SSH tunnel management for local access
- Pre-configured development tools and dependencies
- Support for both staging and production environments
- Cost-effective resource utilization
- Cross-platform compatibility (Linux and macOS)

The environment is particularly well-suited for developers who:

- Find local Docker development too resource-intensive
- Want to avoid the higher costs of cloud-based development environments
- Need a consistent development environment across multiple machines
- Require secure access to development resources
- Want to maintain control over their development infrastructure

By providing a remote development environment that balances performance, cost, and flexibility, this project aims to make development more accessible and efficient for individual developers and small teams working on the Activist application.

## Features

### Core Features

- **Automated Infrastructure Provisioning**:
  - Command-line interface for environment setup
  - Built-in support for multiple environments (dev, staging, production)

- **Remote Development Environment**:
  - Secure SSH access to remote servers
  - Consistent configurations across machines

- **Cost Optimization**:
  - Pay-as-you-go pricing model
  - Automatic shutdown of unused resources

### Development Tools

- **Environment Management**:
  - Easy environment replication
  - Automated dependency installation

### Security Features

- **Access Control**:
  - SSH key-based authentication

### Integration & Automation

- **VS Code Remote Development**:
  - Seamless integration with VS Code
  - Remote debugging capabilities

### Cross-Platform Support

- **Operating Systems**:
  - Full support for Linux and macOS

### Customization

- **Environment Configuration**:
  - Customizable server sizes
  - Selectable operating systems
  - Configurable development tools

- **Project-Specific Setup**:
  - Custom environment variables
  - Project-specific dependencies
  - Tailored deployment configurations

## Prerequisites

### Required Software

- **Command Line Tools**:
  - Git (version 2.25.0 or higher)
  - Terraform (version 1.10.5 or higher)
  - Ansible (version 2.18 or higher)
  - DigitalOcean CLI (doctl) (version 1.94.0 or higher)

- **Development Environment**:
  - Python 3.8 or higher
  - Node.js 16.x or higher
  - Docker (for local container management)

- **Text Editors/IDEs**:
  - VS Code (with Remote Development extension)
  - Any SSH-compatible text editor

### API Keys and Credentials

- **DigitalOcean**:
  - API token with read/write permissions
  - SSH key registered with DigitalOcean

- **Application**:
  - Environment variables for development
  - Any required API keys for third-party services

### System Requirements

- **Operating Systems**:
  - macOS 10.15 (Catalina) or higher
  - Linux (Ubuntu 20.04 or higher, CentOS 7 or higher)

- **Hardware**:
  - Minimum 4GB RAM
  - 10GB free disk space
  - Stable internet connection

### Accounts

- **DigitalOcean**:
  - Active DigitalOcean account
  - Payment method configured

- **Version Control**:
  - GitHub account (for repository access)
  - SSH key configured for GitHub

### Network Requirements

- **Ports**:
  - Open SSH port (22)
  - Access to DigitalOcean API endpoints

- **Firewall**:
  - Ability to create SSH tunnels
  - Access to required development ports

## Quick Start

### Installation

1. **Install Required Tools**:

   ```bash
   # Install Terraform
   brew install terraform

   # Install Ansible
   brew install ansible

   # Install DigitalOcean CLI
   brew install doctl
   ```

2. **Configure DigitalOcean Access**:

   ```bash
   # Authenticate with DigitalOcean
   doctl auth init

   # Add your SSH key to DigitalOcean
   doctl compute ssh-key create <key-name> --public-key-file ~/.ssh/id_rsa.pub
   ```

### Initial Setup

1. **Clone the Repository**:

   ```bash
   git clone https://github.com/your-username/activist-dev-env.git
   cd activist-dev-env
   ```

2. **Configure Environment Variables**:
   Set the `DO_TOKEN` environment variable:

   ```bash
   export DO_TOKEN="your_digitalocean_api_token"
   ```

### First Deployment

1. **Initialize Terraform**:

   ```bash
   cd terraform/environments/dev
   terraform init
   ```

2. **Create Infrastructure**:

   ```bash
   terraform apply
   ```

3. **Deploy with Ansible**:

   ```bash
   cd ../../ansible
   ansible-playbook -i inventory/dev playbooks/deploy.yml
   ```

4. **Access Your Environment**:

   ```bash
   # Get the droplet IP
   DROPLET_IP=$(terraform output -raw droplet_ip)

   # SSH into the droplet
   ssh root@$DROPLET_IP
   ```

### Next Steps

- Configure your development environment
- Set up VS Code Remote Development
- Explore the project structure

## Project Structure

### Root Directory

```bash
.
├── ansible/               # Ansible configuration and playbooks
├── terraform/             # Terraform infrastructure definitions
├── scripts/               # Utility scripts for development
├── .env                   # Environment variables
├── README.md              # Project documentation
└── .gitignore             # Git ignore rules
```

### Ansible Structure

```bash
ansible/
├── playbooks/             # Deployment playbooks
├── inventory/             # Inventory files for different environments
├── roles/                 # Custom Ansible roles
├── templates/             # Configuration templates
└── ansible.cfg            # Ansible configuration
```

### Terraform Structure

```bash
terraform/
├── environments/          # Environment-specific configurations
│   ├── dev/               # Development environment
│   ├── staging/           # Staging environment
│   └── production/        # Production environment
├── modules/               # Reusable Terraform modules
└── shared/                # Shared Terraform configurations
```

### Scripts Directory

```bash
scripts/
├── droplet-manager.sh      # Main management script
├── ssh-tunnel.sh          # SSH tunnel management
└── utils/                 # Utility scripts
```

### Environment Files

```bash
ansible/group_vars/: Group variables for Ansible
ansible/host_vars/: Host-specific variables for Ansible
```

### Configuration Files

```bash
ansible.cfg: Ansible configuration
terraform/shared/provider.tf: Terraform provider configuration
terraform/shared/versions.tf: Terraform version requirements
```

## Configuration

### Environment Variables

The only required environment variable is:

- `DO_TOKEN`: Your DigitalOcean API token

To set this up:

1. **Add to Shell Configuration**:
   Add the following to your shell's rc file (`~/.bashrc`, `~/.zshrc`, etc.):

   ```bash
   export DO_TOKEN="your_digitalocean_api_token"
   ```

2. **Reload Shell Configuration**:

   ```bash
   source ~/.bashrc  # or ~/.zshrc
   ```

### Configuration File Setup

The project uses a `config.yml` file for application and environment-specific settings. To set up your configuration:

1. **Copy the Template**:

   ```bash
   cp config.yml.template config.yml
   ```

2. **Edit the Configuration**:
   Open `config.yml` in your text editor and fill in the appropriate values. Refer to the template file for the complete structure and available options.

3. **Save the File**:
   After filling in the values, save the file as `config.yml`.

### Configuration Sections

The configuration file is organized into the following sections:

- **Application**: General application settings
- **Project Structure**: Directory paths for the project
- **DigitalOcean**: DigitalOcean droplet and infrastructure settings
- **SSH Tunnel**: SSH tunnel configuration for remote access
- **Docker**: Docker and container management settings
- **Deployment**: Deployment and timeout settings
- **Node.js**: Node.js and package manager configuration
- **Logging**: Logging settings and file management
- **Security**: Security and file permission settings

### Notes

- Replace placeholders (e.g., `<your-username>`) with actual values.
- Ensure sensitive values (e.g., SSH keys) are kept secure.
- Use the same structure as the template to avoid errors.

## Deployment

### Local Development

1. **Start Development Environment**:

   ```bash
   ./scripts/droplet-manager.sh start
   ```

2. **Set Up SSH Tunnel**:

   ```bash
   ./scripts/ssh-tunnel.sh start
   ```

3. **Deploy Application**:

   ```bash
   cd ansible
   ansible-playbook -i inventory/dev playbooks/deploy.yml
   ```

### Staging Environment

1. **Initialize Terraform**:

   ```bash
   cd terraform/environments/staging
   terraform init
   ```

2. **Create Infrastructure**:

   ```bash
   terraform apply
   ```

3. **Deploy Application**:

   ```bash
   cd ../../ansible
   ansible-playbook -i inventory/staging playbooks/deploy.yml
   ```

### Production Environment

1. **Initialize Terraform**:

   ```bash
   cd terraform/environments/production
   terraform init
   ```

2. **Create Infrastructure**:

   ```bash
   terraform apply
   ```

3. **Deploy Application**:

   ```bash
   cd ../../ansible
   ansible-playbook -i inventory/production playbooks/deploy.yml
   ```

## Infrastructure

### DigitalOcean Setup

1. **Create Droplet**:

   ```bash
   doctl compute droplet create <name> \
     --region nyc3 \
     --image ubuntu-22-04-x64 \
     --size s-1vcpu-1gb \
     --ssh-keys <your-key-fingerprint>
   ```

2. **Configure Firewall**:

   ```bash
   doctl compute firewall create \
     --name activist-firewall \
     --inbound-rules "protocol:tcp,ports:22,address:0.0.0.0/0" \
     --outbound-rules "protocol:tcp,ports:all,address:0.0.0.0/0"
   ```

### Network Architecture

- **Public Network**:
  - SSH access (port 22)
  - Application ports (3000, 8000, 5432)
  
- **Private Network**:
  - Database access
  - Internal service communication

### Security Considerations

- **SSH Access**:
  - Use SSH keys instead of passwords
  - Restrict access to specific IPs
  - Use SSH tunnels for secure communication

- **Firewall Rules**:
  - Only open necessary ports
  - Use DigitalOcean's built-in firewall
  - Regularly review and update rules

- **Data Protection**:
  - Use encrypted volumes for sensitive data
  - Regularly back up important data
  - Use secure protocols for data transfer

## Development

### Local Development Setup

1. **Clone the Repository**:

   ```bash
   git clone https://github.com/your-username/activist-dev-env.git
   cd activist-dev-env
   ```

2. **Set Up Environment Variables**:

   Create a `.env` file with your DigitalOcean API token:

   ```bash
   export DO_TOKEN="your_digitalocean_api_token"
   ```

3. **Install Dependencies**:

   ```bash
   brew install terraform ansible doctl
   ```

4. **Initialize Development Environment**:

   ```bash
   ./scripts/droplet-manager.sh start
   ```

### Code Style Guidelines

- **Shell Scripts**:
  - Use `shellcheck` for linting
  - Follow Google Shell Style Guide
  - Use `set -euo pipefail` for error handling

- **Ansible**:
  - Use `ansible-lint` for linting
  - Follow Ansible Best Practices
  - Use roles for reusable components

- **Terraform**:
  - Use `terraform fmt` for formatting
  - Follow Terraform Best Practices
  - Use modules for reusable components

### Testing Guidelines

1. **Shell Scripts**:
   - Use `bats` for unit testing
   - Test error handling and edge cases
   - Verify script output and exit codes

2. **Ansible Playbooks**:
   - Use `molecule` for testing roles
   - Test idempotency
   - Verify playbook execution

3. **Terraform Configurations**:
   - Use `terraform validate` for syntax checking
   - Test plan output
   - Verify infrastructure creation

### Contributing Guidelines

1. **Branching**:
   - Create feature branches from `main`
   - Use descriptive branch names
   - Keep branches focused on single features

2. **Pull Requests**:
   - Include clear descriptions
   - Reference related issues
   - Ensure all tests pass

3. **Code Review**:
   - Review for style and best practices
   - Verify functionality
   - Check for security issues

4. **Documentation**:
   - Update README for new features
   - Add inline comments where necessary
   - Document any breaking changes

## License

This project is licensed under the **MIT License**. Below is a summary of the key terms:

### Permissions

- **Use**: Free to use for any purpose, including commercial use
- **Modify**: Free to modify and adapt the code
- **Distribute**: Free to distribute the original or modified versions

### Conditions

- **Attribution**: Must include the original copyright notice and license terms in all copies or substantial portions of the software

### Limitations

- **Liability**: The software is provided "as is," without warranty of any kind
- **Warranty**: No guarantee of fitness for a particular purpose

### Full License Text

The full text of the MIT License is included in the [LICENSE](LICENSE) file in the root of this repository.

### Contributions

By contributing to this project, you agree to license your contributions under the same MIT License terms.

### Third-Party Licenses

This project may include third-party libraries or tools, each with its own license. Please refer to the respective documentation for their licensing terms.

## Contributing

We welcome contributions from the community! Here's how you can help improve the Activist Development Environment:

### Getting Started

1. **Fork the Repository**:
   Click the "Fork" button on the GitHub repository page to create your own copy.

2. **Clone Your Fork**:

   ```bash
   git clone https://github.com/your-username/activist-dev-env.git
   cd activist-dev-env
   ```

3. **Set Up Development Environment**:
   Follow the [Development](#development) section to set up your local environment.

### Making Changes

1. **Create a Feature Branch**:

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make Your Changes**:
   - Follow the code style guidelines
   - Write tests for new functionality
   - Update documentation as needed

3. **Commit Your Changes**:

   Use descriptive commit messages:

   ```bash
   git commit -m "Add feature: your feature description"
   ```

4. **Push to Your Fork**:

   ```bash
   git push origin feature/your-feature-name
   ```

### Submitting a Pull Request

1. **Create a Pull Request**:
   - Go to the GitHub repository page
   - Click "New Pull Request"
   - Select your feature branch

2. **Describe Your Changes**:
   - Provide a clear title and description
   - Reference any related issues
   - Include screenshots or test results if applicable

3. **Address Feedback**:
   - Respond to code review comments
   - Make requested changes
   - Push updates to your branch

### Code Review Process

- **Reviewers**:
  - At least one maintainer will review your PR
  - Reviews focus on code quality, functionality, and style

- **Approval**:
  - PRs require at least one approval before merging
  - All tests must pass

- **Merging**:
  - Maintainers will squash and merge approved PRs
  - Your changes will be included in the next release

### Reporting Issues

1. **Check Existing Issues**:
   Search the issue tracker to see if your issue has already been reported.

2. **Create a New Issue**:
   - Provide a clear title and description
   - Include steps to reproduce
   - Add relevant logs or screenshots

### Code of Conduct

All contributors are expected to follow our [Code of Conduct](CODE_OF_CONDUCT.md). Please be respectful and considerate in all interactions.

### Acknowledgments

We appreciate all contributions, whether it's code, documentation, or bug reports. Thank you for helping make this project better!

## Changelog

### [0.1.1] - 2025-02-01

- **Added**: Initial project setup with Terraform and Ansible
- **Added**: Basic droplet management scripts
- **Added**: SSH tunnel configuration
- **Added**: Documentation and README

### [0.1.0] - 2025-01-31

- **Added**: Support for multiple environments (dev, staging, production)
- **Added**: Automated dependency installation
- **Improved**: Error handling in deployment scripts
- **Fixed**: SSH key management issues

### [0.0.1] - 2025-01-28

- **Initial Release**: Basic functionality for remote development environment
