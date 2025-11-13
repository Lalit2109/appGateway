# Azure App Gateway Maintenance Mode Automation

This repository contains Azure Pipeline and PowerShell scripts to automate the process of redirecting Azure Application Gateway traffic to a maintenance page during patching operations, and restoring normal routing once patching is complete.

## Overview

When infrastructure engineers need to perform patching on backend servers, this solution allows them to:
1. **Switch to Maintenance Mode**: Redirect all traffic (or specific routing rules) to a static maintenance page
2. **Switch to Normal Mode**: Restore traffic routing to the original backend pools

The solution supports:
- ✅ Multiple environments (dev, staging, prod)
- ✅ Multiple routing rules per environment
- ✅ State management to track original configurations
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

2. **Azure Service Connections**: Create service connections in Azure DevOps for each environment:
   - `Azure-ServiceConnection-dev`
   - `Azure-ServiceConnection-staging`
   - `Azure-ServiceConnection-prod`

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
      "maintenanceBackendPoolURL": "https://maintenance-dev.example.com",
      "maintenanceBackendPoolPort": 443,
      "routingRulesToProcess": [
        "rule-api",
        "rule-web"
      ],
      "routingRules": [
        "rule-api",
        "rule-web",
        "rule-admin"
      ]
    }
  }
}
```

**Important Configuration Notes:**
- `routingRulesToProcess`: Specifies which routing rules will be modified (typically 2 rules as per your requirement)
- `routingRules`: Lists all available routing rules in the App Gateway (for reference)
- `maintenanceBackendPoolURL`: HTTPS URL of the maintenance page (e.g., `https://maintenance.example.com`)
- `maintenanceBackendPoolPort`: Port number (443 for HTTPS, 80 for HTTP)

### 2. Configure Azure Pipeline

1. Import the pipeline (`azure-pipelines.yml`) into your Azure DevOps project
2. Update the service connection names in the pipeline YAML if different
3. **Configure Approval**: The pipeline includes an approval stage. You may need to:
   - Set up approval policies in Azure DevOps (Project Settings → Pipelines → Approvals)
   - Configure who can approve pipeline runs
4. (Optional) Create a Variable Group named `AppGateway-Config` for sensitive values

### 3. Create Maintenance Backend Pool (One-time)

The script will automatically create a maintenance backend pool if it doesn't exist. Ensure:
- The maintenance page server is accessible from the App Gateway
- The HTTPS URL is correct in the configuration
- The maintenance page is accessible via HTTPS (port 443) or HTTP (port 80) as configured

## Usage

### Option 1: Azure Pipeline (Recommended)

1. Navigate to Azure DevOps → Pipelines
2. Select the pipeline
3. Click "Run pipeline"
4. Fill in the parameters:
   - **Environment**: dev, staging, or prod
   - **Action**: Maintenance or Normal

5. Click "Run"
6. **Approval Required**: The pipeline will pause at the Approval stage. An approver must review and approve before changes are made to the App Gateway.
7. Once approved, the pipeline will proceed to modify the routing rules specified in `routingRulesToProcess` in the configuration file.

### Option 2: PowerShell Script (Local/Manual)

#### Switch to Maintenance Mode

```powershell
# Processes routing rules specified in routingRulesToProcess config
.\Scripts\Invoke-AppGatewayRedirect.ps1 -Environment prod -Action Maintenance
```

#### Switch to Normal Mode

```powershell
# Processes routing rules specified in routingRulesToProcess config
.\Scripts\Invoke-AppGatewayRedirect.ps1 -Environment prod -Action Normal
```

**Note**: The script processes only the routing rules specified in `routingRulesToProcess` in the configuration file (typically 2 rules as configured).

#### Direct Script Usage (Advanced)

```powershell
.\Scripts\Set-AppGatewayRedirect.ps1 `
    -ResourceGroupName "rg-prod" `
    -AppGatewayName "agw-prod" `
    -Action Maintenance `
    -MaintenanceBackendPoolURL "https://maintenance.example.com" `
    -RoutingRulesToProcess @("rule-api", "rule-web")
```

## How It Works

### Pipeline Flow

1. **Validate Stage**: Validates parameters and loads configuration
2. **Approval Stage**: Requires manual approval before proceeding (prevents accidental changes)
3. **ManageAppGateway Stage**: Executes the redirect script
4. **Notify Stage**: Logs operation results

### Maintenance Mode

1. Script reads the current App Gateway configuration
2. Filters to only the routing rules specified in `routingRulesToProcess` (typically 2 rules)
3. Creates or updates a maintenance backend pool with the specified HTTPS URL (FQDN)
4. **Saves the original backend pool** for each routing rule to a state file
5. Updates the specified routing rules to point to the maintenance backend pool
6. Applies the configuration

### Normal Mode

1. Script loads the state file to retrieve original backend pool information
2. Filters to only the routing rules specified in `routingRulesToProcess`
3. Restores each specified routing rule to its original backend pool
4. Applies the configuration

### State Management

State files (`appgateway-state-{environment}.json`) are created automatically to track:
- Original backend pool for each routing rule
- Timestamp of last maintenance switch

**Important**: Keep state files safe! They're needed to restore normal mode.

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
- Verify the routing rule names in `routingRulesToProcess` exist in the App Gateway
- Check the routing rule names in `environments.json`
- Ensure the routing rules are spelled correctly (case-sensitive)

### Error: "No saved state found" (Normal mode)
- The state file may have been deleted or not created
- You may need to manually configure routing rules in Azure Portal
- Consider backing up state files to a secure location

### State File Location
- Local execution: Created in the Scripts directory
- Pipeline execution: Published as a pipeline artifact

## Best Practices

1. **Test First**: Always test in dev/staging before production
2. **Approval Process**: The approval stage provides a safety check - ensure approvers understand the impact
3. **Backup State**: Consider storing state files in Azure Blob Storage or Key Vault
4. **Notifications**: Add email/Slack notifications to the pipeline for team awareness
5. **Monitoring**: Monitor App Gateway metrics during maintenance windows
6. **Documentation**: Keep `environments.json` updated as routing rules change, especially `routingRulesToProcess`
7. **Access Control**: Use Azure DevOps pipeline permissions to restrict who can run and approve the pipeline
8. **Configuration Review**: Review the `routingRulesToProcess` list before running the pipeline

## Security Considerations

- ✅ State files contain resource IDs but no secrets
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

