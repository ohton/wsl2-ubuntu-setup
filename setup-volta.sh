#!/bin/bash

set -e

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Volta Setup${NC}"
echo -e "${YELLOW}========================================${NC}"

# Check if Volta is already installed
if command -v volta &> /dev/null; then
    echo -e "${BLUE}Volta is already installed.${NC}"
    volta --version
    read -p "Do you want to reinstall Volta? (y/N): " reinstall
    if [[ ! $reinstall =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Skipping Volta installation.${NC}"
        exit 0
    fi
fi

# Install Volta
echo -e "${BLUE}Installing Volta...${NC}"
curl https://get.volta.sh | bash

# Source Volta environment
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"

# Verify installation
if command -v volta &> /dev/null; then
    echo -e "${GREEN}Volta installed successfully!${NC}"
    volta --version
else
    echo -e "${YELLOW}Volta installation completed, but command not found in PATH.${NC}"
    echo -e "${YELLOW}Please restart your shell or run: source ~/.bashrc${NC}"
    exit 1
fi

# Ask if user wants to install Node.js
echo ""
read -p "Do you want to install Node.js with Volta? (Y/n): " install_node
if [[ ! $install_node =~ ^[Nn]$ ]]; then
    read -p "Enter Node.js version (press Enter for latest LTS): " node_version
    if [ -z "$node_version" ]; then
        echo -e "${BLUE}Installing latest LTS version of Node.js...${NC}"
        volta install node
    else
        echo -e "${BLUE}Installing Node.js version ${node_version}...${NC}"
        volta install node@${node_version}
    fi
    
    # Verify Node.js installation
    if command -v node &> /dev/null; then
        echo -e "${GREEN}Node.js installed successfully!${NC}"
        node --version
        npm --version
    fi
fi

# Ask if user wants to install other tools
echo ""
read -p "Do you want to install yarn with Volta? (y/N): " install_yarn
if [[ $install_yarn =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Installing yarn...${NC}"
    volta install yarn
    yarn --version
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Volta setup completed!${NC}"
echo -e "${YELLOW}Note: You may need to restart your shell or run 'source ~/.bashrc' for changes to take effect.${NC}"
