import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

/// جدار كمسار نقاط (basis points 0–10000) بسمك موحّد رفيع.
class WallPath {
  WallPath(List<Offset> points)
      : points = List<Offset>.unmodifiable(
          points.length >= 2 ? points : const [Offset(2000, 5000), Offset(5000, 5000)],
        );

  final List<Offset> points;

  /// سمك منطقي موحّد (وحدة واحدة) — يُرسم رفيعاً دائماً.
  static const int unitThickness = 1;
  static const double strokePx = 8;

  static WallPath? tryParse(String? metaJson) {
    if (metaJson == null || metaJson.trim().isEmpty) return null;
    try {
      final raw = jsonDecode(metaJson);
      if (raw is! Map) return null;
      final path = raw['path'];
      if (path is! List || path.length < 2) return null;
      final pts = <Offset>[];
      for (final p in path) {
        if (p is List && p.length >= 2) {
          pts.add(Offset(
            (p[0] as num).toDouble().clamp(0, 10000),
            (p[1] as num).toDouble().clamp(0, 10000),
          ));
        }
      }
      if (pts.length < 2) return null;
      return WallPath(pts);
    } catch (_) {
      return null;
    }
  }

  /// من مستطيل قديم (قبل نظام المسار).
  static WallPath fromLegacyRect({
    required int xBp,
    required int yBp,
    required int wBp,
    required int hBp,
  }) {
    final horizontal = wBp >= hBp;
    if (horizontal) {
      final midY = yBp + hBp / 2;
      return WallPath([
        Offset(xBp.toDouble(), midY),
        Offset((xBp + wBp).toDouble(), midY),
      ]);
    }
    final midX = xBp + wBp / 2;
    return WallPath([
      Offset(midX, yBp.toDouble()),
      Offset(midX, (yBp + hBp).toDouble()),
    ]);
  }

  String toMetaJson() {
    return jsonEncode({
      'path': [
        for (final p in points) [p.dx.round(), p.dy.round()],
      ],
      'thickness': unitThickness,
    });
  }

  WallPath copyWithPoints(List<Offset> next) => WallPath(next);

  double get lengthBp {
    var sum = 0.0;
    for (var i = 1; i < points.length; i++) {
      sum += (points[i] - points[i - 1]).distance;
    }
    return sum;
  }

  /// نقطة على المسار عند نسبة 0..1 من الطول.
  Offset pointAlong(double t) {
    final target = t.clamp(0.0, 1.0) * lengthBp;
    if (lengthBp <= 0) return points.first;
    var walked = 0.0;
    for (var i = 1; i < points.length; i++) {
      final seg = points[i] - points[i - 1];
      final d = seg.distance;
      if (walked + d >= target || i == points.length - 1) {
        final local = d <= 0 ? 0.0 : ((target - walked) / d).clamp(0.0, 1.0);
        return points[i - 1] + seg * local;
      }
      walked += d;
    }
    return points.last;
  }

  /// أقرب نقطة على المسار + النسبة على الطول.
  (Offset point, double t) project(Offset queryBp) {
    if (lengthBp <= 0) return (points.first, 0.0);
    var bestDist = double.infinity;
    var bestPoint = points.first;
    var bestAlong = 0.0;
    var walked = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final ab = b - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      final tSeg = len2 <= 0
          ? 0.0
          : (((queryBp - a).dx * ab.dx + (queryBp - a).dy * ab.dy) / len2)
              .clamp(0.0, 1.0);
      final proj = a + ab * tSeg;
      final d = (queryBp - proj).distance;
      if (d < bestDist) {
        bestDist = d;
        bestPoint = proj;
        bestAlong = (walked + math.sqrt(len2) * tSeg) / lengthBp;
      }
      walked += math.sqrt(len2);
    }
    return (bestPoint, bestAlong.clamp(0.0, 1.0));
  }

  /// اتجاه آخر قطعة (وحدة).
  Offset get lastDirection {
    if (points.length < 2) return const Offset(1, 0);
    final d = points.last - points[points.length - 2];
    final len = d.distance;
    if (len < 1e-6) return const Offset(1, 0);
    return d / len;
  }

  /// عطف 90° وإضافة قطعة جديدة.
  WallPath bend({required bool left, double segmentBp = 1400}) {
    final dir = lastDirection;
    final perp = left
        ? Offset(-dir.dy, dir.dx)
        : Offset(dir.dy, -dir.dx);
    final next = points.last + perp * segmentBp;
    return copyWithPoints([
      ...points,
      Offset(next.dx.clamp(0, 10000), next.dy.clamp(0, 10000)),
    ]);
  }

  /// تغيير طول آخر قطعة (موجب = إطالة).
  WallPath extendLast(double deltaBp) {
    if (points.length < 2) return this;
    final dir = lastDirection;
    final next = points.last + dir * deltaBp;
    final pts = [...points];
    pts[pts.length - 1] =
        Offset(next.dx.clamp(0, 10000), next.dy.clamp(0, 10000));
    // لا تقصّر أكثر من الحد الأدنى
    if ((pts.last - pts[pts.length - 2]).distance < 200) {
      pts[pts.length - 1] = pts[pts.length - 2] + dir * 200;
    }
    return copyWithPoints(pts);
  }

  WallPath translate(Offset deltaBp) {
    return copyWithPoints([
      for (final p in points)
        Offset(
          (p.dx + deltaBp.dx).clamp(0, 10000),
          (p.dy + deltaBp.dy).clamp(0, 10000),
        ),
    ]);
  }

  /// صندوق محيط بالمسار (مع هامش للمس).
  (int x, int y, int w, int h) boundsBp({int pad = 80}) {
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final x = (minX - pad).clamp(0, 10000).round();
    final y = (minY - pad).clamp(0, 10000).round();
    final w = (maxX - minX + pad * 2).clamp(200, 10000).round();
    final h = (maxY - minY + pad * 2).clamp(200, 10000).round();
    return (x, y, w, h);
  }

  List<Offset> toCanvasPixels(Size canvas) {
    return [
      for (final p in points)
        Offset(
          (p.dx / 10000) * canvas.width,
          (p.dy / 10000) * canvas.height,
        ),
    ];
  }
}

class DoorWallAnchor {
  const DoorWallAnchor({required this.wallId, required this.along});

  final int wallId;
  final double along;

  static DoorWallAnchor? tryParse(String? metaJson) {
    if (metaJson == null || metaJson.trim().isEmpty) return null;
    try {
      final raw = jsonDecode(metaJson);
      if (raw is! Map) return null;
      final id = raw['wall_id'];
      final along = raw['along'];
      if (id is! num) return null;
      return DoorWallAnchor(
        wallId: id.toInt(),
        along: (along is num ? along.toDouble() : 0.5).clamp(0.0, 1.0),
      );
    } catch (_) {
      return null;
    }
  }

  String toMetaJson() => jsonEncode({
        'wall_id': wallId,
        'along': along,
      });
}
