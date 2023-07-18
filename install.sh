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
private_key="${public_key%.pub}"
#echo "Private key file name: $private_key"

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
image_name="Ubuntu 22.04"

# Set the flavor
flavor="1C-2GB"

# Set the security group
security_group="${tag}_securitygroup"
#security_group="default"

current_date=$(date +"%Y-%m-%d")


start_time=$(date +%s)

current_time=$(date +"%H:%M:%S")
echo -e "$current_date $current_time Deploymnet is in progess ....  \n"
 
current_time=$(date +"%H:%M:%S")
if [ -e "$public_key" ]; then
    echo "$current_date $current_time Key $public_key exists."
else
    echo "\033[31mError: $current_date $current_time Key $public_key does not exist."
    exit 1
fi
 
current_time=$(date +"%H:%M:%S")
if [ -e "$private_key" ]; then
    echo "$current_date $current_time Key $private_key exists."
else
    echo "\033[31mError: $current_date $current_time Key $private_key does not exist."
    exit 1
fi

current_time=$(date +"%H:%M:%S")
if openstack flavor show "$flavor" >/dev/null 2>&1; then
    echo "$current_date $current_time Flavor $flavor exists."
else
    echo -e "\033[31mError:$current_date $current_time Flavor $flavor does not exist.Please replace with desire one. Exiting program."
    exit 1
fi


# echo "creating publickey"
# Generate public key file from private key
#ssh-keygen -y -f "$private_key" > "$public_key"
#echo "create publickey"

# Source the openrc file
source "$openrc_file"

cat <<EOF >hosts

EOF
cat <<EOF >>hosts
[dev]
${tag}_deva
${tag}_devb
${tag}_devc
[haproxy]
${tag}_proxy
[bastion]
${tag}_bastion

[all:vars]
ansible_user=ubuntu
EOF


# Find the external network
external_net=$(openstack network list --external --format value -c ID)
if [ -z "$external_net" ]; then
    echo "No external network found. Exiting."
    exit 1
fi



# Check if there are available floating IP addresses
floating_ips=$(openstack floating ip list -f value -c "Floating IP Address" )
   #  echo -e "Floating IP list is : \n $floating_ips "
floating_num=$(openstack floating ip list -f value -c "Floating IP Address" | wc -l )
     

if [[ floating_num -ge 1 ]]; then
    # Use the first available floating IP for the Bastion server
    floating_ip_bastion=$(echo "$floating_ips" | awk 'NR==1')
    #echo "floating_ip_bastion $floating_ip_bastion"
    
    
    if [[ floating_num -ge 2 ]]; then
        # Use the second available floating IP for the proxy server
        floating_ip_proxy=$(echo "$floating_ips" | awk 'NR==2')
       # echo "floating_ip_proxy $floating_ip_proxy"
    else
        # Create a new floating IP address for the proxy server
        floating_ip_proxy=$(openstack floating ip create  $external_net)
    fi
else
    # Create two new floating IP addresses
    current_time=$(date +"%H:%M:%S")
    
    echo "$current_date $current_time Creating floating IP ..."
    floating_ip_1=$(openstack floating ip create  $external_net ) 
    floating_ip_2=$(openstack floating ip create  $external_net)
     
fi

# Check if the network already exists
network_exists=$(openstack network show -f value -c name "$network_name" 2>/dev/null)
current_time=$(date +"%H:%M:%S")

if [ -n "$network_exists" ]; then
    echo "$current_date $current_time  network with the tag '$tag' already exists: $network_name.Skipping network creation."
else
    # Create the network with the specified name and tag
    openstack network create "$network_name" --tag "$tag" > /dev/null 
    echo "$current_date $current_time Network created with the name  $network_name"
fi

# Check if the key already exists with the same name
key_exists=$(openstack keypair list --format value --column Name | grep "^$key_name$" )
current_time=$(date +"%H:%M:%S")
if [ -n "$key_exists" ]; then
    echo "$current_date $current_time The key with the name '$key_name' already exists. Skipping key creation."
else
    # Create the keypair with the specified public key and name
    openstack keypair create --public-key "$public_key" "$key_name" > /dev/null
    echo "$current_date $current_time Key created with the name '$key_name'"
fi

# Check if the security group already exists
existing_group=$(openstack security group list --column Name --format value | grep -w "$security_group")
current_time=$(date +"%H:%M:%S")
if [ -n "$existing_group" ]; then
    echo "$current_date $current_time Security group $security_group already exists.Skipping Securitygroup creation."
    
else

# Create the security group
openstack security group create --description "Security group with tag: $security_group" "$security_group" > /dev/null 
# Add rules to allow SSH, SNMP, and ICMP traffic
current_time=$(date +"%H:%M:%S")
echo "$current_date $current_time Adding rules to $security_groupss"
openstack security group rule create --protocol tcp --dst-port 22:22 --ingress "$security_group" > /dev/null 
openstack security group rule create --protocol udp --dst-port 161:161 --ingress "$security_group" > /dev/null 
openstack security group rule create --protocol tcp --dst-port 80:80 --ingress "$security_group" > /dev/null 
openstack security group rule create --protocol icmp "$security_group" > /dev/null 
#openstack security group rule create --protocol any --ingress "$security_group"
echo "$current_date $current_time Security rule added to security group"

fi






# Check if the subnet already exists
#subnet_exists=$(openstack subnet show -f value -c  "$subnet_name" 2>/dev/null)
subnet_id=$(openstack subnet show -f value -c id  "$subnet_name" )
#echo "Subnet with the name '$subnet_name' and '$subnet_id' "
current_time=$(date +"%H:%M:%S")
if [ -n "$subnet_id" ]; then
     #subnet_id=$(echo "$subnet_exists" | awk '/ id / {print $4}')
    echo "$current_date $current_time The subnet with the name '$subnet_name' already exists. Skipping subnet creation."
#    echo "the subnet id is $subnet_id "
else
    # Create the subnet with the specified network name and subnet details
   subnet_id=$( openstack subnet create --network "$network_name" --dhcp --ip-version 4 \
        --subnet-range 10.0.0.0/24 --allocation-pool start=10.0.0.100,end=10.0.0.200 \
        --dns-nameserver 1.1.1.1 "$subnet_name" -f value -c id ) > /dev/null 
    echo "$current_date $current_time Subnet created with the name '$subnet_name' and  ID '$subnet_id' "
fi



# Show the subnet list
#openstack subnet list

# Check if the router already exists
router_exists=$(openstack router show -f value -c name "$router_name" 2>/dev/null)
current_time=$(date +"%H:%M:%S")
if [ -n "$router_exists" ]; then
    echo "$current_date $current_time The router with the name '$router_name' already exists. Skipping router creation."
else
    # Create the router with the specified name and tag
    openstack router create "$router_name" --tag "$tag" --external-gateway "$external_net" > /dev/null 
    echo "$current_date $current_time Router created with the tag '$tag': $router_name" 
fi



# Check if the subnet is already attached to the router
subnet_attached=$(openstack router show "$router_name" -c interfaces_info -f json | jq -e '.interfaces_info[] | .subnet_id' | grep -q "$subnet_id" && echo "true" || echo "false")
current_time=$(date +"%H:%M:%S")
if [ "$subnet_attached" = "true" ]; then
    echo "$current_date $current_time The subnet '$subnet_name' is already attached to the router '$router_name'. Skipping add subnet creation."
else
# Add the subnet to the router
openstack router add subnet "$router_name" "$subnet_name"
echo "$current_date $current_time Subnet '$subnet_name' added to router '$router_name'"

fi

echo "$current_date $current_time Detecting suitable image, looking for Ubuntu $image_name"
current_time=$(date +"%H:%M:%S")
# Find the image ID for Ubuntu 20.04
    image=$(openstack image list --status active --format value | grep "$image_name")

    # Check if image is empty
    if [[ -z "$image" ]]; then
        echo "$current_date $current_time Image not found: $image_name"
    else
        image_id=$(echo "$image" | awk 'NR==1{print $1}')
#        echo  -e "$current_date $current_time Image found:\n $image  "
        echo -e "$current_date $current_time Image ID: $image_id  "

echo "$current_date $current_time Creating Servers ..."
current_time=$(date +"%H:%M:%S")
# Check if the server already exists
server_exists=$(openstack server show -f value -c name "$server_name" 2>/dev/null)
if [ -n "$server_exists" ]; then
    echo "$current_date $current_time The Bastion server with the tag '$tag' already exists: $server_name"
else
    
        # Create the server instance with the specified details
        openstack server create --flavor "$flavor" --image "$image_id" --network "$network_name" \
            --security-group "$security_group" --key-name "$key_name" "$server_name" > /dev/null
        echo "$current_date $current_time Bastion server created with the name '$server_name'" 
    fi
fi



# Check if the proxy server already exists
proxy_server_exists=$(openstack server show -f value -c name "$proxy_server_name" 2>/dev/null)
current_time=$(date +"%H:%M:%S")
if [ -n "$proxy_server_exists" ]; then
    echo "$current_date $current_time The proxy server with the tag '$tag' already exists: $proxy_server_name"
else
    # Create the proxy server instance with the same configuration as the Bastion server
    openstack server create --flavor "$flavor" --image "$image_id" --network "$network_name" \
        --security-group "$security_group" --key-name "$key_name" "$proxy_server_name"  > /dev/null 
    echo "$current_date $current_time Proxy server created with the name '$proxy_server_name'"
fi


# Check if the deva server already exists
deva_server_exists=$(openstack server show -f value -c name "${tag}_deva" 2>/dev/null)
current_time=$(date +"%H:%M:%S")
if [ -n "$deva_server_exists" ]; then
    echo "$current_date $current_time The deva server with the tag '$tag' already exists: ${tag}_deva"
else
    # Create the deva server instance with the same configuration as the previous servers
    openstack server create --flavor "$flavor" --image "$image_id" --network "$network_name" \
        --security-group "$security_group" --key-name "$key_name" "${tag}_deva" > /dev/null 
    echo "$current_date $current_time Deva server created with the name '${tag}_deva'"
fi


# Check if the devb server already exists
devb_server_exists=$(openstack server show -f value -c name "${tag}_devb" 2>/dev/null)
current_time=$(date +"%H:%M:%S")
if [ -n "$devb_server_exists" ]; then
    echo "$current_date $current_time The devb server with the tag '$tag' already exists: ${tag}_devb"
else
    # Create the devb server instance with the same configuration as the previous servers
    openstack server create --flavor "$flavor" --image "$image_id" --network "$network_name" \
        --security-group "$security_group" --key-name "$key_name" "${tag}_devb" > /dev/null 
    echo "$current_date $current_time Devb server created with the name '${tag}_devb'"
fi


# Check if the devc server already exists
devc_server_exists=$(openstack server show -f value -c name "${tag}_devc" 2>/dev/null)
current_time=$(date +"%H:%M:%S")
if [ -n "$devc_server_exists" ]; then
    echo "$current_date $current_time The devc server with the tag '$tag' already exists: ${tag}_devc"
else
    # Create the devc server instance with the same configuration as the previous servers
    openstack server create --flavor "$flavor" --image "$image_id" --network "$network_name" \
        --security-group "$security_group" --key-name "$key_name" "${tag}_devc" > /dev/null 
    echo "$current_date $current_time Devc server created with the name '${tag}_devc'"
fi
current_time=$(date +"%H:%M:%S")
bastion_ip=$(openstack server show -f value -c addresses $server_name | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
echo "$current_date $current_time IP bastion = '$bastion_ip'"
current_time=$(date +"%H:%M:%S")
proxy_ip=$(openstack server show -f value -c addresses $proxy_server_name | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
echo "$current_date $current_time IP proxy = '$proxy_ip'"
current_time=$(date +"%H:%M:%S")
deva_ip=$(openstack server show -f value -c addresses "${tag}_deva" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
echo "$current_date $current_time IP deva = '$deva_ip'"
current_time=$(date +"%H:%M:%S")
devb_ip=$(openstack server show -f value -c addresses "${tag}_devb" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
current_time=$(date +"%H:%M:%S")
echo "$current_date $current_time IP devb = '$devb_ip'"
current_time=$(date +"%H:%M:%S")
devc_ip=$(openstack server show -f value -c addresses "${tag}_devc" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
echo "$current_date $current_time IP devc = '$devc_ip'"

floating_ips=$(openstack floating ip list -f value -c "Floating IP Address" )
floating_ip_bastion=$(echo "$floating_ips" | awk 'NR==1')
current_time=$(date +"%H:%M:%S")
echo "$current_date $current_time Floating_ip_bastion $floating_ip_bastion"
current_time=$(date +"%H:%M:%S")
floating_ip_proxy=$(echo "$floating_ips" | awk 'NR==2')
echo "$current_date $current_time Floating_ip_proxy $floating_ip_proxy"






# Assign the floating IPs to the servers
openstack server add floating ip $server_name $floating_ip_bastion

openstack server add floating ip $proxy_server_name $floating_ip_proxy

current_time=$(date +"%H:%M:%S")
echo "$current_date $current_time Assigned floating IP $floating_ip_bastion to server $server_name"
echo "$current_date $current_time Assigned floating IP $floating_ip_proxy to server $proxy_server_name"

# Build base SSH config file
ssh_config_file="config"

echo "# SSH configuration for ${tag}_deva" > "$ssh_config_file"
echo "Host ${tag}_deva" >> "$ssh_config_file"
echo "  HostName $deva_ip" >> "$ssh_config_file"
echo "  User ubuntu" >> "$ssh_config_file"
echo " StrictHostKeyChecking no" >> "$ssh_config_file"
echo "  IdentityFile ~/.ssh/$private_key" >> "$ssh_config_file"
echo "" >> "$ssh_config_file"

echo "# SSH configuration for ${tag}_devb" >> "$ssh_config_file"
echo "Host ${tag}_devb" >> "$ssh_config_file"
echo "  HostName $devb_ip" >> "$ssh_config_file"
echo "  User ubuntu" >> "$ssh_config_file"
echo " StrictHostKeyChecking no" >> "$ssh_config_file"
echo "  IdentityFile ~/.ssh/$private_key" >> "$ssh_config_file"
echo "" >> "$ssh_config_file"

echo "# SSH configuration for ${tag}_devc" >> "$ssh_config_file"
echo "Host ${tag}_devc" >> "$ssh_config_file"
echo "  HostName $devc_ip" >> "$ssh_config_file"
echo "  User ubuntu" >> "$ssh_config_file"
echo " StrictHostKeyChecking no" >> "$ssh_config_file"
echo "  IdentityFile ~/.ssh/$private_key" >> "$ssh_config_file"
echo "" >> "$ssh_config_file"

echo "# SSH configuration for ${tag}_proxy" >> "$ssh_config_file"
echo "Host ${tag}_proxy" >> "$ssh_config_file"
echo "  HostName $proxy_ip" >> "$ssh_config_file"
echo "  User ubuntu" >> "$ssh_config_file"
echo " StrictHostKeyChecking no" >> "$ssh_config_file"
echo "  IdentityFile ~/.ssh/$private_key" >> "$ssh_config_file"

echo "# SSH configuration for ${tag}_bastion" >> "$ssh_config_file"
echo "Host ${tag}_bastion" >> "$ssh_config_file"
echo "  HostName $bastion_ip" >> "$ssh_config_file"
echo "  User ubuntu" >> "$ssh_config_file"
echo " StrictHostKeyChecking no" >> "$ssh_config_file"
echo "  IdentityFile ~/.ssh/$private_key" >> "$ssh_config_file"

echo "$current_date $current_time Base SSH configuration file created: $ssh_config_file"

current_time=$(date +"%H:%M:%S")
# Install Ansible on the server
echo "$current_date $current_time Install ansible on Bastion host"
ssh -o StrictHostKeyChecking=no -i $public_key ubuntu@$floating_ip_bastion 'sudo apt update >/dev/null 2>&1 && sudo apt install -y ansible >/dev/null 2>&1' > sshout.txt 2>&1
current_time=$(date +"%H:%M:%S")
if grep -q "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED"  sshout.txt ; then
    echo "Warning message found! Running ssh-keygen command..."
    ssh-keygen -f "/home/user/.ssh/known_hosts" -R "$floating_ip_bastion"
else
    echo  "$current_date $current_time Warning message not found."
fi

current_time=$(date +"%H:%M:%S")
# Check the Ansible version on the server
#ansible_version=$(ssh -i id_rsa.pub ubuntu@$floating_ip_bastion 'ansible --version')
echo "$current_date $current_time Ansible installed successfully"
#echo "Ansible version: $ansible_version"
current_time=$(date +"%H:%M:%S")
# Copy the public key to the Bastion server
echo "$current_date $current_time Copying public key to the Bastion server"
scp  -o StrictHostKeyChecking=no $public_key ubuntu@$floating_ip_bastion:~/.ssh  > /dev/null
scp  -o BatchMode=yes $private_key ubuntu@$floating_ip_bastion:~/.ssh  > /dev/null
scp  -o BatchMode=yes  $ssh_config_file ubuntu@$floating_ip_bastion:~/.ssh > /dev/null
#scp  -o BatchMode=yes  -r ansible ubuntu@$floating_ip_bastion:~/.ssh
scp  -o BatchMode=yes  application2.py ubuntu@$floating_ip_bastion:~/.ssh > /dev/null
scp  -o BatchMode=yes  haproxy.cfg.j2 ubuntu@$floating_ip_bastion:~/.ssh > /dev/null
scp  -o BatchMode=yes  hosts ubuntu@$floating_ip_bastion:~/.ssh > /dev/null
scp  -o BatchMode=yes  my_flask_app.service ubuntu@$floating_ip_bastion:~/.ssh > /dev/null
scp  -o BatchMode=yes  site.yaml ubuntu@$floating_ip_bastion:~/.ssh > /dev/null
scp  -o BatchMode=yes  config ubuntu@$floating_ip_bastion:~/.ssh > /dev/null
scp  -o BatchMode=yes  snmpd.conf ubuntu@$floating_ip_bastion:~/.ssh > /dev/null


ssh -i $public_key ubuntu@$floating_ip_bastion "ansible-playbook -i ~/.ssh/hosts ~/.ssh/site.yaml " > /dev/null
current_time=$(date +"%H:%M")
echo "$current_date $current_time   Site Verification.."

for ((i=1; i<=3; i++))
do
    current_time=$(date +"%H:%M:%S")
    echo "$current_date $current_time Request $i:"
    curl http://$floating_ip_proxy
    echo "================"
done

end_time=$(date +%s)
execution_time=$((end_time - start_time))
echo "================"
echo "Script execution time: $execution_time seconds"















