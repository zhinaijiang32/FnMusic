class Song {
  final String id;
  final String name;
  final String artist;
  final String album;
  final String coverUrl;
  final int duration;
  final String? localPath;
  final String? lyricPath;
  final int? fileSize;

  Song({
    required this.id,
    required this.name,
    required this.artist,
    this.album = '',
    this.coverUrl = '',
    this.duration = 0,
    this.localPath,
    this.lyricPath,
    this.fileSize,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    final albumData = json['al'] is Map
        ? Map<String, dynamic>.from(json['al'] as Map)
        : json['album'] is Map
            ? Map<String, dynamic>.from(json['album'] as Map)
            : const <String, dynamic>{};
    return Song(
      // 下载列表同时有数据库主键 id 和网易歌曲 ID song_id；播放和删除
      // 必须使用后者，否则会请求 /play/1 这类无效地址。
      id: json['song_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      artist: (json['ar'] is List)
          ? (json['ar'] as List).map((a) => a['name'] ?? '').join('/')
          : (json['artist'] ?? ''),
      album: albumData['name']?.toString() ?? (json['album'] ?? ''),
      coverUrl: _coverUrl(json, albumData),
      duration: (json['dt'] ?? json['duration'] ?? 0) as int,
      localPath: json['file_path'],
      lyricPath: json['lyric_path'],
      fileSize: json['size'],
    );
  }

  static String _coverUrl(
    Map<String, dynamic> json,
    Map<String, dynamic> album,
  ) {
    final candidates = [
      album['picUrl'],
      album['pic_url'],
      json['picUrl'],
      json['coverImgUrl'],
      json['coverUrl'],
      json['cover_url'],
    ];
    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return '';
  }

  String get durationText {
    final s = (duration / 1000).floor();
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }
}
