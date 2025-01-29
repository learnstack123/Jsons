#!/bin/bash

# Function to read user input
read_input() {
  local prompt="$1"
  local var_name="$2"
  read -p "$prompt" $var_name
}

# Function to select a valid region
select_region() {
  # List of available regions in Azure, including Canada regions
  regions=("eastus" "westeurope" "eastus2" "centralus" "northcentralus" "westus" "southcentralus" "uksouth" "japaneast" "australiaeast" "canadacentral" "canadaeast")
  
  # Display regions with index numbers
  echo "Select a region by number:"
  for i in "${!regions[@]}"; do
    echo "$i) ${regions[$i]}"
  done
  
  # Input validation for region selection
  while true; do
    read_input "Enter the number of the region: " region_index
    if [[ "$region_index" =~ ^[0-9]+$ ]] && (( region_index >= 0 && region_index < ${#regions[@]} )); then
      region="${regions[$region_index]}"
      echo "Selected region: $region"
      break
    else
      echo "Invalid selection. Please select a valid region index."
    fi
  done
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
declare -a vnet_names
declare -a vnet_addresses
declare -a subnet_names
declare -a subnet_addresses
declare -a vnet_subnet_counts

# Get resource group name and check if it exists
read_input "Enter the name of the resource group: " resource_group
rg_exists=$(az group exists --name "$resource_group")

# Select the region
select_region

# Ask for the number of VNets to create
read_input "How many VNets would you like to create? " num_vnets

# Collect information for all VNets and their subnets
for (( i=0; i<num_vnets; i++ ))
do
  # Ask for VNet name and IP address range
  read_input "Enter name for VNet $((i+1)): " vnet_name
  vnet_address=$(validate_address "Enter the IP address range for VNet $vnet_name (e.g., 10.0.0.0/16): ")
  
  vnet_names[$i]=$vnet_name
  vnet_addresses[$i]=$vnet_address

  # Ask how many subnets to create in this VNet
  read_input "How many subnets do you want to create in $vnet_name? " num_subnets
  vnet_subnet_counts[$i]=$num_subnets

  # Collect subnet information
  for (( j=0; j<num_subnets; j++ ))
  do
    # Calculate the index for the subnet arrays
    index=$((i * 100 + j))  # Using 100 to allow for up to 100 subnets per VNet
    
    read_input "Enter name for subnet $((j+1)) in $vnet_name: " subnet_name
    subnet_address=$(validate_address "Enter the IP address range for subnet $subnet_name (e.g., 10.0.1.0/24): ")
    
    subnet_names[$index]=$subnet_name
    subnet_addresses[$index]=$subnet_address
  done
done

echo "Creating resources..."

# Create resource group if it doesn't exist
if [ "$rg_exists" = "false" ]; then
  echo "Creating resource group $resource_group..."
  az group create --name "$resource_group" --location "$region"
fi

# Create all VNets
for (( i=0; i<num_vnets; i++ ))
do
  echo "Creating VNet ${vnet_names[$i]}..."
  az network vnet create \
    --resource-group "$resource_group" \
    --location "$region" \
    --name "${vnet_names[$i]}" \
    --address-prefix "${vnet_addresses[$i]}"

  # Create all subnets for this VNet
  num_subnets=${vnet_subnet_counts[$i]}
  for (( j=0; j<num_subnets; j++ ))
  do
    index=$((i * 100 + j))
    echo "Creating subnet ${subnet_names[$index]} in VNet ${vnet_names[$i]}..."
    az network vnet subnet create \
      --resource-group "$resource_group" \
      --vnet-name "${vnet_names[$i]}" \
      --name "${subnet_names[$index]}" \
      --address-prefix "${subnet_addresses[$index]}"
  done
done

echo "All resources have been created successfully."