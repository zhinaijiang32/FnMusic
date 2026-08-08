import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../services/audio_player_service.dart';

class MusicNotifier extends StateNotifier<List<Song>> {
  final ApiService _api = ApiService();

  MusicNotifier() : super([]);

  Future<List<Song>> search(String keyword, {int limit = 30}) async {
    final res = await _api
        .get('/api/music/search', params: {'keyword': keyword, 'limit': limit});
    if (res.statusCode == 200 && res.data['success'] == true) {
      final result = res.data['data']['result'];
      if (result != null && result['songs'] != null) {
        final songs =
            (result['songs'] as List).map((s) => Song.fromJson(s)).toList();
        state = songs;
        return songs;
      }
    }
    return [];
  }

  Future<List<Song>> getRecommendSongs() async {
    final res = await _api.get('/api/music/recommend');
    if (res.statusCode == 200 && res.data['success'] == true) {
      final data = res.data['data']['data'];
      if (data != null && data['dailySongs'] != null) {
        final songs =
            (data['dailySongs'] as List).map((s) => Song.fromJson(s)).toList();
        state = songs;
        return songs;
      }
    }
    return [];
  }

  Future<List<Song>> getLocalSongs() async {
    final res = await _api.get('/api/downloads');
    if (res.statusCode == 200 && res.data['success'] == true) {
      return (res.data['data'] as List).map((s) => Song.fromJson(s)).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getUserPlaylists(int uid) async {
    final res = await _api.get('/api/music/user/playlist/$uid');
    if (res.statusCode == 200 && res.data['success'] == true) {
      final data = res.data['data'];
      final playlists = _nestedList(data, 'playlist');
      return playlists
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return [];
  }

  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final res = await _api.get('/api/music/playlist/$playlistId');
    if (res.statusCode == 200 && res.data['success'] == true) {
      final data = res.data['data'];
      final playlist = _nestedMap(data, 'playlist');
      final tracks = playlist?['tracks'];
      if (tracks is List) {
        return tracks
            .whereType<Map>()
            .map((item) => Song.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
    }
    return [];
  }

  Future<void> deleteLocalSong(String songId) async {
    await _api.delete('/api/downloads/$songId');
  }

  Future<bool> finalizePlaybackSave(String songId) async {
    final res = await _api.post('/api/downloads/$songId/finalize');
    return res.statusCode == 200 &&
        res.data is Map &&
        res.data['success'] == true &&
        res.data['data']?['complete'] == true;
  }

  Future<PlaybackSource> getPlaybackSource(String songId) async {
    try {
      final res = await _api.get('/api/music/source/$songId');
      if (res.statusCode == 200 &&
          res.data is Map &&
          res.data['success'] == true) {
        return switch (res.data['data']?['source']) {
          'nas-cache' => PlaybackSource.nasCache,
          'netease' => PlaybackSource.netease,
          _ => PlaybackSource.unavailable,
        };
      }
    } catch (_) {
      // Playback can still proceed when the optional status request fails.
    }
    return PlaybackSource.unavailable;
  }
}

List<dynamic> _nestedList(dynamic data, String key) {
  if (data is! Map) return const [];
  final direct = data[key];
  if (direct is List) return direct;
  final nested = data['data'];
  if (nested is Map && nested[key] is List) return nested[key] as List<dynamic>;
  return const [];
}

Map<String, dynamic>? _nestedMap(dynamic data, String key) {
  if (data is! Map) return null;
  final direct = data[key];
  if (direct is Map) return Map<String, dynamic>.from(direct);
  final nested = data['data'];
  if (nested is Map && nested[key] is Map) {
    return Map<String, dynamic>.from(nested[key] as Map);
  }
  return null;
}

final musicProvider =
    StateNotifierProvider<MusicNotifier, List<Song>>((ref) => MusicNotifier());
final currentSongProvider = StateProvider<Song?>((ref) => null);

enum PlaybackMode { sequence, shuffle, repeatOne }

enum PlaybackSource { checking, nasCache, netease, unavailable }

final playbackQueueProvider = StateProvider<List<Song>>((ref) => const []);
// One deterministic shuffle cycle. Keeping it separately lets the UI show the
// same upcoming order that the next/previous controls actually use.
final shuffledPlaybackQueueProvider =
    StateProvider<List<Song>>((ref) => const []);
final playbackModeProvider =
    StateProvider<PlaybackMode>((ref) => PlaybackMode.sequence);
final playbackSourceProvider = StateProvider<PlaybackSource?>((ref) => null);

final playbackControllerProvider = Provider<PlaybackController>(
  (ref) => PlaybackController(ref),
);

class PlaybackController {
  PlaybackController(this._ref);

  final Ref _ref;
  final _player = AudioPlayerService();

  Future<void> playSong(Song song, {bool preserveShuffleOrder = false}) async {
    if (_ref.read(playbackModeProvider) == PlaybackMode.shuffle &&
        !preserveShuffleOrder) {
      _resetShuffleOrder(song);
    }
    _ref.read(currentSongProvider.notifier).state = song;
    _ref.read(playbackSourceProvider.notifier).state = PlaybackSource.checking;

    // Probe before the streaming request. The server uses the identical cache
    // check when it opens the stream, so this describes the actual source.
    final source = _ref.read(musicProvider.notifier).getPlaybackSource(song.id);
    final token = await ApiService().readStoredToken();
    await _player.play(song.id, token);
    _ref.read(playbackSourceProvider.notifier).state = await source;
  }

  Future<void> skipNext({bool allowWrap = true}) => _skip(1, allowWrap);

  Future<void> skipPrevious() => _skip(-1, true);

  void setPlaybackMode(PlaybackMode mode) {
    _ref.read(playbackModeProvider.notifier).state = mode;
    if (mode == PlaybackMode.shuffle) {
      final current = _ref.read(currentSongProvider);
      if (current != null) _resetShuffleOrder(current);
    } else {
      _ref.read(shuffledPlaybackQueueProvider.notifier).state = const [];
    }
  }

  void _resetShuffleOrder(Song current) {
    final queue = _ref.read(playbackQueueProvider);
    final remaining = queue.where((song) => song.id != current.id).toList()
      ..shuffle();
    _ref.read(shuffledPlaybackQueueProvider.notifier).state = [
      current,
      ...remaining,
    ];
  }

  List<Song> _shuffleOrder(Song current, List<Song> queue) {
    final order = _ref.read(shuffledPlaybackQueueProvider);
    final orderMatchesQueue = order.length == queue.length &&
        order.every((song) => queue.any((item) => item.id == song.id));
    if (!orderMatchesQueue || !order.any((song) => song.id == current.id)) {
      _resetShuffleOrder(current);
      return _ref.read(shuffledPlaybackQueueProvider);
    }
    return order;
  }

  Future<void> _skip(int offset, bool allowWrap) async {
    final queue = _ref.read(playbackQueueProvider);
    final current = _ref.read(currentSongProvider);
    if (queue.isEmpty || current == null) return;

    if (queue.length == 1) {
      await _player.restart();
      return;
    }

    final mode = _ref.read(playbackModeProvider);
    if (mode == PlaybackMode.repeatOne) {
      await _player.restart();
      return;
    }
    final activeQueue =
        mode == PlaybackMode.shuffle ? _shuffleOrder(current, queue) : queue;
    final currentIndex =
        activeQueue.indexWhere((song) => song.id == current.id);
    final index = currentIndex < 0 ? 0 : currentIndex;
    final targetIndex = index + offset;
    if (!allowWrap && (targetIndex < 0 || targetIndex >= activeQueue.length)) {
      await _player.stop();
      return;
    }
    final normalizedIndex =
        (targetIndex + activeQueue.length) % activeQueue.length;
    await playSong(activeQueue[normalizedIndex],
        preserveShuffleOrder: mode == PlaybackMode.shuffle);
  }
}
