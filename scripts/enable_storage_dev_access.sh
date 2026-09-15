#!/bin/bash
# Temporarily opens the deployed Storage Account's public network endpoint,
# restricted to your current public IP address, so you can run apps (such as
# apps/blob-file-manager) from a normal developer workstation and have
# uploads/downloads/edits actually land in the real Azure Storage account —
# not just a local emulator.
#
# This accelerator deploys the Storage Account with public network access
# fully DISABLED when networkIsolation=true (the default). That setting
# blocks ALL public traffic unconditionally, including IP-allowlisted
# traffic, so there is no firewall rule that can let a normal dev machine
# reach it directly.
#
# This script:
#   1. Detects your current public IP address (or uses --ip if provided).
#   2. Sets the Storage Account's public network access to 'Enabled' with a
#      default-deny network ACL, then adds a firewall rule allowing only
#      your IP address.
#   3. Grants the specified principal (defaults to your signed-in `az`
#      account) the 'Storage Blob Data Contributor' role on the Storage
#      Account, so it can read/write blobs.
#
# Private endpoint traffic (used by the Container Apps environment and the
# Jump VM) is unaffected by this change — private endpoints bypass the
# public firewall entirely. This only opens a narrow, IP-restricted hole in
# the public endpoint for local development.
#
# Run ./disable_storage_dev_access.sh afterwards to lock the account back
# down to fully private.
#
# Usage:
#   ./enable_storage_dev_access.sh --resource-group rg-dev080626c [--storage-account NAME] [--ip 1.2.3.4] [--principal-id GUID]

set -e

RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
STORAGE_ACCOUNT_NAME=""
MY_IP=""
PRINCIPAL_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
        --storage-account) STORAGE_ACCOUNT_NAME="$2"; shift 2 ;;
        --ip) MY_IP="$2"; shift 2 ;;
        --principal-id) PRINCIPAL_ID="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$RESOURCE_GROUP" ] && command -v azd >/dev/null 2>&1; then
    RESOURCE_GROUP="$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null || true)"
fi
if [ -z "$RESOURCE_GROUP" ]; then
    echo "ERROR: --resource-group is required (or set AZURE_RESOURCE_GROUP / run from an azd environment)." >&2
    exit 1
fi

if [ -z "$STORAGE_ACCOUNT_NAME" ] && command -v azd >/dev/null 2>&1; then
    STORAGE_ACCOUNT_NAME="$(azd env get-value STORAGE_ACCOUNT_NAME 2>/dev/null || true)"
fi
if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    echo "ERROR: --storage-account is required (or set it via azd env STORAGE_ACCOUNT_NAME)." >&2
    exit 1
fi

if [ -z "$MY_IP" ]; then
    echo "Detecting your public IP address..."
    MY_IP="$(curl -s https://api.ipify.org)"
fi
if ! [[ "$MY_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    echo "ERROR: Could not determine a valid IPv4 address. Pass --ip explicitly." >&2
    exit 1
fi
echo "Using public IP: $MY_IP"

if [ -z "$PRINCIPAL_ID" ]; then
    echo "Resolving signed-in account object ID..."
    PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv)"
fi
if [ -z "$PRINCIPAL_ID" ]; then
    echo "ERROR: Could not resolve a principal ID. Pass --principal-id explicitly, or run 'az login' first." >&2
    exit 1
fi

echo ""
echo "================================================"
echo " Opening Storage Account '$STORAGE_ACCOUNT_NAME' to IP $MY_IP"
echo " Resource Group: $RESOURCE_GROUP"
echo "================================================"
echo ""

echo "[1/3] Enabling public network access with default-deny network ACL..."
az storage account update \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --public-network-access Enabled \
    --default-action Deny \
    --bypass AzureServices \
    --only-show-errors >/dev/null

echo "[2/3] Adding firewall rule for $MY_IP..."
az storage account network-rule add \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --ip-address "$MY_IP" \
    --only-show-errors >/dev/null

echo "[3/3] Granting Storage Blob Data Contributor to principal $PRINCIPAL_ID..."
STORAGE_ID="$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type User \
    --role "Storage Blob Data Contributor" \
    --scope "$STORAGE_ID" \
    --only-show-errors >/dev/null

echo ""
echo "[OK] Done. You can now run apps/blob-file-manager locally against the real Storage Account:"
echo ""
echo "    cd apps/blob-file-manager"
echo "    pip install -r requirements.txt"
echo "    unset AZURE_STORAGE_CONNECTION_STRING"
echo "    export STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME"
echo "    az login"
echo "    python app.py"
echo ""
echo "Uploads/downloads/edits will now go to the real Azure Storage account."
echo "Run ./disable_storage_dev_access.sh when you're done to lock it back down."
