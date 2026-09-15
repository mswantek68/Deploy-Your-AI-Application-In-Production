# Blob Manager App Service (Private Endpoint Ready)

This app provides a local web interface and API for securely managing blobs in Azure Blob Storage by using **Managed Identity** (`DefaultAzureCredential`) instead of connection strings or keys.

## Features

- Upload one or more blobs (`POST /api/blobs/upload`)
- List blobs with metadata and pagination marker (`GET /api/blobs`)
- Download blobs (`GET /api/blobs/:blobName`)
- View text blob content (`GET /api/blobs/:blobName/content`)
- Update text blobs (`PUT /api/blobs/:blobName`)
- Delete blobs (`DELETE /api/blobs/:blobName`)
- Health endpoint (`GET /health`)
- Admin dashboard UI (`GET /`)

## Security Model

- Uses system-assigned managed identity from App Service.
- Requires `Storage Blob Data Contributor` role on the storage account.
- Uses `ADMIN_ACCESS_KEY` to gate management API access.
- Supports secure HttpOnly admin session cookie.
- No storage account keys or connection strings are used.

## Required App Settings

| Setting | Description |
|---|---|
| `STORAGE_ACCOUNT_NAME` | Storage account name (without endpoint suffix). |
| `BLOB_CONTAINER_NAME` | Container managed by the app. |
| `ADMIN_ACCESS_KEY` | Required admin key for login/API access. |
| `SESSION_COOKIE_NAME` | Optional cookie name for admin session. |
| `SESSION_COOKIE_SECURE` | `true` for HTTPS-only cookie (recommended in production). |
| `SESSION_COOKIE_MAX_AGE_MS` | Optional cookie max age in milliseconds. |
| `CORS_ALLOWED_ORIGINS` | Optional comma-separated allowed origins. |
| `MAX_UPLOAD_FILE_SIZE_MB` | Optional per-file size limit for uploads. |

## Pre-deployment Checklist

- [ ] Storage account private endpoint is already reachable from the App Service integration subnet.
- [ ] DNS for `*.blob.core.windows.net` resolves to private endpoint IP from the VNet.
- [ ] App Service subnet is delegated to `Microsoft.Web/serverFarms`.
- [ ] App Service managed identity has `Storage Blob Data Contributor` on the storage account.
- [ ] `ADMIN_ACCESS_KEY` is generated and stored securely.
- [ ] CORS origins are restricted to trusted origins only.

## Infrastructure Deployment

The repository includes dedicated Bicep + PowerShell deployment assets:

- Bicep: `/infra/blob-manager/main.bicep`
- Parameter sample: `/infra/blob-manager/main.parameters.sample.json`
- Deploy script: `/scripts/automationScripts/blob-manager/deploy_blob_manager.ps1`

Run:

```powershell
pwsh ./scripts/automationScripts/blob-manager/deploy_blob_manager.ps1 \
  -ResourceGroupName <resource-group> \
  -ParameterFile infra/blob-manager/main.parameters.sample.json
```

## Local Development

```bash
cd blob-manager-app
npm install
ADMIN_ACCESS_KEY='<key>' STORAGE_ACCOUNT_NAME='<account>' BLOB_CONTAINER_NAME='<container>' npm start
```

## Updating Existing Deployments from This Fork

1. Deploy `/infra/blob-manager/main.bicep` into the existing resource group.
2. Confirm managed identity RBAC assignment propagated.
3. Deploy application code to the created App Service.
4. Validate access from inside the VNet and verify public internet access is restricted per your network policy.
