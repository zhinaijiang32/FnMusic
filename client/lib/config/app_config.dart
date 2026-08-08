class AppConfig {
  static String serverHost = const String.fromEnvironment(
    'FNMUSIC_SERVER_HOST',
    defaultValue: 'localhost',
  );
  static int serverPort = const int.fromEnvironment(
    'FNMUSIC_SERVER_PORT',
    defaultValue: 8443,
  );
  static bool useTls = const bool.fromEnvironment(
    'FNMUSIC_USE_TLS',
    defaultValue: true,
  );

  static String get baseUrl {
    return '${useTls ? "https" : "http"}://$serverHost:$serverPort';
  }

  static void setServer(String host, int port, {bool tls = true}) {
    serverHost = host;
    serverPort = port;
    useTls = tls;
  }
}
