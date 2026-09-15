"""Blob File Manager

A minimal web application that lets users upload, edit, download and delete
files stored in an Azure Storage account.

Two ways to run it:

1. **Local development** — set `AZURE_STORAGE_CONNECTION_STRING` (e.g. to the
   well-known Azurite emulator connection string, see `docker-compose.yml`).
   No Azure subscription, VNet, VM, or Bastion connection is required; the
   app runs entirely on your workstation like any other local web app.
2. **Deployed to Azure** — when running as the Container App provisioned by
   this accelerator, no connection string is set, and the app instead uses
   the container app's system-assigned managed identity (via
   `DefaultAzureCredential`) to reach the private storage account over the
   private endpoint. Configuration is resolved at runtime from Azure App
   Configuration, matching the pattern used by the `orchestrator` sample app
   in this repository.
"""
import io
import os
import logging

from azure.appconfiguration.provider import load
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from flask import Flask, redirect, render_template, request, send_file, url_for, abort

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("blob-file-manager")

app = Flask(__name__)

# Text file extensions that are safe to render/edit inline in the browser.
EDITABLE_EXTENSIONS = {
    ".txt", ".md", ".json", ".csv", ".yaml", ".yml", ".xml", ".log", ".ini", ".config",
}

_credential = None
_blob_service_client = None
_container_name = None


def _load_config():
    """Resolve the storage connection details.

    Priority order:
    1. ``AZURE_STORAGE_CONNECTION_STRING`` — local development / Azurite. No
       Azure AD credential or network access to Azure is required at all.
    2. Azure App Configuration (``APP_CONFIG_ENDPOINT``) — used when deployed
       as the Container App in this accelerator, read via managed identity.
    3. Plain ``STORAGE_BLOB_ENDPOINT`` / ``STORAGE_ACCOUNT_NAME`` environment
       variables — manual override/fallback.
    """
    connection_string = os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
    container_name = os.environ.get("UPLOADS_STORAGE_CONTAINER", "uploads")
    if connection_string:
        return {"connection_string": connection_string}, container_name

    app_config_endpoint = os.environ.get("APP_CONFIG_ENDPOINT")
    label = os.environ.get("APP_CONFIG_LABEL", "ai-lz")

    blob_endpoint = os.environ.get("STORAGE_BLOB_ENDPOINT")
    storage_account_name = os.environ.get("STORAGE_ACCOUNT_NAME")

    if app_config_endpoint:
        try:
            settings = load(
                endpoint=app_config_endpoint,
                credential=_get_credential(),
                selects=[{"key_filter": "*", "label_filter": label}],
            )
            blob_endpoint = settings.get("STORAGE_BLOB_ENDPOINT", blob_endpoint)
            storage_account_name = settings.get("STORAGE_ACCOUNT_NAME", storage_account_name)
            container_name = settings.get("UPLOADS_STORAGE_CONTAINER", container_name)
        except Exception:  # noqa: BLE001 - fall back to env vars if App Config is unreachable
            logger.exception("Unable to load settings from App Configuration; falling back to environment variables")

    if not blob_endpoint and storage_account_name:
        blob_endpoint = f"https://{storage_account_name}.blob.core.windows.net"

    if not blob_endpoint:
        raise RuntimeError(
            "Storage configuration is missing. For local development, set "
            "AZURE_STORAGE_CONNECTION_STRING (see docker-compose.yml for Azurite). "
            "For deployed use, set APP_CONFIG_ENDPOINT (with STORAGE_BLOB_ENDPOINT/"
            "STORAGE_ACCOUNT_NAME populated), or set STORAGE_BLOB_ENDPOINT/STORAGE_ACCOUNT_NAME directly."
        )

    return {"blob_endpoint": blob_endpoint}, container_name


def _get_credential():
    global _credential
    if _credential is None:
        _credential = DefaultAzureCredential()
    return _credential


def _get_container_client():
    global _blob_service_client, _container_name
    if _blob_service_client is None:
        target, container_name = _load_config()
        if "connection_string" in target:
            _blob_service_client = BlobServiceClient.from_connection_string(target["connection_string"])
        else:
            _blob_service_client = BlobServiceClient(account_url=target["blob_endpoint"], credential=_get_credential())
        _container_name = container_name
        try:
            _blob_service_client.create_container(_container_name)
        except Exception:  # noqa: BLE001 - container likely already exists
            pass
    return _blob_service_client.get_container_client(_container_name)


def _is_editable(name: str) -> bool:
    _, ext = os.path.splitext(name)
    return ext.lower() in EDITABLE_EXTENSIONS


@app.route("/")
def index():
    container_client = _get_container_client()
    blobs = [
        {"name": b.name, "size": b.size, "last_modified": b.last_modified, "editable": _is_editable(b.name)}
        for b in container_client.list_blobs()
    ]
    return render_template("index.html", blobs=blobs)


@app.route("/upload", methods=["POST"])
def upload():
    uploaded_file = request.files.get("file")
    if not uploaded_file or uploaded_file.filename == "":
        abort(400, description="No file selected")

    container_client = _get_container_client()
    container_client.upload_blob(
        name=uploaded_file.filename, data=uploaded_file.stream, overwrite=True
    )
    return redirect(url_for("index"))


@app.route("/download/<path:blob_name>")
def download(blob_name):
    container_client = _get_container_client()
    blob_client = container_client.get_blob_client(blob_name)
    stream = blob_client.download_blob()
    return send_file(
        io.BytesIO(stream.readall()),
        as_attachment=True,
        download_name=blob_name,
    )


@app.route("/edit/<path:blob_name>", methods=["GET", "POST"])
def edit(blob_name):
    if not _is_editable(blob_name):
        abort(400, description="This file type cannot be edited inline")

    container_client = _get_container_client()
    blob_client = container_client.get_blob_client(blob_name)

    if request.method == "POST":
        new_content = request.form.get("content", "")
        blob_client.upload_blob(new_content.encode("utf-8"), overwrite=True)
        return redirect(url_for("index"))

    content = blob_client.download_blob().readall().decode("utf-8", errors="replace")
    return render_template("edit.html", blob_name=blob_name, content=content)


@app.route("/delete/<path:blob_name>", methods=["POST"])
def delete(blob_name):
    container_client = _get_container_client()
    container_client.delete_blob(blob_name)
    return redirect(url_for("index"))


@app.route("/healthz")
def healthz():
    return {"status": "ok"}


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
