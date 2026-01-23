#!/bin/bash

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting package installation...${NC}"

# Check if packages.json exists
if [ ! -f "packages.json" ]; then
    echo -e "${RED}Error: packages.json not found!${NC}"
    exit 1
fi

# Check if jq is installed, if not install it first
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}jq not found. Installing jq first...${NC}"
    sudo apt update
    sudo apt install -y jq
fi

# Update apt package list
echo -e "${YELLOW}Updating apt package list...${NC}"
sudo apt update

# Install apt packages
echo -e "${YELLOW}Installing apt packages...${NC}"
apt_packages=$(jq -r '.apt.packages[]' packages.json)

if [ -n "$apt_packages" ]; then
    for package in $apt_packages; do
        echo -e "${GREEN}Installing $package...${NC}"
        sudo apt install -y "$package"
    done
else
    echo -e "${YELLOW}No apt packages to install${NC}"
fi

# Install snap packages
echo -e "${YELLOW}Installing snap packages...${NC}"
snap_packages=$(jq -r '.snap.packages[]' packages.json)

if [ -n "$snap_packages" ]; then
    # Check if snapd is installed
    if ! command -v snap &> /dev/null; then
        echo -e "${YELLOW}snapd not found. Installing snapd...${NC}"
        sudo apt install -y snapd
    fi
    
    for package in $snap_packages; do
        echo -e "${GREEN}Installing $package via snap...${NC}"
        sudo snap install "$package"
    done
else
    echo -e "${YELLOW}No snap packages to install${NC}"
fi

echo -e "${GREEN}Package installation completed!${NC}"
