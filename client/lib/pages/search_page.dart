import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
                      itemBuilder: (_, i) =>
                          MusicTile(song: _r[i], onTap: () => _p(_r[i]))))
        ]));
  }
}
