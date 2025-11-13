<#
.SYNOPSIS
    Wrapper script to manage App Gateway redirects using environment configuration.

.DESCRIPTION
    This script reads environment configuration from environments.json and calls
    Set-AppGatewayRedirect.ps1 for the specified environment and routing rules.

.PARAMETER Environment
    The environment name (dev, staging, prod) as defined in environments.json.

.PARAMETER Action
    The action to perform: 'Maintenance' or 'Normal'.

# Note: All routing rules for the environment will be modified automatically.

.PARAMETER ConfigPath
    Path to the environments.json configuration file (default: ..\config\environments.json).

.EXAMPLE
    .\Invoke-AppGatewayRedirect.ps1 -Environment prod -Action Maintenance

.EXAMPLE
    .\Invoke-AppGatewayRedirect.ps1 -Environment dev -Action Normal
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet('Maintenance', 'Normal')]
    [string]$Action,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "..\config\environments.json"
)

$ErrorActionPreference = "Stop"

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configFullPath = Join-Path $scriptDir $ConfigPath

# Load configuration
if (-not (Test-Path $configFullPath)) {
    throw "Configuration file not found: $configFullPath"
}

$config = Get-Content $configFullPath -Raw | ConvertFrom-Json

if (-not $config.environments.$Environment) {
    throw "Environment '$Environment' not found in configuration file. Available environments: $($config.environments.PSObject.Properties.Name -join ', ')"
}

$envConfig = $config.environments.$Environment

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "App Gateway Redirect Management" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Action: $Action" -ForegroundColor Yellow
Write-Host "Resource Group: $($envConfig.resourceGroupName)" -ForegroundColor Yellow
Write-Host "App Gateway: $($envConfig.appGatewayName)" -ForegroundColor Yellow
Write-Host "Routing Rules: $($envConfig.routingRules -join ', ')" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Build parameters for Set-AppGatewayRedirect.ps1
$scriptParams = @{
    ResourceGroupName = $envConfig.resourceGroupName
    AppGatewayName = $envConfig.appGatewayName
    Action = $Action
    SubscriptionId = $envConfig.subscriptionId
    StateFilePath = ".\appgateway-state-$Environment.json"
}

# Add maintenance parameters if switching to maintenance mode
if ($Action -eq "Maintenance") {
    $scriptParams.MaintenanceBackendPoolURL = $envConfig.maintenanceBackendPoolURL
    $scriptParams.MaintenanceBackendPoolPort = $envConfig.maintenanceBackendPoolPort
}

# Add routing rules to process if specified in config
if ($envConfig.routingRulesToProcess -and $envConfig.routingRulesToProcess.Count -gt 0) {
    $scriptParams.RoutingRulesToProcess = $envConfig.routingRulesToProcess
    Write-Host "Routing Rules to Process: $($envConfig.routingRulesToProcess -join ', ')" -ForegroundColor Yellow
}

# Call the main script
$mainScriptPath = Join-Path $scriptDir "Set-AppGatewayRedirect.ps1"

Write-Host "Executing: $mainScriptPath" -ForegroundColor Green
Write-Host ""

& $mainScriptPath @scriptParams

if ($LASTEXITCODE -ne 0) {
    throw "Script execution failed with exit code: $LASTEXITCODE"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Operation completed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

