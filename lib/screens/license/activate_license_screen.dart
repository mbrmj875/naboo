import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/license_service.dart';

const Color _kAccent = Color(0xFF1E3A5F);

class ActivateLicenseScreen extends StatefulWidget {
  const ActivateLicenseScreen({super.key, this.showBackButton = false});
  final bool showBackButton;

  @override
  State<ActivateLicenseScreen> createState() => _ActivateLicenseScreenState();
}

class _ActivateLicenseScreenState extends State<ActivateLicenseScreen> {
  final _keyCtrl    = TextEditingController();
  final _focusNode  = FocusNode();
  bool  _loading    = false;
  String? _error;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_loading) return;
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'أدخل مفتاح الترخيص');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final result = await LicenseService.instance.activateLicense(key);
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.ok) {
      setState(() => _error = result.message);
    }
    // إذا نجح التفعيل → LicenseGate تعيد البناء تلقائياً
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _kAccent,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // شعار
                const Text(
                  'NaBoo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
                const Text(
                  'نظام إدارة المتاجر',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 40),

                // بطاقة التفعيل
                Container(
                  width: 440,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.lock_open_outlined,
                        size: 48,
                        color: _kAccent,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'تفعيل الترخيص',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _kAccent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'أدخل مفتاح الترخيص للحصول على 15 يوم تجربة مجانية',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),

                      // حقل المفتاح
                      TextField(
                        controller: _keyCtrl,
                        focusNode: _focusNode,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                        decoration: InputDecoration(
                          hintText: 'NABOO-XXXX-XXXX-XXXX',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                            letterSpacing: 1,
                          ),
                          errorText: _error,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: _kAccent, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          suffixIcon: _keyCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _keyCtrl.clear();
                                    setState(() => _error = null);
                                  },
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() => _error = null),
                        onSubmitted: (_) => _activate(),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9\-]'),
                          ),
                          TextInputFormatter.withFunction((old, n) =>
                              n.copyWith(text: n.text.toUpperCase())),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // زر التفعيل
                      SizedBox(
                        height: 50,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _kAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _loading ? null : _activate,
                          child: _loading
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'تفعيل',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      // معلومات المساعدة
                      Row(
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'للحصول على مفتاح ترخيص، تواصل مع فريق NaBoo.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Text(
                  'NaBoo v2.0 — جميع الحقوق محفوظة',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
