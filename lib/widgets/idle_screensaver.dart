import 'dart:async';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../theme/design_tokens.dart';

/// شاشة سكون عصرية متناسقة مع هوية «نظام إدارة الأعمال».
class IdleScreensaver extends StatefulWidget {
  const IdleScreensaver({
    super.key,
    required this.isDark,
    this.userLabel,
    this.onWake,
  });

  final bool isDark;
  final String? userLabel;
  final VoidCallback? onWake;

  @override
  State<IdleScreensaver> createState() => _IdleScreensaverState();
}

class _IdleScreensaverState extends State<IdleScreensaver> {
  late DateTime _now;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final timeFmt = DateFormat('HH:mm', 'en');
    final dateFmt = DateFormat('dd/MM/yyyy', 'ar');

    final isDark = widget.isDark;
    final onWake = widget.onWake;
    final displayName = widget.userLabel?.trim();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onWake,
      onPanDown: (_) => onWake?.call(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // خلفية متدرّجة
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: isDark
                    ? [
                        const Color(0xFF0A1628),
                        const Color(0xFF0F2847),
                        const Color(0xFF0D3D4A),
                      ]
                    : [
                        const Color(0xFFE8EEF5),
                        const Color(0xFFD4E4F0),
                        const Color(0xFFC8E6E9),
                      ],
              ),
            ),
          ),
          // ضباب خفيف
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                    Colors.transparent,
                    Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ClipRRect(
                borderRadius: BorderRadius.zero,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 32,
                    ),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : AppColors.primary)
                          .withValues(alpha: isDark ? 0.06 : 0.85),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.45),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hub_rounded,
                          size: 52,
                          color: isDark
                              ? AppColors.accent
                              : AppColors.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          timeFmt.format(now),
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w200,
                            letterSpacing: 2,
                            color: isDark ? Colors.white : AppColors.primary,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          dateFmt.format(now),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: isDark
                                ? Colors.white70
                                : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          width: 48,
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.accent,
                                AppColors.primary,
                              ],
                            ),
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'نظام إدارة الأعمال',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'وضع السكون — الجلسة محمية',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? Colors.white60
                                : Colors.black45,
                          ),
                        ),
                        if (displayName != null && displayName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.accent.withValues(alpha: 0.95),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(height: 28),
                        FilledButton.icon(
                          onPressed: onWake,
                          icon: const Icon(Icons.touch_app_rounded, size: 20),
                          label: const Text('المتابعة'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'اضغط في أي مكان أو زر المتابعة',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
