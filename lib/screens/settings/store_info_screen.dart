import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/print_settings_data.dart';
import '../../providers/print_settings_provider.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/print_settings_repository.dart';
import '../../utils/screen_layout.dart';
import '../../utils/store_logo_codec.dart';
import '../../verticals/oil_change/widgets/oil_change_form_theme.dart';

/// بيانات المتجر — تُحفظ محلياً وتُزامن للحساب، وتُستخدم في الإيصال وواتساب.
class StoreInfoScreen extends StatefulWidget {
  const StoreInfoScreen({super.key});

  @override
  State<StoreInfoScreen> createState() => _StoreInfoScreenState();
}

class _StoreInfoScreenState extends State<StoreInfoScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final List<TextEditingController> _phones = [TextEditingController()];
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  bool _pickingLogo = false;
  /// تعديلات محلية لم تُحفظ بعد — لا نسمح للمزامنة بمسح النموذج.
  bool _dirty = false;
  String? _error;

  /// شعار مؤقت قبل الحفظ (أو من الإعدادات المحمّلة).
  Uint8List? _logoBytes;
  String? _logoMime;
  bool _logoCleared = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_markDirty);
    _address.addListener(_markDirty);
    for (final c in _phones) {
      c.addListener(_markDirty);
    }
    CloudSyncService.instance.remoteImportGeneration.addListener(_onCloudImport);
    unawaited(_load(initial: true));
  }

  @override
  void dispose() {
    CloudSyncService.instance.remoteImportGeneration.removeListener(
      _onCloudImport,
    );
    _name.removeListener(_markDirty);
    _address.removeListener(_markDirty);
    _name.dispose();
    _address.dispose();
    for (final c in _phones) {
      c.removeListener(_markDirty);
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (_loading || _dirty) return;
    _dirty = true;
  }

  void _onCloudImport() {
    // أثناء الكتابة أو اختيار الشعار: إعادة التحميل كانت تمسح الحقول.
    if (!mounted || _saving || _pickingLogo || _dirty) return;
    unawaited(_load(initial: false));
  }

  TextEditingController _phoneController([String text = '']) {
    final c = TextEditingController(text: text);
    c.addListener(_markDirty);
    return c;
  }

  Future<void> _load({required bool initial}) async {
    if (initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final p = await PrintSettingsRepository.instance
          .loadStoreIdentityForActiveUser();
      if (!mounted) return;
      // استيراد سحابي وصل بعد أن بدأ المستخدم بالتعديل — لا نمسّ النموذج.
      if (!initial && (_dirty || _pickingLogo || _saving)) return;

      _name.removeListener(_markDirty);
      _address.removeListener(_markDirty);
      _name.text = p.storeTitleLine.trim();
      _address.text = p.storeAddress.trim();
      _name.addListener(_markDirty);
      _address.addListener(_markDirty);

      for (final c in _phones) {
        c.removeListener(_markDirty);
        c.dispose();
      }
      _phones
        ..clear()
        ..addAll(
          p.storePhones.isEmpty
              ? [_phoneController()]
              : p.storePhones.map((phone) => _phoneController(phone)),
        );
      setState(() {
        _logoBytes = p.storeLogoBytes;
        _logoMime = p.storeLogoMime;
        _logoCleared = false;
        _dirty = false;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل بيانات المتجر';
      });
    }
  }

  void _addPhoneField() {
    setState(() {
      _phones.add(_phoneController());
      _dirty = true;
    });
  }

  void _removePhoneField(int index) {
    if (_phones.length <= 1) {
      _phones.first.clear();
      _dirty = true;
      return;
    }
    setState(() {
      final c = _phones.removeAt(index);
      c.removeListener(_markDirty);
      c.dispose();
      _dirty = true;
    });
  }

  List<String> _collectPhones() =>
      _phones.map((c) => c.text.trim()).where((p) => p.isNotEmpty).toList();

  Future<void> _pickLogo() async {
    if (_saving || _pickingLogo) return;
    setState(() => _pickingLogo = true);
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        // لا نفرض جودة ضعيفة — الضغط يتم عبر StoreLogoCodec مع الحفاظ على الشفافية.
        requestFullMetadata: false,
      );
      if (x == null) return;
      final raw = await x.readAsBytes();
      final prepared = StoreLogoCodec.prepare(raw);
      if (!mounted) return;
      if (prepared == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذّر استخدام الصورة. اختر PNG أو JPG بحجم مناسب كشعار',
            ),
          ),
        );
        return;
      }
      setState(() {
        _logoBytes = prepared.bytes;
        _logoMime = prepared.mime;
        _logoCleared = false;
        _dirty = true;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر اختيار الشعار')),
      );
    } finally {
      if (mounted) setState(() => _pickingLogo = false);
    }
  }

  void _clearLogo() {
    setState(() {
      _logoBytes = null;
      _logoMime = null;
      _logoCleared = true;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم المتجر')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final phones = _collectPhones();
      PrintSettingsData next = PrintSettingsData.defaults().copyWith(
        storeTitleLine: name,
        storeAddress: _address.text.trim(),
        storePhones: phones,
      );
      if (_logoCleared) {
        next = next.copyWith(clearStoreLogo: true);
      } else if (_logoBytes != null && _logoBytes!.isNotEmpty) {
        next = next.copyWith(
          storeLogoBase64: base64Encode(_logoBytes!),
          storeLogoMime: _logoMime ?? 'image/png',
        );
      }
      if (mounted) {
        await context.read<PrintSettingsProvider>().saveStoreIdentity(next);
      } else {
        await PrintSettingsRepository.instance
            .saveStoreIdentityForActiveUser(next);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم حفظ بيانات المتجر لهذا الموظف ورفعها للسحابة — '
            'ستظهر على أجهزتك عند دخوله بعد المزامنة',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final noStaff = e is StateError;
      setState(() {
        _error = noStaff
            ? 'اختر موظفاً من شاشة «من سيبدأ العمل؟» ثم أعد الحفظ'
            : 'تعذّر الحفظ. حاول مرة أخرى.';
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layout = ScreenLayout.of(context);
    final pad = layout.pageHorizontalGap;
    final hasLogo = _logoBytes != null && _logoBytes!.isNotEmpty;

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: OilChangeFormTheme.appBar(
            context: context,
            title: 'بيانات المتجر',
            actions: [
              TextButton(
                onPressed: _loading || _saving ? null : _save,
                child: Text(
                  _saving ? 'جارٍ الحفظ…' : 'حفظ',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: OilChangeFormTheme.gold,
                  ),
                ),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: EdgeInsetsDirectional.fromSTEB(pad, 16, pad, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'لكل موظف من شاشة «من سيبدأ العمل؟» اسم وشعار وعنوان خاص به فقط. '
                        'لا تُشارك بين محمد والقبلة أو أي موظف آخر. '
                        'تُحفظ على السحابة وتبقى بعد حذف التطبيق عند الدخول بنفس الرمز.',
                        style: TextStyle(
                          color: OilChangeFormTheme.secondaryText(context),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.start,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Center(
                        child: Column(
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _saving || _pickingLogo ? null : _pickLogo,
                                customBorder: const CircleBorder(),
                                child: Ink(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: OilChangeFormTheme.gold
                                        .withValues(alpha: 0.12),
                                    border: Border.all(
                                      color: OilChangeFormTheme.gold
                                          .withValues(alpha: 0.55),
                                      width: 1.5,
                                    ),
                                    image: hasLogo
                                        ? DecorationImage(
                                            image: MemoryImage(_logoBytes!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: hasLogo
                                      ? (_pickingLogo
                                          ? const Center(
                                              child: SizedBox(
                                                width: 28,
                                                height: 28,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                ),
                                              ),
                                            )
                                          : null)
                                      : Center(
                                          child: _pickingLogo
                                              ? const SizedBox(
                                                  width: 28,
                                                  height: 28,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.add_a_photo_rounded,
                                                  size: 36,
                                                  color:
                                                      OilChangeFormTheme.gold,
                                                ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              hasLogo
                                  ? 'اضغط لتغيير الشعار'
                                  : 'اضغط لإضافة شعار المتجر',
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    OilChangeFormTheme.secondaryText(context),
                              ),
                            ),
                            if (hasLogo)
                              TextButton(
                                onPressed: _saving ? null : _clearLogo,
                                child: Text(
                                  'إزالة الشعار',
                                  style: TextStyle(
                                    color: cs.error.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _StoreField(
                        controller: _name,
                        label: 'اسم المتجر',
                        icon: Icons.store_rounded,
                      ),
                      const SizedBox(height: 14),
                      _StoreField(
                        controller: _address,
                        label: 'العنوان',
                        icon: Icons.location_on_rounded,
                        minLines: 1,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_rounded,
                            size: 20,
                            color: OilChangeFormTheme.gold,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'أرقام هاتف المتجر',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: OilChangeFormTheme.emphasisText(context),
                            ),
                            textAlign: TextAlign.start,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _saving ? null : _addPhoneField,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('إضافة رقم'),
                            style: TextButton.styleFrom(
                              foregroundColor: OilChangeFormTheme.gold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _phones.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _StoreField(
                                controller: _phones[i],
                                label: i == 0
                                    ? 'الهاتف الرئيسي'
                                    : 'هاتف إضافي ${i + 1}',
                                icon: Icons.phone_rounded,
                                keyboard: TextInputType.phone,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.start,
                              ),
                            ),
                            if (_phones.length > 1) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'حذف الرقم',
                                onPressed:
                                    _saving ? null : () => _removePhoneField(i),
                                icon: Icon(
                                  Icons.remove_circle_outline_rounded,
                                  color: cs.error.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _StoreField extends StatelessWidget {
  const _StoreField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboard = TextInputType.text,
    this.minLines = 1,
    this.maxLines = 1,
    this.textDirection,
    this.textAlign,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboard;
  final int minLines;
  final int maxLines;
  final TextDirection? textDirection;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      minLines: minLines,
      maxLines: maxLines,
      textDirection: textDirection,
      textAlign: textAlign ?? TextAlign.start,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: OilChangeFormTheme.gold, size: 22),
      ),
    );
  }
}
