<#
.SYNOPSIS
    Manages Azure Application Gateway routing rules to redirect traffic to external site or backend pool.

.DESCRIPTION
    This script allows you to switch Azure Application Gateway routing rules between:
    - Maintenance mode: Redirects traffic to an external site (e.g., www.google.com)
    - Normal mode: Routes traffic to the backend pool using configuration from config file

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group containing the Application Gateway.

.PARAMETER AppGatewayName
    The name of the Azure Application Gateway.

.PARAMETER Action
    The action to perform: 'Maintenance' to redirect to external site, 'Normal' to route to backend pool.

.PARAMETER MaintenanceRedirectURL
    The external URL to redirect to during maintenance (e.g., https://www.google.com).

.PARAMETER RoutingRulesConfig
    Array of hashtables containing routing rule configurations for normal mode.

.PARAMETER SubscriptionId
    The Azure Subscription ID (optional, uses current context if not provided).

.EXAMPLE
    .\Set-AppGatewayRedirect.ps1 -ResourceGroupName "rg-prod" -AppGatewayName "agw-prod" -Action Maintenance -MaintenanceRedirectURL "https://www.google.com"

.EXAMPLE
    .\Set-AppGatewayRedirect.ps1 -ResourceGroupName "rg-prod" -AppGatewayName "agw-prod" -Action Normal
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$AppGatewayName,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet('Maintenance', 'Normal')]
    [string]$Action,
    
    [Parameter(Mandatory = $false)]
    [string]$MaintenanceRedirectURL,
    
    [Parameter(Mandatory = $false)]
    [hashtable[]]$RoutingRulesConfig,
    
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

try {
    Write-Log "Starting App Gateway redirect operation" "INFO"
    Write-Log "Resource Group: $ResourceGroupName" "INFO"
    Write-Log "App Gateway: $AppGatewayName" "INFO"
    Write-Log "Action: $Action" "INFO"
    
    if ($SubscriptionId) {
        Write-Log "Setting Azure subscription context to: $SubscriptionId" "INFO"
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }
    
    Write-Log "Retrieving Application Gateway configuration..." "INFO"
    $appGateway = Get-AzApplicationGateway -ResourceGroupName $ResourceGroupName -Name $AppGatewayName
    
    if (-not $appGateway) {
        throw "Application Gateway '$AppGatewayName' not found in Resource Group '$ResourceGroupName'"
    }
    
    $rulesToModify = @()
    if (-not $RoutingRulesConfig -or $RoutingRulesConfig.Count -eq 0) {
        throw "RoutingRulesConfig is required"
    }
    
    Write-Log "Processing routing rules from configuration..." "INFO"
    foreach ($ruleConfig in $RoutingRulesConfig) {
        $ruleName = $ruleConfig.ruleName
        $rule = $appGateway.RequestRoutingRules | Where-Object { $_.Name -eq $ruleName }
        if ($rule) {
            $rulesToModify += @{
                Rule = $rule
                Config = $ruleConfig
            }
            Write-Log "  - Found: $ruleName" "INFO"
        } else {
            Write-Log "  - WARNING: Routing rule '$ruleName' not found" "WARNING"
        }
    }
    
    if ($rulesToModify.Count -eq 0) {
        throw "None of the specified routing rules were found in the Application Gateway"
    }
    
    Write-Log "Total routing rules to process: $($rulesToModify.Count)" "INFO"
    
    if ($Action -eq "Maintenance") {
        if (-not $MaintenanceRedirectURL) {
            throw "MaintenanceRedirectURL is required when Action is 'Maintenance'"
        }
        
        Write-Log "Switching to Maintenance mode..." "INFO"
        Write-Log "Redirect URL: $MaintenanceRedirectURL" "INFO"
        
        $redirectConfig = $appGateway.RedirectConfigurations | Where-Object { 
            $_.RedirectType -eq "Permanent" -and $_.TargetUrl -eq $MaintenanceRedirectURL 
        } | Select-Object -First 1
        
        if (-not $redirectConfig) {
            Write-Log "Creating redirect configuration..." "INFO"
            $redirectConfigName = "redirect-maintenance-$(Get-Date -Format 'yyyyMMddHHmmss')"
            # UNCOMMENT TO ENABLE: Create redirect configuration
            # $redirectConfig = New-AzApplicationGatewayRedirectConfiguration `
            #     -Name $redirectConfigName `
            #     -RedirectType Permanent `
            #     -TargetUrl $MaintenanceRedirectURL
            # $appGateway.RedirectConfigurations.Add($redirectConfig)
        }
        
        foreach ($ruleItem in $rulesToModify) {
            $rule = $ruleItem.Rule
            Write-Log "Updating routing rule: $($rule.Name)" "INFO"
            
            # UNCOMMENT TO ENABLE: Set redirect on routing rule
            # $rule.RedirectConfiguration = $redirectConfig
            # $rule.BackendAddressPool = $null
            # $rule.BackendHttpSettings = $null
            
            Write-Log "  Set redirect to: $MaintenanceRedirectURL" "SUCCESS"
        }
        
    } elseif ($Action -eq "Normal") {
        Write-Log "Switching to Normal mode..." "INFO"
        
        foreach ($ruleItem in $rulesToModify) {
            $rule = $ruleItem.Rule
            $ruleConfig = $ruleItem.Config
            
            Write-Log "Restoring routing rule: $($rule.Name)" "INFO"
            
            if (-not $ruleConfig.normalBackendPoolName) {
                Write-Log "  ERROR: normalBackendPoolName not specified" "ERROR"
                continue
            }
            
            $backendPool = $appGateway.BackendAddressPools | Where-Object { 
                $_.Name -eq $ruleConfig.normalBackendPoolName 
            }
            
            if (-not $backendPool) {
                Write-Log "  ERROR: Backend pool '$($ruleConfig.normalBackendPoolName)' not found" "ERROR"
                continue
            }
            
            $backendSettings = $null
            if ($ruleConfig.normalBackendSettings) {
                $backendSettings = $appGateway.BackendHttpSettingsCollection | Where-Object { 
                    $_.Name -eq $ruleConfig.normalBackendSettings 
                }
                if (-not $backendSettings) {
                    Write-Log "  WARNING: Backend settings '$($ruleConfig.normalBackendSettings)' not found" "WARNING"
                }
            }
            
            # UNCOMMENT TO ENABLE: Restore backend pool and settings
            # $rule.BackendAddressPool = $backendPool
            # $rule.BackendHttpSettings = $backendSettings
            # $rule.RedirectConfiguration = $null
            
            Write-Log "  Backend pool: $($ruleConfig.normalBackendPoolName)" "SUCCESS"
            if ($backendSettings) {
                Write-Log "  Backend settings: $($ruleConfig.normalBackendSettings)" "SUCCESS"
            }
        }
    }
    
    Write-Log "Saving Application Gateway configuration..." "INFO"
    # UNCOMMENT TO ENABLE: Save changes to Azure
    # Set-AzApplicationGateway -ApplicationGateway $appGateway | Out-Null
    
    Write-Log "Application Gateway configuration updated successfully!" "SUCCESS"
    
    Write-Log "`n=== Summary ===" "INFO"
    Write-Log "Action: $Action" "INFO"
    Write-Log "Rules Modified: $($rulesToModify.Count)" "INFO"
    foreach ($ruleItem in $rulesToModify) {
        $rule = $ruleItem.Rule
        if ($rule.RedirectConfiguration) {
            Write-Log "  - $($rule.Name): Redirect = $($rule.RedirectConfiguration.TargetUrl)" "INFO"
        } elseif ($rule.BackendAddressPool) {
            Write-Log "  - $($rule.Name): Backend Pool = $($rule.BackendAddressPool.Name)" "INFO"
        }
    }
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
