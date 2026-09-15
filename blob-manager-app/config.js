const parseCsv = (value) => {
  if (!value) return [];
  return value
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
};

module.exports = {
  port: Number(process.env.PORT || 3000),
  storageAccountName: process.env.STORAGE_ACCOUNT_NAME,
  blobContainerName: process.env.BLOB_CONTAINER_NAME,
  adminAccessKey: process.env.ADMIN_ACCESS_KEY,
  sessionCookieName: process.env.SESSION_COOKIE_NAME || 'blob-manager-admin',
  sessionCookieSecure: (process.env.SESSION_COOKIE_SECURE || 'true').toLowerCase() !== 'false',
  sessionCookieMaxAgeMs: Number(process.env.SESSION_COOKIE_MAX_AGE_MS || 8 * 60 * 60 * 1000),
  corsAllowedOrigins: parseCsv(process.env.CORS_ALLOWED_ORIGINS),
  maxUploadFileSizeMb: Number(process.env.MAX_UPLOAD_FILE_SIZE_MB || 20)
};
