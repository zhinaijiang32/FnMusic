import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/auth_provider.dart';
import 'server_settings_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _pc = TextEditingController(), _pwc = TextEditingController();
  final _captchaController = TextEditingController();
  bool _loading = false;
  String? _info;
  bool _showQr = false;
  bool _showSms = false;
  bool _showEmail = false;
  String? _qrContent;
  String? _qrKey;
  Timer? _pollTimer;
  Timer? _smsTimer;
  int _pollCount = 0;
  int _qrGeneration = 0;
  int _smsSecondsLeft = 0;

  @override
  void dispose() {
    _pc.dispose();
    _pwc.dispose();
    _captchaController.dispose();
    _pollTimer?.cancel();
    _smsTimer?.cancel();
    super.dispose();
  }

  // 生成新的二维码
  Future<void> _newQr() async {
    final generation = ++_qrGeneration;
    _pollTimer?.cancel();
    setState(() {
      _showQr = true;
      _showSms = false;
      _showEmail = false;
      _loading = true;
      _info = '正在生成二维码...';
      _pollCount = 0;
    });
    setState(() {
      _qrContent = null;
      _qrKey = null;
    });
    try {
      final keyResult = await ref.read(authProvider.notifier).getQrKey();
      if (!mounted || generation != _qrGeneration) return;
      final unikey = keyResult['data']?['data']?['unikey'];
      if (unikey == null) {
        setState(() => _info = '获取二维码失败');
        return;
      }
      _qrKey = unikey;

      // 获取真实的网易云登录 URL
      try {
        final imgResult =
            await ref.read(authProvider.notifier).getQrImage(unikey);
        if (!mounted || generation != _qrGeneration) return;
        if (imgResult['success'] == true &&
            imgResult['data']?['qrurl'] != null) {
          _qrContent = imgResult['data']['qrurl'];
        } else {
          _qrContent = 'https://music.163.com/login?codekey=$unikey';
        }
      } catch (_) {
        _qrContent = 'https://music.163.com/login?codekey=$unikey';
      }

      setState(() {
        _loading = false;
        _info = '请使用网易云音乐APP扫描二维码';
      });

      // 开始轮询检查
      _startPolling(unikey, generation);
    } catch (e) {
      setState(() => _info = '网络错误');
    }
  }

  // 轮询二维码状态
  void _startPolling(String unikey, int generation) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) {
        _pollTimer?.cancel();
        return;
      }
      if (generation != _qrGeneration || unikey != _qrKey) {
        _pollTimer?.cancel();
        return;
      }

      // 检查是否已登录
      final authState = ref.read(authProvider);
      if (authState.isLoggedIn) {
        _pollTimer?.cancel();
        return; // TuneCacheApp 会自动切换到主页
      }

      _pollCount++;
      try {
        final r = await ref.read(authProvider.notifier).checkQrStatus(unikey);
        if (!mounted || generation != _qrGeneration || unikey != _qrKey) return;
        final d = r['data'];
        if (d == null) return;

        final status = d['status'];

        if (status == 'authorized') {
          _pollTimer?.cancel();
          // 再次确认 AuthState 已更新
          if (mounted) {
            setState(() => _info = '登录成功！正在跳转...');
            // TuneCacheApp 监听 authProvider 后会自动切换到主页
          }
          return;
        }

        if (status == 'scanned') {
          if (mounted) setState(() => _info = '已扫描，请在手机上确认登录');
          return;
        }

        if (status == 'expired' || _pollCount > 30) {
          // 二维码已过期，自动生成新的
          if (mounted) {
            setState(() => _info = '二维码已过期，正在刷新...');
            _newQr(); // 自动刷新
          }
          return;
        }
      } catch (_) {}
    });
  }

  Widget _loginStatus(BuildContext context) {
    if (_info == null || _info!.isEmpty) return const SizedBox.shrink();
    final isNotice = _info!.contains('已发送') || _info!.contains('正在');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        _info!,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isNotice
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }

  void _startSmsCountdown() {
    _smsTimer?.cancel();
    setState(() => _smsSecondsLeft = 60);
    _smsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _smsSecondsLeft <= 1) {
        timer.cancel();
        if (mounted) setState(() => _smsSecondsLeft = 0);
        return;
      }
      setState(() => _smsSecondsLeft--);
    });
  }

  Future<void> _sendSmsCaptcha() async {
    final phone = _pc.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _info = '请输入正确的 11 位中国大陆手机号。');
      return;
    }
    setState(() {
      _loading = true;
      _info = null;
    });
    try {
      final result =
          await ref.read(authProvider.notifier).sendLoginCaptcha(phone);
      if (!mounted) return;
      if (result['success'] == true) {
        setState(
            () => _info = (result['message'] ?? '验证码已发送，请查收短信。').toString());
        _startSmsCountdown();
      } else {
        setState(() => _info =
            (result['error'] ?? result['message'] ?? '验证码发送失败。').toString());
      }
    } catch (_) {
      if (mounted) setState(() => _info = '网络错误，请稍后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginBySmsCaptcha() async {
    setState(() {
      _loading = true;
      _info = null;
    });
    try {
      final result = await ref
          .read(authProvider.notifier)
          .loginByCaptcha(_pc.text.trim(), _captchaController.text.trim());
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() => _info =
            (result['error'] ?? result['message'] ?? '验证码登录失败。').toString());
      }
    } catch (_) {
      if (mounted) setState(() => _info = '网络错误，请稍后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginByEmail() async {
    final email = _pc.text.trim();
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email) || _pwc.text.isEmpty) {
      setState(() => _info = '请输入有效的网易邮箱和密码。');
      return;
    }
    setState(() {
      _loading = true;
      _info = null;
    });
    try {
      final result =
          await ref.read(authProvider.notifier).loginByEmail(email, _pwc.text);
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() => _info =
            (result['error'] ?? result['message'] ?? '网易邮箱登录失败。').toString());
      }
    } catch (_) {
      if (mounted) setState(() => _info = '网络错误，请稍后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.small(
        tooltip: '服务器连接',
        onPressed: () => Navigator.of(c).push(
          MaterialPageRoute(builder: (_) => const ServerSettingsPage()),
        ),
        child: const Icon(Icons.dns_rounded),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.music_note, size: 80, color: Colors.deepPurple),
              const SizedBox(height: 16),
              Text('音栈 TuneCache',
                  style: Theme.of(c)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              if (!_showQr && !_showSms && !_showEmail) ...[
                TextField(
                    controller: _pc,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: '手机号',
                        prefixIcon: Icon(Icons.phone_android),
                        border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(
                    controller: _pwc,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: '密码',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder())),
                const SizedBox(height: 24),
                SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              setState(() {
                                _loading = true;
                                _info = null;
                              });
                              try {
                                final r = await ref
                                    .read(authProvider.notifier)
                                    .loginByPhone(_pc.text, _pwc.text);
                                if (r['success'] != true) {
                                  setState(() => _info =
                                      (r['error'] ?? r['message'] ?? '登录失败')
                                          .toString());
                                }
                              } catch (_) {
                                setState(() => _info = '网络错误');
                              } finally {
                                if (mounted) setState(() => _loading = false);
                              }
                            },
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('登录'),
                    )),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                    onPressed: _newQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('扫码登录')),
                const SizedBox(height: 8),
                TextButton.icon(
                    onPressed: () => setState(() {
                          _showSms = true;
                          _info = null;
                        }),
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('短信验证码登录')),
                TextButton.icon(
                    onPressed: () => setState(() {
                          _showEmail = true;
                          _showSms = false;
                          _info = null;
                        }),
                    icon: const Icon(Icons.alternate_email),
                    label: const Text('网易邮箱＋密码登录')),
                _loginStatus(c),
              ] else if (_showSms) ...[
                Text('短信验证码登录', style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('验证码将由网易云音乐发送到你的手机号。', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                TextField(
                    controller: _pc,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: '手机号',
                        prefixIcon: Icon(Icons.phone_android),
                        border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(
                    controller: _captchaController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: '短信验证码',
                        prefixIcon: const Icon(Icons.password),
                        border: const OutlineInputBorder(),
                        suffixIcon: TextButton(
                            onPressed: _loading || _smsSecondsLeft > 0
                                ? null
                                : _sendSmsCaptcha,
                            child: Text(_smsSecondsLeft > 0
                                ? '${_smsSecondsLeft}s 后重发'
                                : '发送验证码')))),
                const SizedBox(height: 24),
                SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                        onPressed: _loading ? null : _loginBySmsCaptcha,
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('验证码登录'))),
                _loginStatus(c),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton.icon(
                      onPressed: _loading
                          ? null
                          : () {
                              _smsTimer?.cancel();
                              setState(() {
                                _showSms = false;
                                _smsSecondsLeft = 0;
                                _info = null;
                              });
                            },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('密码登录')),
                  const SizedBox(width: 12),
                  TextButton.icon(
                      onPressed: _loading ? null : _newQr,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('扫码登录')),
                ]),
              ] else if (_showEmail) ...[
                Text('网易邮箱登录', style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('使用已绑定网易云音乐的网易邮箱和密码登录。',
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                TextField(
                    controller: _pc,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                        labelText: '网易邮箱',
                        hintText: 'name@163.com',
                        prefixIcon: Icon(Icons.alternate_email),
                        border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(
                    controller: _pwc,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _loading ? null : _loginByEmail(),
                    decoration: const InputDecoration(
                        labelText: '密码',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder())),
                const SizedBox(height: 24),
                SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                        onPressed: _loading ? null : _loginByEmail,
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('登录'))),
                _loginStatus(c),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton.icon(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _showEmail = false;
                                _info = null;
                              }),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('手机号登录')),
                  const SizedBox(width: 12),
                  TextButton.icon(
                      onPressed: _loading ? null : _newQr,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('扫码登录')),
                ]),
              ] else ...[
                if (_qrContent != null)
                  Container(
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        QrImageView(
                            data: _qrContent!,
                            size: 220,
                            backgroundColor: Colors.white),
                        const SizedBox(height: 12),
                        Text(_info ?? '',
                            style: TextStyle(
                                color: auth.isLoggedIn
                                    ? Colors.green
                                    : Colors.blue),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton.icon(
                                  onPressed: () {
                                    _pollTimer?.cancel();
                                    setState(() => _showQr = false);
                                  },
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('返回')),
                              const SizedBox(width: 16),
                              TextButton.icon(
                                  onPressed: _newQr,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('刷新二维码')),
                            ]),
                      ])),
                if (_loading)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator()),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
