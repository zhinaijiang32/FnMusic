import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const _hostKey = 'server_host';
  static const _portKey = 'server_port';
  static const _tlsKey = 'server_use_tls';

  static const _defaultHost = String.fromEnvironment(
    'TUNECACHE_SERVER_HOST',
    defaultValue: 'localhost',
  );
  static const _defaultPort = int.fromEnvironment(
    'TUNECACHE_SERVER_PORT',
    defaultValue: 8443,
  );
  static const _defaultUseTls = bool.fromEnvironment(
    'TUNECACHE_USE_TLS',
    defaultValue: true,
  );

  static String serverHost = _defaultHost;
  static int serverPort = _defaultPort;
  static bool useTls = _defaultUseTls;

  static String get baseUrl {
    return '${useTls ? 'https' : 'http'}://$serverHost:$serverPort';
  }

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_hostKey)?.trim();
    final port = prefs.getInt(_portKey);
    if (host != null &&
        host.isNotEmpty &&
        port != null &&
        port > 0 &&
        port <= 65535) {
      serverHost = host;
      serverPort = port;
      useTls = prefs.getBool(_tlsKey) ?? _defaultUseTls;
    }
  }

  static Future<void> saveServer(String host, int port,
      {required bool tls}) async {
    serverHost = host;
    serverPort = port;
    useTls = tls;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host);
    await prefs.setInt(_portKey, port);
    await prefs.setBool(_tlsKey, tls);
  }
}
