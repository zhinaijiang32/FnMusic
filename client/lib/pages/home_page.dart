import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/music_provider.dart';
import '../models/song.dart';
import '../widgets/music_tile.dart';
import 'now_playing_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(musicProvider.notifier).getRecommendSongs());
  }

  void _play(Song s) {
    ref.read(playbackQueueProvider.notifier).state = ref.read(musicProvider);
    ref.read(currentSongProvider.notifier).state = s;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
  }

  @override
  Widget build(BuildContext c) {
    final songs = ref.watch(musicProvider);
    return Scaffold(
        appBar: AppBar(title: const Text('每日推荐')),
        body: songs.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: songs.length,
                itemBuilder: (_, i) =>
                    MusicTile(song: songs[i], onTap: () => _play(songs[i]))));
  }
}
