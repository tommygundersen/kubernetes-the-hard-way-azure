# Terraform deployment scripts for Windows users

# Quick deployment script for Windows PowerShell
# Run this script to deploy the entire infrastructure with minimal interaction

param(
    [string]$Location = "SwedenCentral",
    [string]$StudentName = "",
    [string]$VmSize = "Standard_B2s",
    [switch]$SkipPlan,
    [switch]$AutoApprove
)

Write-Host "🚀 Kubernetes the Hard Way - Azure Infrastructure Deployment" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# Check prerequisites
Write-Host "📋 Checking prerequisites..." -ForegroundColor Yellow

# Check if Terraform is installed
try {
    $terraformVersion = terraform version
    Write-Host "✅ Terraform found: $($terraformVersion.Split("`n")[0])" -ForegroundColor Green
} catch {
    Write-Error "❌ Terraform not found. Please install Terraform from https://www.terraform.io/downloads.html"
    exit 1
}

# Check if Azure CLI is installed
try {
    $azVersion = az version --query '"azure-cli"' -o tsv
    Write-Host "✅ Azure CLI found: $azVersion" -ForegroundColor Green
} catch {
    Write-Error "❌ Azure CLI not found. Please install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
}

# Check if logged into Azure
try {
    $account = az account show --query "name" -o tsv 2>$null
    if ($account) {
        Write-Host "✅ Logged into Azure: $account" -ForegroundColor Green
    } else {
        throw "Not logged in"
    }
} catch {
    Write-Host "❌ Not logged into Azure. Running 'az login'..." -ForegroundColor Red
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to login to Azure"
        exit 1
    }
}

# Create terraform.tfvars if it doesn't exist
if (-not (Test-Path "terraform.tfvars")) {
    Write-Host "📝 Creating terraform.tfvars..." -ForegroundColor Yellow
    
    $tfvarsContent = @"
# Terraform variables for Kubernetes the Hard Way
location = "$Location"
vm_size = "$VmSize"
admin_username = "azureuser"
environment = "lab"
auto_shutdown_enabled = true
auto_shutdown_time = "1900"
auto_shutdown_timezone = "UTC"
enable_accelerated_networking = false
kubernetes_version = "1.28.0"
"@

    if ($StudentName) {
        $tfvarsContent += "`nstudent_name = `"$StudentName`""
    }

    $tfvarsContent | Out-File -FilePath "terraform.tfvars" -Encoding UTF8
    Write-Host "✅ terraform.tfvars created" -ForegroundColor Green
} else {
    Write-Host "✅ terraform.tfvars already exists" -ForegroundColor Green
}

# Initialize Terraform
Write-Host "🔧 Initializing Terraform..." -ForegroundColor Yellow
terraform init
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Terraform initialization failed"
    exit 1
}
Write-Host "✅ Terraform initialized" -ForegroundColor Green

# Validate configuration
Write-Host "🔍 Validating configuration..." -ForegroundColor Yellow
terraform validate
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Terraform validation failed"
    exit 1
}
Write-Host "✅ Configuration valid" -ForegroundColor Green

# Plan deployment
if (-not $SkipPlan) {
    Write-Host "📋 Planning deployment..." -ForegroundColor Yellow
    terraform plan -out=tfplan
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Terraform planning failed"
        exit 1
    }
    Write-Host "✅ Plan completed" -ForegroundColor Green
    
    if (-not $AutoApprove) {
        $confirm = Read-Host "Do you want to proceed with the deployment? (y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "❌ Deployment cancelled" -ForegroundColor Red
            exit 0
        }
    }
}

# Apply deployment
Write-Host "🚀 Deploying infrastructure..." -ForegroundColor Yellow
Write-Host "This will take approximately 5-10 minutes..." -ForegroundColor Cyan

if ($SkipPlan) {
    if ($AutoApprove) {
        terraform apply -auto-approve
    } else {
        terraform apply
    }
} else {
    terraform apply tfplan
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Terraform deployment failed"
    exit 1
}

Write-Host ""
Write-Host "🎉 Infrastructure deployment completed successfully!" -ForegroundColor Green
Write-Host ""

# Display outputs
Write-Host "📊 Deployment Information:" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan
terraform output

Write-Host ""
Write-Host "🔗 Next Steps:" -ForegroundColor Yellow
Write-Host "1. Go to the Azure Portal" -ForegroundColor White
Write-Host "2. Navigate to your jumpbox VM" -ForegroundColor White
Write-Host "3. Connect using Azure Bastion" -ForegroundColor White
Write-Host "4. Clone the repository on the jumpbox" -ForegroundColor White
Write-Host "5. Follow the documentation starting with docs/01-prerequisites.md" -ForegroundColor White

Write-Host ""
Write-Host "💡 Pro Tips:" -ForegroundColor Cyan
Write-Host "• Use 'terraform output vm_information' to see VM details" -ForegroundColor White
Write-Host "• VMs will auto-shutdown at 7 PM UTC to save costs" -ForegroundColor White
Write-Host "• SSH keys are available in ./ssh-keys/ directory" -ForegroundColor White

Write-Host ""
Write-Host "Happy learning! 🎓" -ForegroundColor Green