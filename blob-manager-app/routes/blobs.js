const express = require('express');
const multer = require('multer');
const config = require('../config');

const textContentTypes = [
  'application/json',
  'application/javascript',
  'application/xml',
  'application/x-yaml',
  'text/plain',
  'text/csv',
  'text/html',
  'text/markdown',
  'text/xml',
  'text/yaml'
];

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: config.maxUploadFileSizeMb * 1024 * 1024 }
});

const decodeName = (value) => decodeURIComponent(value || '').trim();

module.exports = ({ containerClient }) => {
  const router = express.Router();

  router.get('/', async (req, res) => {
    const pageSize = Math.min(Math.max(Number(req.query.pageSize) || 50, 1), 200);
    const marker = req.query.marker;

    const blobs = [];
    let continuationToken;

    for await (const page of containerClient
      .listBlobsFlat({ includeMetadata: true })
      .byPage({ maxPageSize: pageSize, continuationToken: marker })) {
      continuationToken = page.continuationToken;
      for (const item of page.segment.blobItems) {
        blobs.push({
          name: item.name,
          size: item.properties.contentLength,
          createdOn: item.properties.createdOn,
          contentType: item.properties.contentType,
          etag: item.properties.etag,
          metadata: item.metadata || {}
        });
      }
      break;
    }

    return res.json({
      items: blobs,
      pageSize,
      nextMarker: continuationToken || null
    });
  });

  router.post('/upload', upload.array('files', 25), async (req, res) => {
    const files = req.files || [];
    if (!files.length) {
      return res.status(400).json({ error: 'No files uploaded' });
    }

    const uploaded = [];
    for (const file of files) {
      const blobClient = containerClient.getBlockBlobClient(file.originalname);
      await blobClient.uploadData(file.buffer, {
        blobHTTPHeaders: {
          blobContentType: file.mimetype || 'application/octet-stream'
        }
      });

      uploaded.push({ name: file.originalname, size: file.size, contentType: file.mimetype });
    }

    return res.status(201).json({ uploadedCount: uploaded.length, uploaded });
  });

  router.get('/:blobName', async (req, res) => {
    const blobName = decodeName(req.params.blobName);
    const blobClient = containerClient.getBlobClient(blobName);

    if (!(await blobClient.exists())) {
      return res.status(404).json({ error: 'Blob not found' });
    }

    const download = await blobClient.download();
    const contentType = download.contentType || 'application/octet-stream';
    res.setHeader('Content-Type', contentType);
    res.setHeader('Content-Disposition', `attachment; filename="${encodeURIComponent(blobName)}"`);

    if (!download.readableStreamBody) {
      return res.status(500).json({ error: 'Blob stream unavailable' });
    }

    download.readableStreamBody.pipe(res);
    return undefined;
  });

  router.get('/:blobName/content', async (req, res) => {
    const blobName = decodeName(req.params.blobName);
    const blockBlob = containerClient.getBlockBlobClient(blobName);

    if (!(await blockBlob.exists())) {
      return res.status(404).json({ error: 'Blob not found' });
    }

    const props = await blockBlob.getProperties();
    const contentType = props.contentType || 'application/octet-stream';
    if (!contentType.startsWith('text/') && !textContentTypes.includes(contentType)) {
      return res.status(400).json({ error: 'Blob is not a supported text-based file' });
    }

    const download = await blockBlob.downloadToBuffer();
    return res.json({
      name: blobName,
      contentType,
      content: download.toString('utf8'),
      etag: props.etag
    });
  });

  router.put('/:blobName', async (req, res) => {
    const blobName = decodeName(req.params.blobName);
    const { content, contentType } = req.body || {};

    if (typeof content !== 'string') {
      return res.status(400).json({ error: 'content must be a string' });
    }

    const normalizedContentType = contentType || 'text/plain; charset=utf-8';
    if (!normalizedContentType.startsWith('text/') && !textContentTypes.includes(normalizedContentType)) {
      return res.status(400).json({ error: 'Only text-based content types are supported for updates' });
    }

    const blockBlob = containerClient.getBlockBlobClient(blobName);
    await blockBlob.upload(content, Buffer.byteLength(content), {
      blobHTTPHeaders: { blobContentType: normalizedContentType }
    });

    return res.status(200).json({ updated: blobName, contentType: normalizedContentType });
  });

  router.delete('/:blobName', async (req, res) => {
    const blobName = decodeName(req.params.blobName);
    const deleteResult = await containerClient.deleteBlob(blobName, {
      deleteSnapshots: 'include'
    });

    if (deleteResult.errorCode === 'BlobNotFound') {
      return res.status(404).json({ error: 'Blob not found' });
    }

    return res.status(204).send();
  });

  return router;
};
