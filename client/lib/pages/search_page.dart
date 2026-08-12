import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/music_provider.dart';
import '../models/song.dart';
import '../widgets/music_tile.dart';
import 'now_playing_page.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _c = TextEditingController();
  List<Song> _r = [];
  final Set<String> _pendingLikes = <String>{};
  final Set<String> _likedInSearch = <String>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadLikedSongIds);
    ref.listenManual<AuthState>(authProvider, (previous, next) {
      if (previous?.uid != next.uid && next.uid != null) {
        _loadLikedSongIds();
      }
    });
  }

  Future<void> _loadLikedSongIds() async {
    final uid = ref.read(authProvider).uid;
    if (uid == null) return;
    try {
      final ids = await ref.read(musicProvider.notifier).getLikedSongIds(uid);
      if (mounted) setState(() => _likedInSearch.addAll(ids));
    } catch (_) {
      // Collection state is optional for search. The action itself still
      // returns any real Netease error when the user taps the button.
    }
  }

  void _s() async {
    if (_c.text.trim().isEmpty) return;
    final r = await ref.read(musicProvider.notifier).search(_c.text.trim());
    setState(() => _r = r);
  }

  void _p(Song s) {
    ref.read(playbackQueueProvider.notifier).state = _r;
    ref.read(currentSongProvider.notifier).state = s;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
  }

  Future<void> _setSongLiked(Song song, bool liked) async {
    if (_pendingLikes.contains(song.id)) return;
    setState(() => _pendingLikes.add(song.id));
    try {
      await ref
          .read(musicProvider.notifier)
          .setSongLiked(song.id, liked: liked);
      if (!mounted) return;
      setState(() {
        if (liked) {
          _likedInSearch.add(song.id);
        } else {
          _likedInSearch.remove(song.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(liked ? '已收藏到网易云“我喜欢的音乐”' : '已取消网易云收藏'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _pendingLikes.remove(song.id));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
        appBar: AppBar(title: const Text('搜索音乐')),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                  controller: _c,
                  decoration: InputDecoration(
                      hintText: '搜索歌曲、歌手...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                          icon: const Icon(Icons.send), onPressed: _s),
                      border: const OutlineInputBorder()),
                  onSubmitted: (_) => _s())),
          Expanded(
              child: _r.isEmpty
                  ? const Center(child: Text('输入关键词搜索'))
                  : ListView.builder(
                      itemCount: _r.length,
                      itemBuilder: (_, i) {
                        final song = _r[i];
                        final pending = _pendingLikes.contains(song.id);
                        final liked = _likedInSearch.contains(song.id);
                        return MusicTile(
                          song: song,
                          onTap: () => _p(song),
                          trailing: IconButton(
                            tooltip: liked ? '取消网易云收藏' : '收藏到网易云',
                            onPressed: pending
                                ? null
                                : () => _setSongLiked(song, !liked),
                            icon: pending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(
                                    liked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: liked ? Colors.redAccent : null,
                                  ),
                          ),
                        );
                      }))
        ]));
  }
}
