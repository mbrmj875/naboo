import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../widgets/calculator_panel.dart';

/// شاشة كاملة للحاسبة (اختياري — الاستخدام الأساسي من الأيقونة العائمة).
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final GlobalKey<CalculatorPanelState> _panelKey =
      GlobalKey<CalculatorPanelState>();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: panel,
        appBar: AppBar(
          title: const Text('الحاسبة', style: TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'نسخ الناتج',
              icon: const Icon(Icons.copy_rounded, size: 22),
              onPressed: () =>
                  _panelKey.currentState?.copyToClipboard(context),
            ),
            IconButton(
              tooltip: 'مسح الكل',
              icon: const Icon(Icons.delete_outline_rounded, size: 22),
              onPressed: () => _panelKey.currentState?.clearAll(),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: CalculatorPanel(key: _panelKey),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
