#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNCTION_ROOT="$MODULE_ROOT/azure_function"

if [[ -z "${FUNCTIONAPP_NAME:-}" ]]; then
  echo "FUNCTIONAPP_NAME is required."
  exit 1
fi

if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  echo "RESOURCE_GROUP is required."
  exit 1
fi

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI (az) is required."
  exit 1
fi

PACKAGE_ZIP="$MODULE_ROOT/dist/azure_function.zip"
if [[ ! -f "$PACKAGE_ZIP" ]]; then
  echo "Function package not found at $PACKAGE_ZIP"
  echo "Run: bash module/server_agent/submodule/scripts/build_bundle.sh"
  exit 1
fi

echo "Deploying function code to $FUNCTIONAPP_NAME in $RESOURCE_GROUP ..."
az functionapp deployment source config-zip \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FUNCTIONAPP_NAME" \
  --src "$PACKAGE_ZIP"

echo "Deployment complete."
