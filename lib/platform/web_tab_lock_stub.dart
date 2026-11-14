/// خارج الويب: دائماً قائد.
class WebTabLock {
  WebTabLock._();
  static final WebTabLock instance = WebTabLock._();

  bool get isLeader => true;
  bool get locksApiAvailable => true;

  Future<bool> acquireLeadership({int retries = 1}) async => true;

  void release() {}
}
