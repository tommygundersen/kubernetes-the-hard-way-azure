#!/bin/bash
# Quick deployment script for Linux/macOS users
# Run this script to deploy the entire infrastructure with minimal interaction

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Default values
LOCATION="SwedenCentral"
STUDENT_NAME=""
VM_SIZE="Standard_B2s"
SKIP_PLAN=false
AUTO_APPROVE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -s|--student-name)
            STUDENT_NAME="$2"
            shift 2
            ;;
        -v|--vm-size)
            VM_SIZE="$2"
            shift 2
            ;;
        --skip-plan)
            SKIP_PLAN=true
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -l, --location       Azure region (default: West Europe)"
            echo "  -s, --student-name   Student name for tagging"
            echo "  -v, --vm-size        VM size (default: Standard_B2s)"
            echo "  --skip-plan          Skip terraform plan step"
            echo "  --auto-approve       Auto-approve deployment"
            echo "  -h, --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${CYAN}🚀 Kubernetes the Hard Way - Azure Infrastructure Deployment${NC}"
echo -e "${CYAN}================================================================${NC}"

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"

# Check if Terraform is installed
if command -v terraform >/dev/null 2>&1; then
    TERRAFORM_VERSION=$(terraform version | head -n1)
    echo -e "${GREEN}✅ Terraform found: $TERRAFORM_VERSION${NC}"
else
    echo -e "${RED}❌ Terraform not found. Please install Terraform from https://www.terraform.io/downloads.html${NC}"
    exit 1
fi

# Check if Azure CLI is installed
if command -v az >/dev/null 2>&1; then
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null)
    echo -e "${GREEN}✅ Azure CLI found: $AZ_VERSION${NC}"
else
    echo -e "${RED}❌ Azure CLI not found. Please install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli${NC}"
    exit 1
fi

# Check if logged into Azure
ACCOUNT=$(az account show --query "name" -o tsv 2>/dev/null || echo "")
if [ -n "$ACCOUNT" ]; then
    echo -e "${GREEN}✅ Logged into Azure: $ACCOUNT${NC}"
else
    echo -e "${RED}❌ Not logged into Azure. Running 'az login'...${NC}"
    az login
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to login to Azure${NC}"
        exit 1
    fi
fi

# Create terraform.tfvars if it doesn't exist
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${YELLOW}📝 Creating terraform.tfvars...${NC}"
    
    cat > terraform.tfvars << EOF
# Terraform variables for Kubernetes the Hard Way
location = "$LOCATION"
vm_size = "$VM_SIZE"
admin_username = "azureuser"
environment = "lab"
auto_shutdown_enabled = true
auto_shutdown_time = "1900"
auto_shutdown_timezone = "UTC"
enable_accelerated_networking = false
kubernetes_version = "1.28.0"
EOF

    if [ -n "$STUDENT_NAME" ]; then
        echo "student_name = \"$STUDENT_NAME\"" >> terraform.tfvars
    fi

    echo -e "${GREEN}✅ terraform.tfvars created${NC}"
else
    echo -e "${GREEN}✅ terraform.tfvars already exists${NC}"
fi

# Initialize Terraform
echo -e "${YELLOW}🔧 Initializing Terraform...${NC}"
terraform init
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Terraform initialization failed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Terraform initialized${NC}"

# Validate configuration
echo -e "${YELLOW}🔍 Validating configuration...${NC}"
terraform validate
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Terraform validation failed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Configuration valid${NC}"

# Plan deployment
if [ "$SKIP_PLAN" = false ]; then
    echo -e "${YELLOW}📋 Planning deployment...${NC}"
    terraform plan -out=tfplan
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Terraform planning failed${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Plan completed${NC}"
    
    if [ "$AUTO_APPROVE" = false ]; then
        read -p "Do you want to proceed with the deployment? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo -e "${RED}❌ Deployment cancelled${NC}"
            exit 0
        fi
    fi
fi

# Apply deployment
echo -e "${YELLOW}🚀 Deploying infrastructure...${NC}"
echo -e "${CYAN}This will take approximately 5-10 minutes...${NC}"

if [ "$SKIP_PLAN" = true ]; then
    if [ "$AUTO_APPROVE" = true ]; then
        terraform apply -auto-approve
    else
        terraform apply
    fi
else
    terraform apply tfplan
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Terraform deployment failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 Infrastructure deployment completed successfully!${NC}"
echo ""

# Display outputs
echo -e "${CYAN}📊 Deployment Information:${NC}"
echo -e "${CYAN}=========================${NC}"
terraform output

echo ""
echo -e "${YELLOW}🔗 Next Steps:${NC}"
echo -e "${WHITE}1. Go to the Azure Portal${NC}"
echo -e "${WHITE}2. Navigate to your jumpbox VM${NC}"
echo -e "${WHITE}3. Connect using Azure Bastion${NC}"
echo -e "${WHITE}4. Clone the repository on the jumpbox${NC}"
echo -e "${WHITE}5. Follow the documentation starting with docs/01-prerequisites.md${NC}"

echo ""
echo -e "${CYAN}💡 Pro Tips:${NC}"
echo -e "${WHITE}• Use 'terraform output vm_information' to see VM details${NC}"
echo -e "${WHITE}• VMs will auto-shutdown at 7 PM UTC to save costs${NC}"
echo -e "${WHITE}• SSH keys are available in ./ssh-keys/ directory${NC}"

echo ""
echo -e "${GREEN}Happy learning! 🎓${NC}"