#!/bin/bash

#roster manage script version 0.1a (c) synapse

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default roster file location
default_roster_file="/etc/salt/roster"
default_sshkeys_path="/etc/salt/sshkeys"

# Function to prompt for input with a default value
prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local input
    read -p "$prompt_text [$default_value]: " input
    echo "${input:-$default_value}"
}

# Function to read secret input (no echo)
prompt_secret() {
    local prompt_text="$1"
    local input
    read -s -p "$prompt_text: " input
    echo "$input"
}

# Function to generate SSH key pair in temporary location
generate_ssh_keys_temp() {
    local name="$1"
    local temp_dir="$2"
    local private_key="$temp_dir/${name}"
    local public_key="$temp_dir/${name}.pub"
    
    # Generate SSH key pair
    ssh-keygen -q -t rsa -b 4096 -f "$private_key" -N "" -C "salt-ssh-${name}"
    
    return $?
}

# Function to move keys from temporary to final location
move_keys_to_final() {
    local name="$1"
    local temp_dir="$2"
    local final_path="$3"
    
    # Create final directory if it doesn't exist
    mkdir -p "$final_path"
    
    # Move keys
    mv "$temp_dir/${name}" "$final_path/${name}"
    mv "$temp_dir/${name}.pub" "$final_path/${name}.pub"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SSH keys saved to: $final_path${NC}"
        return 0
    else
        echo -e "${RED}Error: Failed to save SSH keys to final location${NC}"
        return 1
    fi
}

# Function to copy public key to remote host
copy_public_key() {
    local host="$1"
    local port="$2"
    local username="$3"
    local public_key="$4"
    
    # Read public key content
    local key_content=$(cat "$public_key")
    
    # Use ssh with password to add key to authorized_keys
    echo "Enter SSH password to setup key authentication"
    ssh \
        -tt \
        -o BatchMode=no \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password,keyboard-interactive \
        -o PubkeyAuthentication=no \
        -o LogLevel=ERROR \
        -p "$port" "$username@$host" "
            mkdir -p ~/.ssh &&
            chmod 700 ~/.ssh &&
            echo \"$key_content\" >> ~/.ssh/authorized_keys &&
            chmod 600 ~/.ssh/authorized_keys
        "
    
    return $?
}

# Function to check if a name exists in the roster file
check_name_exists() {
    local name="$1"
    local file="$2"
    grep -qE "^${name}:" "$file"
}

# Function to verify SSH by allowing interactive password entry (no sshpass/expect)
verify_ssh() {
    local host="$1"
    local port="$2"
    local username="$3"

    # Force password/keyboard-interactive auth and allow prompt
    # BatchMode=no allows password prompts; PubkeyAuthentication=no avoids key auth masking password failures
    ssh \
        -tt \
        -o BatchMode=no \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password,keyboard-interactive \
        -o PubkeyAuthentication=no \
        -o LogLevel=ERROR \
        -p "$port" "$username@$host" true
    return $?
}

# Function to verify SSH with key authentication
verify_ssh_with_key() {
    local host="$1"
    local port="$2"
    local username="$3"
    local private_key="$4"

    # Try SSH with key authentication
    ssh \
        -i "$private_key" \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PubkeyAuthentication=yes \
        -o PasswordAuthentication=no \
        -o LogLevel=ERROR \
        -p "$port" "$username@$host" true 2>/dev/null
    return $?
}

# Function to add host to known_hosts file
add_to_known_hosts() {
    local host="$1"
    local port="$2"
    
    # Determine the known_hosts file path
    if [ -n "$SUDO_USER" ]; then
        # Running under sudo, use the original user's home
        local user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        local known_hosts_file="$user_home/.ssh/known_hosts"
    else
        # Use current user's home
        local known_hosts_file="$HOME/.ssh/known_hosts"
    fi
    
    # Create .ssh directory if it doesn't exist
    local ssh_dir=$(dirname "$known_hosts_file")
    if [ ! -d "$ssh_dir" ]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi
    
    # Create known_hosts file if it doesn't exist
    if [ ! -f "$known_hosts_file" ]; then
        touch "$known_hosts_file"
        chmod 600 "$known_hosts_file"
    fi
    
    # Check if host is already in known_hosts
    if [ "$port" = "22" ]; then
        if ssh-keygen -F "$host" -f "$known_hosts_file" >/dev/null 2>&1; then
            echo -e "${YELLOW}Host $host is already in known_hosts${NC}"
            return 0
        fi
    else
        if ssh-keygen -F "[$host]:$port" -f "$known_hosts_file" >/dev/null 2>&1; then
            echo -e "${YELLOW}Host [$host]:$port is already in known_hosts${NC}"
            return 0
        fi
    fi
    
    # Add host to known_hosts using ssh-keyscan
    echo "Adding host fingerprint to known_hosts..."
    if [ "$port" = "22" ]; then
        ssh-keyscan -H "$host" >> "$known_hosts_file" 2>/dev/null
    else
        ssh-keyscan -H -p "$port" "$host" >> "$known_hosts_file" 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Host fingerprint added to $known_hosts_file${NC}"
        return 0
    else
        echo -e "${RED}Failed to add host fingerprint to known_hosts${NC}"
        return 1
    fi
}

# Function to remove host from known_hosts file
remove_from_known_hosts() {
    local host="$1"
    local port="$2"
    
    # Determine the known_hosts file path
    if [ -n "$SUDO_USER" ]; then
        # Running under sudo, use the original user's home
        local user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        local known_hosts_file="$user_home/.ssh/known_hosts"
    else
        # Use current user's home
        local known_hosts_file="$HOME/.ssh/known_hosts"
    fi
    
    # Check if known_hosts file exists
    if [ ! -f "$known_hosts_file" ]; then
        echo -e "${YELLOW}No known_hosts file found at $known_hosts_file${NC}"
        return 0
    fi
    
    # Remove host from known_hosts using ssh-keygen -R
    echo "Removing host fingerprint from known_hosts..."
    if [ "$port" = "22" ]; then
        ssh-keygen -R "$host" -f "$known_hosts_file" >/dev/null 2>&1
    else
        ssh-keygen -R "[$host]:$port" -f "$known_hosts_file" >/dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Host fingerprint removed from $known_hosts_file${NC}"
        return 0
    else
        echo -e "${YELLOW}Host fingerprint not found in known_hosts or already removed${NC}"
        return 0
    fi
}

# Function to list hosts from roster file
list_hosts() {
    local roster_file="$1"
    
    # Check if awk is available
    if ! command -v awk >/dev/null 2>&1; then
        echo -e "${RED}Please install awk to enable this feature${NC}"
        exit 1
    fi
    
    if [ ! -f "$roster_file" ]; then
        echo -e "${RED}Error: Roster file not found: $roster_file${NC}"
        exit 1
    fi
    
    echo "Hosts in roster file: $roster_file"
    echo "=========================================================================="
    
    # Parse roster file using awk and add colors
    awk -v green="\033[0;32m" -v yellow="\033[0;33m" -v nc="\033[0m" '
    /^# / {
        # Save description (comment line before host)
        desc = substr($0, 3)
        next
    }
    /^[a-zA-Z0-9_-]+:/ {
        # Print previous host if exists
        if (name != "" && host != "" && user != "") {
            if (port == "") port = "22"
            if (prev_desc != "") {
                printf "%s%-20s%s %s%s@%s:%s%s # %s\n", green, name, nc, yellow, user, host, port, nc, prev_desc
            } else {
                printf "%s%-20s%s %s%s@%s:%s%s\n", green, name, nc, yellow, user, host, port, nc
            }
        }
        # Start new host
        name = $0
        gsub(/:/, "", name)
        host = ""
        user = ""
        port = ""
        prev_desc = desc
        desc = ""
    }
    /^  host:/ { host = $2 }
    /^  user:/ { user = $2 }
    /^  port:/ { port = $2 }
    END {
        # Print last host
        if (name != "" && host != "" && user != "") {
            if (port == "") port = "22"
            if (prev_desc != "") {
                printf "%s%-20s%s %s%s@%s:%s%s # %s\n", green, name, nc, yellow, user, host, port, nc, prev_desc
            } else {
                printf "%s%-20s%s %s%s@%s:%s%s\n", green, name, nc, yellow, user, host, port, nc
            }
        }
    }
    ' "$roster_file"
}

# Function to remove host from roster
remove_host() {
    local name="$1"
    local roster_file="$2"
    
    # Check if awk is available
    if ! command -v awk >/dev/null 2>&1; then
        echo -e "${RED}Please install awk to enable this feature${NC}"
        exit 1
    fi
    
    if [ ! -f "$roster_file" ]; then
        echo -e "${RED}Error: Roster file not found: $roster_file${NC}"
        exit 1
    fi
    
    # Check if host exists
    if ! grep -qE "^${name}:" "$roster_file"; then
        echo -e "${RED}Error: Host '$name' not found in roster file${NC}"
        exit 1
    fi
    
    # Extract host information using awk
    local host_info=$(awk -v name="$name" '
    $0 ~ "^" name ":" {
        found = 1
        next
    }
    found && /^  host:/ { host = $2 }
    found && /^  user:/ { user = $2 }
    found && /^  port:/ { port = $2 }
    found && /^  priv:/ { priv = $2 }
    found && /^[a-zA-Z0-9_-]+:/ { 
        found = 0
    }
    END {
        if (port == "") port = "22"
        print host "|" user "|" port "|" priv
    }
    ' "$roster_file")
    
    local host=$(echo "$host_info" | cut -d'|' -f1)
    local user=$(echo "$host_info" | cut -d'|' -f2)
    local port=$(echo "$host_info" | cut -d'|' -f3)
    local priv=$(echo "$host_info" | cut -d'|' -f4)
    
    echo -e "Host to remove: ${GREEN}${name}${NC}"
    echo -e "Address: ${YELLOW}${user}@${host}:${port}${NC}"
    
    # If using key authentication, ask to remove remote key
    if [ -n "$priv" ]; then
        local public_key="${priv}.pub"
        
        echo ""
        echo -ne "${RED}Do you really want to remove remote key auth y/n [n]: ${NC}"
        read -r remove_remote
        
        if [[ "$remove_remote" =~ ^[Yy]$ ]]; then
            if [ -f "$priv" ] && [ -f "$public_key" ]; then
                echo "Removing public key from remote host..."
                
                # Remove key from remote authorized_keys using key authentication
                ssh \
                    -i "$priv" \
                    -o BatchMode=yes \
                    -o ConnectTimeout=10 \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o LogLevel=ERROR \
                    -p "$port" "$user@$host" << EOF
if [ -f ~/.ssh/authorized_keys ]; then
    grep -v 'salt-ssh-${name}' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp
    mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
fi
EOF
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}Public key removed from remote host successfully.${NC}"
                else
                    echo -e "${RED}Failed to remove public key from remote host.${NC}"
                fi
                
                # Remove local key files after successfully removing from remote
                if [ -f "$priv" ]; then
                    rm -f "$priv"
                    echo -e "${GREEN}Removed private key: $priv${NC}"
                fi
                if [ -f "$public_key" ]; then
                    rm -f "$public_key"
                    echo -e "${GREEN}Removed public key: $public_key${NC}"
                fi
            else
                echo -e "${RED}Key files not found: $priv or $public_key${NC}"
            fi
        else
            # User chose not to remove remote key, only remove local files
            if [ -f "$priv" ]; then
                rm -f "$priv"
                echo -e "${GREEN}Removed private key: $priv${NC}"
            fi
            if [ -f "$public_key" ]; then
                rm -f "$public_key"
                echo -e "${GREEN}Removed public key: $public_key${NC}"
            fi
        fi
    fi
    
    # Remove host from roster file
    # Create temporary file and remove host entry including description
    awk -v name="$name" '
    /^# / && !found {
        desc_line = $0
        next
    }
    $0 ~ "^" name ":" {
        found = 1
        desc_line = ""
        next
    }
    found && /^  / {
        next
    }
    found && /^[a-zA-Z0-9_-]+:/ {
        found = 0
    }
    !found {
        if (desc_line != "") {
            print desc_line
            desc_line = ""
        }
        print
    }
    ' "$roster_file" > "${roster_file}.tmp"
    
    mv "${roster_file}.tmp" "$roster_file"
    
    # Remove host from known_hosts
    remove_from_known_hosts "$host" "$port"
    
    echo -e "${GREEN}Host ${BOLD}${name}${NC}${GREEN} has been removed from roster file${NC}"
}

# Function to add host non-interactively with key authentication
add_host_noninteractive() {
    local name="$1"
    local userhost="$2"
    local description="$3"
    local roster_file="$4"
    
    # Parse username@host:port
    if [[ ! "$userhost" =~ ^([^@]+)@([^:]+):([0-9]+)$ ]]; then
        echo -e "${RED}Error: Invalid format. Expected username@host:port${NC}"
        echo "Example: root@192.168.1.100:22"
        exit 1
    fi
    
    local username="${BASH_REMATCH[1]}"
    local host="${BASH_REMATCH[2]}"
    local port="${BASH_REMATCH[3]}"
    
    # Check if host name already exists
    if grep -qE "^${name}:" "$roster_file"; then
        echo -e "${RED}Error: A host with the name '$name' already exists in the roster file${NC}"
        exit 1
    fi
    
    echo "Adding host to roster with key-based authentication..."
    echo -e "Name: ${GREEN}${name}${NC}"
    echo -e "Address: ${YELLOW}${username}@${host}:${port}${NC}"
    if [ -n "$description" ]; then
        echo "Description: $description"
    fi
    
    # Create temporary directory for SSH keys
    local temp_keys_dir=$(mktemp -d)
    trap "rm -rf '$temp_keys_dir'" RETURN
    
    # Generate SSH keys in temporary location
    if generate_ssh_keys_temp "$name" "$temp_keys_dir"; then
        local temp_private_key="$temp_keys_dir/${name}"
        local temp_public_key="$temp_keys_dir/${name}.pub"
        
        # Copy public key to remote host
        if copy_public_key "$host" "$port" "$username" "$temp_public_key"; then
            echo -e "${GREEN}Public key added to remote host successfully.${NC}"
            
            # Test key authentication
            if verify_ssh_with_key "$host" "$port" "$username" "$temp_private_key"; then
                echo -e "${GREEN}Key authentication verified successfully.${NC}"
                
                # Move keys to final location
                if move_keys_to_final "$name" "$temp_keys_dir" "$default_sshkeys_path"; then
                    local final_private_key="$default_sshkeys_path/${name}"
                    
                    # Append to roster file
                    {
                        echo ""
                        if [ -n "$description" ]; then
                            echo "# $description"
                        fi
                        echo "$name:"
                        echo "  host: $host"
                        echo "  user: $username"
                        echo "  priv: $final_private_key"
                        if [ "$username" != "root" ]; then
                            echo "  sudo: True"
                        fi
                        echo "  port: $port"
                    } >> "$roster_file"
                    
                    # Add host to known_hosts
                    add_to_known_hosts "$host" "$port"
                    
                    echo -e "${GREEN}Host ${BOLD}${name}${NC}${GREEN} with address ${BOLD}${host}${NC}${GREEN} has been added to the roster file: $roster_file${NC}"
                else
                    echo -e "${RED}Failed to save SSH keys. Cannot add host to roster.${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}Key authentication failed.${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Failed to copy public key to remote host.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Failed to generate SSH keys.${NC}"
        exit 1
    fi
}

# Function to show help
show_help() {
    echo "Salt-SSH Roster Management Script"
    echo "=================================="
    echo ""
    echo "Usage:"
    echo "  $0                                      - Add new host (interactive mode)"
    echo "  $0 add <name> <user@host:port> [desc]  - Add new host (non-interactive)"
    echo "  $0 ls [roster_file]                     - List all hosts from roster"
    echo "  $0 rm <name> [roster_file]              - Remove host from roster"
    echo "  $0 help                                 - Show this help message"
    echo ""
    echo -e "Default roster file: ${YELLOW}$default_roster_file${NC}"
    echo -e "Default SSH keys path: ${YELLOW}$default_sshkeys_path${NC}"
}

# Check for command line arguments
if [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
elif [ "$1" = "add" ]; then
    if [ -z "$2" ] || [ -z "$3" ]; then
        echo -e "${RED}Error: Name and user@host:port are required${NC}"
        echo "Usage: $0 add <name> <user@host:port> [description]"
        exit 1
    fi
    roster_file="$default_roster_file"
    add_host_noninteractive "$2" "$3" "$4" "$roster_file"
    exit 0
elif [ "$1" = "ls" ]; then
    roster_file="${2:-$default_roster_file}"
    list_hosts "$roster_file"
    exit 0
elif [ "$1" = "rm" ]; then
    if [ -z "$2" ]; then
        echo -e "${RED}Error: Host name is required${NC}"
        echo "Usage: $0 rm <hostname> [roster_file]"
        exit 1
    fi
    roster_file="${3:-$default_roster_file}"
    remove_host "$2" "$roster_file"
    exit 0
fi

# Check if a roster file path is provided; default to /etc/salt/roster if not
roster_file="${1:-$default_roster_file}"

# Check if we have write permissions to the roster file directory
roster_dir=$(dirname "$roster_file")
if [ ! -w "$roster_dir" ] && [ ! -w "$roster_file" ]; then
    echo -e "${RED}Error: No write permission for roster file: $roster_file${NC}"
    echo "Try running with sudo or check file permissions."
    exit 1
fi

# Ensure the roster file exists
if [ ! -f "$roster_file" ]; then
    echo "The roster file does not exist. Creating a new one at $roster_file."
    touch "$roster_file"
fi

# Create temporary directory for SSH keys
temp_keys_dir=$(mktemp -d)
trap "rm -rf '$temp_keys_dir'" EXIT

# Gather input from the user
echo "Adding a new host to the roster..."

# Loop until a unique name is provided
while true; do
    name=$(prompt_with_default "Enter the unique name for the host" "")
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Name is required. Please try again.${NC}"
        continue
    fi
    if check_name_exists "$name" "$roster_file"; then
        echo -e "${RED}Error: A host with the name '$name' already exists in the roster file. Please enter a different name.${NC}"
    else
        break
    fi
done

description=$(prompt_with_default "Enter a description for the host" "")
# Default host to name, allow override
host=$(prompt_with_default "Enter the host (IP address or hostname)" "$name")
port=$(prompt_with_default "Enter the SSH port" "22")

# Ask user about authentication method
auth_choice=$(prompt_with_default "Do you want to enable key based auth y/n" "y")

# Initialize username with default value
username="root"

if [[ "$auth_choice" =~ ^[Yy]$ ]]; then
    # SSH Key authentication
    echo "Setting up SSH key authentication..."
    
    # Get username
    username=$(prompt_with_default "Enter the SSH username" "$username")
    
    # Generate SSH keys in temporary location
    if generate_ssh_keys_temp "$name" "$temp_keys_dir"; then
        temp_private_key="$temp_keys_dir/${name}"
        temp_public_key="$temp_keys_dir/${name}.pub"
        
        # Copy public key to remote host
        if copy_public_key "$host" "$port" "$username" "$temp_public_key"; then
            echo -e "${GREEN}Public key added to remote host successfully.${NC}"
            
            # Test key authentication
            if verify_ssh_with_key "$host" "$port" "$username" "$temp_private_key"; then
                echo -e "${GREEN}Key authentication verified successfully.${NC}"
                auth_method="key"
            else
                echo -e "${RED}Key authentication failed. Falling back to password authentication.${NC}"
                auth_method="password"
            fi
        else
        echo -e "${RED}Failed to copy public key. Falling back to password authentication.${NC}"
        auth_method="password"
    fi
    else
        echo -e "${RED}Failed to generate SSH keys. Falling back to password authentication.${NC}"
        auth_method="password"
    fi
else
    # Password authentication
    auth_method="password"
fi

# Handle password authentication (either chosen or fallback)
if [ "$auth_method" = "password" ]; then
    # Loop until SSH credentials are verified; SSH will prompt for password interactively
    while true; do
        username=$(prompt_with_default "Enter the SSH username" "$username")
        echo "Enter the SSH password for remote host"
        if verify_ssh "$host" "$port" "$username"; then
            echo -e "${GREEN}SSH credentials verified successfully.${NC}"
            break
        else
            echo -e "${RED}SSH connection check failed${NC}"
            echo "Please try again."
        fi
    done
    
    # Ask for the password once to store in the roster (hidden input)
    password=$(prompt_secret "Enter the SSH password again to store in roster")
fi

# Move SSH keys to final location if using key authentication
if [ "$auth_method" = "key" ]; then
    if move_keys_to_final "$name" "$temp_keys_dir" "$default_sshkeys_path"; then
        final_private_key="$default_sshkeys_path/${name}"
    else
        echo -e "${RED}Error: Failed to save SSH keys. Cannot add host to roster.${NC}"
        exit 1
    fi
fi

# Append the new host configuration to the roster file
{
    echo ""
    echo "# $description"
    echo "$name:"
    echo "  host: $host"
    echo "  user: $username"
    if [ "$auth_method" = "key" ]; then
        echo "  priv: $final_private_key"
    else
        echo "  passwd: $password"
    fi
    if [ "$username" != "root" ]; then
        echo "  sudo: True"
    fi
    echo "  port: $port"
} >> "$roster_file"

# Add host to known_hosts
add_to_known_hosts "$host" "$port"

echo -e "${GREEN}Host ${BOLD}$name${NC}${GREEN} with address ${BOLD}$host${NC}${GREEN} has been added to the roster file: $roster_file${NC}"
