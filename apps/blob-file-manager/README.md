# Blob File Manager

A minimal web app for uploading, listing, downloading, editing (text files),
and deleting files in Azure Storage. It supports two modes:

- **Local development** — run entirely on your workstation against the
  [Azurite](https://learn.microsoft.com/azure/storage/common/storage-use-azurite)
  storage emulator. No Azure subscription, VNet, VM, or Bastion connection
  required — just Docker.
- **Deployed to Azure** — runs as an Azure Container App inside the same
  private virtual network as the storage account's private endpoint, using
  its system-assigned managed identity (via `DefaultAzureCredential`) — no
  storage keys or SAS tokens are used.

See [docs/blob_file_manager_app.md](../../docs/blob_file_manager_app.md) for
full deployment instructions, including how to add this app to an existing
deployed environment.

## Run locally (no Azure, no VM required)

The fastest way to iterate on the app is against the Azurite emulator, using
Docker Compose:

```bash
cd apps/blob-file-manager
docker compose up --build
```

Then browse to `http://localhost:8080`. Files you upload are stored in a
local Azurite volume — nothing ever touches Azure.

### Without Docker Compose

```bash
cd apps/blob-file-manager
pip install -r requirements.txt
cp .env.example .env   # then `export $(grep -v '^#' .env | xargs)` or use a tool like direnv
python app.py
```

This requires an Azurite instance running locally (`docker run -p 10000:10000 mcr.microsoft.com/azure-storage/azurite azurite-blob --blobHost 0.0.0.0`), or you can point `AZURE_STORAGE_CONNECTION_STRING` at any Storage account connection string.

## Run against a real (non-isolated) Azure Storage account

If you want to test against a real Azure Storage account instead of Azurite,
and that account allows public network access (i.e. `networkIsolation` is
`false` or the account isn't behind a private endpoint):

```bash
cd apps/blob-file-manager
pip install -r requirements.txt
unset AZURE_STORAGE_CONNECTION_STRING
export STORAGE_ACCOUNT_NAME=<your-storage-account-name>
export UPLOADS_STORAGE_CONTAINER=uploads
az login   # so DefaultAzureCredential can authenticate
python app.py
```

Then browse to `http://localhost:8080`.

> **Note:** When `networkIsolation=true` (the default for this accelerator),
> the deployed storage account has public network access disabled, so this
> mode only works if you've explicitly enabled public access on the account.
> To reach the real, fully-private storage account from a normal workstation
> instead, see **Run against the real, private storage account (no VM)** below.

## Run against the real, private storage account (no VM)

When `networkIsolation=true`, the storage account's public network access
stays fully `Disabled` — it is never opened up, even temporarily. Instead,
this accelerator supports an optional Point-to-Site (P2S) VPN Gateway
(`deployVpnGateway` in `infra/main.bicepparam`) that lets your own workstation
join the private VNet directly, the same way `mswantek68.github.io`'s app
reached its private-endpoint storage — without a jump VM or Bastion session.

1. Enable the gateway once, then provision/re-provision:

   ```bash
   azd env set DEPLOY_VPN_GATEWAY true
   azd provision
   ```

   (This adds a VPN Gateway + public IP to the VNet; it has an ongoing hourly
   cost while deployed, so turn it back off with
   `azd env set DEPLOY_VPN_GATEWAY false && azd provision` when you're done.)

2. Install the [Azure VPN Client](https://aka.ms/azvpnclient), then generate
   and import the connection profile:

   ```bash
   ./scripts/connect_vpn_gateway.sh        # bash
   # or
   ./scripts/connect_vpn_gateway.ps1       # PowerShell
   ```

3. Open Azure VPN Client, import the generated profile, click **Connect**,
   and sign in with your Microsoft Entra ID account (the gateway uses Entra
   ID authentication — no certificates to manage).

4. Once connected, your workstation has a private IP inside the VNet and can
   reach the storage account through its private endpoint:

   ```bash
   cd apps/blob-file-manager
   pip install -r requirements.txt
   unset AZURE_STORAGE_CONNECTION_STRING
   export STORAGE_ACCOUNT_NAME=<your-storage-account-name>
   export UPLOADS_STORAGE_CONTAINER=uploads
   az login   # so DefaultAzureCredential can authenticate
   python app.py
   ```

   Then browse to `http://localhost:8080`. Uploads/edits/downloads now go to
   the real Azure Storage account, over the private endpoint, exactly as they
   would from inside a Container App — the storage account's public network
   access is never touched.

