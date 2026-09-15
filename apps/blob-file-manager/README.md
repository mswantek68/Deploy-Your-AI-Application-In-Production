# Blob File Manager

A minimal web app for uploading, listing, downloading, editing (text files),
and deleting files in the private Azure Storage account deployed by this
accelerator. It runs as an Azure Container App inside the same private
virtual network as the storage account's private endpoint and uses its
system-assigned managed identity (via `DefaultAzureCredential`) — no storage
keys or SAS tokens are used.

See [docs/blob_file_manager_app.md](../../docs/blob_file_manager_app.md) for
deployment instructions, including how to add this app to an existing
deployed environment.

## Local development

```bash
cd apps/blob-file-manager
pip install -r requirements.txt
export STORAGE_ACCOUNT_NAME=<your-storage-account-name>
export UPLOADS_STORAGE_CONTAINER=uploads
az login   # so DefaultAzureCredential can authenticate
python app.py
```

Then browse to `http://localhost:8080`.
