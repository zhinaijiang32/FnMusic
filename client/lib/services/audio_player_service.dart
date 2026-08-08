import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../config/app_config.dart';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;

  final Player _player = Player();
  String? _currentSongId;
  final _spectrumController = StreamController<List<double>>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  Timer? _spectrumTimer;
  bool _readingSpectrum = false;
  List<double>? _smoothedSpectrum;
  bool _isPlaying = false;
  static const _audioMeter = MethodChannel('fnmusic/audio_meter');

  AudioPlayerService._internal() {
    _player.stream.playing.listen(_publishPlaying);
    if (Platform.isWindows || Platform.isAndroid) {
      _spectrumTimer = Timer.periodic(
        const Duration(milliseconds: 70),
        (_) => _readOutputSpectrum(),
      );
    }
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(_configureMobileTls());
    }
  }

  Future<void> _configureMobileTls() async {
    // 手机端仍连接局域网 NAS 的自签名 HTTPS 服务。libmpv 不会使用
    // Dart 的 HttpOverrides，因此仅对移动端播放器禁用该服务器的证书校验。
    try {
      await (_player.platform as dynamic).setProperty('tls-verify', 'no');
    } catch (_) {
      // 某些播放器后端不暴露该底层选项；Dio 请求仍会使用 HttpOverrides。
    }
  }

  Player get player => _player;

  Future<void> play(String songId, String? token) async {
    // The now-playing page may be opened again from the mini player.  Keep the
    // existing stream and position when it is already the selected song.
    if (_currentSongId == songId) {
      if (_player.state.completed) {
        await restart();
      } else if (!_player.state.playing) {
        await _player.play();
        _publishPlaying(true);
      }
      return;
    }

    final url = '${AppConfig.baseUrl}/api/music/play/$songId';
    try {
      await _player.open(
        Media(
          url,
          httpHeaders: token != null ? {'Authorization': 'Bearer $token'} : {},
        ),
        play: true,
      );
      _currentSongId = songId;
      // Some Android media backends publish the first `playing` event after
      // buffering starts. Update the UI intent immediately, then keep it in
      // sync with the backend stream above.
      _publishPlaying(true);
    } catch (e) {
      throw Exception('播放失败: $e');
    }
  }

  Future<void> pause() async {
    await _player.pause();
    _publishPlaying(false);
  }

  Future<void> resume() async {
    await _player.play();
    _publishPlaying(true);
  }

  Future<void> stop() async {
    await _player.stop();
    _publishPlaying(false);
  }

  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> restart() async {
    await _player.seek(Duration.zero);
    await _player.play();
    _publishPlaying(true);
  }

  Stream<Duration> get positionStream => _player.stream.position;
  Stream<Duration> get durationStream => _player.stream.duration;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<bool> get completedStream => _player.stream.completed;
  bool get isPlaying => _isPlaying;
  Stream<double> get volumeStream => _player.stream.volume;
  double get volume => _player.state.volume;
  Stream<List<double>> get audioSpectrumStream => _spectrumController.stream;

  Future<void> setVolume(double value) =>
      _player.setVolume(value.clamp(0, 100).toDouble());

  List<AudioDevice> get audioDevices => _player.state.audioDevices;
  AudioDevice get selectedAudioDevice => _player.state.audioDevice;
  Stream<List<AudioDevice>> get audioDevicesStream =>
      _player.stream.audioDevices;

  Future<void> selectAudioDevice(AudioDevice device) =>
      _player.setAudioDevice(device);

  Future<void> useSystemDefaultAudioDevice() =>
      _player.setAudioDevice(AudioDevice.auto());

  Future<void> _readOutputSpectrum() async {
    if (_readingSpectrum) return;
    _readingSpectrum = true;
    try {
      final data = await _audioMeter.invokeMethod<List<dynamic>>(
        'getOutputSpectrum',
        {
          'deviceId': _player.state.audioDevice.name,
        },
      );
      if (data != null) {
        final spectrum = data
            .whereType<num>()
            .map((value) => value.clamp(0, 1).toDouble())
            .toList(growable: false);
        if (spectrum.length == 64) {
          final previous = _smoothedSpectrum;
          // Fast attack keeps kicks and transients responsive; slower release
          // prevents adjacent measurements from looking like visual jumps.
          final smoothed = List<double>.generate(64, (index) {
            final prior = previous?[index] ?? spectrum[index];
            final factor = spectrum[index] > prior ? 0.88 : 0.34;
            return prior + ((spectrum[index] - prior) * factor);
          }, growable: false);
          _smoothedSpectrum = smoothed;
          _spectrumController.add(smoothed);
        }
      }
    } catch (_) {
      // Audio visualisation is optional; playback must continue if the meter
      // cannot access an endpoint.
    } finally {
      _readingSpectrum = false;
    }
  }

  void _publishPlaying(bool playing) {
    if (_isPlaying == playing) return;
    _isPlaying = playing;
    _playingController.add(playing);
  }

  void dispose() {
    _spectrumTimer?.cancel();
    _spectrumController.close();
    _playingController.close();
    _player.dispose();
  }
}
