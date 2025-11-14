# Azure App Gateway Maintenance Mode Automation

This repository contains Azure Pipeline and PowerShell scripts to automate the process of redirecting Azure Application Gateway traffic to a maintenance page during patching operations, and restoring normal routing once patching is complete.

## Overview

When infrastructure engineers need to perform patching on backend servers, this solution allows them to:
1. **Switch to Maintenance Mode**: Redirect all traffic (or specific routing rules) to a static maintenance page
2. **Switch to Normal Mode**: Restore traffic routing to the original backend pools

The solution supports:
- ✅ Multiple environments (dev, dev002, test, test002, prod, prod002)
- ✅ Multiple routing rules per environment
- ✅ Configuration-driven restoration (no state files needed)
- ✅ Azure Pipeline integration for easy execution

## Architecture

```
┌─────────────────┐
│ Azure Pipeline  │
│  (Manual Run)   │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│ Invoke-AppGateway       │
│ Redirect.ps1            │
│ (Wrapper Script)        │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ Set-AppGatewayRedirect  │
│ .ps1                    │
│ (Core Logic)            │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│ Azure App Gateway       │
│ (Update Routing Rules)  │
└─────────────────────────┘
```

## Prerequisites

1. **Azure PowerShell Module**: Install `Az` module
   ```powershell
   Install-Module -Name Az -Scope CurrentUser -Force
   ```

2. **Azure Service Connections**: Create service connections in Azure DevOps for each environment group:
   - Service connection for dev/dev002 environments
   - Service connection for test/test002 environments
   - Service connection for prod/prod002 environments

3. **Permissions**: The service principal used in the service connections needs:
   - `Contributor` role on the Application Gateway resource groups
   - Or `Network Contributor` role with specific App Gateway permissions

## Setup

### 1. Configure Environments

Edit `config/environments.json` with your environment details:

```json
{
  "environments": {
    "dev": {
      "resourceGroupName": "rg-appgateway-dev",
      "appGatewayName": "agw-dev",
      "subscriptionId": "your-dev-subscription-id",
      "maintenance": {
        "routingRules": [
          "rule-api-dev",
          "rule-web-dev"
        ]
      },
      "normal": {
        "routingRules": [
          {
            "ruleName": "rule-api-dev",
            "backendPoolName": "api-backend-pool-dev",
            "backendSettings": "api-backend-settings-dev"
          },
          {
            "ruleName": "rule-web-dev",
            "backendPoolName": "web-backend-pool-dev",
            "backendSettings": "web-backend-settings-dev"
          }
        ]
      }
    },
    "dev002": {
      "resourceGroupName": "rg-appgateway-dev",
      "appGatewayName": "agw-dev",
      "subscriptionId": "your-dev-subscription-id",
      "maintenance": {
        "routingRules": [
          "rule-api-dev002",
          "rule-web-dev002"
        ]
      },
      "normal": {
        "routingRules": [
          {
            "ruleName": "rule-api-dev002",
            "backendPoolName": "api-backend-pool-dev002",
            "backendSettings": "api-backend-settings-dev002"
          }
        ]
      }
    }
  }
}
```

**Important Configuration Notes:**
- Each environment (dev, dev002, test, test002, prod, prod002) has its own configuration
- `maintenance.routingRules`: Array of routing rule names to redirect during maintenance mode
- `normal.routingRules`: Array of routing rule configurations to restore in Normal mode
  - `ruleName`: Name of the routing rule in App Gateway
  - `backendPoolName`: Backend pool name to restore (must exist in App Gateway)
  - `backendSettings`: Backend HTTP settings name to restore (must exist in App Gateway)
- `maintenanceRedirectURL` is provided as a pipeline parameter, not in the config file

### 2. Configure Azure Pipeline

1. Import the pipeline (`azure-pipelines.yml`) into your Azure DevOps project
2. **Create Service Principal Connections**: Create service connections and map them in the pipeline:
   - Service connection for dev/dev002 environments
   - Service connection for test/test002 environments
   - Service connection for prod/prod002 environments
   - Update the `serviceConnectionName` variable in `azure-pipelines.yml` with your actual SPN names
   - Each SPN needs `Contributor` role on the respective App Gateway resource group
3. **Configure Approval**: The pipeline includes an approval stage with 15-minute timeout. You may need to:
   - Set up approval policies in Azure DevOps (Project Settings → Pipelines → Approvals)
   - Configure who can approve pipeline runs
   - Approval will automatically reject after 15 minutes if not approved
4. (Optional) Create a Variable Group named `AppGateway-Config` for sensitive values

### 3. Ensure Backend Pools and Settings Exist

**Important**: All backend pools and backend settings referenced in the configuration must already exist in your App Gateway.

- Ensure backend pools (`normalBackendPoolName`) exist in your App Gateway
- Ensure backend HTTP settings (`normalBackendSettings`) exist in your App Gateway
- The names in the configuration must match exactly (case-sensitive) with the names in Azure

## Usage

### Option 1: Azure Pipeline (Recommended)

1. Navigate to Azure DevOps → Pipelines
2. Select the pipeline
3. Click "Run pipeline"
4. Fill in the parameters:
   - **Environment**: dev, dev002, test, test002, prod, or prod002
   - **Action**: Maintenance or Normal
   - **Maintenance Redirect URL**: (Only shown when Action is Maintenance) URL to redirect to during maintenance (default: https://www.google.com)

5. Click "Run"
6. **Approval Required**: The pipeline will pause at the Approval stage. An approver must review and approve before changes are made to the App Gateway.
7. Once approved, the pipeline will proceed to modify the routing rules specified in the environment's configuration.

### Option 2: PowerShell Script (Local/Manual)

#### Switch to Maintenance Mode

```powershell
# Processes routing rules specified in maintenance.routingRules config
.\Scripts\Invoke-AppGatewayRedirect.ps1 -Environment prod -Action Maintenance -MaintenanceRedirectURL 'https://www.google.com'
```

#### Switch to Normal Mode

```powershell
# Processes routing rules specified in normal.routingRules config
.\Scripts\Invoke-AppGatewayRedirect.ps1 -Environment prod -Action Normal
```

**Note**: The script processes only the routing rules specified in the environment's `maintenance.routingRules` (for Maintenance) or `normal.routingRules` (for Normal) in the configuration file.

#### Direct Script Usage (Advanced)

```powershell
$rulesConfig = @(
    @{
        ruleName = "rule-api"
        normalBackendPoolName = "api-backend-pool"
        normalBackendSettings = "api-backend-settings"
    },
    @{
        ruleName = "rule-web"
        normalBackendPoolName = "web-backend-pool"
        normalBackendSettings = "web-backend-settings"
    }
)

.\Scripts\Set-AppGatewayRedirect.ps1 `
    -ResourceGroupName "rg-prod" `
    -AppGatewayName "agw-prod" `
    -Action Maintenance `
    -MaintenanceRedirectURL "https://www.google.com" `
    -RoutingRulesConfig $rulesConfig
```

## How It Works

### Pipeline Flow

1. **Validate Stage**: Validates parameters and loads configuration
2. **Approval Stage**: Requires manual approval before proceeding (prevents accidental changes)
3. **ManageAppGateway Stage**: Executes the redirect script
4. **Notify Stage**: Logs operation results

### Maintenance Mode

1. Script reads the current App Gateway configuration
2. Processes routing rules specified in `maintenance.routingRules` for the selected environment
3. Creates/uses a redirect configuration pointing to the external URL (from pipeline parameter)
4. Updates routing rules to use the redirect configuration (redirects to external site)
5. Clears backend pool and backend settings from routing rules
6. Applies the configuration

### Normal Mode

1. Script reads backend pool and backend settings names from `normal.routingRules` in configuration file
2. Processes routing rules specified in `normal.routingRules` for the selected environment
3. Finds backend pools and backend settings in App Gateway by name (from config)
4. Restores each routing rule to use the backend pool and settings specified in config
5. Clears redirect configuration from routing rules
6. Applies the configuration

**Note**: No state files are used. All restoration values come directly from the configuration file.

## File Structure

```
App-gateway-Redirect/
├── azure-pipelines.yml          # Azure Pipeline definition
├── config/
│   └── environments.json        # Environment configuration
├── Scripts/
│   ├── Set-AppGatewayRedirect.ps1    # Core script
│   └── Invoke-AppGatewayRedirect.ps1 # Wrapper script
├── README.md                    # This file
└── .gitignore                   # Git ignore rules
```

## Troubleshooting

### Error: "Application Gateway not found"
- Verify the resource group and App Gateway names in `environments.json`
- Check that the service connection has access to the subscription

### Error: "Routing rule not found"
- Verify the routing rule names in `maintenance.routingRules` or `normal.routingRules` exist in the App Gateway
- Check the routing rule names in `environments.json` for the selected environment
- Ensure the routing rules are spelled correctly (case-sensitive)

### Error: "Backend pool not found" (Normal mode)
- Verify the `normalBackendPoolName` in configuration matches the actual pool name in App Gateway
- Check that the backend pool exists in your App Gateway
- Ensure the name is spelled correctly (case-sensitive)

### Error: "Backend settings not found" (Normal mode)
- Verify the `normalBackendSettings` in configuration matches the actual settings name in App Gateway
- Check that the backend HTTP settings exist in your App Gateway
- Ensure the name is spelled correctly (case-sensitive)

## Best Practices

1. **Test First**: Always test in dev/staging before production
2. **Approval Process**: The approval stage provides a safety check - ensure approvers understand the impact
3. **Configuration Accuracy**: Ensure all backend pool and backend settings names in config match exactly with App Gateway (case-sensitive)
4. **Notifications**: Add email/Slack notifications to the pipeline for team awareness
5. **Monitoring**: Monitor App Gateway metrics during maintenance windows
6. **Documentation**: Keep `environments.json` updated as routing rules change, especially `maintenance.routingRules` and `normal.routingRules`
7. **Access Control**: Use Azure DevOps pipeline permissions to restrict who can run and approve the pipeline
8. **Configuration Review**: Review the environment's routing rules configuration before running the pipeline

## Security Considerations

- ✅ No state files required - all configuration is in the config file
- ✅ Service connections use managed identities or service principals
- ✅ Pipeline requires manual trigger (no automatic runs)
- ⚠️ Consider storing sensitive config in Azure Key Vault
- ⚠️ Review and audit pipeline execution logs

## Alternative Approaches

If you prefer a different approach, consider:

1. **Azure Automation Runbooks**: For scheduled or event-driven maintenance
2. **Azure Functions**: For API-based control
3. **Terraform/ARM Templates**: For infrastructure-as-code approach
4. **Azure App Gateway Health Probes**: Automatic failover (requires backend health endpoints)

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review Azure App Gateway logs
3. Verify PowerShell module versions
4. Check Azure service connection permissions

## License

This solution is provided as-is for internal use.

