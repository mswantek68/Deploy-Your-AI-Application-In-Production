const express = require('express');
const path = require('path');
const cors = require('cors');
const cookieParser = require('cookie-parser');
const { DefaultAzureCredential } = require('@azure/identity');
const { BlobServiceClient } = require('@azure/storage-blob');
const config = require('./config');
const { ensureConfigured, requireAdmin } = require('./middleware/auth');
const errorHandler = require('./middleware/errorHandler');
const adminRoutes = require('./routes/admin');
const createBlobRoutes = require('./routes/blobs');

function createContainerClient() {
  if (!config.storageAccountName || !config.blobContainerName) {
    throw new Error('STORAGE_ACCOUNT_NAME and BLOB_CONTAINER_NAME must be configured');
  }

  const accountUrl = `https://${config.storageAccountName}.blob.core.windows.net`;
  const credential = new DefaultAzureCredential();
  const serviceClient = new BlobServiceClient(accountUrl, credential);
  return serviceClient.getContainerClient(config.blobContainerName);
}

function createApp({ containerClient } = {}) {
  const app = express();
  const resolvedContainerClient = containerClient || createContainerClient();

  const corsOrigins = config.corsAllowedOrigins;
  if (corsOrigins.length) {
    app.use(
      cors({
        origin: corsOrigins,
        credentials: true
      })
    );
  }

  app.use(express.json({ limit: '10mb' }));
  app.use(cookieParser());

  app.get('/health', async (req, res, next) => {
    try {
      await resolvedContainerClient.exists();
      return res.status(200).json({ status: 'ok' });
    } catch (error) {
      return next(error);
    }
  });

  app.use('/api/admin', adminRoutes);
  app.use('/api/blobs', ensureConfigured, requireAdmin, createBlobRoutes({ containerClient: resolvedContainerClient }));

  app.use(express.static(path.join(__dirname, 'public')));
  app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
  });

  app.use(errorHandler);

  return app;
}

if (require.main === module) {
  const app = createApp();
  app.listen(config.port, () => {
    console.log(`Blob manager listening on port ${config.port}`);
  });
}

module.exports = {
  createApp,
  createContainerClient
};
