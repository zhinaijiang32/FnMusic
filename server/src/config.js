require('dotenv').config();
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const dataDir = process.env.DATA_DIR || '/app/data';
const certDir = process.env.CERT_DIR || path.join(dataDir, 'certs');
const dbPath = process.env.DB_PATH || path.join(dataDir, 'db', 'fnmusic.db');
const musicStorePath = process.env.MUSIC_STORE_PATH || path.join(dataDir, 'music');

function getJwtSecret() {
  if (process.env.JWT_SECRET) return process.env.JWT_SECRET;

  // Keep an automatically generated signing key in the persistent data volume
  // so container upgrades do not invalidate every client session.
  const secretFile = process.env.JWT_SECRET_FILE ||
      path.join(dataDir, 'state', 'jwt-secret');
  try {
    if (fs.existsSync(secretFile)) {
      const saved = fs.readFileSync(secretFile, 'utf8').trim();
      if (saved) return saved;
    }
    fs.mkdirSync(path.dirname(secretFile), { recursive: true });
    const secret = crypto.randomBytes(32).toString('hex');
    fs.writeFileSync(secretFile, `${secret}\n`, { mode: 0o600 });
    console.warn(`[Config] JWT_SECRET not set; generated persistent key: ${secretFile}`);
    return secret;
  } catch (error) {
    console.warn(`[Config] Could not persist JWT secret: ${error.message}`);
    return crypto.randomBytes(32).toString('hex');
  }
}

module.exports = {
  port: parseInt(process.env.HTTPS_PORT, 10) || 8443,
  domain: process.env.DOMAIN || '',
  dataDir,
  musicStorePath,
  ncmApiPort: parseInt(process.env.NCM_API_PORT, 10) || 3000,
  jwtSecret: getJwtSecret(),
  letsencrypt: {
    enabled: process.env.LETSENCRYPT_ENABLED === 'true',
    dnsProvider: process.env.DNS_PROVIDER || 'cloudflare',
    email: process.env.ACME_EMAIL || '',
    token: process.env.DNS_API_TOKEN || '',
  },
  hosts: {
    internal: process.env.INTERNAL_HOST || 'localhost',
    public: process.env.PUBLIC_HOST || '',
  },
  certDir,
  dbPath,
};
