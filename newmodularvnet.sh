#!/bin/bash

# Function to read user input
read_input() {
  local prompt="$1"
  local var_name="$2"
  read -p "$prompt" $var_name
}

# Initialize regions array globally so it's available throughout the script
regions=("eastus" "westeurope" "eastus2" "centralus" "northcentralus" "westus" "southcentralus" "uksouth" "japaneast" "australiaeast" "canadacentral" "canadaeast")

# Function to select a valid region
select_region() {
  local prompt="$1"
  
  # Display the prompt and regions list
  echo "$prompt"
  echo "Available Azure regions:"
  for i in "${!regions[@]}"; do
    echo "$i) ${regions[$i]}"
  done
  
  # Input validation for region selection
  while true; do
    read_input "Enter the number of the region: " region_index
    if [[ "$region_index" =~ ^[0-9]+$ ]] && (( region_index >= 0 && region_index < ${#regions[@]} )); then
      selected_region="${regions[$region_index]}"
      break
    else
      echo "Invalid selection. Please select a valid region index."
      echo "Available Azure regions:"
      for i in "${!regions[@]}"; do
        echo "$i) ${regions[$i]}"
      done
    fi
  done
  echo $selected_region
}

# Function to validate address prefix
validate_address() {
  local prompt="$1"
  local address
  while true; do
    read_input "$prompt" address
    prefix=$(echo "$address" | cut -d'/' -f2)
    
    # Validate that the prefix is between /16 and /27
    if [[ "$prefix" -ge 16 && "$prefix" -le 27 ]]; then
      echo "$address"
      break
    else
      echo "Error: The prefix must be between /16 and /27. Please enter a valid IP address range (e.g., 10.0.0.0/16)."
    fi
  done
}

# Arrays to store resource information
declare -a resource_groups
declare -a resource_group_regions
declare -a vnet_names
declare -a vnet_addresses
declare -a vnet_regions
declare -a vnet_rg_indices
declare -a subnet_names
declare -a subnet_addresses
declare -a vnet_subnet_counts

# Get number of resource groups
read_input "How many resource groups would you like to create/use? " num_rgs

# Collect resource group information
for (( i=0; i<num_rgs; i++ ))
do
  # Get resource group name and check if it exists
  read_input "Enter the name for resource group $((i+1)): " rg_name
  resource_groups[$i]=$rg_name
  
  rg_exists=$(az group exists --name "$rg_name")
  if [ "$rg_exists" = "false" ]; then
    echo "Resource group $rg_name doesn't exist."
    echo "You need to specify a region for the new resource group."
    echo "----------------------------------------"
    region=$(select_region "Select a region for resource group $rg_name:")
    resource_group_regions[$i]=$region
  else
    echo "Resource group $rg_name already exists."
    # Get existing resource group's region
    resource_group_regions[$i]=$(az group show --name "$rg_name" --query location -o tsv)
    echo "Using existing region: ${resource_group_regions[$i]}"
  fi
  echo "----------------------------------------"
done

# Ask for the number of VNets to create
read_input "How many VNets would you like to create in total? " num_vnets

# Collect information for all VNets and their subnets
for (( i=0; i<num_vnets; i++ ))
do
  echo "----------------------------------------"
  echo "Configuring VNet $((i+1)) of $num_vnets"
  echo "----------------------------------------"
  
  # Ask for VNet name and IP address range
  read_input "Enter name for VNet $((i+1)): " vnet_name
  vnet_address=$(validate_address "Enter the IP address range for VNet $vnet_name (e.g., 10.0.0.0/16): ")
  
  # Select resource group for this VNet
  echo "Select resource group for VNet $vnet_name:"
  for (( j=0; j<num_rgs; j++ ))
  do
    echo "$j) ${resource_groups[$j]} (Region: ${resource_group_regions[$j]})"
  done
  
  while true; do
    read_input "Enter the number of the resource group: " rg_index
    if [[ "$rg_index" =~ ^[0-9]+$ ]] && (( rg_index >= 0 && rg_index < num_rgs )); then
      break
    else
      echo "Invalid selection. Please select a valid resource group index."
    fi
  done
  
  # Select region for this VNet
  vnet_region=$(select_region "Select a region for VNet $vnet_name:")
  
  vnet_names[$i]=$vnet_name
  vnet_addresses[$i]=$vnet_address
  vnet_regions[$i]=$vnet_region
  vnet_rg_indices[$i]=$rg_index

  # Ask how many subnets to create in this VNet
  read_input "How many subnets do you want to create in $vnet_name? " num_subnets
  vnet_subnet_counts[$i]=$num_subnets

  # Collect subnet information
  for (( j=0; j<num_subnets; j++ ))
  do
    echo "----------------------------------------"
    echo "Configuring Subnet $((j+1)) of $num_subnets for VNet $vnet_name"
    echo "----------------------------------------"
    
    # Calculate the index for the subnet arrays
    index=$((i * 100 + j))  # Using 100 to allow for up to 100 subnets per VNet
    
    read_input "Enter name for subnet $((j+1)) in $vnet_name: " subnet_name
    subnet_address=$(validate_address "Enter the IP address range for subnet $subnet_name (e.g., 10.0.1.0/24): ")
    
    subnet_names[$index]=$subnet_name
    subnet_addresses[$index]=$subnet_address
  done
done

echo "Creating resources..."
echo "----------------------------------------"

# Create or update resource groups
for (( i=0; i<num_rgs; i++ ))
do
  rg_exists=$(az group exists --name "${resource_groups[$i]}")
  if [ "$rg_exists" = "false" ]; then
    echo "Creating resource group ${resource_groups[$i]} in region ${resource_group_regions[$i]}..."
    az group create --name "${resource_groups[$i]}" --location "${resource_group_regions[$i]}"
  fi
done

# Create all VNets
for (( i=0; i<num_vnets; i++ ))
do
  rg_index=${vnet_rg_indices[$i]}
  echo "Creating VNet ${vnet_names[$i]} in resource group ${resource_groups[$rg_index]}..."
  az network vnet create \
    --resource-group "${resource_groups[$rg_index]}" \
    --location "${vnet_regions[$i]}" \
    --name "${vnet_names[$i]}" \
    --address-prefix "${vnet_addresses[$i]}"

  # Create all subnets for this VNet
  num_subnets=${vnet_subnet_counts[$i]}
  for (( j=0; j<num_subnets; j++ ))
  do
    index=$((i * 100 + j))
    echo "Creating subnet ${subnet_names[$index]} in VNet ${vnet_names[$i]}..."
    az network vnet subnet create \
      --resource-group "${resource_groups[$rg_index]}" \
      --vnet-name "${vnet_names[$i]}" \
      --name "${subnet_names[$index]}" \
      --address-prefix "${subnet_addresses[$index]}"
  done
done

echo "----------------------------------------"
echo "All resources have been created successfully."