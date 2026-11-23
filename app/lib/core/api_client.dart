import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  String baseUrl;
  String? token;
  final http.Client _client;

  ApiClient({
    required this.baseUrl,
    this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$cleanBase$path')
        .replace(queryParameters: query?.isEmpty == true ? null : query);
  }

  Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? query}) async {
    final res = await _client
        .get(_uri(path, query), headers: _headers())
        .timeout(const Duration(seconds: 10));
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic>? body}) async {
    final res = await _client
        .post(_uri(path), headers: _headers(), body: jsonEncode(body ?? {}))
        .timeout(const Duration(seconds: 10));
    return _decode(res);
  }

  Future<Map<String, dynamic>> patch(String path,
      {Map<String, dynamic>? body}) async {
    final res = await _client
        .patch(_uri(path), headers: _headers(), body: jsonEncode(body ?? {}))
        .timeout(const Duration(seconds: 10));
    return _decode(res);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final res = await _client
        .delete(_uri(path), headers: _headers())
        .timeout(const Duration(seconds: 10));
    return _decode(res);
  }

  Future<Map<String, dynamic>> checkHealth(String targetUrl) async {
    final clean = targetUrl.trim().endsWith('/')
        ? targetUrl.trim().substring(0, targetUrl.trim().length - 1)
        : targetUrl.trim();
    final sw = Stopwatch()..start();
    final res = await _client
        .get(Uri.parse('$clean/health'))
        .timeout(const Duration(seconds: 5));
    sw.stop();
    final data = _decode(res);
    data['latency_ms'] = sw.elapsedMilliseconds;
    return data;
  }

  Map<String, dynamic> _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes);
    final decoded = text.isNotEmpty ? jsonDecode(text) : <String, dynamic>{};
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    }
    final detail = decoded is Map<String, dynamic>
        ? (decoded['detail']?.toString() ??
            'Ошибка сервера (${res.statusCode})')
        : 'Ошибка сервера (${res.statusCode})';
    throw ApiException(res.statusCode, detail);
  }
}
