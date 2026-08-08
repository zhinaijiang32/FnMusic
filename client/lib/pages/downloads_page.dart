import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/music_provider.dart';
import '../models/song.dart';
import '../widgets/music_tile.dart';
import 'now_playing_page.dart';

class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});
  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  List<Song> _s = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ref.read(musicProvider.notifier).getLocalSongs();
    setState(() => _s = s);
  }

  void _p(Song s) {
    ref.read(playbackQueueProvider.notifier).state = _s;
    ref.read(currentSongProvider.notifier).state = s;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
        appBar: AppBar(title: const Text('已下载的音乐')),
        body: _s.isEmpty
            ? const Center(child: Text('暂无已保存的音乐'))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                    itemCount: _s.length,
                    itemBuilder: (_, i) => MusicTile(
                        song: _s[i],
                        onTap: () => _p(_s[i]),
                        trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () async {
                              await ref
                                  .read(musicProvider.notifier)
                                  .deleteLocalSong(_s[i].id);
                              _load();
                            })))));
  }
}
