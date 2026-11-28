import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// DPAPI من ويندوز مباشرة (CryptProtectData / CryptUnprotectData).
///
/// لا يعمل على خيط الواجهة: كل نداء في عزلة خلفية، فإن علق النظام لا تتجمد
/// النافذة، وتنتهي المهلة في العزلة الرئيسية كالمعتاد.

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Utf16> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);
typedef _CryptDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Utf16> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);
typedef _UnprotectNative = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Pointer<Utf16>> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);
typedef _UnprotectDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Pointer<Utf16>> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);

const _uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN: لا نوافذ أبداً.

bool get dpapiAvailable => Platform.isWindows;

Uint8List _run(Uint8List input, {required bool protect}) {
  final crypt32 = DynamicLibrary.open('crypt32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final localFree =
      kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
  final inBlob = calloc<_DataBlob>();
  final outBlob = calloc<_DataBlob>();
  final data = calloc<Uint8>(input.isEmpty ? 1 : input.length);
  try {
    data.asTypedList(input.length).setAll(0, input);
    inBlob.ref
      ..cbData = input.length
      ..pbData = data;
    final ok = protect
        ? crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptProtectData')(
            inBlob, nullptr, nullptr, nullptr, nullptr, _uiForbidden, outBlob)
        : crypt32.lookupFunction<_UnprotectNative, _UnprotectDart>(
                'CryptUnprotectData')(
            inBlob, nullptr, nullptr, nullptr, nullptr, _uiForbidden, outBlob);
    if (ok == 0) {
      throw StateError(protect ? 'CryptProtectData failed' : 'CryptUnprotectData failed');
    }
    final out = Uint8List.fromList(
      outBlob.ref.pbData.asTypedList(outBlob.ref.cbData),
    );
    localFree(outBlob.ref.pbData.cast());
    return out;
  } finally {
    calloc
      ..free(data)
      ..free(inBlob)
      ..free(outBlob);
  }
}

Future<Uint8List> dpapiProtect(Uint8List data) =>
    Isolate.run(() => _run(data, protect: true));

Future<Uint8List> dpapiUnprotect(Uint8List blob) =>
    Isolate.run(() => _run(blob, protect: false));
