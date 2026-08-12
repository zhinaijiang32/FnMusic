import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/theme.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/search_page.dart';
import 'pages/favorites_page.dart';
import 'pages/downloads_page.dart';
import 'pages/server_settings_page.dart';
import 'widgets/mini_player.dart';
import 'providers/auth_provider.dart';
import 'providers/music_provider.dart';

class TuneCacheApp extends ConsumerWidget {
  const TuneCacheApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: '音栈 TuneCache',
      debugShowCheckedModeBanner: false,
      theme: TuneCacheTheme.lightTheme,
      darkTheme: TuneCacheTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: authState.isInitializing
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (authState.isLoggedIn ? const TuneCacheShell() : const LoginPage()),
    );
  }
}

class TuneCacheShell extends ConsumerStatefulWidget {
  const TuneCacheShell({super.key});

  @override
  ConsumerState<TuneCacheShell> createState() => _TuneCacheShellState();
}

class _TuneCacheShellState extends ConsumerState<TuneCacheShell> {
  int _currentIndex = 0;

  final _pages = const [
    HomePage(),
    SearchPage(),
    FavoritesPage(),
    DownloadsPage(),
    ServerSettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final nowPlaying = ref.watch(currentSongProvider);

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: _pages[_currentIndex]),
          if (nowPlaying != null) MiniPlayer(key: ValueKey(nowPlaying.id)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(icon: Icon(Icons.favorite), label: '收藏'),
          NavigationDestination(icon: Icon(Icons.download), label: '已下载'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
