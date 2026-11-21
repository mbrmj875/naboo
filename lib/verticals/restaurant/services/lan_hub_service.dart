import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../utils/app_logger.dart';
import 'lan_hub_service_stub.dart'
    if (dart.library.io) 'lan_hub_service_io.dart' as impl;

enum LanHubRole { idle, hub, client }

/// انتخاب Hub + بث أحداث LAN (spec §10).
///
/// على الويب: no-op (كاشير/KDS على المتصفح لا يشغّلان mDNS/WebSocket server).
/// على الموبايل/سطح المكتب: UDP discovery + WebSocket عبر [dart:io].
class LanHubService extends ChangeNotifier {
  LanHubService._();
  static final LanHubService instance = LanHubService._();

  LanHubRole _role = LanHubRole.idle;
  String? _hubDeviceId;
  String? _localDeviceId;
  int _lastEventId = 0;
  final _eventController = StreamController<LanHubEvent>.broadcast();
  Timer? _heartbeatTimer;
  Timer? _watchdogTimer;
  DateTime? _lastAliveAt;
  bool _running = false;

  LanHubRole get role => _role;
  String? get hubDeviceId => _hubDeviceId;
  String? get localDeviceId => _localDeviceId;
  Stream<LanHubEvent> get events => _eventController.stream;
  bool get isHub => _role == LanHubRole.hub;
  bool get running => _running;

  /// يبدأ الاكتشاف والانتخاب (§10.2).
  Future<void> start({required String deviceId}) async {
    if (kIsWeb) {
      _localDeviceId = deviceId;
      _role = LanHubRole.idle;
      AppLogger.info('LanHub', 'web: LAN hub معطل');
      notifyListeners();
      return;
    }
    if (_running) return;
    _running = true;
    _localDeviceId = deviceId;
    await impl.startLanTransport(
      deviceId: deviceId,
      onPeerHello: _onPeerHello,
      onPeerAlive: _onPeerAlive,
      onPeerIAmHub: _onPeerIAmHub,
      onWsEvent: _onWsEvent,
    );
    await _elect();
  }

  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _watchdogTimer?.cancel();
    _running = false;
    await impl.stopLanTransport();
    _role = LanHubRole.idle;
    notifyListeners();
  }

  /// ينشر حدثاً عبر الـhub (أو محلياً إن كنا الـhub).
  Future<void> publish(LanHubEvent event) async {
    _lastEventId = event.eventId > _lastEventId ? event.eventId : _lastEventId + 1;
    final stamped = event.copyWith(eventId: _lastEventId);
    _eventController.add(stamped);
    if (_role == LanHubRole.hub) {
      await impl.broadcastWs(jsonEncode(stamped.toJson()));
    } else if (_role == LanHubRole.client) {
      await impl.sendToHub(jsonEncode(stamped.toJson()));
    }
  }

  Future<void> _elect() async {
    final deviceId = _localDeviceId!;
    // استمع 3 ثوانٍ لـ hub موجود
    final found = await impl.waitForExistingHub(timeout: const Duration(seconds: 3));
    if (found != null) {
      _role = LanHubRole.client;
      _hubDeviceId = found;
      _startWatchdog();
      notifyListeners();
      AppLogger.info('LanHub', 'joined as client → hub=$found');
      return;
    }

    // أعلن نفسك hub
    await impl.announceIAmHub(deviceId);
    // تعارض قصير: انتظر 500ms لأي مُعلِن أقدم
    final rival = await impl.waitForRivalHub(
      selfId: deviceId,
      timeout: const Duration(milliseconds: 500),
    );
    if (rival != null && rival.compareTo(deviceId) < 0) {
      _role = LanHubRole.client;
      _hubDeviceId = rival;
      _startWatchdog();
      notifyListeners();
      AppLogger.info('LanHub', 'lost election to $rival');
      return;
    }

    _role = LanHubRole.hub;
    _hubDeviceId = deviceId;
    await impl.startHubServer(deviceId: deviceId);
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(impl.announceAlive(deviceId));
    });
    notifyListeners();
    AppLogger.info('LanHub', 'elected as hub');
  }

  void _onPeerHello(String peerId) {
    if (_role == LanHubRole.hub && _localDeviceId != null) {
      unawaited(impl.announceIAmHub(_localDeviceId!));
    }
  }

  void _onPeerAlive(String hubId) {
    _lastAliveAt = DateTime.now();
    if (_role == LanHubRole.client) {
      _hubDeviceId = hubId;
    }
  }

  void _onPeerIAmHub(String hubId) {
    final self = _localDeviceId;
    if (self == null) return;
    if (_role == LanHubRole.hub && hubId.compareTo(self) < 0) {
      // خسرنا التعارض
      unawaited(_demoteToClient(hubId));
    } else if (_role == LanHubRole.idle || _role == LanHubRole.client) {
      _hubDeviceId = hubId;
      _role = LanHubRole.client;
      _lastAliveAt = DateTime.now();
      notifyListeners();
    }
  }

  void _onWsEvent(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return;
      final event = LanHubEvent.fromJson(map);
      if (event.eventId > _lastEventId) _lastEventId = event.eventId;
      _eventController.add(event);
    } catch (e) {
      AppLogger.warn('LanHub', 'bad ws event: $e');
    }
  }

  void _startWatchdog() {
    _lastAliveAt = DateTime.now();
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final last = _lastAliveAt;
      if (last == null) return;
      if (DateTime.now().difference(last) > const Duration(seconds: 5)) {
        AppLogger.warn('LanHub', 'hub timeout — re-elect');
        unawaited(_reelect());
      }
    });
  }

  Future<void> _demoteToClient(String hubId) async {
    _heartbeatTimer?.cancel();
    await impl.stopHubServer();
    _role = LanHubRole.client;
    _hubDeviceId = hubId;
    _startWatchdog();
    notifyListeners();
  }

  Future<void> _reelect() async {
    _watchdogTimer?.cancel();
    _heartbeatTimer?.cancel();
    await impl.stopHubServer();
    _role = LanHubRole.idle;
    notifyListeners();
    await _elect();
  }
}

class LanHubEvent {
  const LanHubEvent({
    required this.eventId,
    required this.type,
    required this.payload,
    required this.clientGeneratedId,
    required this.atMs,
  });

  final int eventId;
  final String type;
  final Map<String, dynamic> payload;
  final String clientGeneratedId;
  final int atMs;

  LanHubEvent copyWith({int? eventId}) => LanHubEvent(
        eventId: eventId ?? this.eventId,
        type: type,
        payload: payload,
        clientGeneratedId: clientGeneratedId,
        atMs: atMs,
      );

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'type': type,
        'payload': payload,
        'client_generated_id': clientGeneratedId,
        'at_ms': atMs,
      };

  factory LanHubEvent.fromJson(Map<String, dynamic> json) => LanHubEvent(
        eventId: (json['event_id'] as num?)?.toInt() ?? 0,
        type: json['type'] as String? ?? '',
        payload: Map<String, dynamic>.from(
          (json['payload'] as Map?) ?? const {},
        ),
        clientGeneratedId: json['client_generated_id'] as String? ?? '',
        atMs: (json['at_ms'] as num?)?.toInt() ?? 0,
      );
}
