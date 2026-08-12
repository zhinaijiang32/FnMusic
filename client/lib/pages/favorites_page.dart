import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../providers/auth_provider.dart';
import '../providers/music_provider.dart';
import '../widgets/music_tile.dart';
import 'now_playing_page.dart';

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  List<Map<String, dynamic>> _playlists = const [];
  List<Song> _songs = const [];
  Map<String, dynamic>? _selectedPlaylist;
  final _searchController = TextEditingController();
  final Set<String> _pendingLikeChanges = <String>{};
  String _searchQuery = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadPlaylists);
  }

  Future<void> _loadPlaylists() async {
    final uid = ref.read(authProvider).uid;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '请先登录网易云音乐';
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final playlists =
          await ref.read(musicProvider.notifier).getUserPlaylists(uid);
      if (!mounted) return;
      if (playlists.isEmpty) {
        setState(() {
          _playlists = const [];
          _songs = const [];
          _selectedPlaylist = null;
          _loading = false;
          _error = '未找到收藏歌单';
        });
        return;
      }

      final preferred = _likedPlaylist(playlists) ?? playlists.first;
      setState(() => _playlists = playlists);
      await _openPlaylist(preferred);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载收藏歌单失败，请检查网络后重试';
        });
      }
    }
  }

  Map<String, dynamic>? _likedPlaylist(List<Map<String, dynamic>> playlists) {
    for (final playlist in playlists) {
      if (_isLikedPlaylist(playlist)) {
        return playlist;
      }
    }
    return null;
  }

  bool _isLikedPlaylist(Map<String, dynamic>? playlist) =>
      playlist?['specialType']?.toString() == '5' ||
      playlist?['name'] == '我喜欢的音乐';

  Future<void> _openPlaylist(Map<String, dynamic> playlist) async {
    final id = playlist['id']?.toString();
    if (id == null || id.isEmpty) return;

    setState(() {
      _selectedPlaylist = playlist;
      _loading = true;
      _error = null;
      _songs = const [];
      _searchQuery = '';
      _searchController.clear();
    });

    try {
      final songs = await ref.read(musicProvider.notifier).getPlaylistSongs(id);
      if (mounted) {
        setState(() {
          _songs = songs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载歌曲失败，请稍后重试';
        });
      }
    }
  }

  void _play(Song song) {
    ref.read(playbackQueueProvider.notifier).state = _filteredSongs;
    ref.read(currentSongProvider.notifier).state = song;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NowPlayingPage()),
    );
  }

  List<Song> get _filteredSongs {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _songs;
    return _songs.where((song) {
      return song.name.toLowerCase().contains(query) ||
          song.artist.toLowerCase().contains(query) ||
          song.album.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _setSongLiked(Song song, bool liked) async {
    if (_pendingLikeChanges.contains(song.id)) return;
    setState(() => _pendingLikeChanges.add(song.id));
    try {
      await ref
          .read(musicProvider.notifier)
          .setSongLiked(song.id, liked: liked);
      if (!mounted) return;
      setState(() {
        if (!liked && _isLikedPlaylist(_selectedPlaylist)) {
          _songs = _songs.where((item) => item.id != song.id).toList();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(liked ? '已收藏到网易云“我喜欢的音乐”' : '已取消网易云收藏')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingLikeChanges.remove(song.id));
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的收藏'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _loadPlaylists,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _selectedPlaylist == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _selectedPlaylist == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _loadPlaylists, child: const Text('重试')),
          ]),
        ),
      );
    }

    final selected = _selectedPlaylist;
    final songs = _filteredSongs;
    final isLikedPlaylist = _isLikedPlaylist(selected);
    return RefreshIndicator(
      onRefresh: _loadPlaylists,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (selected != null) _playlistHeader(selected),
          if (!_loading && selected != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: '搜索此收藏列表中的歌曲、歌手或专辑',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_songs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('这个歌单还没有歌曲')),
            )
          else if (songs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('没有匹配的收藏音乐')),
            )
          else
            ...songs.map(
              (song) => MusicTile(
                song: song,
                onTap: () => _play(song),
                trailing: isLikedPlaylist
                    ? IconButton(
                        tooltip: '取消网易云收藏',
                        icon: _pendingLikeChanges.contains(song.id)
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.favorite,
                                color: Colors.redAccent),
                        onPressed: _pendingLikeChanges.contains(song.id)
                            ? null
                            : () => _setSongLiked(song, false),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _playlistHeader(Map<String, dynamic> playlist) {
    final name = playlist['name']?.toString() ?? '收藏歌单';
    final trackCount = playlist['trackCount'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(children: [
        const CircleAvatar(child: Icon(Icons.favorite)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              if (trackCount != null) Text('$trackCount 首歌曲'),
            ],
          ),
        ),
        PopupMenuButton<Map<String, dynamic>>(
          tooltip: '切换歌单',
          onSelected: _openPlaylist,
          itemBuilder: (context) => _playlists
              .map(
                (item) => PopupMenuItem(
                  value: item,
                  child: Text(item['name']?.toString() ?? '未命名歌单'),
                ),
              )
              .toList(),
        ),
      ]),
    );
  }
}
