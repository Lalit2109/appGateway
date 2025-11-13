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
      "maintenanceRedirectURL": "https://www.google.com",
      "routingRulesToProcess": [
        {
          "ruleName": "rule-api",
          "normalBackendPoolName": "api-backend-pool",
          "normalBackendSettings": "api-backend-settings"
        },
        {
          "ruleName": "rule-web",
          "normalBackendPoolName": "web-backend-pool",
          "normalBackendSettings": "web-backend-settings"
        }
      ]
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
   - Environment: `prod`
   - Action: `Maintenance`

#### Via PowerShell (Local):
```powershell
# Login to Azure first
Connect-AzAccount

# Switch to maintenance
.\Scripts\Invoke-AppGatewayRedirect.ps1 -Environment prod -Action Maintenance

# Switch back to normal
.\Scripts\Invoke-AppGatewayRedirect.ps1 -Environment prod -Action Normal
```

## Common Workflows

### During Patching Window

1. **Before Patching Starts:**
   ```
   Pipeline → Run → Environment: prod, Action: Maintenance
   ```

2. **Perform Patching:**
   - Do your patching work
   - Users see maintenance page

3. **After Patching Complete:**
   ```
   Pipeline → Run → Environment: prod, Action: Normal
   ```


## Troubleshooting

**"Application Gateway not found"**
- Check resource group and App Gateway names in `environments.json`
- Verify service connection has access

**"Backend pool not found" (when switching to Normal)**
- Verify `normalBackendPoolName` in config matches the actual pool name in App Gateway
- Check that the backend pool exists in your App Gateway

**Script fails with permission errors**
- Ensure service connection has `Contributor` role on resource group
- Check subscription access

## Next Steps

- Read full [README.md](README.md) for advanced usage
- Set up notifications in the pipeline
- Consider backing up state files to Azure Blob Storage
- Add monitoring/alerting for maintenance windows

