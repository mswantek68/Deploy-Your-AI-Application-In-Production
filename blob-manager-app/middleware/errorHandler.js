function errorHandler(error, req, res, next) {
  if (res.headersSent) {
    return next(error);
  }

  const status = error.statusCode || error.status || 500;
  const message = status >= 500 ? 'Internal server error' : error.message;

  return res.status(status).json({ error: message });
}

module.exports = errorHandler;
