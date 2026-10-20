import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/app_logger.dart';

const _udpPort = 38471;
const _wsPort = 38472;
const _magic = 'naboo-rst-hub-v1';

RawDatagramSocket? _udp;
HttpServer? _http;
final _wsClients = <WebSocket>{};
WebSocket? _hubSocket;
void Function(String peerId)? _onHello;
void Function(String hubId)? _onAlive;
void Function(String hubId)? _onIAmHub;
void Function(String raw)? _onWs;
String? _selfId;
final _pendingHubs = <String>{};
StreamSubscription<RawSocketEvent>? _udpSub;

Future<void> startLanTransport({
  required String deviceId,
  required void Function(String peerId) onPeerHello,
  required void Function(String hubId) onPeerAlive,
  required void Function(String hubId) onPeerIAmHub,
  required void Function(String raw) onWsEvent,
}) async {
  _selfId = deviceId;
  _onHello = onPeerHello;
  _onAlive = onPeerAlive;
  _onIAmHub = onPeerIAmHub;
  _onWs = onWsEvent;
  _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _udpPort);
  _udp!.broadcastEnabled = true;
  _udpSub = _udp!.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = _udp!.receive();
    if (dg == null) return;
    try {
      final msg = utf8.decode(dg.data);
      final map = jsonDecode(msg);
      if (map is! Map) return;
      if (map['magic'] != _magic) return;
      final type = map['type'] as String?;
      final id = map['device_id'] as String?;
      final host = map['host'] as String?;
      if (host != null && host.isNotEmpty) {
        _lastHubHost = host;
      }
      if (id == null || id == _selfId) return;
      switch (type) {
        case 'hello':
          _onHello?.call(id);
        case 'alive':
          _onAlive?.call(id);
        case 'i-am-hub':
          _pendingHubs.add(id);
          _onIAmHub?.call(id);
      }
    } catch (_) {}
  });
  _broadcast({'type': 'hello', 'device_id': deviceId});
}

Future<void> stopLanTransport() async {
  await stopHubServer();
  await _udpSub?.cancel();
  _udpSub = null;
  _udp?.close();
  _udp = null;
  try {
    await _hubSocket?.close();
  } catch (_) {}
  _hubSocket = null;
}

Future<String?> waitForExistingHub({required Duration timeout}) async {
  _pendingHubs.clear();
  _broadcast({'type': 'hello', 'device_id': _selfId});
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (_pendingHubs.isNotEmpty) {
      final list = _pendingHubs.toList()..sort();
      final hubId = list.first;
      await _connectClient(hubId);
      return hubId;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return null;
}

Future<void> announceIAmHub(String deviceId) async {
  _broadcast({'type': 'i-am-hub', 'device_id': deviceId});
}

Future<String?> waitForRivalHub({
  required String selfId,
  required Duration timeout,
}) async {
  final end = DateTime.now().add(timeout);
  String? rival;
  while (DateTime.now().isBefore(end)) {
    for (final id in _pendingHubs) {
      if (id != selfId && (rival == null || id.compareTo(rival) < 0)) {
        rival = id;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return rival;
}

Future<void> announceAlive(String deviceId) async {
  _broadcast({'type': 'alive', 'device_id': deviceId});
}

Future<void> startHubServer({required String deviceId}) async {
  await stopHubServer();
  _http = await HttpServer.bind(InternetAddress.anyIPv4, _wsPort);
  AppLogger.info('LanHubIO', 'WS hub on :$_wsPort');
  _http!.listen((req) async {
    if (req.uri.path != '/ws') {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    _wsClients.add(ws);
    ws.listen(
      (data) {
        if (data is String) {
          for (final c in _wsClients) {
            if (c != ws) c.add(data);
          }
          _onWs?.call(data);
        }
      },
      onDone: () => _wsClients.remove(ws),
      onError: (_) => _wsClients.remove(ws),
    );
  });
}

Future<void> stopHubServer() async {
  for (final c in List<WebSocket>.from(_wsClients)) {
    try {
      await c.close();
    } catch (_) {}
  }
  _wsClients.clear();
  await _http?.close(force: true);
  _http = null;
}

Future<void> broadcastWs(String message) async {
  for (final c in List<WebSocket>.from(_wsClients)) {
    try {
      c.add(message);
    } catch (_) {
      _wsClients.remove(c);
    }
  }
}

Future<void> sendToHub(String message) async {
  final ws = _hubSocket;
  if (ws == null) return;
  ws.add(message);
}

Future<void> _connectClient(String hubId) async {
  // عميل يحاول الاتصال بـ localhost أولاً؛ في شبكة حقيقية يحتاج IP من الحزمة.
  // المرحلة 3: نضمّن host في إعلان i-am-hub.
  try {
    final host = await _resolveHubHost();
    _hubSocket = await WebSocket.connect('ws://$host:$_wsPort/ws');
    _hubSocket!.listen(
      (data) {
        if (data is String) _onWs?.call(data);
      },
      onDone: () => _hubSocket = null,
      onError: (_) => _hubSocket = null,
    );
  } catch (e) {
    AppLogger.warn('LanHubIO', 'ws connect failed: $e');
  }
}

String? _lastHubHost;

void _broadcast(Map<String, Object?> body) {
  final udp = _udp;
  if (udp == null) return;
  final payload = Map<String, Object?>.from(body)
    ..['magic'] = _magic
    ..['ws_port'] = _wsPort
    ..['host'] = _localHostHint();
  if (body['type'] == 'i-am-hub' || body['type'] == 'alive') {
    _lastHubHost = payload['host'] as String?;
  }
  final bytes = utf8.encode(jsonEncode(payload));
  udp.send(bytes, InternetAddress('255.255.255.255'), _udpPort);
}

String _localHostHint() {
  try {
    // أفضل جهد — بدون package إضافي
    return InternetAddress.loopbackIPv4.address;
  } catch (_) {
    return '127.0.0.1';
  }
}

Future<String> _resolveHubHost() async {
  return _lastHubHost ?? '127.0.0.1';
}
