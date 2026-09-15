const config = require('../config');

const getExpectedKey = () => {
  if (process.env.NODE_ENV === 'test' && !config.adminAccessKey) {
    return 'test-admin-key';
  }
  return config.adminAccessKey;
};

function ensureConfigured(req, res, next) {
  if (!getExpectedKey()) {
    return res.status(500).json({ error: 'ADMIN_ACCESS_KEY is not configured' });
  }
  return next();
}

function requireAdmin(req, res, next) {
  const expected = getExpectedKey();
  const cookieKey = req.cookies?.[config.sessionCookieName];
  const headerKey = req.get('x-admin-key');

  if (cookieKey === expected || headerKey === expected) {
    return next();
  }

  return res.status(401).json({ error: 'Unauthorized' });
}

function login(req, res) {
  const provided = req.body?.adminAccessKey;
  const expected = getExpectedKey();

  if (!provided || provided !== expected) {
    return res.status(401).json({ error: 'Invalid admin access key' });
  }

  res.cookie(config.sessionCookieName, expected, {
    httpOnly: true,
    secure: config.sessionCookieSecure,
    sameSite: 'strict',
    maxAge: config.sessionCookieMaxAgeMs
  });

  return res.status(204).send();
}

function logout(req, res) {
  res.clearCookie(config.sessionCookieName);
  return res.status(204).send();
}

module.exports = {
  ensureConfigured,
  requireAdmin,
  login,
  logout
};
