# Blob File Manager App

This accelerator can optionally deploy a lightweight web application — the
**Blob File Manager** — that lets you upload, list, download, edit (text
files), and delete files in the private Azure Storage account created by this
solution. It runs as an Azure Container App inside the same private virtual
network as the storage account's private endpoint, so no storage keys, SAS
tokens, or public network access are required. Authentication to Azure
Storage and Azure App Configuration is performed with the container app's
system-assigned managed identity.

This is similar in spirit to a small file-manager site, but wired for a
private, production-style environment: the app, the storage account, and the
Container Apps environment communicate entirely over the private VNet.

## What gets deployed

| Resource | Purpose |
|----------|---------|
| Storage container `uploads` | Where files uploaded through the app are stored (added to `storageAccountContainersList` in `infra/main.bicepparam`) |
| Container App `blobmanager` | Runs the app (added to `containerAppsList` in `infra/main.bicepparam`) |
| RBAC: `Storage Blob Data Contributor` | Granted to the container app's managed identity on the storage account |
| RBAC: `App Configuration Data Reader` | Granted to the container app's managed identity so it can read `STORAGE_ACCOUNT_NAME` / `STORAGE_BLOB_ENDPOINT` / `UPLOADS_STORAGE_CONTAINER` |
| RBAC: `AcrPull` | Granted so the container app can pull its image from the deployed Azure Container Registry |

The application source code lives in [`apps/blob-file-manager`](../apps/blob-file-manager).

## Option A — Deploy as part of a fresh `azd up`

If you haven't deployed yet, or are comfortable re-running provisioning, the
`uploads` container and `blobmanager` container app are already included in
`infra/main.bicepparam`. Running `azd up` (or `azd provision`) will create
them along with the rest of the environment. After provisioning, continue
with **Build and publish the app image** below.

## Option B — Add it to an already-deployed environment (e.g. `rg-dev080626c`)

If you already have a deployed environment and don't want to re-run the full
`azd up` flow, you can add just the new container and container app with an
incremental deployment against your existing resource group:

1. Make sure your local checkout includes the `uploads` container entry in
   `storageAccountContainersList` and the `blobmanager` entry in
   `containerAppsList` in `infra/main.bicepparam` (already present after this
   change).
2. Re-run the existing preprovision flow, which performs an incremental
   deployment of the AI Landing Zone submodule against your resource group
   (it will only add the new container and container app; existing resources
   are left untouched):

   ```powershell
   pwsh ./scripts/preprovision-integrated.ps1 -ResourceGroup rg-dev080626c
   ```

   Or, equivalently, run `azd provision` from an environment already pointed
   at `rg-dev080626c` (`azd env set AZURE_RESOURCE_GROUP rg-dev080626c` /
   matching environment name), which invokes the same preprovision hook.

3. Confirm the new resources exist:

   ```bash
   az storage container show --account-name <storageAccountName> --name uploads --auth-mode login
   az containerapp show -g rg-dev080626c -n <blobmanager-container-app-name>
   ```

## Build and publish the app image

The container app is deployed with a placeholder image, matching the pattern
used for the `orchestrator` sample app in this repository. Build and push the
Blob File Manager image to the environment's Azure Container Registry, then
update the container app to use it:

```bash
# From the repository root
ACR_NAME=<your-container-registry-name>
RESOURCE_GROUP=rg-dev080626c
APP_NAME=<blobmanager-container-app-name>

az acr build --registry "$ACR_NAME" --image blob-file-manager:latest apps/blob-file-manager

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --image "$ACR_NAME.azurecr.io/blob-file-manager:latest"
```

## Accessing the app

Because the Container Apps environment is private, the app is only reachable
from inside the virtual network. Access it the same way you access other
private resources in this accelerator — through the **Jump VM** via Azure
Bastion. See [Accessing Private Resources](./Accessing_Private_Resources.md)
for connection steps, then browse to the container app's FQDN
(`https://<app-name>.<container-env-domain>`) from the Jump VM.

## Troubleshooting

- **403 / Forbidden errors accessing storage** — verify the container app's
  managed identity has the `Storage Blob Data Contributor` role on the
  storage account (granted automatically when `blobmanager` includes
  `StorageBlobDataContributor` in its `roles` list).
- **App can't find storage settings** — verify the container app has
  `AppConfigurationDataReader` in its `roles` list and that
  `APP_CONFIG_ENDPOINT` is set as an environment variable (set automatically
  by the AI Landing Zone container app module).
- **Can't reach the app URL** — confirm you're connected through the Jump VM;
  the app is not exposed to the public internet.
