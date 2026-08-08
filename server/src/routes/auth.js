const express = require('express');
const jwt = require('jsonwebtoken');
const config = require('../config');
const netease = require('../services/netease');
const auth = require('../middleware/auth');
const db = require('../db/database');

const router = express.Router();

function finishLogin(res, result, fallbackMessage) {
  if (result.code === 200 && result.profile?.userId) {
    const token = jwt.sign({ uid: result.profile.userId }, config.jwtSecret, { expiresIn: '30d' });
    return res.json({ success: true, data: { token, profile: result.profile } });
  }

  const needsCaptcha = result.code === 8821;
  return res.status(400).json({
    success: false,
    code: result.code,
    error: needsCaptcha
      ? '网易云仍要求完成行为验证，请在官方客户端完成验证后再重试。'
      : (result.message || result.msg || fallbackMessage),
  });
}

// 获取登录状态
router.get('/status', async (req, res) => {
  try {
    const status = await netease.getLoginStatus();
    res.json({ success: true, data: status });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// 校验客户端保存的登录令牌，并返回用于恢复界面的账号信息。
router.get('/session', auth, (req, res) => {
  const user = db.prepare('SELECT uid, nickname, avatar_url FROM users WHERE uid = ?').get(req.user.uid);
  res.json({
    success: true,
    data: {
      profile: {
        userId: req.user.uid,
        nickname: user?.nickname || '',
        avatarUrl: user?.avatar_url || '',
      },
    },
  });
});

// 手机号登录
router.post('/login/cellphone', async (req, res) => {
  try {
    const phone = String(req.body.phone || '').trim();
    const password = String(req.body.password || '');
    if (!phone || !password) {
      return res.status(400).json({ success: false, error: '请输入手机号和密码。' });
    }

    const result = await netease.loginByPhone(phone, password);
    return finishLogin(res, result, '网易云登录失败，请检查手机号和密码。');
  } catch (e) {
    res.status(500).json({ success: false, error: '密码登录请求失败，请稍后重试。' });
  }
});

// 网易邮箱账号密码登录
router.post('/login/email', async (req, res) => {
  try {
    const email = String(req.body.email || '').trim();
    const password = String(req.body.password || '');
    if (!/^\S+@\S+\.\S+$/.test(email) || !password) {
      return res.status(400).json({ success: false, error: '请输入有效的网易邮箱和密码。' });
    }

    const result = await netease.loginByEmail(email, password);
    return finishLogin(res, result, '网易邮箱登录失败，请检查邮箱和密码。');
  } catch (e) {
    return res.status(500).json({ success: false, error: '网易邮箱登录请求失败，请稍后重试。' });
  }
});

// 发送短信登录验证码
router.post('/login/captcha/send', async (req, res) => {
  try {
    const phone = String(req.body.phone || '').trim();
    if (!/^1\d{10}$/.test(phone)) {
      return res.status(400).json({ success: false, error: '请输入正确的 11 位中国大陆手机号。' });
    }
    const result = await netease.sendLoginCaptcha(phone);
    if (result.code === 200) {
      return res.json({ success: true, message: '验证码已发送，请查收短信。' });
    }
    return res.status(400).json({
      success: false,
      code: result.code,
      error: result.message || result.msg || '验证码发送失败，请稍后重试。',
    });
  } catch (e) {
    return res.status(500).json({ success: false, error: '验证码发送请求失败，请稍后重试。' });
  }
});

// 短信验证码登录
router.post('/login/captcha', async (req, res) => {
  try {
    const phone = String(req.body.phone || '').trim();
    const captcha = String(req.body.captcha || '').trim();
    if (!/^1\d{10}$/.test(phone) || !captcha) {
      return res.status(400).json({ success: false, error: '请输入手机号和短信验证码。' });
    }
    const result = await netease.loginByCaptcha(phone, captcha);
    return finishLogin(res, result, '验证码无效或已过期，请重新获取。');
  } catch (e) {
    return res.status(500).json({ success: false, error: '验证码登录请求失败，请稍后重试。' });
  }
});

// 获取二维码 key
router.get('/qr/key', async (req, res) => {
  try {
    const result = await netease.getQrUnikey();
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// 获取二维码所承载的网易云真实登录 URL
router.get('/qr/image/:unikey', async (req, res) => {
  try {
    const result = await netease.getQrImg(req.params.unikey);
    res.json({ success: true, data: result.data || result });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// 检查二维码扫码状态
router.get('/qr/check/:unikey', async (req, res) => {
  try {
    const result = await netease.checkQrStatus(req.params.unikey);
    if (result.code === 803) {
      const profile = result.profile || await netease.getProfileByCookie(result.cookie);
      if (!profile || !profile.userId) {
        return res.status(502).json({
          success: false,
          error: '网易云已确认登录，但暂时无法取得账户信息；请刷新二维码后重试。',
        });
      }
      const token = jwt.sign({ uid: profile.userId }, config.jwtSecret, { expiresIn: '30d' });
      res.json({ success: true, data: { token, profile, status: 'authorized' } });
    } else if (result.code === 802) {
      res.json({ success: true, data: { status: 'scanned' } });
    } else if (result.code === 801) {
      res.json({ success: true, data: { status: 'waiting' } });
    } else {
      res.json({ success: true, data: { status: 'expired' } });
    }
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// 注销
router.post('/logout', (req, res) => {
  res.json({ success: true, message: '已注销' });
});

module.exports = router;
