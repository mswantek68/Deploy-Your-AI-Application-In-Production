const express = require('express');
const { ensureConfigured, login, logout } = require('../middleware/auth');

const router = express.Router();

router.post('/login', ensureConfigured, login);
router.post('/logout', logout);

module.exports = router;
