const axios = require('axios');
const config = require('../config');
const db = require('../db/database');
const NCM = 'http://localhost:' + config.ncmApiPort;

class NeteaseService {
  async getLoginStatus() {
    const u = db.prepare('SELECT cookie FROM users ORDER BY id DESC LIMIT 1').get();
    if (!u) return { profile: null };

    let cookie = u.cookie;
    if (cookie.startsWith('{') || cookie.startsWith('[')) {
      try { cookie = JSON.parse(cookie); } catch (_) { /* use the raw cookie */ }
    }
    return this._req('/login/status', { cookie, timestamp: Date.now() });
  }

  async loginByPhone(phone, password) {
    const r = await this._req('/login/cellphone', { phone, password, md5_password: this._md5(password) }, 'POST');
    if (r && r.cookie) this._saveCookie(r.cookie, r.profile);
    return r;
  }

  async loginByEmail(email, password) {
    const r = await this._req('/login', {
      email,
      password,
      md5_password: this._md5(password),
    }, 'POST');
    if (r && r.cookie) this._saveCookie(r.cookie, r.profile);
    return r;
  }

  async sendLoginCaptcha(phone) {
    return this._req('/captcha/sent', {
      phone,
      ctcode: '86',
      timestamp: Date.now(),
    }, 'POST');
  }

  async loginByCaptcha(phone, captcha) {
    const r = await this._req('/login/cellphone', {
      phone,
      captcha,
      ctcode: '86',
      timestamp: Date.now(),
    }, 'POST');
    if (r && r.cookie) this._saveCookie(r.cookie, r.profile);
    return r;
  }

  // NCM caches GET responses by URL.  A timestamp makes every refresh a new QR code.
  async getQrUnikey() { return this._req('/login/qr/key', { timestamp: Date.now() }); }

  async getQrImg(k) {
    return this._req('/login/qr/create', {
      key: k,
      qrimg: 'true',
      timestamp: Date.now(),
    });
  }

  async getProfileByCookie(cookie) {
    if (!cookie) return null;
    const status = await this._req('/login/status', { cookie, timestamp: Date.now() });
    return status?.data?.profile || status?.profile || null;
  }

  async checkQrStatus(k) {
    const r = await this._req('/login/qr/check', { key: k, timestamp: Date.now() });
    // A successful QR check returns a cookie but usually no profile.  Fetch it
    // before the route creates a JWT for this application.
    if (r && r.code === 803 && r.cookie) {
      r.profile = r.profile || await this.getProfileByCookie(r.cookie);
      this._saveCookie(r.cookie, r.profile);
    }
    return r;
  }

  async search(kw, limit, offset) { return this._req('/search', { keywords: kw, limit: limit||30, offset: offset||0 }); }
  async getSongDetail(ids) { return this._req('/song/detail', { ids: Array.isArray(ids)?ids.join(','):ids }); }
  async getLyric(id) { return this._req('/lyric', { id }); }
  async getFavoritePlaylist(uid) {
    return this._req('/user/playlist', { uid, cookie: this._savedCookie() });
  }

  async getPlaylistDetail(id) {
    return this._req('/playlist/detail', { id, cookie: this._savedCookie() });
  }

  async getRecommendSongs() {
    return this._req('/recommend/songs', { cookie: this._savedCookie() });
  }

  async getPersonalFm() {
    return this._req('/personal_fm', { cookie: this._savedCookie() });
  }

  // 播放地址必须携带当前网易云会话；否则付费歌曲会被 API 按未登录用户
  // 降级为试听资源，即使客户端已完成登录。
  async getSongUrl(id, level = 'exhigh') {
    return this._req('/song/url/v1', {
      id: String(id),
      level,
      cookie: this._savedCookie(),
      timestamp: Date.now(),
    });
  }

  async _req(endpoint, data, method) {
    method = method || 'GET';
    try {
      const opts = { timeout: 15000, validateStatus: function(s) { return true; } };
      let res;
      if (method === 'POST') {
        const params = new URLSearchParams();
        for (const [k,v] of Object.entries(data)) params.append(k, v);
        res = await axios.post(NCM + endpoint, params.toString(), Object.assign({}, opts, { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } }));
      } else {
        res = await axios.get(NCM + endpoint, Object.assign({}, opts, { params: data }));
      }
      return res.data;
    } catch (e) {
      console.error('Netease API [' + endpoint + ']:', e.message);
      return { code: -1, message: e.message };
    }
  }

  _saveCookie(cookie, profile) {
    if (!profile) return;
    const cs = typeof cookie === 'string' ? cookie : JSON.stringify(cookie);
    const ex = db.prepare('SELECT id FROM users WHERE uid = ?').get(profile.userId);
    if (ex) db.prepare('UPDATE users SET cookie=?, nickname=?, avatar_url=?, updated_at=CURRENT_TIMESTAMP WHERE uid=?').run(cs, profile.nickname, profile.avatarUrl, profile.userId);
    else db.prepare('INSERT INTO users (cookie, nickname, avatar_url, uid) VALUES (?,?,?,?)').run(cs, profile.nickname, profile.avatarUrl, profile.userId);
  }

  _savedCookie() {
    const user = db.prepare('SELECT cookie FROM users ORDER BY id DESC LIMIT 1').get();
    if (!user) return undefined;
    return user.cookie;
  }

  _md5(s) { return require('crypto').createHash('md5').update(s).digest('hex'); }
}

module.exports = new NeteaseService();
