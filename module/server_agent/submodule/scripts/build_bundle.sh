#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SUBMODULE_ROOT}/../../.." && pwd)"
DIST_DIR="${SUBMODULE_ROOT}/dist"
BUNDLE_NAME="server-agent-bundle.zip"
FUNCTION_ZIP_NAME="azure_function.zip"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${DIST_DIR}"
cp -R "${SUBMODULE_ROOT}/azure_function" "${TMP_DIR}/azure_function"
cp -R "${SUBMODULE_ROOT}/openapi" "${TMP_DIR}/openapi"
cp "${REPO_ROOT}/docs/server-agent-import-guide.md" "${TMP_DIR}/server-agent-import-guide.md"

(
  cd "${TMP_DIR}/azure_function"
  zip -r "${DIST_DIR}/${FUNCTION_ZIP_NAME}" . \
    -x "local.settings.json" \
    -x "tests/*" >/dev/null
)

(
  cd "${TMP_DIR}"
  zip -r "${DIST_DIR}/${BUNDLE_NAME}" . >/dev/null
)

echo "Function zip: ${DIST_DIR}/${FUNCTION_ZIP_NAME}"
echo "Bundle zip: ${DIST_DIR}/${BUNDLE_NAME}"
