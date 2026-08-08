import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/music_provider.dart';
import '../pages/now_playing_page.dart';
import '../services/audio_player_service.dart';
import 'album_artwork.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    final source = ref.watch(playbackSourceProvider);
    final playback = ref.read(playbackControllerProvider);
    final player = AudioPlayerService();
    if (song == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border:
              Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SafeArea(
          child: Row(
            children: [
              AlbumArtwork(
                url: song.coverUrl,
                width: 40,
                height: 40,
                borderRadius: 4,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    if (source != null)
                      Text(
                        switch (source) {
                          PlaybackSource.nasCache => 'NAS 缓存',
                          PlaybackSource.netease => '网易云服务器',
                          PlaybackSource.checking => '检测播放来源…',
                          PlaybackSource.unavailable => '来源未知',
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '上一首',
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: playback.skipPrevious,
              ),
              StreamBuilder<bool>(
                stream: player.playingStream,
                initialData: player.isPlaying,
                builder: (context, snapshot) {
                  final playing = snapshot.data ?? false;
                  return IconButton(
                    tooltip: playing ? '暂停' : '播放',
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: playing ? player.pause : player.resume,
                  );
                },
              ),
              IconButton(
                tooltip: '下一首',
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: playback.skipNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
