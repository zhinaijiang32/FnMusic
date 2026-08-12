require('dotenv').config();

const fs = require('fs');
const path = require('path');
const https = require('https');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { spawn } = require('child_process');

const config = require('./config');
const certManager = require('./certManager');

// 初始化数据库
require('./db/database');

const app = express();

// 基础中间件
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors());
app.use(morgan('short'));
app.use(express.json());

// 路由
app.use('/api/auth', require('./routes/auth'));
app.use('/api/music', require('./routes/music'));
app.use('/api/downloads', require('./routes/download'));

// 健康检查
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// 启动 NeteaseCloudMusicApi 子进程
function redactNcmLog(value) {
  return value
      .replace(/((?:^|[?&\s])(?:cookie|password|md5_password|email)=)[^&\s]*/gi, '$1[REDACTED]')
      .replace(/"(cookie|password|md5_password|email)"\s*:\s*"[^"]*"/gi, '"$1":"[REDACTED]"');
}

function startNcmApi() {
  console.log('[Server] 启动 NeteaseCloudMusicApi...');
  const npxCommand = process.platform === 'win32' ? 'npx.cmd' : 'npx';
  const ncmProcess = spawn(npxCommand, [
    '--no-install',
    'NeteaseCloudMusicApi',
    '--port', String(config.ncmApiPort),
  ], {
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env },
  });

  ncmProcess.stdout.on('data', (data) => {
    console.log(`[NCM] ${redactNcmLog(data.toString().trim())}`);
  });

  ncmProcess.stderr.on('data', (data) => {
    console.error(`[NCM] ${redactNcmLog(data.toString().trim())}`);
  });

  ncmProcess.on('close', (code) => {
    console.error(`[NCM] 进程退出 (code: ${code}), 10秒后自动重启...`);
    setTimeout(startNcmApi, 10000);
  });

  return ncmProcess;
}

// 初始化证书并启动 HTTPS 服务
async function startServer() {
  let sslOptions;

  if (!certManager.certExists()) {
    console.log('[Server] 证书不存在，生成自签名证书...');
    const fingerprint = certManager.generateSelfSigned();
    console.log(`[Server] 证书指纹 (SHA-256): ${fingerprint}`);
  }

  sslOptions = {
    key: fs.readFileSync(path.join(config.certDir, 'privkey.pem')),
    cert: fs.readFileSync(path.join(config.certDir, 'fullchain.pem')),
  };

  // 启动 NeteaseCloudMusicApi（等待 3 秒就绪）
  startNcmApi();
  await new Promise(resolve => setTimeout(resolve, 3000));

  // 创建 HTTPS 服务器
  https.createServer(sslOptions, app).listen(config.port, '0.0.0.0', () => {
    console.log('');
    console.log('============================================');
    console.log('  🎵 音栈 TuneCache 服务端已启动');
    console.log(`  📡 HTTPS 服务地址: https://0.0.0.0:${config.port}`);
    console.log(`  💾 音乐存储路径: ${config.musicStorePath}`);
    console.log(`  🔐 证书指纹: ${certManager.getFingerprint()}`);
    console.log('============================================');
  });
}

startServer().catch(console.error);
