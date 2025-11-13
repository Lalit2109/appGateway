<#
.SYNOPSIS
    Manages Azure Application Gateway routing rules to redirect traffic to maintenance page or backend pool.

.DESCRIPTION
    This script allows you to switch Azure Application Gateway routing rules between:
    - Maintenance mode: Redirects traffic to a static maintenance page
    - Normal mode: Routes traffic to the backend pool (restores original configuration)

.PARAMETER ResourceGroupName
    The name of the Azure Resource Group containing the Application Gateway.

.PARAMETER AppGatewayName
    The name of the Azure Application Gateway.

.PARAMETER Action
    The action to perform: 'Maintenance' to redirect to maintenance page, 'Normal' to route to backend pool.

.PARAMETER RoutingRulesToProcess
    Array of routing rule names to process. If not specified, all routing rules will be processed.

.PARAMETER MaintenanceBackendPoolName
    The name of the backend pool containing the maintenance page (optional, will be created if needed).

.PARAMETER MaintenanceBackendPoolURL
    The HTTPS URL (FQDN) of the maintenance page server (e.g., https://maintenance.example.com).

.PARAMETER MaintenanceBackendPoolPort
    The port number for the maintenance page (default: 443 for HTTPS).

.PARAMETER SubscriptionId
    The Azure Subscription ID (optional, uses current context if not provided).

.PARAMETER StateFilePath
    Path to JSON file to store state information (default: .\appgateway-state.json).

.EXAMPLE
    .\Set-AppGatewayRedirect.ps1 -ResourceGroupName "rg-prod" -AppGatewayName "agw-prod" -Action Maintenance -MaintenanceBackendPoolURL "https://maintenance.example.com"

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
    [string]$MaintenanceBackendPoolName = "maintenance-backend-pool",
    
    [Parameter(Mandatory = $false)]
    [string]$MaintenanceBackendPoolURL,
    
    [Parameter(Mandatory = $false)]
    [int]$MaintenanceBackendPoolPort = 443,
    
    [Parameter(Mandatory = $false)]
    [string[]]$RoutingRulesToProcess,
    
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $false)]
    [string]$StateFilePath = ".\appgateway-state.json"
)

# Error handling
$ErrorActionPreference = "Stop"

# Function to write log messages
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

# Function to load state
function Get-State {
    param([string]$FilePath)
    
    if (Test-Path $FilePath) {
        try {
            $content = Get-Content $FilePath -Raw | ConvertFrom-Json
            return $content
        } catch {
            Write-Log "Warning: Could not load state file. Starting fresh." "WARNING"
            return $null
        }
    }
    return $null
}

# Function to save state
function Save-State {
    param(
        [string]$FilePath,
        [object]$State
    )
    
    try {
        $State | ConvertTo-Json -Depth 10 | Set-Content $FilePath
        Write-Log "State saved to: $FilePath" "INFO"
    } catch {
        Write-Log "Warning: Could not save state file: $($_.Exception.Message)" "WARNING"
    }
}

try {
    Write-Log "Starting App Gateway redirect operation" "INFO"
    Write-Log "Resource Group: $ResourceGroupName" "INFO"
    Write-Log "App Gateway: $AppGatewayName" "INFO"
    Write-Log "Action: $Action" "INFO"
    
    # Set subscription if provided
    if ($SubscriptionId) {
        Write-Log "Setting Azure subscription context to: $SubscriptionId" "INFO"
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }
    
    # Get the Application Gateway
    Write-Log "Retrieving Application Gateway configuration..." "INFO"
    $appGateway = Get-AzApplicationGateway -ResourceGroupName $ResourceGroupName -Name $AppGatewayName
    
    if (-not $appGateway) {
        throw "Application Gateway '$AppGatewayName' not found in Resource Group '$ResourceGroupName'"
    }
    
    # Load existing state
    $state = Get-State -FilePath $StateFilePath
    if (-not $state) {
        $state = @{
            AppGateways = @{}
        }
    }
    
    $gatewayKey = "$ResourceGroupName/$AppGatewayName"
    if (-not $state.AppGateways.$gatewayKey) {
        $state.AppGateways.$gatewayKey = @{
            Rules = @{}
        }
    }
    
    # Get routing rules to modify
    $rulesToModify = @()
    if ($RoutingRulesToProcess -and $RoutingRulesToProcess.Count -gt 0) {
        Write-Log "Processing specified routing rules: $($RoutingRulesToProcess -join ', ')" "INFO"
        foreach ($ruleName in $RoutingRulesToProcess) {
            $rule = $appGateway.RequestRoutingRules | Where-Object { $_.Name -eq $ruleName }
            if ($rule) {
                $rulesToModify += $rule
                Write-Log "  - Found: $ruleName" "INFO"
            } else {
                Write-Log "  - WARNING: Routing rule '$ruleName' not found in Application Gateway" "WARNING"
            }
        }
        if ($rulesToModify.Count -eq 0) {
            throw "None of the specified routing rules were found in the Application Gateway"
        }
    } else {
        Write-Log "No specific routing rules provided, processing all routing rules" "INFO"
        $rulesToModify = $appGateway.RequestRoutingRules
    }
    
    Write-Log "Total routing rules to process: $($rulesToModify.Count)" "INFO"
    foreach ($rule in $rulesToModify) {
        Write-Log "  - $($rule.Name)" "INFO"
    }
    
    # Handle Maintenance mode
    if ($Action -eq "Maintenance") {
        if (-not $MaintenanceBackendPoolURL) {
            throw "MaintenanceBackendPoolURL is required when Action is 'Maintenance'"
        }
        
        Write-Log "Switching to Maintenance mode..." "INFO"
        
        # Parse URL to extract FQDN
        $maintenanceFQDN = $MaintenanceBackendPoolURL
        if ($MaintenanceBackendPoolURL -match '^https?://(.+)$') {
            $maintenanceFQDN = $matches[1]
            # Remove port if present
            if ($maintenanceFQDN -match '^(.+):\d+$') {
                $maintenanceFQDN = $matches[1]
            }
        }
        
        Write-Log "Maintenance FQDN: $maintenanceFQDN" "INFO"
        Write-Log "Maintenance Port: $MaintenanceBackendPoolPort" "INFO"
        
        # Check if maintenance backend pool exists, create if not
        $maintenancePool = $appGateway.BackendAddressPools | Where-Object { $_.Name -eq $MaintenanceBackendPoolName }
        
        if (-not $maintenancePool) {
            Write-Log "Creating maintenance backend pool: $MaintenanceBackendPoolName" "INFO"
            $maintenancePool = New-AzApplicationGatewayBackendAddressPool `
                -Name $MaintenanceBackendPoolName `
                -BackendIPAddresses @() `
                -BackendFqdns @($maintenanceFQDN) `
                -BackendPort $MaintenanceBackendPoolPort
        } else {
            Write-Log "Updating existing maintenance backend pool: $MaintenanceBackendPoolName" "INFO"
            # Update the existing pool with FQDN
            $maintenancePool.BackendAddresses = @(
                @{
                    IpAddress = $null
                    Fqdn = $maintenanceFQDN
                }
            )
        }
        
        # Update each routing rule to use maintenance backend pool
        foreach ($rule in $rulesToModify) {
            Write-Log "Updating routing rule: $($rule.Name)" "INFO"
            
            # Store original backend pool information in state
            if ($rule.BackendAddressPool) {
                $originalPoolId = $rule.BackendAddressPool.Id
                $originalPoolName = $rule.BackendAddressPool.Name
                
                # Only save if not already in maintenance mode
                if ($originalPoolName -ne $MaintenanceBackendPoolName) {
                    $state.AppGateways.$gatewayKey.Rules[$rule.Name] = @{
                        OriginalBackendPoolId = $originalPoolId
                        OriginalBackendPoolName = $originalPoolName
                        LastMaintenanceSwitch = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    }
                    Write-Log "  Saved original backend pool: $originalPoolName" "INFO"
                }
            }
            
            # Set backend pool to maintenance pool
            $rule.BackendAddressPool = $maintenancePool
            Write-Log "  Set backend pool to: $MaintenanceBackendPoolName" "SUCCESS"
        }
        
        # Add maintenance pool to gateway if it's new
        if ($maintenancePool.Id -notin $appGateway.BackendAddressPools.Id) {
            $appGateway.BackendAddressPools.Add($maintenancePool)
        }
        
    } elseif ($Action -eq "Normal") {
        Write-Log "Switching to Normal mode (restoring original backend pools)..." "INFO"
        
        # Restore original backend pools from state
        $restoredCount = 0
        foreach ($rule in $rulesToModify) {
            $ruleState = $state.AppGateways.$gatewayKey.Rules[$rule.Name]
            
            if ($ruleState -and $ruleState.OriginalBackendPoolName) {
                Write-Log "Restoring routing rule: $($rule.Name)" "INFO"
                
                # Find the original backend pool
                $originalPool = $appGateway.BackendAddressPools | Where-Object { 
                    $_.Name -eq $ruleState.OriginalBackendPoolName 
                }
                
                if ($originalPool) {
                    $rule.BackendAddressPool = $originalPool
                    Write-Log "  Restored backend pool to: $($ruleState.OriginalBackendPoolName)" "SUCCESS"
                    $restoredCount++
                } else {
                    Write-Log "  WARNING: Original backend pool '$($ruleState.OriginalBackendPoolName)' not found. Skipping." "WARNING"
                }
            } else {
                Write-Log "  WARNING: No saved state found for rule '$($rule.Name)'. Cannot restore." "WARNING"
                Write-Log "  You may need to manually configure this rule in Azure Portal." "WARNING"
            }
        }
        
        if ($restoredCount -eq 0) {
            Write-Log "WARNING: No rules were restored. Please verify state file or manually configure routing rules." "WARNING"
        }
    }
    
    # Save state
    Save-State -FilePath $StateFilePath -State $state
    
    # Save the Application Gateway configuration
    Write-Log "Saving Application Gateway configuration..." "INFO"
    Set-AzApplicationGateway -ApplicationGateway $appGateway | Out-Null
    
    Write-Log "Application Gateway configuration updated successfully!" "SUCCESS"
    
    # Output summary
    Write-Log "`n=== Summary ===" "INFO"
    Write-Log "Action: $Action" "INFO"
    Write-Log "Rules Modified: $($rulesToModify.Count)" "INFO"
    foreach ($rule in $rulesToModify) {
        Write-Log "  - $($rule.Name): Backend Pool = $($rule.BackendAddressPool.Name)" "INFO"
    }
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
