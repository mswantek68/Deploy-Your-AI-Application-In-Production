const statusEl = document.getElementById('status');
const blobListEl = document.getElementById('blob-list');

const setStatus = (value) => {
  statusEl.textContent = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
};

const api = async (url, options = {}) => {
  const response = await fetch(url, {
    credentials: 'include',
    ...options
  });

  if (response.status === 204) {
    return null;
  }

  const json = await response.json();
  if (!response.ok) {
    throw new Error(json.error || `Request failed with ${response.status}`);
  }

  return json;
};

const renderBlobs = (items) => {
  blobListEl.innerHTML = '';

  if (!items.length) {
    const row = document.createElement('tr');
    row.innerHTML = '<td colspan="5">No blobs found</td>';
    blobListEl.appendChild(row);
    return;
  }

  for (const blob of items) {
    const row = document.createElement('tr');
    row.innerHTML = `
      <td>${blob.name}</td>
      <td>${blob.size ?? ''}</td>
      <td>${blob.createdOn ? new Date(blob.createdOn).toLocaleString() : ''}</td>
      <td>${blob.contentType ?? ''}</td>
      <td class="actions">
        <button data-action="load" data-name="${blob.name}">Load</button>
        <a href="/api/blobs/${encodeURIComponent(blob.name)}" target="_blank" rel="noopener noreferrer">Download</a>
        <button data-action="delete" data-name="${blob.name}">Delete</button>
      </td>
    `;
    blobListEl.appendChild(row);
  }
};

const refreshBlobs = async () => {
  const data = await api('/api/blobs');
  renderBlobs(data.items || []);
  setStatus(`Loaded ${data.items?.length || 0} blobs`);
};

document.getElementById('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await api('/api/admin/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ adminAccessKey: document.getElementById('adminAccessKey').value })
    });
    setStatus('Signed in');
    await refreshBlobs();
  } catch (error) {
    setStatus(error.message);
  }
});

document.getElementById('logout').addEventListener('click', async () => {
  try {
    await api('/api/admin/logout', { method: 'POST' });
    setStatus('Signed out');
  } catch (error) {
    setStatus(error.message);
  }
});

document.getElementById('upload-form').addEventListener('submit', async (event) => {
  event.preventDefault();

  const files = document.getElementById('files').files;
  const formData = new FormData();
  for (const file of files) {
    formData.append('files', file);
  }

  try {
    const result = await api('/api/blobs/upload', {
      method: 'POST',
      body: formData
    });
    setStatus(result);
    await refreshBlobs();
  } catch (error) {
    setStatus(error.message);
  }
});

document.getElementById('refresh').addEventListener('click', async () => {
  try {
    await refreshBlobs();
  } catch (error) {
    setStatus(error.message);
  }
});

document.getElementById('edit-form').addEventListener('submit', async (event) => {
  event.preventDefault();

  try {
    const blobName = document.getElementById('blobName').value;
    const result = await api(`/api/blobs/${encodeURIComponent(blobName)}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content: document.getElementById('blobContent').value,
        contentType: document.getElementById('blobContentType').value
      })
    });
    setStatus(result);
    await refreshBlobs();
  } catch (error) {
    setStatus(error.message);
  }
});

blobListEl.addEventListener('click', async (event) => {
  const target = event.target;
  const action = target?.dataset?.action;
  const name = target?.dataset?.name;
  if (!action || !name) return;

  try {
    if (action === 'delete') {
      if (!window.confirm(`Delete ${name}?`)) {
        return;
      }
      await api(`/api/blobs/${encodeURIComponent(name)}`, { method: 'DELETE' });
      setStatus(`Deleted ${name}`);
      await refreshBlobs();
      return;
    }

    if (action === 'load') {
      const data = await api(`/api/blobs/${encodeURIComponent(name)}/content`);
      document.getElementById('blobName').value = name;
      document.getElementById('blobContentType').value = data.contentType;
      document.getElementById('blobContent').value = data.content;
      setStatus(`Loaded ${name}`);
    }
  } catch (error) {
    setStatus(error.message);
  }
});
