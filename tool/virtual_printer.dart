// طابعة حرارية وهمية على الشبكة لتجربة الطباعة بلا طابعة حقيقية.
//
//   dart run tool/virtual_printer.dart [المنفذ=9100] [مجلد الحفظ=build/virtual_printer]
//
// ثم في التطبيق: الطباعة ← طابعة شبكة ← عنوان هذا الحاسوب (نفس شبكة Wi-Fi)
// والمنفذ. كل إيصال يصل يُحفظ صورة PNG كما كانت ستطبعه الطابعة بالضبط.
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 9100;
  final outDir = Directory(args.length > 1 ? args[1] : 'build/virtual_printer')
    ..createSync(recursive: true);
  final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
  final ips = [
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
      for (final a in i.addresses)
        if (!a.isLoopback) a.address,
  ];
  stdout.writeln('الطابعة الوهمية تعمل على: ${ips.join('، ')} المنفذ $port');
  stdout.writeln('الإيصالات تُحفظ في: ${outDir.absolute.path}');
  var n = 0;
  await for (final socket in server) {
    final b = BytesBuilder();
    await for (final chunk in socket) {
      b.add(chunk);
    }
    final pages = _decode(b.toBytes());
    if (pages.isEmpty) {
      stdout.writeln('وصلت ${b.length} بايت بلا صورة نقطية (GS v 0).');
      continue;
    }
    for (final p in pages) {
      final f = File('${outDir.path}/receipt_${++n}.png')
        ..writeAsBytesSync(img.encodePng(p));
      stdout.writeln('إيصال ${p.width}×${p.height} نقطة ← ${f.path}');
    }
  }
}

/// يفك أوامر GS v 0 حتى أمر القص (GS V) إلى صفحات.
List<img.Image> _decode(Uint8List d) {
  final pages = <img.Image>[];
  final rows = <List<bool>>[];
  void flush() {
    if (rows.isEmpty) return;
    final im = img.Image(width: rows.first.length, height: rows.length);
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        final v = rows[y][x] ? 0 : 255;
        im.setPixelRgb(x, y, v, v, v);
      }
    }
    pages.add(im);
    rows.clear();
  }

  var i = 0;
  while (i < d.length) {
    if (d[i] == 0x1D && i + 7 < d.length && d[i + 1] == 0x76 && d[i + 2] == 0x30) {
      final xb = d[i + 4] | (d[i + 5] << 8);
      final h = d[i + 6] | (d[i + 7] << 8);
      var p = i + 8;
      for (var y = 0; y < h; y++) {
        final row = <bool>[];
        for (var x = 0; x < xb; x++) {
          final byte = p < d.length ? d[p++] : 0;
          for (var bit = 7; bit >= 0; bit--) {
            row.add((byte >> bit) & 1 == 1);
          }
        }
        rows.add(row);
      }
      i = p;
    } else if (d[i] == 0x1D && i + 1 < d.length && d[i + 1] == 0x56) {
      flush();
      i += 4;
    } else {
      i++;
    }
  }
  flush();
  return pages;
}
