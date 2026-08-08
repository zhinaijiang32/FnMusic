import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'dart:io';
import 'app.dart';
import 'config/app_config.dart';

class _FnMusicHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback =
        (certificate, host, port) => host == AppConfig.serverHost;
    return client;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _FnMusicHttpOverrides();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: FnMusicApp()));
}
