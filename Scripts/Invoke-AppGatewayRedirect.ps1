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

.PARAMETER SubEnvironment
    Sub-environment name (e.g., dev002, test002, prod002). Required.

.PARAMETER MaintenanceRedirectURL
    Maintenance redirect URL (required when Action is 'Maintenance'). Default: https://www.google.com

.PARAMETER ConfigPath
    Path to the environments.json configuration file (default: ..\config\environments.json).

.EXAMPLE
    .\Invoke-AppGatewayRedirect.ps1 -Environment prod -Action Maintenance -SubEnvironment prod -MaintenanceRedirectURL 'https://www.google.com'

.EXAMPLE
    .\Invoke-AppGatewayRedirect.ps1 -Environment dev -Action Normal -SubEnvironment dev002
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet('Maintenance', 'Normal')]
    [string]$Action,
    
    [Parameter(Mandatory = $true)]
    [string]$SubEnvironment,
    
    [Parameter(Mandatory = $false)]
    [string]$MaintenanceRedirectURL = 'https://www.google.com',
    
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
if ($SubEnvironment) {
    Write-Host "Sub-Environment: $SubEnvironment" -ForegroundColor Yellow
}
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

# Check if subEnvironments structure exists
if ($envConfig.subEnvironments) {
    # New structure with sub-environments
    if (-not $envConfig.subEnvironments.$SubEnvironment) {
        $availableSubEnvs = $envConfig.subEnvironments.PSObject.Properties.Name -join ', '
        throw "Sub-environment '$SubEnvironment' not found for environment '$Environment'. Available: $availableSubEnvs"
    }
    $subEnvConfig = $envConfig.subEnvironments.$SubEnvironment
    
    if ($Action -eq "Maintenance") {
        if (-not $subEnvConfig.maintenance) {
            throw "maintenance configuration not found for sub-environment '$SubEnvironment'"
        }
        if (-not $subEnvConfig.maintenance.routingRules) {
            throw "maintenance.routingRules is required for sub-environment '$SubEnvironment'"
        }
        
        # Use redirect URL from parameter, not from config
        $scriptParams.MaintenanceRedirectURL = $MaintenanceRedirectURL
        
        $routingRulesConfig = @()
        foreach ($ruleName in $subEnvConfig.maintenance.routingRules) {
            $routingRulesConfig += @{
                ruleName = $ruleName
            }
        }
        $scriptParams.RoutingRulesConfig = $routingRulesConfig
        
        Write-Host "Sub-Environment: $SubEnvironment" -ForegroundColor Yellow
        Write-Host "Maintenance Redirect URL: $MaintenanceRedirectURL" -ForegroundColor Yellow
        Write-Host "Routing Rules: $($subEnvConfig.maintenance.routingRules -join ', ')" -ForegroundColor Yellow
    }
    
    if ($Action -eq "Normal") {
        if (-not $subEnvConfig.normal) {
            throw "normal configuration not found for sub-environment '$SubEnvironment'"
        }
        if (-not $subEnvConfig.normal.routingRules) {
            throw "normal.routingRules is required for sub-environment '$SubEnvironment'"
        }
        
        $scriptParams.RoutingRulesConfig = $subEnvConfig.normal.routingRules | ForEach-Object {
            @{
                ruleName = $_.ruleName
                normalBackendPoolName = $_.backendPoolName
                normalBackendSettings = $_.backendSettings
            }
        }
        
        Write-Host "Sub-Environment: $SubEnvironment" -ForegroundColor Yellow
        Write-Host "Routing Rules to Restore:" -ForegroundColor Yellow
        foreach ($ruleConfig in $subEnvConfig.normal.routingRules) {
            Write-Host "  - $($ruleConfig.ruleName): Pool=$($ruleConfig.backendPoolName), Settings=$($ruleConfig.backendSettings)" -ForegroundColor Yellow
        }
    }
} else {
    # Legacy structure (backward compatibility)
    throw "Environment '$Environment' does not use sub-environments structure. Sub-environment is required."
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
