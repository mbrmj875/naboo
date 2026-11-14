import 'dart:io';

Future<String?> resolveMarketPosPath(String input) async {
  final raw = input.trim();
  if (raw.isEmpty) return null;

  final direct = File(raw);
  if (await direct.exists()) return direct.path;

  final base = raw.contains('/') || raw.contains('\\')
      ? raw.split(RegExp(r'[\\/]+')).where((e) => e.isNotEmpty).last
      : raw;
  if (base.isEmpty) return null;

  final home = Platform.environment['HOME'] ?? '';
  final candidates = <String>[
    if (home.isNotEmpty) '$home/Documents/$base',
    if (home.isNotEmpty) '$home/Downloads/$base',
    if (home.isNotEmpty) '$home/Desktop/$base',
    base,
  ];

  for (final p in candidates) {
    final f = File(p);
    if (await f.exists()) return f.path;
  }

  final searchRoots = <String>[
    if (home.isNotEmpty) '$home/Documents',
    if (home.isNotEmpty) '$home/Downloads',
    if (home.isNotEmpty) '$home/Desktop',
  ];
  for (final root in searchRoots) {
    final hit = await _searchFileInDir(
      Directory(root),
      base,
      maxDepth: 4,
    );
    if (hit != null) return hit;
  }
  return null;
}

Future<String?> _searchFileInDir(
  Directory dir,
  String fileName, {
  required int maxDepth,
}) async {
  if (maxDepth < 0) return null;
  try {
    await for (final ent in dir.list(followLinks: false)) {
      if (ent is File) {
        try {
          if (ent.path.split(Platform.pathSeparator).last == fileName) {
            return ent.path;
          }
        } catch (_) {}
      } else if (ent is Directory) {
        final hit = await _searchFileInDir(
          ent,
          fileName,
          maxDepth: maxDepth - 1,
        );
        if (hit != null) return hit;
      }
    }
  } catch (_) {}
  return null;
}
