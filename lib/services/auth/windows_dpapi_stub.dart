import 'dart:typed_data';

/// الويب: لا DPAPI.
bool get dpapiAvailable => false;

Future<Uint8List> dpapiProtect(Uint8List data) =>
    Future.error(UnsupportedError('DPAPI is Windows only'));

Future<Uint8List> dpapiUnprotect(Uint8List blob) =>
    Future.error(UnsupportedError('DPAPI is Windows only'));
