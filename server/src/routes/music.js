const express = require('express');
const netease = require('../services/netease');
const axios = require('axios');
const streamSplitter = require('../services/streamSplitter');
const auth = require('../middleware/auth');

const router = express.Router();

// 代理网易封面，避免 Windows 客户端直连图片 CDN 偶发失败。
// 仅允许网易公开封面域名，不能作为通用代理使用。
router.get('/cover', async (req, res) => {
  try {
    const coverUrl = String(req.query.url || '');
    const parsed = new URL(coverUrl);
    if (parsed.protocol !== 'https:' || !/^p[1-4]\.music\.126\.net$/.test(parsed.hostname)) {
      return res.status(400).json({ error: '无效的封面地址' });
    }
    const upstream = await axios.get(coverUrl, {
      responseType: 'stream',
      timeout: 15000,
    });
    res.setHeader('Content-Type', upstream.headers['content-type'] || 'image/jpeg');
    if (upstream.headers['content-length']) {
      res.setHeader('Content-Length', upstream.headers['content-length']);
    }
    res.setHeader('Cache-Control', 'public, max-age=604800');
    upstream.data.on('error', () => res.destroy());
    upstream.data.pipe(res);
  } catch (_) {
    res.status(502).json({ error: '封面加载失败' });
  }
});

// 搜索音乐
router.get('/search', auth, async (req, res) => {
  try {
    const { keyword, limit, offset } = req.query;
    const result = await netease.search(keyword, limit, offset);
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// 获取歌曲详情
router.get('/detail/:ids', auth, async (req, res) => {
  try {
    const result = await netease.getSongDetail(req.params.ids);
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// The client queries this immediately before playback to show whether the
// upcoming stream is served from the verified NAS cache or fetched from Netease.
router.get('/source/:id', auth, (req, res) => {
  const source = streamSplitter.getPlaybackSource(req.params.id);
  res.json({ success: true, data: { source } });
});

// 播放音乐（核心接口：流分流，播放的同时保存到本地）
router.get('/play/:id', auth, async (req, res) => {
  try {
    const songId = req.params.id;

    // 先获取歌曲信息
    const detail = await netease.getSongDetail(songId);
    let songInfo = {};
    if (detail && detail.songs && detail.songs.length > 0) {
      const song = detail.songs[0];
      songInfo = {
        name: song.name,
        artist: (song.ar || []).map(a => a.name).join('/'),
        album: (song.al || {}).name || '',
        coverUrl: (song.al || {}).picUrl || '',
        duration: song.dt || 0,
      };
    }

    // 获取歌词（同时保存）
    try {
      const lyricData = await netease.getLyric(songId);
      await streamSplitter.saveLyric(songId, lyricData);
    } catch (e) {
      // 歌词非必须，忽略错误
    }

    // 流分流播放并保存
    await streamSplitter.streamWithSave(songId, songInfo, req, res);
  } catch (e) {
    if (!res.headersSent) {
      res.status(500).json({ error: e.message });
    }
  }
});

// 获取歌词
router.get('/lyric/:id', auth, async (req, res) => {
  try {
    const result = await netease.getLyric(req.params.id);
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// 获取用户收藏歌单
router.get('/user/playlist/:uid', auth, async (req, res) => {
  try {
    const result = await netease.getFavoritePlaylist(req.params.uid);
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// 获取歌单详情
router.get('/playlist/:id', auth, async (req, res) => {
  try {
    const result = await netease.getPlaylistDetail(req.params.id);
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// 每日推荐
router.get('/recommend', auth, async (req, res) => {
  try {
    const result = await netease.getRecommendSongs();
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// 私人FM
router.get('/fm', auth, async (req, res) => {
  try {
    const result = await netease.getPersonalFm();
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
