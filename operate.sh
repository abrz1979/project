#!/bin/bash

while true; do

# Check if the openrc file path, tag, and public key are provided as command-line arguments
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Please provide the path to the openrc file, tag, and public key as command-line arguments."
    exit 1
fi

# Set the path to the openrc file
openrc_file="$1"

# Set the tag
tag="$2"

# Set the public key
public_key="$3"

# Set the network name with the tag
network_name="${tag}_network"

# Set the key name with the tag
key_name="${tag}_key"

# Set the subnet name with the tag
subnet_name="${tag}_subnet"

# Set the router name with the tag
router_name="${tag}_router"

# Set the server name with the tag
server_name="${tag}_bastion"

# Set the proxy server name with the tag
proxy_server_name="${tag}_proxy"

# Set the image name
image_name="Ubuntu 22.04.1"

# Set the flavor
flavor="1C-1GB"

# Set the security group
security_group="default"

# Source the openrc file
source "$openrc_file"

# Find the image ID for Ubuntu 20.04
    image=$(openstack image list --format value | grep "$image_name")

    # Check if image is empty
    if [[ -z "$image" ]]; then
        echo "Image not found: $image_name"
    else
        image_id=$(echo "$image" | awk '{print $1}')
        echo "Image found: $image"
        echo "Image ID: $image_id"
    fi

# Find the external network
external_net=$(openstack network list --external --format value -c ID)
if [ -z "$external_net" ]; then
    echo "No external network found. Exiting."
    exit 1
fi

#!/bin/bash

# Fetch the server list from OpenStack
server_list=$(openstack server list -c Name -f value)

# Declare an associative array to store server name and IP address pairs
declare -A ip_list

# Iterate over the server list and retrieve IP addresses
while read -r server_name; do
  # Execute the command to retrieve the IP address
  bastion_ip=$(openstack server show -f value -c addresses "$server_name" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

  # Store the server name and IP address pair in the array
  ip_list["$server_name"]=$bastion_ip
done <<< "$server_list"

# Generate the telegraf.conf.tmp file
cat <<EOF > telegraf.conf.tmp
[agent]
  interval = "1s"
  flush_interval = "1s"

[[outputs.influxdb]]
  urls = ["http://127.0.0.1:8086"]
  database = "telegraf"
  precision = "s"

[[inputs.ping]]
  urls = [
EOF

# Iterate over the IP list and append server IPs (containing "dev") to the urls section
for server_name in "${!ip_list[@]}"; do
  if [[ "$server_name" == *"dev"* ]]; then
    ip_address=${ip_list["$server_name"]}
    echo "    \"$ip_address\"," >> telegraf.conf.tmp
  fi
done

# Complete the telegraf.conf.tmp file
echo "  ]" >> telegraf.conf.tmp
echo "EOF"

echo "telegraf.conf.tmp file created successfully."


floating_ips=$(openstack floating ip list -f value -c "Floating IP Address" )
floating_ip_bastion=$(echo "$floating_ips" | awk 'NR==1')
echo "floating_ip_bastion $floating_ip_bastion"
floating_ip_proxy=$(echo "$floating_ips" | awk 'NR==2')
echo "floating_ip_proxy $floating_ip_proxy"


# Get the number of servers in OpenStack
server_num=$(openstack server list -c ID -c Name -f value | grep dev | wc -l)

# Create the config file
cat <<EOF > active-server.sh
#!/bin/bash

# Execute the InfluxDB command and capture the output
output=\$(influx -database telegraf -execute "SELECT * FROM \"ping\" ORDER BY time DESC LIMIT $server_num")
echo "\$output"

# Find the row with result code equal to 0
row_with_zero_code=\$(echo "\$output" | awk '\$9 == 0')

# Check if a row with result code 0 was found
if [ -n "\$row_with_zero_code" ]; then
    echo "Row with result code 0:"
    echo "\$row_with_zero_code"
else
    echo "No rows with result code 0 found."
fi

# Count the number of active hosts
active_hosts=\$(echo "\$output" | awk '\$9 == 0 {count++} END {print count}')

# Check if any active hosts were found
if [ "\$active_hosts" -gt 0 ]; then
    echo "Number of active hosts: \$active_hosts"
else
    echo "No active hosts found."
fi
EOF
# Change the permissions of the created file
chmod 777 active-server.sh

echo "active-server file has been created successfully."
remote_output=$(ssh -o StrictHostKeyChecking=no -i id_rsa.pub ubuntu@$floating_ip_bastion "bash -s" < active-server.sh)
echo "$remote_output"



# Install telegraf on the server
echo "Install Telegraf and influxdb"
ssh -o StrictHostKeyChecking=no -i id_rsa ubuntu@$floating_ip_bastion 'sudo apt update >/dev/null 2>&1 && sudo apt install -y telegraf >/dev/null 2>&1'
ssh -o StrictHostKeyChecking=no -i id_rsa ubuntu@$floating_ip_bastion 'sudo apt install -y influxdb >/dev/null 2>&1'
ssh -o StrictHostKeyChecking=no -i id_rsa ubuntu@$floating_ip_bastion 'sudo apt install -y influxdb-client >/dev/null 2>&1'




# Stop the telegraf service
ssh -o StrictHostKeyChecking=no -i id_rsa ubuntu@$floating_ip_bastion 'sudo systemctl stop telegraf >/dev/null 2>&1'
# Replace the configuration file with the temporary file

scp  -o BatchMode=yes  telegraf.conf.tmp ubuntu@$floating_ip_bastion:~/.ssh
# Replace the configuration file with the temporary file
ssh -o StrictHostKeyChecking=no -i id_rsa.pub ubuntu@$floating_ip_bastion 'sudo cp ~/.ssh/telegraf.conf.tmp /etc/telegraf/telegraf.conf'


# Start the telegraf service
ssh -o StrictHostKeyChecking=no -i id_rsa.pub ubuntu@$floating_ip_bastion 'sudo systemctl start telegraf >/dev/null 2>&1'
ssh -o StrictHostKeyChecking=no -i id_rsa.pub ubuntu@$floating_ip_bastion 'sudo systemctl status telegraf '



# Execute the InfluxDB command and capture the output
#remote_output=(ssh -o StrictHostKeyChecking=no -i id_rsa.pub ubuntu@$floating_ip_bastion  < monitor.sh) 
remote_output=$(ssh -o StrictHostKeyChecking=no -i id_rsa.pub ubuntu@$floating_ip_bastion "bash -s" < active-server.sh)
echo "$remote_output"

active_hosts_remote=$(echo "$remote_output" | awk '/Number of active hosts:/ {print $NF}')

echo "Active hosts on the remote server: $active_hosts_remote"


# Local number of active hosts
local_active_hosts=$(cat number.txt)
echo " config num is $local_active_hosts"

# Compare local_active_hosts with active_hosts_remote
if [ "$local_active_hosts" -gt "$active_hosts_remote" ]; then
    echo "Number of active hosts on the local server ($local_active_hosts) is greater than active_hosts_remote ($active_hosts_remote). Creating a new server."

    # Generate a random number for the server name
    random_number=$(shuf -i 1000-9999 -n 1)
    server_name="${tag}_dev_${random_number}"

    # Create the new server instance with the same configuration as the previous servers
    openstack server create --flavor "$flavor" --image "$image_id" --network "$network_name" \
        --security-group "$security_group" --key-name "$key_name" "$server_name"

    echo "New server created with the name '$server_name'"
#=============================================================== 
     # Fetch the server list from OpenStack
server_list=$(openstack server list -c Name -f value)

# Create the hosts file
cat <<EOF >hosts
[dev]

EOF

# Add all OpenStack servers with "dev" in their names below the [dev] section
while read -r server_name; do
  if [[ "$server_name" == *"dev"* ]]; then
    echo "$server_name" >>hosts
  fi
done <<< "$server_list"

# Append the remaining sections to the hosts file
cat <<EOF >>hosts

[haproxy]

test_proxy

[all:vars]
ansible_user=ubuntu
EOF

echo "The 'hosts' file has been created successfully." 
#======================================================================
# Fetch the server list from OpenStack
server_list=$(openstack server list -c Name -c Networks -f value)

# Create the ssh_config file
cat <<EOF >config

EOF

# Add SSH configuration for each OpenStack server with "dev" in its name
while read -r server_name server_networks; do
  if [[ "$server_name" == *"dev"* ]]; then
    # Extract the IP address from the server networks
    server_ip=$(openstack server show -f value -c addresses "$server_name" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    # Add the SSH configuration for the server
    cat <<EOF >>config
# SSH configuration for $server_name
Host $server_name
  HostName $server_ip
  User ubuntu
  StrictHostKeyChecking no
  IdentityFile ~/.ssh/id_rsa

EOF
  elif [[ "$server_name" == *"proxy"* ]]; then
    # Extract the IP address from the server networks
    server_ip=$(openstack server show -f value -c addresses "$server_name" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    # Add the SSH configuration for the test_proxy server
    cat <<EOF >>config
# SSH configuration for $server_name
Host $server_name
  HostName $server_ip
  User ubuntu
  StrictHostKeyChecking no
  IdentityFile ~/.ssh/id_rsa

EOF
  fi
done <<< "$server_list"

echo "The 'ssh_config' file has been created successfully." 
 
 # Copy the Host and config to the Bastion server
echo "Copying config ssh and host to the Bastion server"
scp  -o StrictHostKeyChecking=no config ubuntu@$floating_ip_bastion:~/.ssh
scp  -o BatchMode=yes hosts ubuntu@$floating_ip_bastion:~/.ssh/ansible

sleep 5s
#read -p  "Enter wait.."
ssh -i id_rsa.pub ubuntu@$floating_ip_bastion "ansible-playbook -i ~/.ssh/ansible/hosts ~/.ssh/ansible/site.yaml "


#================================================================================================== Delete
 
elif [ "$local_active_hosts" -lt "$active_hosts_remote" ]; then
    echo "Number of active hosts on the local server ($local_active_hosts) is less than active_hosts_remote ($active_hosts_remote).  new server will be deleted."
    # Find servers containing "dev" in their names
server_list1=$(openstack server list  -c ID -c Name -f value | grep dev)
echo " server list is $server_list1"

# Check if there are any dev servers
if [[ -z $server_list ]]; then
  echo "No dev servers found."
  exit 0
fi

# Extract server ID of the first server in the list
server_id=$(echo "$server_list1" | head -n 1 | awk '{print $1}')

#read -p  "wait.."

# Delete the first server
openstack server delete "$server_id"
echo "Deleting server: $server_id"
# Wait for the server to be deleted
sleep 5s
#read -p  "wait.."

# Fetch the server list from OpenStack
server_list=$(openstack server list -c Name -f value)
echo "server list is $server_list"
sleep 5s

# Create the hosts file
cat <<EOF >hosts
[dev]

EOF

# Add all OpenStack servers with "dev" in their names below the [dev] section
while read -r server_name; do
  if [[ "$server_name" == *"dev"* ]]; then
    echo "$server_name" >>hosts
  fi
done <<< "$server_list"

# Append the remaining sections to the hosts file
cat <<EOF >>hosts

[haproxy]

test_proxy

[all:vars]
ansible_user=ubuntu
EOF

echo "The 'hosts' file has been created successfully."

#read -p  "wait.."
sleep 5s

# Fetch the server list from OpenStack
server_list=$(openstack server list -c Name -c Networks -f value)

# Create the ssh_config file
cat <<EOF >config

EOF

# Add SSH configuration for each OpenStack server with "dev" in its name
while read -r server_name server_networks; do
  if [[ "$server_name" == *"dev"* ]]; then
    # Extract the IP address from the server networks
    server_ip=$(openstack server show -f value -c addresses "$server_name" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    # Add the SSH configuration for the server
    cat <<EOF >>config
# SSH configuration for $server_name
Host $server_name
  HostName $server_ip
  User ubuntu
  StrictHostKeyChecking no
  IdentityFile ~/.ssh/id_rsa

EOF
  elif [[ "$server_name" == *"proxy"* ]]; then
    # Extract the IP address from the server networks
    server_ip=$(openstack server show -f value -c addresses "$server_name" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    # Add the SSH configuration for the test_proxy server
    cat <<EOF >>config
# SSH configuration for $server_name
Host $server_name
  HostName $server_ip
  User ubuntu
  StrictHostKeyChecking no
  IdentityFile ~/.ssh/id_rsa

EOF
  fi
done <<< "$server_list"

echo "The 'ssh_config' file has been created successfully." 
 
 # Copy the Host and config to the Bastion server
echo "Copying config ssh and host to the Bastion server"
scp  -o StrictHostKeyChecking=no config ubuntu@$floating_ip_bastion:~/.ssh
scp  -o BatchMode=yes hosts ubuntu@$floating_ip_bastion:~/.ssh/ansible
ssh -i id_rsa.pub ubuntu@$floating_ip_bastion "ansible-playbook -i ~/.ssh/ansible/hosts ~/.ssh/ansible/site.yaml "



    
    
else
   echo "Number of active hosts on the local server ($local_active_hosts) is equal than active_hosts_remote ($active_hosts_remote). No new server will be created."
 
 
 # Fetch the server list from OpenStack
server_list=$(openstack server list -c Name -f value)

# Create the hosts file
cat <<EOF >hosts
[dev]

EOF

# Add all OpenStack servers with "dev" in their names below the [dev] section
while read -r server_name; do
  if [[ "$server_name" == *"dev"* ]]; then
    echo "$server_name" >>hosts
  fi
done <<< "$server_list"

# Append the remaining sections to the hosts file
cat <<EOF >>hosts

[haproxy]

test_proxy

[all:vars]
ansible_user=ubuntu
EOF

echo "The 'hosts' file has been created successfully."

    
fi
echo " Waiting for 30s..."
sleep 30
done























