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
flavor="4C-8GB"

# Set the security group
security_group="${tag}_securitygroup"

# Source the openrc file
source "$openrc_file"

current_date=$(date +"%Y-%m-%d")


start_time=$(date +%s)

# Check if tag argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <tag>"
  exit 1
fi
current_time=$(date +"%H:%M:%S")
echo -e "$current_date $current_time Cleaning is in progress ... \n "

# Extract the tag from the argument
#tag="$1"

# Locate the router name based on the tag
router_name="${tag}_router"


current_time=$(date +"%H:%M:%S")
# Get the keypair name with the specified tag
keypair_name=$(openstack keypair list  -f value -c Name | grep $tag)
if [ -n "$keypair_name" ]; then
  # Remove the tag key from the keypair
  openstack keypair delete "$keypair_name"
  if [ $? -eq 0 ]; then
    echo "$current_date $current_time Tag '$tag' removed from keypair '$keypair_name'."
  else
    echo "$current_date $current_time Failed to remove tag '$tag' from keypair '$keypair_name'."
  fi
else
  echo "$current_date $current_time No keypair found with tag '$tag'."
fi

# Rest of the script to delete router, subnet, network, server, and floating IPs
# ...
current_time=$(date +"%H:%M:%S")
# Remove floating IP addresses
floating_ips=$(openstack floating ip list -f value -c ID)
if [ -n "$floating_ips" ]; then
  while read -r floating_ip; do
    openstack floating ip delete "$floating_ip"
    if [ $? -eq 0 ]; then
      echo "$current_date $current_time Floating IP '$floating_ip' deleted."
    else
      echo "$current_date $current_time Failed to delete floating IP '$floating_ip'."
    fi
  done <<< "$floating_ips"
else
  echo "$current_date $current_time No floating IP addresses found."
fi
current_time=$(date +"%H:%M:%S")
# Delete servers with names starting with the tag
server_names=$(openstack server list   -c Name -f value | grep "^${tag}_")
if [ -n "$server_names" ]; then
  while read -r server_name; do
    openstack server delete "$server_name"
    if [ $? -eq 0 ]; then
      echo "$current_date $current_time Server '$server_name' deleted."
    else
      echo "$current_date $current_time Failed to delete server '$server_name'."
    fi
  done <<< "$server_names"
else
  echo "$current_date $current_time No servers found with names starting with '$tag'."
fi

# Check if the security group exists
#echo "$security_group"
existing_group=$(openstack security group show "$security_group" --format value -c name  )
current_time=$(date +"%H:%M:%S")
if [ -z "$existing_group" ]; then
    echo "$current_date $current_time No security group with name $security_group"
else
    # Delete the security group
    openstack security group delete "$security_group"
    echo "$current_date $current_time Security group $security_group deleted"
fi

# Check if the router exists
current_time=$(date +"%H:%M:%S")
openstack router show "$router_name" > /dev/null 
if [ $? -eq 0 ]; then
  # Find the subnet based on the tag
  subnet_name="${tag}_subnet"

  # Disconnect subnet from router
  openstack router remove subnet "$router_name" "$subnet_name"
  if [ $? -eq 0 ]; then
    echo "$current_date $current_time Subnet '$subnet_name' disconnected from router '$router_name'."
  else
    echo "$current_date $current_time Failed to disconnect subnet '$subnet_name' from router '$router_name'."
    exit 1
  fi

  # Delete the subnet
  current_time=$(date +"%H:%M:%S")
  openstack subnet delete "$subnet_name"
  if [ $? -eq 0 ]; then
    echo "$current_date $current_time Subnet '$subnet_name' deleted."
  else
    echo "$current_date $current_time Failed to delete subnet '$subnet_name'."
  fi

  # Delete the router
  current_time=$(date +"%H:%M:%S")
  openstack router delete "$router_name"
  if [ $? -eq 0 ]; then
    echo "$current_date $current_time Router '$router_name' deleted."
  else
    echo "$current_date $current_time Failed to delete router '$router_name'."
  fi
else
  echo "$current_date $current_time Router '$router_name' not found."
fi

# Delete the network
current_time=$(date +"%H:%M:%S")
network_name="${tag}_network"
openstack network delete "$network_name" > /dev/null 
if [ $? -eq 0 ]; then
  echo "$current_date $current_time Network '$network_name' deleted."
else
  echo "$current_date $current_time network  '$network_name' not found  ."
fi

# Check if there are any networks remaining
current_time=$(date +"%H:%M:%S")
remaining_networks=$(openstack network list --tags "$tag" -f value -c ID)
if [ -z "$remaining_networks" ]; then
  echo "$current_date $current_time No networks found with tag '$tag'."
fi
current_time=$(date +"%H:%M:%S")
echo "$current_date $current_time All components have been removed "
end_time=$(date +%s)
execution_time=$((end_time - start_time))
echo "================"
echo "Script execution time: $execution_time seconds"

