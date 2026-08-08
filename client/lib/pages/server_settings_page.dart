import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_service.dart';

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  late final TextEditingController _urlController;
  bool _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: AppConfig.baseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final raw = _urlController.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      setState(() => _status = '请输入完整服务器地址，例如 https://192.168.2.6:8443');
      return;
    }

    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    setState(() {
      _saving = true;
      _status = null;
    });

    await AppConfig.saveServer(uri.host, port, tls: uri.scheme == 'https');
    ApiService().refreshServerConfig();

    try {
      final response = await ApiService().get('/api/health');
      if (response.statusCode == 200 &&
          response.data is Map &&
          response.data['status'] == 'ok') {
        _urlController.text = AppConfig.baseUrl;
        if (mounted) {
          setState(() => _status = '已保存，服务器连接正常。');
        }
      } else if (mounted) {
        setState(() => _status = '地址已保存，但服务器未返回健康检查结果。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = '地址已保存，但暂时无法连接服务器。请检查地址、端口和 HTTPS 设置。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器连接')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.dns_rounded, size: 52, color: Colors.deepPurple),
          const SizedBox(height: 16),
          Text(
            '输入 FnMusic 服务端地址',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            '支持 HTTP 或 HTTPS。保存后会立即用于登录、播放和下载，并在下次启动时自动恢复。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://192.168.2.6:8443',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saving ? null : _saveAndTest(),
          ),
          const SizedBox(height: 12),
          Text(
            '请不要附加 /api 或其他路径。',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveAndTest,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? '正在测试连接…' : '保存并测试连接'),
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_status!, textAlign: TextAlign.center),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
