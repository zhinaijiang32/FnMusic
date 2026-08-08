import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  final _storage = const FlutterSecureStorage();
  static const _windowsSessionChannel = MethodChannel('fnmusic/session_store');
  String? _token;
  Map<String, dynamic>? _profile;
  late final Future<void> _ready;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 300),
      headers: {'Content-Type': 'application/json'},
      validateStatus: (_) => true,
    ));

    // 跳过自签名证书验证
    (_dio.httpClientAdapter as dynamic).onHttpClientCreate =
        (HttpClient client) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    };

    _ready = _init();
  }

  Future<void> _init() async {
    if (Platform.isWindows) {
      try {
        final raw = await _windowsSessionChannel.invokeMethod<String>('read');
        final session = _decodeWindowsSession(raw);
        if (session != null) {
          _token = session['token'] as String?;
          _profile = session['profile'] as Map<String, dynamic>?;
          return;
        }
      } catch (_) {
        // Keep the previous secure-storage path as a safe fallback.
      }

      // One-time migration from builds released before the fixed DPAPI store.
      _token = await _storage.read(key: 'auth_token');
      _profile = _decodeProfile(await _storage.read(key: 'auth_profile'));
      if (_token != null && _token!.isNotEmpty) {
        await _saveWindowsSession();
      }
      return;
    }

    _token = await _storage.read(key: 'auth_token');
    _profile = _decodeProfile(await _storage.read(key: 'auth_profile'));
  }

  Future<void> initialize() => _ready;

  Future<Map<String, dynamic>?> readStoredProfile() async {
    await _ready;
    return _profile == null ? null : Map<String, dynamic>.from(_profile!);
  }

  Map<String, dynamic>? _decodeProfile(String? raw) {
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _decodeWindowsSession(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map || value['token'] is! String) return null;
      final profile = value['profile'];
      return {
        'token': value['token'],
        if (profile is Map) 'profile': Map<String, dynamic>.from(profile),
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveWindowsSession() async {
    if (!Platform.isWindows || _token == null || _token!.isEmpty) return;
    try {
      await _windowsSessionChannel.invokeMethod<void>(
        'write',
        jsonEncode({'token': _token, 'profile': _profile}),
      );
    } catch (_) {
      // The legacy Flutter secure storage remains available as a fallback.
    }
  }

  Future<bool> hasStoredSession() async {
    await _ready;
    return _token != null && _token!.isNotEmpty;
  }

  Future<void> saveSession(String token, Map<String, dynamic> profile) async {
    _token = token;
    _profile = Map<String, dynamic>.from(profile);
    await _storage.write(key: 'auth_token', value: token);
    await _storage.write(key: 'auth_profile', value: jsonEncode(profile));
    await _saveWindowsSession();
  }

  Future<void> updateStoredProfile(Map<String, dynamic> profile) async {
    await _ready;
    _profile = Map<String, dynamic>.from(profile);
    await _storage.write(key: 'auth_profile', value: jsonEncode(profile));
    await _saveWindowsSession();
  }

  Future<void> setToken(String token) async {
    _token = token;
    await _storage.write(key: 'auth_token', value: token);
    await _saveWindowsSession();
  }

  Future<void> clearToken() async {
    _token = null;
    _profile = null;
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'auth_profile');
    if (Platform.isWindows) {
      try {
        await _windowsSessionChannel.invokeMethod<void>('clear');
      } catch (_) {
        // The legacy store has already been cleared above.
      }
    }
  }

  Future<String?> readStoredToken() async {
    await _ready;
    return _token;
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) async {
    await _ready;
    return _dio.get(path, queryParameters: params, options: _authOptions());
  }

  Future<Response> post(String path, {dynamic data}) async {
    await _ready;
    return _dio.post(path, data: data, options: _authOptions());
  }

  Future<Response> delete(String path) async {
    await _ready;
    return _dio.delete(path, options: _authOptions());
  }

  Options? _authOptions() {
    if (_token != null) {
      return Options(headers: {'Authorization': 'Bearer $_token'});
    }
    return null;
  }
}
