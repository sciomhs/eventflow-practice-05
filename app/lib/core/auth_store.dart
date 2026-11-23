import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'models/models.dart';
import 'sse_client.dart';

class AuthStore extends ChangeNotifier {
  static const _kTokenKey = 'ef_jwt_token';
  static const _kBaseUrlKey = 'ef_base_url';

  late final ApiClient api;
  final SseClient sse = SseClient();

  EfUser? _user;
  bool _loading = true;
  String? _error;

  EfUser? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get loading => _loading;
  String? get error => _error;
  String get baseUrl => api.baseUrl;

  String get defaultBaseUrl =>
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          ? 'http://10.0.2.2:8085'
          : 'http://localhost:8085';

  AuthStore() {
    api = ApiClient(baseUrl: defaultBaseUrl);
  }

  Future<void> saveCache(String key, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'ef_cache_${api.baseUrl}_${_user?.id ?? 'anon'}_$key',
        jsonEncode(data),
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs
          .getString('ef_cache_${api.baseUrl}_${_user?.id ?? 'anon'}_$key');
      if (raw == null || raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    _loading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_kBaseUrlKey);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        api.baseUrl = savedUrl;
      }
      final savedToken = prefs.getString(_kTokenKey);
      if (savedToken != null && savedToken.isNotEmpty) {
        api.token = savedToken;
        final me = await api.get('/api/v1/auth/me');
        _user = EfUser.fromJson(me);
        sse.start(api.baseUrl, savedToken);
      }
    } catch (_) {
      api.token = null;
      _user = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setBaseUrl(String url) async {
    final clean = url.trim();
    if (clean.isEmpty) return;
    api.baseUrl = clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrlKey, clean);
    if (api.token != null && _user != null) {
      sse.start(api.baseUrl, api.token!);
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    _error = null;
    final res = await api.post('/api/v1/auth/login', body: {
      'email': email.trim(),
      'password': password,
    });
    final token = res['access_token'] as String;
    api.token = token;
    _user = EfUser.fromJson(res['user'] as Map<String, dynamic>);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token);
    sse.start(api.baseUrl, token);
    notifyListeners();
  }

  Future<void> register(String name, String email, String password) async {
    _error = null;
    final res = await api.post('/api/v1/auth/register', body: {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
    });
    final token = res['access_token'] as String;
    api.token = token;
    _user = EfUser.fromJson(res['user'] as Map<String, dynamic>);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token);
    sse.start(api.baseUrl, token);
    notifyListeners();
  }

  Future<void> logout() async {
    sse.stop();
    api.token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
    notifyListeners();
  }
}
