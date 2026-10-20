Future<void> startLanTransport({
  required String deviceId,
  required void Function(String peerId) onPeerHello,
  required void Function(String hubId) onPeerAlive,
  required void Function(String hubId) onPeerIAmHub,
  required void Function(String raw) onWsEvent,
}) async {}

Future<void> stopLanTransport() async {}

Future<String?> waitForExistingHub({required Duration timeout}) async => null;

Future<void> announceIAmHub(String deviceId) async {}

Future<String?> waitForRivalHub({
  required String selfId,
  required Duration timeout,
}) async =>
    null;

Future<void> announceAlive(String deviceId) async {}

Future<void> startHubServer({required String deviceId}) async {}

Future<void> stopHubServer() async {}

Future<void> broadcastWs(String message) async {}

Future<void> sendToHub(String message) async {}
