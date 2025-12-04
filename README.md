# RosterMan - Salt-SSH Roster Management Script

**Version:** 0.2a  
**Author:** synapse

## Overview

RosterMan is a comprehensive Bash script designed to simplify the management of Salt-SSH roster files. It automates the process of adding, removing, and listing remote hosts with support for both SSH key-based and password-based authentication. The script also manages SSH known_hosts entries to prevent fingerprint confirmation prompts on first connection.

## Features

- ✅ **Interactive and Non-Interactive Modes**: Add hosts via command-line arguments or interactive prompts
- 🔐 **SSH Key Management**: Automatically generates, deploys, and manages SSH key pairs
- 🔑 **Dual Authentication**: Supports both SSH key-based and password-based authentication
- 📝 **Automatic known_hosts Management**: Adds/removes host fingerprints to prevent confirmation prompts
- 🗑️ **Safe Host Removal**: Option to remove SSH keys from remote hosts when deleting entries
- 📋 **Colorized List Output**: Beautiful formatted listing of all roster entries
- ✨ **Validation**: Verifies SSH connectivity before adding hosts to roster

## Requirements

- Bash 4.0+
- OpenSSH client with `ssh-keygen` and `ssh-keyscan`
- `awk` for parsing roster files
- Write permissions to roster file (default: `/etc/salt/roster`)

## Installation

1. Download the script:
```bash
wget https://raw.githubusercontent.com/syn4ps/rosterman/refs/heads/main/rosterman.sh
# or
curl -O https://raw.githubusercontent.com/syn4ps/rosterman/refs/heads/main/rosterman.sh
```

2. Make it executable:
```bash
chmod +x rosterman.sh
```

3. Optionally, move to a system path:
```bash
sudo mv rosterman.sh /usr/local/bin/rosterman
```

## Usage

### Interactive Mode

Simply run the script without arguments to enter interactive mode:

```bash
./rosterman.sh
# or with custom roster file
./rosterman.sh /path/to/custom/roster
```

The script will prompt you for:
- Unique host name
- Description
- Host IP/hostname
- SSH port (default: 22)
- Authentication method (key-based or password)
- SSH username
- Credentials (password or automatic key deployment)

### Non-Interactive Mode

#### Add a Host

```bash
./rosterman.sh add <name> <user@host:port> [description]
```

**Examples:**
```bash
# Add a host with default SSH port
./rosterman.sh add webserver01 root@192.168.1.100:22 "Production web server"

# Add a host with custom port
./rosterman.sh add dbserver admin@10.0.0.50:2222 "Database server"

# Add without description
./rosterman.sh add minion01 salt@172.16.0.10:22
```

#### List Hosts

```bash
./rosterman.sh ls [roster_file]
```

**Examples:**
```bash
# List hosts from default roster file
./rosterman.sh ls

# List hosts from custom roster file
./rosterman.sh ls /path/to/custom/roster
```

**Sample Output:**
```
Hosts in roster file: /etc/salt/roster
==========================================================================
webserver01          root@192.168.1.100:22 # Production web server
dbserver             admin@10.0.0.50:2222 # Database server
minion01             salt@172.16.0.10:22
```

#### Remove a Host

```bash
./rosterman.sh rm <hostname> [roster_file]
```

**Examples:**
```bash
# Remove host from default roster
./rosterman.sh rm webserver01

# Remove host from custom roster
./rosterman.sh rm dbserver /path/to/custom/roster
```

When removing a host with key authentication, you'll be prompted:
- Whether to remove the public key from the remote host
- Local key files are always removed

#### Show Help

```bash
./rosterman.sh help
# or
./rosterman.sh --help
# or
./rosterman.sh -h
```

## Configuration

Default settings can be modified at the top of the script:

```bash
# Default roster file location
default_roster_file="/etc/salt/roster"

# Default SSH keys storage path
default_sshkeys_path="/etc/salt/sshkeys"
```

## SSH Key Management

### Key Generation

When you choose key-based authentication, RosterMan:

1. Generates a 4096-bit RSA key pair
2. Names keys using the host's unique name
3. Adds a comment: `salt-ssh-<hostname>`
4. Stores keys in `/etc/salt/sshkeys/` (or custom path)

### Key Deployment

The script automatically:

1. Connects to the remote host using password authentication
2. Creates `~/.ssh/` directory if needed
3. Appends public key to `~/.ssh/authorized_keys`
4. Sets proper permissions (700 for .ssh, 600 for authorized_keys)
5. Verifies key authentication works before saving to roster

### Key Removal

When removing a host with `rm` command:

- You can choose to remove the public key from remote `authorized_keys`
- Local private and public keys are removed from `/etc/salt/sshkeys/`
- Host fingerprint is removed from `~/.ssh/known_hosts`

## known_hosts Management

RosterMan automatically manages SSH known_hosts entries:

### Adding Hosts

When a host is added (both interactive and non-interactive modes):
- Uses `ssh-keyscan` to fetch host SSH keys
- Adds hashed entries to `~/.ssh/known_hosts`
- Supports custom SSH ports
- Handles both regular user and sudo execution

### Removing Hosts

When a host is removed:
- Uses `ssh-keygen -R` to safely remove entries
- Handles both standard port 22 and custom ports
- Removes both hashed and non-hashed entries

This ensures that Salt-SSH connections won't prompt for fingerprint confirmation.

## Roster File Format

RosterMan creates entries in Salt-SSH roster format:

### Key-Based Authentication Entry
```yaml
# Production web server
webserver01:
  host: 192.168.1.100
  user: root
  priv: /etc/salt/sshkeys/webserver01
  port: 22
```

### Password-Based Authentication Entry
```yaml
# Database server
dbserver:
  host: 10.0.0.50
  user: admin
  passwd: secretpassword
  sudo: True
  port: 2222
```

**Note:** Non-root users automatically get `sudo: True` added.

## Security Considerations

1. **File Permissions**: Roster files containing passwords should be protected:
   ```bash
   chmod 600 /etc/salt/roster
   ```

2. **Key-Based Auth Recommended**: Use SSH keys instead of passwords when possible

3. **Hashed known_hosts**: Host fingerprints are stored in hashed format (`-H` flag)

4. **Secure Key Storage**: SSH private keys are stored in `/etc/salt/sshkeys/` with restrictive permissions

5. **Password Storage**: Passwords stored in roster file are in plain text - use key-based auth for sensitive systems

## Troubleshooting

### Permission Denied

If you get permission denied errors:
```bash
# Run with sudo
sudo ./rosterman.sh
```

### SSH Connection Failures

The script validates SSH connectivity before adding hosts. If validation fails:
- Check network connectivity
- Verify SSH service is running on remote host
- Confirm firewall allows SSH connections
- Ensure credentials are correct

### awk Not Found

Install awk:
```bash
# Debian/Ubuntu
sudo apt-get install gawk

# RHEL/CentOS
sudo yum install gawk

# Alpine
sudo apk add gawk
```

### known_hosts Issues

If you have problems with known_hosts:
```bash
# Manually scan and add host
ssh-keyscan -H -p 22 192.168.1.100 >> ~/.ssh/known_hosts

# Or remove old entry
ssh-keygen -R 192.168.1.100
```

## Examples

### Complete Workflow: Adding a New Host

```bash
# Non-interactive mode with key auth
sudo ./rosterman.sh add prod-web root@web.example.com:22 "Production Web Server"

# The script will:
# 1. Generate SSH key pair
# 2. Deploy public key (prompts for password)
# 3. Verify key authentication
# 4. Add to roster file
# 5. Add host fingerprint to known_hosts

# Test with Salt-SSH
sudo salt-ssh 'prod-web' test.ping
```

### Listing All Hosts

```bash
./rosterman.sh ls
```

### Removing a Host Completely

```bash
sudo ./rosterman.sh rm prod-web
# Choose 'y' when prompted to remove remote key
```

## Integration with Salt-SSH

After adding hosts with RosterMan, use them with Salt-SSH:

```bash
# Test connectivity
salt-ssh '*' test.ping

# Run commands
salt-ssh 'webserver*' cmd.run 'uptime'

# Apply states
salt-ssh 'dbserver' state.apply database
```

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This script is provided as-is for use with SaltStack deployments.

## Changelog

### Version 0.2a
- Fixed password trailing newline bug in prompt_secret function
- Added SSH port change functionality for security (non-standard ports)
- Improved password handling in roster file

### Version 0.1a
- Initial release
- Interactive and non-interactive host addition
- SSH key generation and deployment
- Host listing with colors
- Host removal with key cleanup
- Automatic known_hosts management
- Support for both key and password authentication
- sudo support for known_hosts operations

## Support

For issues, questions, or suggestions, please contact the author or open an issue in the repository.

---

**Made with ❤️ for SaltStack users**

