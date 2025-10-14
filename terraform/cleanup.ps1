# PowerShell script for cleaning up the Terraform deployment
# Run this to destroy all resources when you're done with the lab

param(
    [switch]$Force,
    [switch]$KeepResourceGroup
)

Write-Host "🧹 Kubernetes the Hard Way - Infrastructure Cleanup" -ForegroundColor Red
Write-Host "====================================================" -ForegroundColor Red

if (-not $Force) {
    Write-Host ""
    Write-Host "⚠️  WARNING: This will destroy ALL infrastructure resources!" -ForegroundColor Yellow
    Write-Host "This includes:" -ForegroundColor Yellow
    Write-Host "  • All Virtual Machines" -ForegroundColor Yellow
    Write-Host "  • Virtual Network and subnets" -ForegroundColor Yellow
    Write-Host "  • Azure Bastion" -ForegroundColor Yellow
    Write-Host "  • NAT Gateway" -ForegroundColor Yellow
    Write-Host "  • All data on the VMs" -ForegroundColor Yellow
    Write-Host ""
    
    $confirm = Read-Host "Are you absolutely sure you want to continue? Type 'DELETE' to confirm"
    if ($confirm -ne "DELETE") {
        Write-Host "❌ Cleanup cancelled" -ForegroundColor Green
        exit 0
    }
}

# Check if Terraform is initialized
if (-not (Test-Path ".terraform")) {
    Write-Host "❌ Terraform not initialized in this directory" -ForegroundColor Red
    Write-Host "Please run this script from the terraform directory" -ForegroundColor Yellow
    exit 1
}

# Show what will be destroyed
Write-Host "🔍 Showing resources that will be destroyed..." -ForegroundColor Yellow
terraform plan -destroy

if (-not $Force) {
    $finalConfirm = Read-Host "Proceed with destruction? (y/N)"
    if ($finalConfirm -ne "y" -and $finalConfirm -ne "Y") {
        Write-Host "❌ Cleanup cancelled" -ForegroundColor Green
        exit 0
    }
}

# Destroy infrastructure
Write-Host "💥 Destroying infrastructure..." -ForegroundColor Red
Write-Host "This may take several minutes..." -ForegroundColor Cyan

if ($Force) {
    terraform destroy -auto-approve
} else {
    terraform destroy
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Terraform destroy failed"
    Write-Host "You may need to manually clean up some resources in the Azure portal" -ForegroundColor Yellow
    exit 1
}

# Clean up local files
Write-Host "🧹 Cleaning up local files..." -ForegroundColor Yellow

# Remove terraform state files
if (Test-Path "terraform.tfstate") {
    Remove-Item "terraform.tfstate" -Force
    Write-Host "✅ Removed terraform.tfstate" -ForegroundColor Green
}

if (Test-Path "terraform.tfstate.backup") {
    Remove-Item "terraform.tfstate.backup" -Force
    Write-Host "✅ Removed terraform.tfstate.backup" -ForegroundColor Green
}

if (Test-Path "tfplan") {
    Remove-Item "tfplan" -Force
    Write-Host "✅ Removed tfplan" -ForegroundColor Green
}

# Remove SSH keys if generated
if (Test-Path "ssh-keys") {
    $removeSshKeys = Read-Host "Remove generated SSH keys? (y/N)"
    if ($removeSshKeys -eq "y" -or $removeSshKeys -eq "Y") {
        Remove-Item "ssh-keys" -Recurse -Force
        Write-Host "✅ Removed SSH keys" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "🎉 Cleanup completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "💰 Cost Savings:" -ForegroundColor Cyan
Write-Host "All Azure resources have been destroyed and will no longer incur charges." -ForegroundColor White
Write-Host ""
Write-Host "📝 Note:" -ForegroundColor Yellow
Write-Host "• terraform.tfvars has been preserved for future deployments" -ForegroundColor White
Write-Host "• You can redeploy anytime using the deploy script" -ForegroundColor White

if (-not $KeepResourceGroup) {
    Write-Host ""
    Write-Host "💡 Tip: Check the Azure portal to ensure the resource group was completely removed" -ForegroundColor Cyan
}