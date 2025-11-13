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

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configFullPath = Join-Path $scriptDir $ConfigPath

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
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scriptParams = @{
    ResourceGroupName = $envConfig.resourceGroupName
    AppGatewayName = $envConfig.appGatewayName
    Action = $Action
    SubscriptionId = $envConfig.subscriptionId
}

if ($Action -eq "Maintenance") {
    if (-not $envConfig.maintenance) {
        throw "maintenance configuration not found for environment '$Environment'"
    }
    if (-not $envConfig.maintenance.redirectURL) {
        throw "maintenance.redirectURL is required in configuration for environment '$Environment'"
    }
    $scriptParams.MaintenanceRedirectURL = $envConfig.maintenance.redirectURL
    
    $routingRulesConfig = @()
    foreach ($ruleName in $envConfig.maintenance.routingRules) {
        $routingRulesConfig += @{
            ruleName = $ruleName
        }
    }
    $scriptParams.RoutingRulesConfig = $routingRulesConfig
    
    Write-Host "Maintenance Redirect URL: $($envConfig.maintenance.redirectURL)" -ForegroundColor Yellow
    Write-Host "Routing Rules: $($envConfig.maintenance.routingRules -join ', ')" -ForegroundColor Yellow
}

if ($Action -eq "Normal") {
    if (-not $envConfig.normal) {
        throw "normal configuration not found for environment '$Environment'"
    }
    if (-not $envConfig.normal.routingRules) {
        throw "normal.routingRules is required in configuration for environment '$Environment'"
    }
    
    $scriptParams.RoutingRulesConfig = $envConfig.normal.routingRules | ForEach-Object {
        @{
            ruleName = $_.ruleName
            normalBackendPoolName = $_.backendPoolName
            normalBackendSettings = $_.backendSettings
        }
    }
    
    Write-Host "Routing Rules to Restore:" -ForegroundColor Yellow
    foreach ($ruleConfig in $envConfig.normal.routingRules) {
        Write-Host "  - $($ruleConfig.ruleName): Pool=$($ruleConfig.backendPoolName), Settings=$($ruleConfig.backendSettings)" -ForegroundColor Yellow
    }
}

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
