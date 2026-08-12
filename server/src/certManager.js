const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const config = require('./config');

class CertManager {
  constructor() {
    this.certDir = config.certDir;
    this.certPath = path.join(this.certDir, 'fullchain.pem');
    this.keyPath = path.join(this.certDir, 'privkey.pem');
  }
  certExists() { return fs.existsSync(this.certPath) && fs.existsSync(this.keyPath); }
  generateSelfSigned() {
    console.log('[CertManager] Generating...');
    fs.mkdirSync(this.certDir, { recursive: true });
    const hn = config.hosts.internal || 'localhost';
    let san = 'IP:127.0.0.1';
    if (/^\d+\.\d+\.\d+\.\d+$$/.test(hn)) san += ',IP:' + hn;
    else if (hn) san += ',DNS:' + hn;
    if (config.hosts.public) {
      if (/^\d+\.\d+\.\d+\.\d+$$/.test(config.hosts.public)) san += ',IP:' + config.hosts.public;
      else san += ',DNS:' + config.hosts.public;
    }
    if (config.domain) san += ',DNS:' + config.domain;
    console.log('[CertManager] SAN: ' + san);
    const subj = '/C=CN/O=TuneCache/CN=' + hn;
    const cmd = 'openssl req -x509 -newkey rsa:2048 -keyout ' + this.keyPath + ' -out ' + this.certPath + ' -days 3650 -nodes -subj ' + subj + ' -addext subjectAltName=' + san;
    execSync(cmd, { stdio: 'pipe' });
    console.log('[CertManager] Done');
    return this.getFingerprint();
  }
  getFingerprint() {
    try {
      const o = execSync('openssl x509 -in ' + this.certPath + ' -fingerprint -sha256 -noout', { stdio: 'pipe' }).toString();
      return o.replace('sha256 Fingerprint=', '').trim();
    } catch (e) { return null; }
  }
}
module.exports = new CertManager();
