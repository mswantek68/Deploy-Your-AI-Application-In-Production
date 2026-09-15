const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.SESSION_COOKIE_SECURE = 'false';

const { createApp } = require('../app');

const createContainerClientStub = () => ({
  exists: async () => true,
  listBlobsFlat: () => ({ byPage: async function* byPage() { yield { continuationToken: null, segment: { blobItems: [] } }; } }),
  getBlockBlobClient: () => ({
    upload: async () => {},
    exists: async () => false
  }),
  getBlobClient: () => ({ exists: async () => false }),
  deleteBlob: async () => ({})
});

test('GET /health returns ok', async () => {
  const app = createApp({ containerClient: createContainerClientStub() });

  const response = await request(app).get('/health');

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.status, 'ok');
});

test('blob routes require admin auth', async () => {
  const app = createApp({ containerClient: createContainerClientStub() });

  const response = await request(app).get('/api/blobs');

  assert.equal(response.statusCode, 401);
});

test('admin login enables blob list access', async () => {
  const app = createApp({ containerClient: createContainerClientStub() });

  const login = await request(app)
    .post('/api/admin/login')
    .send({ adminAccessKey: 'test-admin-key' });

  assert.equal(login.statusCode, 204);
  const cookie = login.headers['set-cookie'][0].split(';')[0];

  const list = await request(app).get('/api/blobs').set('Cookie', cookie);

  assert.equal(list.statusCode, 200);
  assert.deepEqual(list.body.items, []);
});
