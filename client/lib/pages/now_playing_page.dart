import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../models/lyric_line.dart';
import '../models/song.dart';
import '../providers/music_provider.dart';
import '../services/api_service.dart';
import '../services/audio_player_service.dart';
import '../widgets/album_artwork.dart';

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage> {
  final _playerService = AudioPlayerService();
  final _api = ApiService();
  final List<LyricLine> _lyrics = [];
  StreamSubscription<bool>? _completedSubscription;
  bool _lyricsLoading = true;
  String? _lyricError;
  double? _draggingPositionMs;
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    _completedSubscription = _playerService.completedStream
        .where((completed) => completed)
        .listen((_) => _advanceAfterCompletion());
    ref.listenManual<Song?>(currentSongProvider, (previous, next) {
      if (next != null && previous?.id != next.id) {
        unawaited(_loadLyrics(next.id));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final song = ref.read(currentSongProvider);
    if (song == null) return;
    if (ref.read(playbackQueueProvider).isEmpty) {
      ref.read(playbackQueueProvider.notifier).state = [song];
    }
    await ref.read(playbackControllerProvider).playSong(song);
    unawaited(_loadLyrics(song.id));
  }

  Future<void> _advanceAfterCompletion() async {
    if (!mounted || _advancing) return;
    _advancing = true;
    try {
      final current = ref.read(currentSongProvider);
      if (current == null) return;
      await ref.read(musicProvider.notifier).finalizePlaybackSave(current.id);
      if (!mounted) return;
      final mode = ref.read(playbackModeProvider);
      final queue = ref.read(playbackQueueProvider);
      if (mode == PlaybackMode.repeatOne || queue.length <= 1) {
        await _playerService.restart();
        return;
      }
      await ref
          .read(playbackControllerProvider)
          .skipNext(allowWrap: mode == PlaybackMode.shuffle);
    } finally {
      _advancing = false;
    }
  }

  Future<void> _skipNext() => ref.read(playbackControllerProvider).skipNext();

  Future<void> _skipPrevious() =>
      ref.read(playbackControllerProvider).skipPrevious();

  void _cyclePlaybackMode() {
    final current = ref.read(playbackModeProvider);
    final next = switch (current) {
      PlaybackMode.sequence => PlaybackMode.shuffle,
      PlaybackMode.shuffle => PlaybackMode.repeatOne,
      PlaybackMode.repeatOne => PlaybackMode.sequence,
    };
    ref.read(playbackControllerProvider).setPlaybackMode(next);
    final text = switch (next) {
      PlaybackMode.sequence => '顺序播放',
      PlaybackMode.shuffle => '随机播放',
      PlaybackMode.repeatOne => '单曲循环',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  IconData _playbackModeIcon(PlaybackMode mode) => switch (mode) {
        PlaybackMode.sequence => Icons.format_list_numbered,
        PlaybackMode.shuffle => Icons.shuffle,
        PlaybackMode.repeatOne => Icons.repeat_one,
      };

  String _playbackModeLabel(PlaybackMode mode) => switch (mode) {
        PlaybackMode.sequence => '顺序播放',
        PlaybackMode.shuffle => '随机播放',
        PlaybackMode.repeatOne => '单曲循环',
      };

  Future<void> _loadLyrics(String songId) async {
    setState(() {
      _lyricsLoading = true;
      _lyricError = null;
      _lyrics.clear();
    });
    try {
      final response = await _api.get('/api/music/lyric/$songId');
      final lyric = _extractLyric(response.data);
      if (!mounted) return;
      setState(() {
        _lyrics.addAll(LyricLine.parse(lyric ?? ''));
        _lyricsLoading = false;
        if (_lyrics.isEmpty) _lyricError = '暂无歌词';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _lyricsLoading = false;
          _lyricError = '歌词加载失败';
        });
      }
    }
  }

  String? _extractLyric(dynamic payload) {
    if (payload is! Map) return null;
    final data = payload['data'];
    final candidate = data is Map ? data : payload;
    final lrc = candidate['lrc'];
    if (lrc is Map && lrc['lyric'] is String) return lrc['lyric'] as String;
    final nested = candidate['data'];
    if (nested is Map && nested['lrc'] is Map) {
      final nestedLrc = nested['lrc'];
      if (nestedLrc['lyric'] is String) return nestedLrc['lyric'] as String;
    }
    return null;
  }

  int _activeLyricIndex(Duration position) {
    for (var index = _lyrics.length - 1; index >= 0; index--) {
      if (position >= _lyrics[index].timestamp) return index;
    }
    return 0;
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _progressBar() {
    return StreamBuilder<Duration>(
      stream: _playerService.durationStream,
      initialData: _playerService.player.state.duration,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        if (duration <= Duration.zero) return const SizedBox(height: 28);

        return StreamBuilder<Duration>(
          stream: _playerService.positionStream,
          initialData: _playerService.player.state.position,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final maximum = duration.inMilliseconds.toDouble();
            final value =
                (_draggingPositionMs ?? position.inMilliseconds.toDouble())
                    .clamp(0, maximum)
                    .toDouble();
            return Column(children: [
              Slider(
                value: value,
                min: 0,
                max: maximum,
                onChanged: (next) => setState(() => _draggingPositionMs = next),
                onChangeEnd: (next) async {
                  await _playerService.seek(
                    Duration(milliseconds: next.round()),
                  );
                  if (mounted) setState(() => _draggingPositionMs = null);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        _formatDuration(Duration(milliseconds: value.round()))),
                    Text(_formatDuration(duration)),
                  ],
                ),
              ),
            ]);
          },
        );
      },
    );
  }

  Future<void> _chooseAudioDevice() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: StreamBuilder<List<AudioDevice>>(
          stream: _playerService.audioDevicesStream,
          initialData: _playerService.audioDevices,
          builder: (context, snapshot) {
            final devices = snapshot.data ?? const <AudioDevice>[];
            final selected = _playerService.selectedAudioDevice;
            return ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                  title: Text('选择音频输出设备'),
                  subtitle: Text('仅切换飞牛音乐的播放输出'),
                ),
                RadioListTile<String>(
                  value: 'auto',
                  groupValue: selected.name,
                  title: const Text('跟随系统默认设备'),
                  onChanged: (_) async {
                    await _playerService.useSystemDefaultAudioDevice();
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
                if (devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('正在读取可用音频设备，请稍候…'),
                  ),
                ...devices.map(
                  (device) => RadioListTile<String>(
                    value: device.name,
                    groupValue: selected.name,
                    title: Text(device.description.isEmpty
                        ? device.name
                        : device.description),
                    subtitle:
                        device.description.isEmpty ? null : Text(device.name),
                    onChanged: (_) async {
                      await _playerService.selectAudioDevice(device);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _completedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(currentSongProvider);
    final mode = ref.watch(playbackModeProvider);
    final source = ref.watch(playbackSourceProvider);
    if (song == null) {
      return const Scaffold(body: Center(child: Text('无歌曲')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        actions: [
          if (!Platform.isAndroid && !Platform.isIOS)
            IconButton(
              tooltip: '选择输出设备',
              onPressed: _chooseAudioDevice,
              icon: const Icon(Icons.speaker),
            ),
          IconButton(
            tooltip: _playbackModeLabel(mode),
            onPressed: _cyclePlaybackMode,
            icon: Icon(_playbackModeIcon(mode)),
          ),
          IconButton(
            tooltip: '当前播放列表',
            onPressed: _showPlaybackQueue,
            icon: const Icon(Icons.queue_music),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final lyrics = _lyricsPanel();
          final player = _playerPanel(song, source, constraints.maxWidth);
          final isMobile = Platform.isAndroid || Platform.isIOS;
          if (!isMobile && constraints.maxWidth >= 780) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Row(children: [
                Expanded(flex: 9, child: lyrics),
                const VerticalDivider(width: 48),
                Expanded(flex: 11, child: player),
              ]),
            );
          }
          return ListView(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            children: [
              SizedBox(height: isMobile ? 410 : 440, child: player),
              SizedBox(height: isMobile ? 16 : 24),
              SizedBox(height: isMobile ? 340 : 380, child: lyrics)
            ],
          );
        },
      ),
    );
  }

  List<Song> _displayQueue(
    List<Song> queue,
    List<Song> shuffledQueue,
    Song current,
    PlaybackMode mode,
  ) {
    if (mode == PlaybackMode.repeatOne) return [current];
    final source = mode == PlaybackMode.shuffle && shuffledQueue.isNotEmpty
        ? shuffledQueue
        : queue;
    final index = source.indexWhere((song) => song.id == current.id);
    if (index < 0) return [current, ...source];
    if (mode == PlaybackMode.sequence) return source.sublist(index);
    return [...source.sublist(index), ...source.sublist(0, index)];
  }

  String _queueSubtitle(PlaybackMode mode, int count) => switch (mode) {
        PlaybackMode.sequence => '顺序播放 · 接下来 $count 首',
        PlaybackMode.shuffle => '随机播放 · 本轮顺序 $count 首',
        PlaybackMode.repeatOne => '单曲循环 · 仅当前歌曲',
      };

  void _showPlaybackQueue() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final current = ref.watch(currentSongProvider);
          final mode = ref.watch(playbackModeProvider);
          final queue = ref.watch(playbackQueueProvider);
          final shuffledQueue = ref.watch(shuffledPlaybackQueueProvider);
          if (current == null) return const SizedBox.shrink();
          final songs = _displayQueue(queue, shuffledQueue, current, mode);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .72,
              child: Column(children: [
                ListTile(
                  leading: Icon(_playbackModeIcon(mode)),
                  title: const Text('当前播放列表'),
                  subtitle: Text(_queueSubtitle(mode, songs.length)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final item = songs[index];
                      final isCurrent = item.id == current.id;
                      return ListTile(
                        leading: SizedBox(
                          width: 28,
                          child: isCurrent
                              ? Icon(Icons.equalizer,
                                  color: Theme.of(context).colorScheme.primary)
                              : Text('${index + 1}',
                                  textAlign: TextAlign.center),
                        ),
                        title: Text(item.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(item.artist,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(item.durationText),
                        selected: isCurrent,
                        onTap: () async {
                          await ref
                              .read(playbackControllerProvider)
                              .playSong(item);
                          if (context.mounted) Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _lyricsPanel() {
    if (_lyricsLoading) return const Center(child: CircularProgressIndicator());
    if (_lyricError != null) return Center(child: Text(_lyricError!));

    return StreamBuilder<Duration>(
      stream: _playerService.positionStream,
      initialData: _playerService.player.state.position,
      builder: (context, snapshot) {
        final active = _activeLyricIndex(snapshot.data ?? Duration.zero);
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 32),
          itemCount: _lyrics.length,
          itemBuilder: (context, index) {
            final isActive = index == active;
            return AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 2.1,
                  ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(_lyrics[index].text, textAlign: TextAlign.center),
              ),
            );
          },
        );
      },
    );
  }

  Widget _playerPanel(
    Song song,
    PlaybackSource? source,
    double availableWidth,
  ) {
    final spectrumSize =
        math.min(math.max(availableWidth - 28, 230), 390).toDouble();
    final artworkSize = spectrumSize - 86;
    return Center(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          StreamBuilder<double>(
            stream: _playerService.volumeStream,
            initialData: _playerService.volume,
            builder: (context, snapshot) {
              final volume = snapshot.data ?? 100;
              return StreamBuilder<List<double>>(
                stream: _playerService.audioSpectrumStream,
                initialData: const <double>[],
                builder: (context, spectrumSnapshot) {
                  final scheme = Theme.of(context).colorScheme;
                  return TweenAnimationBuilder<List<double>>(
                    duration: const Duration(milliseconds: 115),
                    curve: Curves.easeOutCubic,
                    tween: _SpectrumTween(
                      end: spectrumSnapshot.data ?? const <double>[],
                    ),
                    builder: (context, interpolatedSpectrum, child) => SizedBox(
                      width: spectrumSize,
                      height: spectrumSize,
                      child: CustomPaint(
                        painter: _CircularSpectrumPainter(
                          volume: volume,
                          spectrum: interpolatedSpectrum,
                          background: scheme.surface,
                          accent: scheme.primary,
                        ),
                        child: child,
                      ),
                    ),
                    child: Center(
                      child: AlbumArtwork(
                        url: song.coverUrl,
                        width: artworkSize,
                        height: artworkSize,
                        borderRadius: artworkSize,
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 28),
          Text(song.name,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(song.artist,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: 10),
          _PlaybackSourceBadge(source: source),
          const SizedBox(height: 20),
          StreamBuilder<bool>(
            stream: _playerService.playingStream,
            initialData: _playerService.isPlaying,
            builder: (_, snapshot) {
              final playing = snapshot.data ?? false;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '上一首',
                    iconSize: 42,
                    icon: const Icon(Icons.skip_previous_rounded),
                    onPressed: _skipPrevious,
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    tooltip: playing ? '暂停' : '播放',
                    iconSize: 64,
                    icon: Icon(playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled),
                    onPressed: () => playing
                        ? _playerService.pause()
                        : _playerService.resume(),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    tooltip: '下一首',
                    iconSize: 42,
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: _skipNext,
                  ),
                ],
              );
            },
          ),
          _progressBar(),
          const SizedBox(height: 8),
          StreamBuilder<double>(
            stream: _playerService.volumeStream,
            initialData: _playerService.volume,
            builder: (context, snapshot) {
              final volume = snapshot.data ?? 100;
              return Row(children: [
                const Icon(Icons.volume_down),
                Expanded(
                  child: Slider(
                    value: volume.clamp(0, 100).toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${volume.round()}%',
                    onChanged: _playerService.setVolume,
                  ),
                ),
                const Icon(Icons.volume_up),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

class _SpectrumTween extends Tween<List<double>> {
  _SpectrumTween({required super.end});

  @override
  List<double> lerp(double t) {
    final start = begin ?? const <double>[];
    final target = end ?? const <double>[];
    const bars = 64;
    return List<double>.generate(bars, (index) {
      final from = index < start.length ? start[index] : 0.0;
      final to = index < target.length ? target[index] : 0.0;
      return from + ((to - from) * t);
    }, growable: false);
  }
}

class _CircularSpectrumPainter extends CustomPainter {
  const _CircularSpectrumPainter({
    required this.volume,
    required this.spectrum,
    required this.background,
    required this.accent,
  });

  final double volume;
  final List<double> spectrum;
  final Color background;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 64;
    const barWidth = 3.2;
    final center = Offset(size.width / 2, size.height / 2);
    final innerRadius = size.shortestSide / 2 - 38;
    final intensity = (volume / 100).clamp(0.0, 1.0).toDouble();
    final baseColor = Color.lerp(background, accent, .48)!;

    for (var index = 0; index < barCount; index++) {
      final angle = (math.pi * 2 * index / barCount) - math.pi / 2;
      // Each radial bar receives its own FFT band. No decorative sine wave is
      // mixed in, so bass, vocals, and treble visibly move independently.
      final band = index < spectrum.length ? spectrum[index] : 0.0;
      final amplitude = (band * (.25 + (.75 * intensity))).clamp(0.0, 1.0);
      // 40.92 is 20% above the previous 34.1px maximum amplitude.
      final length = 3 + (40.92 * amplitude);
      final alpha = .28 + (.56 * amplitude);
      final paint = Paint()
        ..color = baseColor.withValues(alpha: alpha.clamp(0, 1).toDouble())
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;

      final start = Offset(
        center.dx + math.cos(angle) * innerRadius,
        center.dy + math.sin(angle) * innerRadius,
      );
      final end = Offset(
        center.dx + math.cos(angle) * (innerRadius + length),
        center.dy + math.sin(angle) * (innerRadius + length),
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CircularSpectrumPainter oldDelegate) =>
      oldDelegate.volume != volume ||
      oldDelegate.spectrum != spectrum ||
      oldDelegate.background != background ||
      oldDelegate.accent != accent;
}

class _PlaybackSourceBadge extends StatelessWidget {
  const _PlaybackSourceBadge({required this.source});

  final PlaybackSource? source;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (source) {
      PlaybackSource.nasCache => ('NAS 缓存', Icons.dns_rounded, Colors.teal),
      PlaybackSource.netease => ('网易云服务器', Icons.cloud_rounded, Colors.blue),
      PlaybackSource.checking => ('正在检测播放来源', Icons.sync_rounded, Colors.grey),
      _ => ('播放来源未知', Icons.help_outline_rounded, Colors.grey),
    };
    return Chip(
      avatar: Icon(icon, color: color, size: 17),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: .35)),
      visualDensity: VisualDensity.compact,
    );
  }
}
