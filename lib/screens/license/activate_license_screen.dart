import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/license_service.dart';
import '../../widgets/secure_screen.dart';

class ActivateLicenseScreen extends StatefulWidget {
  const ActivateLicenseScreen({super.key, this.showBackButton = false});
  final bool showBackButton;

  @override
  State<ActivateLicenseScreen> createState() => _ActivateLicenseScreenState();
}

class _ActivateLicenseScreenState extends State<ActivateLicenseScreen> {
  final _keyCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
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
    setState(() {
      _loading = true;
      _error = null;
    });
    final isJwt = key.split('.').length == 3;
    final result = isJwt
        ? await LicenseService.instance.activateSignedToken(key)
        : await LicenseService.instance.activateLicense(key);
    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.ok) {
      setState(() => _error = result.message);
    }
    // إذا نجح التفعيل → LicenseGate تعيد البناء تلقائياً
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SecureScreen(
      child: Scaffold(
        backgroundColor: cs.primary,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'NaBoo',
                style: TextStyle(
                  color: cs.onPrimary,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              Text(
                'نظام إدارة المتاجر',
                style: TextStyle(
                  color: cs.onPrimary.withOpacity(0.75),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 40),

              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.lock_open_outlined,
                          size: 48,
                          color: cs.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'تفعيل الترخيص',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'أدخل مفتاح الترخيص للمتابعة',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),

                        TextField(
                          controller: _keyCtrl,
                          focusNode: _focusNode,
                          textAlign: TextAlign.start,
                          textDirection: TextDirection.ltr,
                          maxLines: 3,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText: 'NABOO-XXXX-XXXX-XXXX أو JWT',
                            errorText: _error,
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
                              RegExp(r'[a-zA-Z0-9\-\._]'),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: _loading ? null : _activate,
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'تفعيل',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        Divider(color: cs.outlineVariant),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'للحصول على مفتاح ترخيص، تواصل مع فريق NaBoo.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Text(
                'NaBoo v2.0 — جميع الحقوق محفوظة',
                style: TextStyle(
                  color: cs.onPrimary.withOpacity(0.45),
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
