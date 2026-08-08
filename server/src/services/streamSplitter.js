const fs = require('fs');
const path = require('path');
const axios = require('axios');
const config = require('../config');
const db = require('../db/database');
const netease = require('./netease');

class StreamSplitter {
  constructor() {
    this.musicDir = path.join(config.musicStorePath, 'songs');
    this.lyricDir = path.join(config.musicStorePath, 'lyrics');
    this.activeSaves = new Map();
  }

  // 播放时保存歌曲。未验证完成的内容只会存在于 .part 临时文件中。
  async streamWithSave(songId, songInfo, req, res) {
    const id = String(songId);
    const cached = db.prepare('SELECT file_path, size FROM songs WHERE song_id = ?').get(id);
    if (cached && this._isValidFile(cached.file_path, cached.size)) {
      this._streamCachedFile(id, songInfo, cached.file_path, req, res);
      return;
    }
    if (cached) this._deleteSongRecord(id, cached);

    let source;
    let writeStream;
    let finalPath;
    let partPath;
    let finishSave;
    const save = {
      completion: new Promise((resolve) => { finishSave = resolve; }),
      settled: false,
    };
    this.activeSaves.set(id, save);

    let expectedBytes = null;
    let receivedBytes = 0;
    let sourceEnded = false;
    let sourceFailed = false;
    let clientAborted = false;

    const settle = (reason) => {
      if (save.settled) return;
      save.settled = true;

      const sizeMatches = expectedBytes == null || receivedBytes === expectedBytes;
      const complete = sourceEnded && !sourceFailed && !clientAborted && receivedBytes > 0 && sizeMatches;
      if (complete) {
        try {
          fs.renameSync(partPath, finalPath);
          const stat = fs.statSync(finalPath);
          db.prepare(
            'INSERT OR REPLACE INTO songs (song_id,name,artist,album,cover_url,duration,file_path,size) VALUES (?,?,?,?,?,?,?,?)',
          ).run(
            id,
            songInfo.name || '',
            songInfo.artist || '',
            songInfo.album || '',
            songInfo.coverUrl || '',
            songInfo.duration || 0,
            finalPath,
            stat.size,
          );
          db.prepare('INSERT INTO play_history (song_id) VALUES (?)').run(id);
          console.log(`[SS] Saved verified: ${path.basename(finalPath)} (${(stat.size / 1048576).toFixed(2)}MB)`);
        } catch (error) {
          this._removeFile(partPath);
          this._removeFile(finalPath);
          this._deleteSongRecord(id);
          this._removeFile(path.join(this.lyricDir, `${id}.lrc`));
          this.activeSaves.delete(id);
          finishSave({ complete: false, reason: error.message });
          return;
        }
      } else {
        this._removeFile(partPath);
        this._removeFile(finalPath);
        this._deleteSongRecord(id);
        this._removeFile(path.join(this.lyricDir, `${id}.lrc`));
        console.warn(`[SS] Discarded incomplete save for ${id}: ${reason}`);
      }

      this.activeSaves.delete(id);
      finishSave({ complete, reason: complete ? 'verified' : reason });
    };

    try {
      const songUrl = songInfo.url || await this._fetchUrl(id);
      if (!songUrl) {
        this.activeSaves.delete(id);
        finishSave({ complete: false, reason: 'resource-unavailable' });
        return res.status(404).json({ error: '无法获取音乐资源' });
      }

      // Do not touch the music-cache volume during service startup or while
      // nobody is using the client. Directories are created only for a real
      // playback/save request.
      this._ensureCacheDirectories();
      const fileName = `${id}_${this._sanitize(songInfo.name || 'unknown')}_${this._sanitize(songInfo.artist || 'unknown')}.mp3`;
      finalPath = path.join(this.musicDir, fileName);
      partPath = `${finalPath}.part`;
      this._removeFile(partPath);
      this._removeFile(finalPath);

      const upstream = await axios({
        method: 'get',
        url: songUrl,
        responseType: 'stream',
        timeout: 30000,
      });
      source = upstream.data;
      const declaredLength = Number.parseInt(upstream.headers['content-length'], 10);
      expectedBytes = Number.isFinite(declaredLength) && declaredLength > 0 ? declaredLength : null;
      writeStream = fs.createWriteStream(partPath);

      res.setHeader('Content-Type', upstream.headers['content-type'] || 'audio/mpeg');
      if (expectedBytes != null) res.setHeader('Content-Length', expectedBytes);
      res.setHeader('X-Cache', 'MISS');
      res.setHeader('X-Song-Id', id);

      source.on('data', (chunk) => { receivedBytes += chunk.length; });
      source.on('end', () => { sourceEnded = true; });
      source.on('error', (error) => {
        sourceFailed = true;
        writeStream.destroy(error);
        if (!res.writableEnded) res.destroy(error);
      });
      writeStream.on('finish', () => settle('stream-ended'));
      writeStream.on('error', (error) => {
        sourceFailed = true;
        settle(error.message || 'write-failed');
      });
      res.once('close', () => {
        if (!res.writableEnded) {
          clientAborted = true;
          source.destroy();
          writeStream.destroy();
          settle('client-aborted');
        }
      });

      source.pipe(writeStream);
      source.pipe(res);
    } catch (error) {
      sourceFailed = true;
      if (writeStream) writeStream.destroy();
      settle(error.message || 'stream-failed');
      if (!res.headersSent) res.status(500).json({ error: '流传输失败' });
    }
  }

  // 在切换下一首前由客户端调用；会等待当前保存完成并清理任何残留。
  async finalizePlaybackSave(songId) {
    const id = String(songId);
    const active = this.activeSaves.get(id);
    if (active) return active.completion;

    const song = db.prepare('SELECT file_path, size FROM songs WHERE song_id = ?').get(id);
    if (song && this._isValidFile(song.file_path, song.size)) {
      return { complete: true, reason: 'cached' };
    }
    if (song) this._deleteSongRecord(id, song);
    return { complete: false, reason: 'not-saved' };
  }

  getPlaybackSource(songId) {
    const id = String(songId);
    const cached = db.prepare('SELECT file_path, size FROM songs WHERE song_id = ?').get(id);
    if (cached && this._isValidFile(cached.file_path, cached.size)) {
      return 'nas-cache';
    }
    if (cached) this._deleteSongRecord(id, cached);
    return 'netease';
  }

  async saveLyric(id, data) {
    if (!data?.lrc) return;
    this._ensureCacheDirectories();
    const lyricPath = path.join(this.lyricDir, `${id}.lrc`);
    fs.writeFileSync(lyricPath, data.lrc.lyric || '', 'utf-8');
    db.prepare('UPDATE songs SET lyric_path = ? WHERE song_id = ?').run(lyricPath, String(id));
  }

  async getLocalSongs() {
    const songs = db.prepare('SELECT * FROM songs WHERE file_path IS NOT NULL ORDER BY created_at DESC').all();
    return songs.filter((song) => {
      if (this._isValidFile(song.file_path, song.size)) return true;
      this._deleteSongRecord(song.song_id, song);
      return false;
    });
  }

  async deleteLocalSong(songId) {
    const song = db.prepare('SELECT file_path, lyric_path FROM songs WHERE song_id = ?').get(String(songId));
    this._deleteSongRecord(String(songId), song);
    this._removeFile(path.join(this.lyricDir, `${songId}.lrc`));
  }

  async _fetchUrl(id) {
    try {
      const response = await netease.getSongUrl(id, 'exhigh');
      return response?.data?.[0]?.url || null;
    } catch (_) {
      return null;
    }
  }

  _streamCachedFile(songId, songInfo, filePath, req, res) {
    const stat = fs.statSync(filePath);
    const size = stat.size;
    res.setHeader('Content-Type', 'audio/mpeg');
    res.setHeader('Accept-Ranges', 'bytes');
    res.setHeader('X-Cache', 'HIT');
    res.setHeader('X-Song-Id', songId);
    res.setHeader('X-Song-Name', encodeURIComponent(songInfo.name || ''));
    res.setHeader('X-Song-Artist', encodeURIComponent(songInfo.artist || ''));

    const range = req.headers.range;
    if (range) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(range);
      if (!match) {
        res.status(416).setHeader('Content-Range', `bytes */${size}`);
        return res.end();
      }
      const start = match[1] ? Number.parseInt(match[1], 10) : 0;
      const end = match[2] ? Math.min(Number.parseInt(match[2], 10), size - 1) : size - 1;
      if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || start > end || start >= size) {
        res.status(416).setHeader('Content-Range', `bytes */${size}`);
        return res.end();
      }
      res.status(206);
      res.setHeader('Content-Range', `bytes ${start}-${end}/${size}`);
      res.setHeader('Content-Length', end - start + 1);
      fs.createReadStream(filePath, { start, end }).pipe(res);
    } else {
      res.setHeader('Content-Length', size);
      fs.createReadStream(filePath).pipe(res);
    }
    db.prepare('INSERT INTO play_history (song_id) VALUES (?)').run(songId);
  }

  _isValidFile(filePath, expectedSize) {
    try {
      return Boolean(filePath) && fs.statSync(filePath).size > 0 && fs.statSync(filePath).size === Number(expectedSize);
    } catch (_) {
      return false;
    }
  }

  _deleteSongRecord(songId, song) {
    if (song?.file_path) this._removeFile(song.file_path);
    if (song?.lyric_path) this._removeFile(song.lyric_path);
    db.prepare('DELETE FROM songs WHERE song_id = ?').run(String(songId));
  }

  _removeFile(filePath) {
    if (!filePath) return;
    try { fs.unlinkSync(filePath); } catch (_) {}
  }

  _ensureCacheDirectories() {
    fs.mkdirSync(this.musicDir, { recursive: true });
    fs.mkdirSync(this.lyricDir, { recursive: true });
  }

  _sanitize(value) {
    return value.replace(/[\\/:*?"<>|]/g, '_').substring(0, 80);
  }
}

module.exports = new StreamSplitter();
