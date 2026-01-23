#!/bin/bash

set -e

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Git Setup${NC}"
echo -e "${YELLOW}========================================${NC}"

# Get existing Git configuration
existing_user_name=$(git config --global user.name 2>/dev/null || echo "")
existing_email=$(git config --global user.email 2>/dev/null || echo "")
existing_branch=$(git config --global init.defaultBranch 2>/dev/null || echo "")
existing_editor=$(git config --global core.editor 2>/dev/null || echo "")

# Prompt for user name
if [ -n "$existing_user_name" ]; then
    read -p "Enter your Git user name (current: $existing_user_name): " git_user_name
    git_user_name=${git_user_name:-$existing_user_name}
else
    read -p "Enter your Git user name: " git_user_name
fi

# Prompt for email address
if [ -n "$existing_email" ]; then
    read -p "Enter your Git email address (current: $existing_email): " git_email
    git_email=${git_email:-$existing_email}
else
    read -p "Enter your Git email address: " git_email
fi

# Prompt for default branch name
default_branch_prompt="main"
if [ -n "$existing_branch" ]; then
    default_branch_prompt="$existing_branch"
fi
read -p "Enter default branch name (default: $default_branch_prompt): " git_default_branch
git_default_branch=${git_default_branch:-$default_branch_prompt}

# Prompt for editor
default_editor_prompt="vim"
if [ -n "$existing_editor" ]; then
    default_editor_prompt="$existing_editor"
fi
read -p "Enter your preferred editor (default: $default_editor_prompt): " git_editor
git_editor=${git_editor:-$default_editor_prompt}

# Set Git global config
echo -e "${YELLOW}Setting up Git configuration...${NC}"
git config --global user.name "$git_user_name"
git config --global user.email "$git_email"
git config --global init.defaultBranch "$git_default_branch"
git config --global core.editor "$git_editor"

# Display configured values
echo -e "${GREEN}Git configuration completed!${NC}"
echo -e "${YELLOW}Current Git configuration:${NC}"
echo "User name:  $(git config --global user.name)"
echo "Email:      $(git config --global user.email)"
echo "Default branch: $(git config --global init.defaultBranch)"
echo "Editor:     $(git config --global core.editor)"
