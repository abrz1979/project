#!/bin/bash

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

# Find the external network
external_net=$(openstack network list --external --format value -c ID)
if [ -z "$external_net" ]; then
    echo "No external network found. Exiting."
    exit 1
fi

# Check if there are available floating IP addresses
floating_ips=$(openstack floating ip list -f value -c "Floating IP Address" )
     echo "Floating IP list is $floating_ips"
floating_num=$(openstack floating ip list -f value -c "Floating IP Address" | wc -l )
     

if [[ floating_num -ge 1 ]]; then
    # Use the first available floating IP for the Bastion server
    floating_ip_bastion=$(echo "$floating_ips" | awk 'NR==1')
    echo "floating_ip_bastion $floating_ip_bastion"
    
    
    if [[ floating_num -ge 2 ]]; then
        # Use the second available floating IP for the proxy server
        floating_ip_proxy=$(echo "$floating_ips" | awk 'NR==2')
        echo "floating_ip_proxy $floating_ip_proxy"
    else
        # Create a new floating IP address for the proxy server
        floating_ip_proxy=$(openstack floating ip create  $external_net)
    fi
else
    # Create two new floating IP addresses
    echo "creating floating IP"
    floating_ip_1=$(openstack floating ip create  $external_net ) 
    floating_ip_2=$(openstack floating ip create  $external_net)
    
    
    
    
 #   sleep 10
    
fi

# Check if the network already exists
network_exists=$(openstack network show -f value -c name "$network_name" 2>/dev/null)
if [ -n "$network_exists" ]; then
    echo "A network with the tag '$tag' already exists: $network_name"
else
    # Create the network with the specified name and tag
    openstack network create "$network_name" --tag "$tag"
    echo "Network created with the tag '$tag': $network_name"
fi

# Check if the key already exists with the same name
key_exists=$(openstack keypair list --format value --column Name | grep "^$key_name$")
if [ -n "$key_exists" ]; then
    echo "The key with the name '$key_name' already exists. Skipping key creation."
else
    # Create the keypair with the specified public key and name
    openstack keypair create --public-key "$public_key" "$key_name"
    echo "Key created with the name '$key_name'"
fi

# Show the keypair list
#openstack keypair list




# Check if the subnet already exists
subnet_exists=$(openstack subnet show -f value -c name "$subnet_name" 2>/dev/null)
if [ -n "$subnet_exists" ]; then
    echo "The subnet with the name '$subnet_name' already exists. Skipping subnet creation."
else
    # Create the subnet with the specified network name and subnet details
    openstack subnet create --network "$network_name" --dhcp --ip-version 4 \
        --subnet-range 10.0.0.0/24 --allocation-pool start=10.0.0.100,end=10.0.0.200 \
        --dns-nameserver 1.1.1.1 "$subnet_name"
    echo "Subnet created with the name '$subnet_name'"
fi

# Show the subnet list
#openstack subnet list

# Check if the router already exists
router_exists=$(openstack router show -f value -c name "$router_name" 2>/dev/null)
if [ -n "$router_exists" ]; then
    echo "The router with the name '$router_name' already exists. Skipping router creation."
else
    # Create the router with the specified name and tag
    openstack router create "$router_name" --tag "$tag" --external-gateway "$external_net"
    echo "Router created with the tag '$tag': $router_name"
fi

# Show the router list
#openstack router list

# Add the subnet to the router
openstack router add subnet "$router_name" "$subnet_name"
echo "Subnet '$subnet_name' added to router '$router_name'"

# Check if the server already exists
server_exists=$(openstack server show -f value -c name "$server_name" 2>/dev/null)
if [ -n "$server_exists" ]; then
    echo "The Bastion server with the tag '$tag' already exists: $server_name"
else
    # Find the image ID for Ubuntu 20.04
    image=$(openstack image list --format value | grep "$image_name")

    # Check if image is empty
    if [[ -z "$image" ]]; then
        echo "Image not found: $image_name"
    else
        image_id=$(echo "$image" | awk '{print $1}')
        echo "Image found: $image"
        echo "Image ID: $image_id"

        # Create the server instance with the specified details
        openstack server create --flavor "$flavor" --image "$image_id" --network "$network_name" \
            --security-group "$security_group" --key-name "$key_name" "$server_name"
        echo "Server created with the name '$server_name'"
    fi
fi



# Check if the proxy server already exists
proxy_server_exists=$(openstack server show -f value -c name "$proxy_server_name" 2>/dev/null)
if [ -n "$proxy_server_exists" ]; then
    echo "The proxy server with the tag '$tag' already exists: $proxy_server_name"
else
    # Create the proxy server instance with the same configuration as the Bastion server
    openstack server create --flavor "$flavor" --image "$image_id" --network "$network_name" \
        --security-group "$security_group" --key-name "$key_name" "$proxy_server_name"
    echo "Proxy server created with the name '$proxy_server_name'"
fi


# Check if the deva server already exists
deva_server_exists=$(openstack server show -f value -c name "${tag}_deva" 2>/dev/null)
if [ -n "$deva_server_exists" ]; then
    echo "The deva server with the tag '$tag' already exists: ${tag}_deva"
else
    # Create the deva server instance with the same configuration as the previous servers
    openstack server create --flavor "$flavor" --image "$image_id" --network "$network_name" \
        --security-group "$security_group" --key-name "$key_name" "${tag}_deva"
    echo "Deva server created with the name '${tag}_deva'"
fi


# Check if the devb server already exists
devb_server_exists=$(openstack server show -f value -c name "${tag}_devb" 2>/dev/null)
if [ -n "$devb_server_exists" ]; then
    echo "The devb server with the tag '$tag' already exists: ${tag}_devb"
else
    # Create the devb server instance with the same configuration as the previous servers
    openstack server create --flavor "$flavor" --image "$image_id" --network "$network_name" \
        --security-group "$security_group" --key-name "$key_name" "${tag}_devb"
    echo "Devb server created with the name '${tag}_devb'"
fi


# Check if the devc server already exists
devc_server_exists=$(openstack server show -f value -c name "${tag}_devc" 2>/dev/null)
if [ -n "$devc_server_exists" ]; then
    echo "The devc server with the tag '$tag' already exists: ${tag}_devc"
else
    # Create the devc server instance with the same configuration as the previous servers
    openstack server create --flavor "$flavor" --image "$image_id" --network "$network_name" \
        --security-group "$security_group" --key-name "$key_name" "${tag}_devc"
    echo "Devc server created with the name '${tag}_devc'"
fi

bastion_ip=$(openstack server show -f value -c addresses $server_name | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
echo " IP bastion = '$bastion_ip'"
proxy_ip=$(openstack server show -f value -c addresses $proxy_server_name | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
echo " IP proxy = '$proxy_ip'"

deva_ip=$(openstack server show -f value -c addresses "${tag}_deva" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
echo " IP deva = '$deva_ip'"
devb_ip=$(openstack server show -f value -c addresses "${tag}_devb" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
echo " IP devb = '$devb_ip'"
devc_ip=$(openstack server show -f value -c addresses "${tag}_devc" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
echo " IP devc = '$devc_ip'"

floating_ips=$(openstack floating ip list -f value -c "Floating IP Address" )
floating_ip_bastion=$(echo "$floating_ips" | awk 'NR==1')
echo "floating_ip_bastion $floating_ip_bastion"
floating_ip_proxy=$(echo "$floating_ips" | awk 'NR==2')
echo "floating_ip_proxy $floating_ip_proxy"






# Assign the floating IPs to the servers
openstack server add floating ip $server_name $floating_ip_bastion

openstack server add floating ip $proxy_server_name $floating_ip_proxy


echo "Assigned floating IP $floating_ip_bastion to server $server_name"
echo "Assigned floating IP $floating_ip_proxy to server $proxy_server_name"

# Build base SSH config file
ssh_config_file="config"

echo "# SSH configuration for ${tag}_deva" > "$ssh_config_file"
echo "Host ${tag}_deva" >> "$ssh_config_file"
echo "  HostName $deva_ip" >> "$ssh_config_file"
echo "  User ubuntu" >> "$ssh_config_file"
echo " StrictHostKeyChecking no" >> "$ssh_config_file"
echo "  IdentityFile ~/.ssh/id_rsa" >> "$ssh_config_file"
echo "" >> "$ssh_config_file"

echo "# SSH configuration for ${tag}_devb" >> "$ssh_config_file"
echo "Host ${tag}_devb" >> "$ssh_config_file"
echo "  HostName $devb_ip" >> "$ssh_config_file"
echo "  User ubuntu" >> "$ssh_config_file"
echo " StrictHostKeyChecking no" >> "$ssh_config_file"
echo "  IdentityFile ~/.ssh/id_rsa" >> "$ssh_config_file"
echo "" >> "$ssh_config_file"

echo "# SSH configuration for ${tag}_devc" >> "$ssh_config_file"
echo "Host ${tag}_devc" >> "$ssh_config_file"
echo "  HostName $devc_ip" >> "$ssh_config_file"
echo "  User ubuntu" >> "$ssh_config_file"
echo " StrictHostKeyChecking no" >> "$ssh_config_file"
echo "  IdentityFile ~/.ssh/id_rsa" >> "$ssh_config_file"
echo "" >> "$ssh_config_file"

echo "# SSH configuration for ${tag}_proxy" >> "$ssh_config_file"
echo "Host ${tag}_proxy" >> "$ssh_config_file"
echo "  HostName $proxy_ip" >> "$ssh_config_file"
echo "  User ubuntu" >> "$ssh_config_file"
echo " StrictHostKeyChecking no" >> "$ssh_config_file"
echo "  IdentityFile ~/.ssh/id_rsa" >> "$ssh_config_file"

echo "Base SSH configuration file created: $ssh_config_file"


# Install Ansible on the server
echo "Install ansible"
ssh -o StrictHostKeyChecking=no -i id_rsa ubuntu@$floating_ip_bastion 'sudo apt update >/dev/null 2>&1 && sudo apt install -y ansible >/dev/null 2>&1'
# Check the Ansible version on the server
ansible_version=$(ssh -i id_rsa.pub ubuntu@$floating_ip_bastion 'ansible --version')
echo "Ansible installed successfully"
echo "Ansible version: $ansible_version"

# Copy the public key to the Bastion server
echo "Copying public key to the Bastion server"
#scp  -o StrictHostKeyChecking=no id_rsa.pub ubuntu@$floating_ip_bastion:~/.ssh
scp  -o BatchMode=yes id_rsa ubuntu@$floating_ip_bastion:~/.ssh
scp  -o BatchMode=yes  $ssh_config_file ubuntu@$floating_ip_bastion:~/.ssh
scp  -o BatchMode=yes  site.yaml ubuntu@$floating_ip_bastion:~/.ssh
scp  -o BatchMode=yes  application2.py ubuntu@$floating_ip_bastion:~/.ssh
scp  -o BatchMode=yes  haproxy.cfg.j2 ubuntu@$floating_ip_bastion:~/.ssh
scp  -o BatchMode=yes  my_flask_app.service ubuntu@$floating_ip_bastion:~/.ssh	
scp  -o BatchMode=yes  hosts ubuntu@$floating_ip_bastion:~/.ssh


ssh -i id_rsa.pub ubuntu@$floating_ip_bastion "ansible-playbook -i ~/.ssh/ansible/hosts ~/.ssh/ansible/site.yaml "

















