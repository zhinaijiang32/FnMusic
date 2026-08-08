import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

class AuthState {
  final bool isLoggedIn;
  final bool isInitializing;
  final String? nickname;
  final String? avatarUrl;
  final int? uid;

  AuthState({
    this.isLoggedIn = false,
    this.isInitializing = false,
    this.nickname,
    this.avatarUrl,
    this.uid,
  });
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api = ApiService();

  AuthNotifier() : super(AuthState(isInitializing: true)) {
    _restoreSession();
  }

  AuthState _stateFromProfile(Map<String, dynamic> profile) {
    final rawUid = profile['userId'];
    return AuthState(
      isLoggedIn: true,
      nickname: profile['nickname']?.toString(),
      avatarUrl: profile['avatarUrl']?.toString(),
      uid: rawUid is int ? rawUid : int.tryParse(rawUid?.toString() ?? ''),
    );
  }

  Future<void> _applyLogin(Map<String, dynamic> data) async {
    final profile = Map<String, dynamic>.from(data['profile'] as Map);
    await _api.saveSession(data['token'].toString(), profile);
    state = _stateFromProfile(profile);
  }

  Future<void> _restoreSession() async {
    await _api.initialize();
    final storedProfile = await _api.readStoredProfile();
    if (!await _api.hasStoredSession()) {
      state = AuthState();
      return;
    }

    try {
      final res = await _api.get('/api/auth/session');
      if (res.statusCode == 200 &&
          res.data is Map<String, dynamic> &&
          res.data['success'] == true) {
        final profile =
            Map<String, dynamic>.from(res.data['data']['profile'] as Map);
        await _api.updateStoredProfile(profile);
        state = _stateFromProfile(profile);
        return;
      }
      await _api.clearToken();
      state = AuthState();
    } catch (_) {
      // 服务器暂时不可达时，仍恢复已保存的会话以便使用本地音乐；下次联网会再次校验。
      state = storedProfile == null
          ? AuthState()
          : _stateFromProfile(storedProfile);
    }
  }

  Future<Map<String, dynamic>> loginByPhone(
      String phone, String password) async {
    final res = await _api.post('/api/auth/login/cellphone', data: {
      'phone': phone,
      'password': password,
    });
    if (res.statusCode == 200 && res.data['success'] == true) {
      final d = res.data['data'];
      await _applyLogin(Map<String, dynamic>.from(d));
    }
    if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
    return {'success': false, 'error': '服务器返回了无效的登录结果。'};
  }

  Future<Map<String, dynamic>> loginByEmail(
      String email, String password) async {
    final res = await _api.post('/api/auth/login/email', data: {
      'email': email,
      'password': password,
    });
    if (res.statusCode == 200 && res.data['success'] == true) {
      final d = res.data['data'];
      await _applyLogin(Map<String, dynamic>.from(d));
    }
    if (res.data is Map<String, dynamic>) return res.data;
    return {'success': false, 'error': '服务器返回了无效的登录结果。'};
  }

  Future<Map<String, dynamic>> sendLoginCaptcha(String phone) async {
    final res = await _api.post('/api/auth/login/captcha/send', data: {
      'phone': phone,
    });
    if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
    return {'success': false, 'error': '服务器返回了无效的验证码结果。'};
  }

  Future<Map<String, dynamic>> loginByCaptcha(
      String phone, String captcha) async {
    final res = await _api.post('/api/auth/login/captcha', data: {
      'phone': phone,
      'captcha': captcha,
    });
    if (res.statusCode == 200 &&
        res.data is Map<String, dynamic> &&
        res.data['success'] == true) {
      final d = res.data['data'];
      await _applyLogin(Map<String, dynamic>.from(d));
    }
    if (res.data is Map<String, dynamic>) return res.data;
    return {'success': false, 'error': '服务器返回了无效的登录结果。'};
  }

  Future<Map<String, dynamic>> getQrKey() async {
    final res = await _api.get('/api/auth/qr/key');
    return res.data;
  }

  Future<Map<String, dynamic>> getQrImage(String unikey) async {
    final res = await _api.get('/api/auth/qr/image/$unikey');
    return res.data;
  }

  Future<Map<String, dynamic>> checkQrStatus(String unikey) async {
    final res = await _api.get('/api/auth/qr/check/$unikey');
    if (res.statusCode == 200 && res.data['success'] == true) {
      final data = res.data['data'];
      if (data['status'] == 'authorized') {
        await _applyLogin(Map<String, dynamic>.from(data));
      }
    }
    return res.data;
  }

  Future<void> logout() async {
    await _api.clearToken();
    state = AuthState();
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
