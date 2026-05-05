# Server Inventory Agent Bundle - Import Guide

This guide explains how to deploy the downloadable bundle into Azure and connect it to Copilot Studio.

## 1) Package contents

- `module/server_agent/submodule/azure_function/` - Python Azure Function that executes deterministic Dataverse queries.
- `module/server_agent/submodule/openapi/run-server-query-v2.openapi.json` - OpenAPI definition for Copilot custom connector.
- `module/server_agent/submodule/scripts/` - Build and deployment helper scripts.

## 2) Fill placeholders

Copy `local.settings.template.json` to `local.settings.json` and set all values:

- `AZURE_TENANT_ID`
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `DATAVERSE_URL`
- `DV_ENTITY_SET_NAME`
- `DV_ENTITY_LOGICAL_NAME`
- `DV_PRIMARY_KEY`
- `DV_COL_NAME`
- `DV_COL_OWNER`
- `DV_COL_OS`
- `DV_COL_PATCH_STATUS`
- `DV_COL_SIZE_GB`
- `DV_COL_ENVIRONMENT`
- `DV_COL_LAST_PATCHED_DATE`

## 3) Build downloadable zip

From repo root:

```bash
bash module/server_agent/submodule/scripts/build_bundle.sh
```

This generates:

- `dist/server-agent-bundle.zip`

## 4) Deploy Azure Function

Prerequisites:

- Azure CLI login (`az login`)
- Function app already created on Linux Python runtime

Set variables and deploy:

```bash
export FUNCTIONAPP_NAME="your-function-app-name"
export RESOURCE_GROUP="your-resource-group"
bash module/server_agent/submodule/scripts/deploy_function.sh
```

The script expects zip at:

- `module/server_agent/submodule/dist/server-agent-bundle.zip`

It deploys that package to your function app.

## 5) Configure function app settings

Set the same environment variables from section 2 in Azure Function App Configuration.

## 6) Import into Copilot Studio (custom connector)

1. Go to Power Platform > Custom connectors.
2. Create new connector > Import OpenAPI.
3. Upload: `module/server_agent/submodule/openapi/run-server-query-v2.openapi.json`
4. In connector host/base URL, set your function URL:
   - `https://<FUNCTIONAPP_NAME>.azurewebsites.net`
5. Create connector.
6. Add connector action to your Copilot Studio agent.

## 7) Copilot topic wiring

Use one action call with inputs:

- `questionText`
- `previousFiltersJson`
- `pageNumber`
- `pagingCookie`
- `pageSize`

Use outputs:

- `status`, `queryType`, `count`, `markdownTable`, `rowsJson`, `hasMore`, `nextPagingCookie`, `nextPageNumber`, `appliedFiltersJson`, `clarifyQuestion`.

## 8) Move to other system

You can move this package by:

1. Uploading `module/server_agent/submodule/dist/server-agent-bundle.zip` to your other machine.
2. Unzip.
3. Run the same deploy steps there.

Or commit this folder into your source repo and clone from the other machine.
