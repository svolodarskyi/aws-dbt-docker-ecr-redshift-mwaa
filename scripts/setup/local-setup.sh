#!/bin/bash
set -e

echo "=================================="
echo "AWS Data Platform - Local Setup"
echo "=================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "Checking prerequisites..."

command -v python3 >/dev/null 2>&1 || { echo -e "${RED}Error: Python 3 is not installed${NC}" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Error: Docker is not installed${NC}" >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo -e "${RED}Error: Terraform is not installed${NC}" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}Error: AWS CLI is not installed${NC}" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo -e "${RED}Error: Git is not installed${NC}" >&2; exit 1; }

echo -e "${GREEN}✓ All prerequisites installed${NC}"
echo ""

# Create virtual environment
echo "Creating Python virtual environment..."
if [ -d "venv" ]; then
    echo -e "${YELLOW}Virtual environment already exists, skipping...${NC}"
else
    python3 -m venv venv
    echo -e "${GREEN}✓ Virtual environment created${NC}"
fi

# Activate virtual environment
echo "Activating virtual environment..."
source venv/bin/activate
echo -e "${GREEN}✓ Virtual environment activated${NC}"
echo ""

# Install Python dependencies
echo "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements-dev.txt
echo -e "${GREEN}✓ Python dependencies installed${NC}"
echo ""

# Setup pre-commit hooks
echo "Setting up pre-commit hooks..."
pre-commit install
echo -e "${GREEN}✓ Pre-commit hooks installed${NC}"
echo ""

# Create .env.local from template
echo "Creating .env.local from template..."
if [ -f ".env.local" ]; then
    echo -e "${YELLOW}.env.local already exists, skipping...${NC}"
else
    cp .env.example .env.local
    echo -e "${GREEN}✓ .env.local created${NC}"
    echo -e "${YELLOW}⚠️  Please edit .env.local with your actual values${NC}"
fi
echo ""

# Initialize dbt
echo "Initializing dbt project..."
cd dbt
if [ -d "dbt_packages" ]; then
    echo -e "${YELLOW}dbt packages already installed, skipping...${NC}"
else
    dbt deps
    echo -e "${GREEN}✓ dbt packages installed${NC}"
fi
cd ..
echo ""

# Create necessary directories
echo "Creating project directories..."
mkdir -p logs
mkdir -p data/raw
mkdir -p data/processed
echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# Summary
echo "=================================="
echo "Setup Complete! 🎉"
echo "=================================="
echo ""
echo "Next steps:"
echo "1. Edit .env.local with your AWS credentials and configuration"
echo "2. Configure AWS CLI: aws configure --profile data-platform-dev"
echo "3. Initialize Terraform: cd terraform/environments/dev && terraform init"
echo "4. Read the documentation: docs/QUICKSTART.md"
echo ""
echo "To activate the virtual environment in the future, run:"
echo "  source venv/bin/activate"
echo ""
echo -e "${GREEN}Happy coding!${NC}"
