const { createHmac, timingSafeEqual } = require('node:crypto');
const jwt = require('jsonwebtoken');
const pool = require('../config/db');
const env = require('../config/env');

// Bind tokens to current credentials without disclosing password hashes.
function sessionVersion(user) {
  return createHmac('sha256', env.JWT_SECRET)
    .update(JSON.stringify([user.id, user.password, user.role])).digest('hex');
}
async function verifySession(token) {
  const decoded = jwt.verify(token, env.JWT_SECRET, { algorithms: ['HS256'] });
  if (!Number.isSafeInteger(decoded.id) || typeof decoded.sv !== 'string') throw new Error('INVALID_TOKEN');
  const { rows } = await pool.query('SELECT id, username, password, role FROM usuarios WHERE id = $1', [decoded.id]);
  const user = rows[0];
  if (!user) throw new Error('INVALID_TOKEN');
  const expected = Buffer.from(sessionVersion(user)), actual = Buffer.from(decoded.sv);
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) throw new Error('INVALID_TOKEN');
  return { id: user.id, username: user.username, role: user.role, exp: decoded.exp };
}
module.exports = { sessionVersion, verifySession };
