#!/bin/bash

echo "=================================="
echo "Verifying Local Setup"
echo "=================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0

# Check Python environment
echo -n "Checking Python environment... "
if [ -d "venv" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Virtual environment not found. Run ./scripts/setup/local-setup.sh"
    ERRORS=$((ERRORS + 1))
fi

# Check if venv is activated
echo -n "Checking if venv is activated... "
if [[ "$VIRTUAL_ENV" != "" ]]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC}"
    echo "  Warning: Virtual environment not activated. Run: source venv/bin/activate"
fi

# Check Python packages
echo -n "Checking dbt installation... "
if command -v dbt >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} ($(dbt --version | head -n 1))"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: dbt not installed"
    ERRORS=$((ERRORS + 1))
fi

# Check AWS CLI configuration
echo -n "Checking AWS credentials... "
if aws sts get-caller-identity --profile data-platform-dev >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: AWS credentials not configured or invalid"
    echo "  Run: aws configure --profile data-platform-dev"
    ERRORS=$((ERRORS + 1))
fi

# Check .env.local
echo -n "Checking .env.local... "
if [ -f ".env.local" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: .env.local not found. Copy from .env.example"
    ERRORS=$((ERRORS + 1))
fi

# Check dbt packages
echo -n "Checking dbt packages... "
if [ -d "dbt/dbt_packages" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC}"
    echo "  Warning: dbt packages not installed. Run: cd dbt && dbt deps"
fi

# Check Docker
echo -n "Checking Docker... "
if docker ps >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Docker not running or not accessible"
    ERRORS=$((ERRORS + 1))
fi

# Check pre-commit
echo -n "Checking pre-commit hooks... "
if [ -f ".git/hooks/pre-commit" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC}"
    echo "  Warning: Pre-commit hooks not installed. Run: pre-commit install"
fi

# Check Terraform
echo -n "Checking Terraform... "
if command -v terraform >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} ($(terraform version | head -n 1))"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Terraform not installed"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=================================="

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All checks passed! ✓${NC}"
    echo "You're ready to start development!"
    exit 0
else
    echo -e "${RED}$ERRORS error(s) found ✗${NC}"
    echo "Please fix the errors above before continuing."
    exit 1
fi
