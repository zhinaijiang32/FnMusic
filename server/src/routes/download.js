const express = require('express');
const streamSplitter = require('../services/streamSplitter');
const auth = require('../middleware/auth');

const router = express.Router();

// 获取本地已保存的音乐列表
router.get('/', auth, async (req, res) => {
  try {
    const songs = await streamSplitter.getLocalSongs();
    res.json({ success: true, data: songs });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// 播放完成后确认本次边播边存是否完整；不完整内容会在服务端清理。
router.post('/:songId/finalize', auth, async (req, res) => {
  try {
    const result = await streamSplitter.finalizePlaybackSave(req.params.songId);
    res.json({ success: true, data: result });
  } catch (e) {
    res.status(500).json({ success: false, error: '保存状态校验失败' });
  }
});

// 删除本地保存的音乐
router.delete('/:songId', auth, async (req, res) => {
  try {
    await streamSplitter.deleteLocalSong(req.params.songId);
    res.json({ success: true, message: '删除成功' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
