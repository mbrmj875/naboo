import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/restaurant_models.dart';
import '../theme/restaurant_os_tokens.dart';
import '../utils/wall_path.dart';

/// شاغرة = أخضر · مشغولة = أحمر · طلب حساب = برتقالي.
class FloorPlanTablePainter extends CustomPainter {
  FloorPlanTablePainter({
    required this.tableNumber,
    required this.seatCount,
    required this.seatStyle,
    required this.state,
    required this.selected,
    this.occupiedLabel,
  });

  final String tableNumber;
  final int seatCount;
  final RestaurantTableSeatStyle seatStyle;
  final DerivedTableState state;
  final bool selected;
  /// مثل «12 د» تحت الرقم عند الانشغال.
  final String? occupiedLabel;

  Color get _fill {
    switch (state) {
      case DerivedTableState.available:
        return const Color(0xFF14532D);
      case DerivedTableState.occupied:
        return const Color(0xFF7F1D1D);
      case DerivedTableState.awaitingPayment:
        return const Color(0xFF9A3412);
    }
  }

  Color get _rim {
    switch (state) {
      case DerivedTableState.available:
        return const Color(0xFF22C55E);
      case DerivedTableState.occupied:
        return const Color(0xFFEF4444);
      case DerivedTableState.awaitingPayment:
        return const Color(0xFFF59E0B);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final tableW = size.width * 0.46;
    final tableH = size.height * 0.34;

    final fill = Paint()
      ..color = _fill
      ..style = PaintingStyle.fill;
    final rim = Paint()
      ..color = selected ? RestaurantOsTokens.amber : _rim
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.8 : 2.0;

    final seats = seatCount >= 6 ? 6 : 4;
    final angles = <double>[];
    if (seatStyle == RestaurantTableSeatStyle.wall) {
      if (seats == 4) {
        angles.addAll(
          [math.pi * 0.15, math.pi * 0.85, math.pi * 1.15, math.pi * 1.85],
        );
      } else {
        angles.addAll([
          math.pi * 0.12,
          math.pi * 0.35,
          math.pi * 0.65,
          math.pi * 0.88,
          math.pi * 1.15,
          math.pi * 1.85,
        ]);
      }
    } else {
      final step = (math.pi * 2) / seats;
      for (var i = 0; i < seats; i++) {
        angles.add(-math.pi / 2 + i * step);
      }
    }

    final chairR = size.shortestSide * 0.09;
    final orbit = size.shortestSide * 0.38;
    final chairFill = Paint()..color = const Color(0xFF1E293B);
    final chairRim = Paint()
      ..color = _rim.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final a in angles) {
      final x = cx + math.cos(a) * orbit;
      final y = cy + math.sin(a) * orbit;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, y),
          width: chairR * 2.1,
          height: chairR * 1.7,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, chairFill);
      canvas.drawRRect(rect, chairRim);
    }

    final tableRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: tableW, height: tableH),
      const Radius.circular(6),
    );
    canvas.drawRRect(tableRect, fill);
    canvas.drawRRect(tableRect, rim);

    final label = occupiedLabel == null || occupiedLabel!.isEmpty
        ? tableNumber
        : '$tableNumber\n$occupiedLabel';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: RestaurantOsTokens.bone,
          fontSize: occupiedLabel == null
              ? size.shortestSide * 0.18
              : size.shortestSide * 0.13,
          fontWeight: FontWeight.w900,
          height: 1.1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    )..layout(maxWidth: tableW);
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant FloorPlanTablePainter oldDelegate) {
    return oldDelegate.tableNumber != tableNumber ||
        oldDelegate.seatCount != seatCount ||
        oldDelegate.seatStyle != seatStyle ||
        oldDelegate.state != state ||
        oldDelegate.selected != selected ||
        oldDelegate.occupiedLabel != occupiedLabel;
  }
}

/// رسم عنصر ثابت على المخطّط (كاشير، باب، حمّام…).
class FloorPlanFixturePainter extends CustomPainter {
  FloorPlanFixturePainter({
    required this.kind,
    required this.label,
    required this.selected,
  });

  final RestaurantFloorFixtureKind kind;
  final String label;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = selected
          ? RestaurantOsTokens.amber
          : RestaurantOsTokens.bone.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.2 : 1.4;
    final fill = Paint()
      ..color = RestaurantOsTokens.charcoalHigh.withValues(alpha: 0.92);

    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(kind == RestaurantFloorFixtureKind.wall ? 2 : 4),
    );
    final skipChrome = kind == RestaurantFloorFixtureKind.hallFrame ||
        kind.isZone ||
        kind == RestaurantFloorFixtureKind.entrance ||
        kind == RestaurantFloorFixtureKind.exit ||
        kind == RestaurantFloorFixtureKind.wall;
    if (!skipChrome) {
      canvas.drawRRect(r, fill);
      canvas.drawRRect(r, stroke);
    }

    final cx = size.width / 2;
    final cy = size.height * 0.38;
    final icon = Paint()
      ..color = RestaurantOsTokens.amberSoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    switch (kind) {
      case RestaurantFloorFixtureKind.hallFrame:
        final frameStroke = Paint()
          ..color = selected
              ? RestaurantOsTokens.amber
              : RestaurantOsTokens.amber.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 5 : 4;
        final inner = RRect.fromRectAndRadius(
          Rect.fromLTWH(3, 3, size.width - 6, size.height - 6),
          const Radius.circular(2),
        );
        canvas.drawRRect(inner, frameStroke);
        final labelTp = TextPainter(
          text: TextSpan(
            text: 'إطار القاعة النهائي',
            style: TextStyle(
              color: RestaurantOsTokens.amberSoft.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.rtl,
        )..layout();
        labelTp.paint(canvas, const Offset(12, 8));
        return;
      case RestaurantFloorFixtureKind.zoneSeating:
      case RestaurantFloorFixtureKind.zoneKitchen:
      case RestaurantFloorFixtureKind.zoneCashier:
      case RestaurantFloorFixtureKind.zoneBathroom:
        final wash = switch (kind) {
          RestaurantFloorFixtureKind.zoneSeating =>
            const Color(0xFF1E3A5F).withValues(alpha: 0.35),
          RestaurantFloorFixtureKind.zoneKitchen =>
            const Color(0xFF3F3A32).withValues(alpha: 0.40),
          RestaurantFloorFixtureKind.zoneCashier =>
            RestaurantOsTokens.amber.withValues(alpha: 0.18),
          RestaurantFloorFixtureKind.zoneBathroom =>
            const Color(0xFF2A4A4A).withValues(alpha: 0.38),
          _ => RestaurantOsTokens.bone.withValues(alpha: 0.1),
        };
        final borderColor = switch (kind) {
          RestaurantFloorFixtureKind.zoneKitchen =>
            RestaurantOsTokens.bone.withValues(alpha: 0.35),
          RestaurantFloorFixtureKind.zoneCashier => RestaurantOsTokens.amber,
          RestaurantFloorFixtureKind.zoneBathroom => const Color(0xFF5F9E9E),
          _ => RestaurantOsTokens.bone.withValues(alpha: 0.25),
        };
        final zoneR = RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(8),
        );
        canvas.drawRRect(zoneR, Paint()..color = wash);
        canvas.drawRRect(
          zoneR,
          Paint()
            ..color = selected ? RestaurantOsTokens.amber : borderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 2.4 : 1.4
            ..strokeJoin = StrokeJoin.round,
        );
        if (kind == RestaurantFloorFixtureKind.zoneKitchen) {
          final dash = Paint()
            ..color = borderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2;
          const step = 10.0;
          for (double x = 8; x < size.width - 8; x += step * 2) {
            canvas.drawLine(
              Offset(x, 8),
              Offset(math.min(x + step, size.width - 8), 8),
              dash,
            );
            canvas.drawLine(
              Offset(x, size.height - 8),
              Offset(math.min(x + step, size.width - 8), size.height - 8),
              dash,
            );
          }
        }
        final ztp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: RestaurantOsTokens.bone.withValues(alpha: 0.85),
              fontSize: (size.shortestSide * 0.12).clamp(11, 16),
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.rtl,
        )..layout(maxWidth: size.width - 16);
        ztp.paint(canvas, Offset(cx - ztp.width / 2, 12));
        return;
      case RestaurantFloorFixtureKind.wall:
        _paintWall(canvas, size, selected);
        return;
      case RestaurantFloorFixtureKind.entrance:
        _paintDoorway(canvas, size, selected: selected, isExit: false);
        return;
      case RestaurantFloorFixtureKind.exit:
        _paintDoorway(canvas, size, selected: selected, isExit: true);
        return;
      case RestaurantFloorFixtureKind.cashier:
        canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, cy), width: 22, height: 14),
          icon,
        );
        canvas.drawLine(Offset(cx - 8, cy - 10), Offset(cx + 8, cy - 10), icon);
        break;
      case RestaurantFloorFixtureKind.bathroom:
        canvas.drawCircle(Offset(cx - 6, cy), 5, icon);
        canvas.drawCircle(Offset(cx + 6, cy), 5, icon);
        break;
      case RestaurantFloorFixtureKind.stairs:
        for (var i = 0; i < 4; i++) {
          final y = cy - 10 + i * 6.0;
          canvas.drawLine(
            Offset(cx - 12 + i * 2, y),
            Offset(cx + 12 - i * 2, y),
            icon,
          );
        }
        break;
      case RestaurantFloorFixtureKind.arrow:
        final path = Path()
          ..moveTo(8, size.height / 2)
          ..lineTo(size.width - 14, size.height / 2)
          ..moveTo(size.width - 22, size.height / 2 - 8)
          ..lineTo(size.width - 10, size.height / 2)
          ..lineTo(size.width - 22, size.height / 2 + 8);
        canvas.drawPath(path, icon);
        break;
      case RestaurantFloorFixtureKind.text:
        break;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: RestaurantOsTokens.bone.withValues(alpha: 0.9),
          fontSize: (size.shortestSide * 0.14).clamp(10, 14),
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.rtl,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: size.width - 8);
    tp.paint(
      canvas,
      Offset(cx - tp.width / 2, size.height * 0.62 - tp.height / 2),
    );
  }

  void _paintWall(Canvas canvas, Size size, bool selected) {
    // احتياطي إذا رُسم الجدار كمستطيل — خط رفيع في المنتصف.
    final horizontal = size.width >= size.height;
    final p = Paint()
      ..color = selected
          ? RestaurantOsTokens.amber
          : const Color(0xFF94A3B8)
      ..strokeWidth = WallPath.strokePx
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (horizontal) {
      final y = size.height / 2;
      canvas.drawLine(Offset(4, y), Offset(size.width - 4, y), p);
    } else {
      final x = size.width / 2;
      canvas.drawLine(Offset(x, 4), Offset(x, size.height - 4), p);
    }
  }

  void _paintDoorway(
    Canvas canvas,
    Size size, {
    required bool selected,
    required bool isExit,
  }) {
    final accent = isExit
        ? const Color(0xFFEF4444)
        : const Color(0xFF22C55E);
    final frame = Paint()
      ..color = selected ? RestaurantOsTokens.amber : accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.6 : 2.0
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    // إطار باب مقوّس
    final doorW = w * 0.55;
    final doorH = h * 0.72;
    final left = (w - doorW) / 2;
    final top = h * 0.18;
    final path = Path()
      ..moveTo(left, top + doorH)
      ..lineTo(left, top + doorH * 0.35)
      ..arcToPoint(
        Offset(left + doorW, top + doorH * 0.35),
        radius: Radius.elliptical(doorW / 2, doorH * 0.28),
        clockwise: true,
      )
      ..lineTo(left + doorW, top + doorH);
    canvas.drawPath(path, frame);

    // ورقة الباب مفتوحة قليلاً
    final leaf = Path()
      ..moveTo(left + doorW * 0.08, top + doorH)
      ..lineTo(left + doorW * 0.08, top + doorH * 0.4)
      ..lineTo(left + doorW * 0.72, top + doorH * 0.38)
      ..lineTo(left + doorW * 0.72, top + doorH);
    canvas.drawPath(
      leaf,
      Paint()
        ..color = accent.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(leaf, frame);

    // سهم اتجاه
    final midY = top + doorH * 0.55;
    final arrow = Paint()
      ..color = accent
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (isExit) {
      canvas.drawLine(
        Offset(w * 0.28, midY),
        Offset(w * 0.72, midY),
        arrow,
      );
      canvas.drawLine(
        Offset(w * 0.58, midY - 7),
        Offset(w * 0.72, midY),
        arrow,
      );
      canvas.drawLine(
        Offset(w * 0.58, midY + 7),
        Offset(w * 0.72, midY),
        arrow,
      );
    } else {
      canvas.drawLine(
        Offset(w * 0.72, midY),
        Offset(w * 0.28, midY),
        arrow,
      );
      canvas.drawLine(
        Offset(w * 0.42, midY - 7),
        Offset(w * 0.28, midY),
        arrow,
      );
      canvas.drawLine(
        Offset(w * 0.42, midY + 7),
        Offset(w * 0.28, midY),
        arrow,
      );
    }

    final tp = TextPainter(
      text: TextSpan(
        text: isExit ? 'مخرج' : 'مدخل',
        style: TextStyle(
          color: RestaurantOsTokens.bone.withValues(alpha: 0.9),
          fontSize: (size.shortestSide * 0.14).clamp(10, 13),
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, Offset((w - tp.width) / 2, h - tp.height - 4));
  }

  @override
  bool shouldRepaint(covariant FloorPlanFixturePainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.label != label ||
        oldDelegate.selected != selected;
  }
}

/// رسم جدار كمسار رفيع موحّد السمك على إحداثيات اللوحة.
class FloorPlanWallPathPainter extends CustomPainter {
  FloorPlanWallPathPainter({
    required this.pointsPx,
    required this.selected,
  });

  final List<Offset> pointsPx;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (pointsPx.length < 2) return;
    final path = Path()..moveTo(pointsPx.first.dx, pointsPx.first.dy);
    for (var i = 1; i < pointsPx.length; i++) {
      path.lineTo(pointsPx[i].dx, pointsPx[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = selected
            ? RestaurantOsTokens.amber
            : const Color(0xFF94A3B8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = WallPath.strokePx
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (selected) {
      for (final p in pointsPx) {
        canvas.drawCircle(
          p,
          5,
          Paint()..color = RestaurantOsTokens.amber,
        );
      }
      // مقبض الطول عند النهاية
      canvas.drawCircle(
        pointsPx.last,
        9,
        Paint()
          ..color = RestaurantOsTokens.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FloorPlanWallPathPainter oldDelegate) {
    if (oldDelegate.selected != selected) return true;
    if (oldDelegate.pointsPx.length != pointsPx.length) return true;
    for (var i = 0; i < pointsPx.length; i++) {
      if (oldDelegate.pointsPx[i] != pointsPx[i]) return true;
    }
    return false;
  }
}

