# Quick Start Guide

## 5-Minute Setup

### Step 1: Configure Your Environments

Edit `config/environments.json`:

```json
{
  "environments": {
    "prod": {
      "resourceGroupName": "rg-appgateway-prod",
      "appGatewayName": "agw-prod",
      "subscriptionId": "12345678-1234-1234-1234-123456789012",
      "maintenance": {
        "routingRules": [
          "rule-api-prod",
          "rule-web-prod"
        ]
      },
      "normal": {
        "routingRules": [
          {
            "ruleName": "rule-api-prod",
            "backendPoolName": "api-backend-pool-prod",
            "backendSettings": "api-backend-settings-prod"
          },
          {
            "ruleName": "rule-web-prod",
            "backendPoolName": "web-backend-pool-prod",
            "backendSettings": "web-backend-settings-prod"
          }
        ]
      }
    }
  }
}
```

### Step 2: Set Up Azure Pipeline

1. In Azure DevOps, go to **Pipelines** → **New Pipeline**
2. Select your repository
3. Choose **Existing Azure Pipelines YAML file**
4. Select `azure-pipelines.yml` (or `azure-pipelines-simple.yml` for simpler version)
5. Update the service connection name in the YAML if needed:
   ```yaml
   azureSubscription: 'Azure-ServiceConnection-prod'  # Change to your service connection
   ```

### Step 3: Create Azure Service Connection

1. Go to **Project Settings** → **Service connections**
2. Create new **Azure Resource Manager** connection
3. Name it: `Azure-ServiceConnection-prod` (or match your naming)
4. Grant appropriate permissions (Contributor on App Gateway resource group)

### Step 4: Test It!

#### Via Pipeline:
1. Run the pipeline manually
2. Select:
   - Environment: `prod` (or dev, dev002, test, test002, prod002)
   - Action: `Maintenance`
   - Maintenance Redirect URL: `https://www.google.com` (default)

#### Via PowerShell (Local):
```powershell
# Login to Azure first
Connect-AzAccount

# Switch to maintenance
.\Scripts\Invoke-AppGatewayRedirect.ps1 -Environment prod -Action Maintenance -MaintenanceRedirectURL 'https://www.google.com'

# Switch back to normal
.\Scripts\Invoke-AppGatewayRedirect.ps1 -Environment prod -Action Normal
```

## Common Workflows

### During Patching Window

1. **Before Patching Starts:**
   ```
   Pipeline → Run → Environment: prod, Action: Maintenance, Redirect URL: https://www.google.com
   ```

2. **Perform Patching:**
   - Do your patching work
   - Users see maintenance page (redirected to the specified URL)

3. **After Patching Complete:**
   ```
   Pipeline → Run → Environment: prod, Action: Normal
   ```


## Troubleshooting

**"Application Gateway not found"**
- Check resource group and App Gateway names in `environments.json`
- Verify service connection has access

**"Backend pool not found" (when switching to Normal)**
- Verify `backendPoolName` in `normal.routingRules` config matches the actual pool name in App Gateway
- Check that the backend pool exists in your App Gateway

**Script fails with permission errors**
- Ensure service connection has `Contributor` role on resource group
- Check subscription access

## Next Steps

- Read full [README.md](README.md) for advanced usage
- Set up notifications in the pipeline
- Add monitoring/alerting for maintenance windows
- Configure approval policies in Azure DevOps

