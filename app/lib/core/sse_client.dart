import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SseMessage {
  final String event;
  final Map<String, dynamic> data;
  final String? id;

  const SseMessage({required this.event, required this.data, this.id});
}

/// Auto-reconnecting SSE client supporting Android, Web, and Windows.
class SseClient extends ChangeNotifier {
  String _baseUrl = '';
  String? _token;
  http.Client? _httpClient;
  StreamSubscription<String>? _sub;
  Timer? _retryTimer;

  bool _disposed = false;
  bool _active = false;
  bool _connected = false;
  bool _reconnecting = false;
  int _retryCount = 0;
  String? _lastEventId;

  final _controller = StreamController<SseMessage>.broadcast();
  final _reconnectController = StreamController<void>.broadcast();

  Stream<SseMessage> get messages => _controller.stream;
  Stream<void> get onReconnected => _reconnectController.stream;
  bool get connected => _connected;
  bool get reconnecting => _reconnecting;

  void start(String baseUrl, String token) {
    _baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    _token = token;
    _active = true;
    _retryCount = 0;
    _connect();
  }

  void stop() {
    _active = false;
    _retryTimer?.cancel();
    _sub?.cancel();
    _httpClient?.close();
    _connected = false;
    _reconnecting = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> _connect() async {
    if (_disposed || !_active || _token == null) return;
    _sub?.cancel();
    _httpClient?.close();

    final wasReconnecting = _retryCount > 0;
    try {
      _httpClient = http.Client();
      final uri = Uri.parse(
          '$_baseUrl/api/v1/stream?token=${Uri.encodeComponent(_token!)}');
      final req = http.Request('GET', uri);
      req.headers['Accept'] = 'text/event-stream';
      if (_lastEventId != null) {
        req.headers['Last-Event-ID'] = _lastEventId!;
      }

      final resp =
          await _httpClient!.send(req).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        throw Exception('SSE HTTP ${resp.statusCode}');
      }

      _connected = true;
      _reconnecting = false;
      _retryCount = 0;
      if (!_disposed) notifyListeners();
      if (wasReconnecting) {
        _reconnectController.add(null);
      }

      String? curEvent;
      String? curData;

      _sub = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (_disposed || !_active) return;
          if (line.isEmpty) {
            if (curData != null) {
              try {
                final parsed = jsonDecode(curData!) as Map<String, dynamic>;
                _controller.add(SseMessage(
                  event: curEvent ?? 'message',
                  data: parsed,
                  id: _lastEventId,
                ));
              } catch (_) {}
            }
            curEvent = null;
            curData = null;
            return;
          }
          if (line.startsWith(':')) return;
          if (line.startsWith('id:')) {
            _lastEventId = line.substring(3).trim();
          } else if (line.startsWith('event:')) {
            curEvent = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            final part = line.substring(5).trim();
            curData = curData == null ? part : '$curData\n$part';
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed || !_active) return;
    _connected = false;
    _reconnecting = true;
    _retryCount++;
    if (!_disposed) notifyListeners();

    final seconds = (_retryCount * 2).clamp(1, 10);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), _connect);
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _controller.close();
    _reconnectController.close();
    super.dispose();
  }
}
