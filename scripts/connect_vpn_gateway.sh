#!/bin/bash

# =============================================================================
# Connect VPN Gateway Script for Deploy Your AI Application In Production
# =============================================================================
# Downloads and configures the Azure VPN Client profile for the deployed
# Point-to-Site (P2S) VPN Gateway, so this workstation can connect directly
# to the private VNet (no jump VM / Bastion required).
#
# Prerequisites:
#   - The environment must have been deployed with deployVpnGateway=true
#     (e.g. `DEPLOY_VPN_GATEWAY=true azd up`, or
#     `azd env set DEPLOY_VPN_GATEWAY true` followed by `azd provision`).
#   - Azure VPN Client must be installed on this machine:
#       https://aka.ms/azvpnclient
#   - You must be able to authenticate with Microsoft Entra ID against this
#     tenant (the gateway uses Entra ID / AAD authentication, not certificates).
#
# After importing the profile into the Azure VPN Client and connecting, this
# workstation gets a private IP in the VNet's client address pool and can
# reach the storage account (and any other private-endpoint-only resource)
# exactly like the Container Apps / jump VM do today. The storage account's
# public network access remains fully "Disabled" throughout.
#
# Usage:
#   ./connect_vpn_gateway.sh [--resource-group <rg>] [--gateway-name <name>]
# =============================================================================

set -euo pipefail

RESOURCE_GROUP=""
GATEWAY_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    --gateway-name)
      GATEWAY_NAME="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$RESOURCE_GROUP" ]]; then
  RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null || true)
fi
if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "Could not resolve resource group. Pass --resource-group explicitly or run this from a directory with an azd environment selected." >&2
  exit 1
fi

if [[ -z "$GATEWAY_NAME" ]]; then
  GATEWAY_NAME=$(azd env get-value vpnGatewayName 2>/dev/null || true)
fi
if [[ -z "$GATEWAY_NAME" ]]; then
  echo "Could not resolve VPN gateway name. Pass --gateway-name explicitly, or confirm deployVpnGateway=true was used during provisioning." >&2
  exit 1
fi

echo "Resource group: $RESOURCE_GROUP"
echo "VPN gateway:    $GATEWAY_NAME"

DOWNLOAD_DIR=$(mktemp -d "/tmp/vpnclient-${GATEWAY_NAME}.XXXXXX")

echo "Requesting VPN client configuration package (this can take a minute)..."
PACKAGE_URL=$(az network vnet-gateway vpn-client generate \
  --resource-group "$RESOURCE_GROUP" \
  --name "$GATEWAY_NAME" \
  --authentication-method EAPTLS \
  -o tsv)

if [[ -z "$PACKAGE_URL" ]]; then
  echo "Failed to generate VPN client package. Confirm the gateway exists and vpnClientConfiguration.vpnAuthenticationTypes includes AAD." >&2
  exit 1
fi

ZIP_PATH="${DOWNLOAD_DIR}/vpnclientconfiguration.zip"
echo "Downloading package to ${ZIP_PATH} ..."
curl -sSL -o "$ZIP_PATH" "$PACKAGE_URL"

unzip -q -o "$ZIP_PATH" -d "$DOWNLOAD_DIR"

PROFILE_XML=$(find "$DOWNLOAD_DIR" -type d -iname 'AzureVPN' -exec find {} -maxdepth 1 -iname '*.xml' \; | head -n1 || true)

if [[ -n "$PROFILE_XML" ]]; then
  echo ""
  echo "Azure VPN Client profile ready: ${PROFILE_XML}"
  echo ""
  echo "Next steps:"
  echo "  1. Install the Azure VPN Client (https://aka.ms/azvpnclient) if not already installed."
  echo "  2. Open Azure VPN Client -> Import -> select the XML file above."
  echo "  3. Click Connect and sign in with your Microsoft Entra ID account."
  echo "  4. Once connected, run the blob-file-manager app locally with STORAGE_ACCOUNT_NAME set"
  echo "     (see apps/blob-file-manager/README.md) - it will reach the storage account through"
  echo "     the private endpoint, the same way it does inside the VNet."
else
  echo "Could not locate the AzureVPN profile XML automatically. Inspect the extracted files under: ${DOWNLOAD_DIR}" >&2
fi
