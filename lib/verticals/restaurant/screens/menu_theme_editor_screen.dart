import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../platform/persist_local_bytes.dart';
import '../../../services/tenant_context.dart';
import '../services/menu_theme_repository.dart';
import '../services/restaurant_realtime_service.dart';
import '../theme/presets/presets.dart';
import '../theme/restaurant_menu_interactive_preview.dart';
import '../theme/theme_schema_validator.dart';
import '../theme/gallery_catalog.dart';
import '../theme/layout_slots.dart';
import '../widgets/menu_color_picker_sheet.dart';
import '../widgets/menu_preset_thumb.dart';
import '../widgets/menu_template_train_picker.dart';

class MenuThemeEditorScreen extends StatefulWidget {
  const MenuThemeEditorScreen({super.key});

  @override
  State<MenuThemeEditorScreen> createState() => _MenuThemeEditorScreenState();
}

class _MenuThemeEditorScreenState extends State<MenuThemeEditorScreen> {
  final _repo = MenuThemeRepository();
  final _picker = ImagePicker();

  bool _loading = true;
  String? _error;
  RestaurantThemeCustomization _draft =
      RestaurantThemeCustomization.defaults();
  int _draftVersion = 0;
  int _publishedVersion = 0;
  bool _hasPublished = false;
  bool _advancedOpen = false;

  final _nameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  StreamSubscription<int>? _themeRtSub;
  int? _cloudPublishedVersion;

  @override
  void initState() {
    super.initState();
    _load();
    try {
      final tid = TenantContext.instance.requireTenantId();
      unawaited(RestaurantRealtimeService.instance.start(tenantUuid: tid));
      _themeRtSub = RestaurantRealtimeService.instance.themePublishedVersions
          .listen((v) {
        if (!mounted) return;
        setState(() => _cloudPublishedVersion = v);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('التعديلات المنشورة الآن (نسخة $v)')),
        );
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _themeRtSub?.cancel();
    _nameCtrl.dispose();
    _taglineCtrl.dispose();
    super.dispose();
  }

  void _syncControllers() {
    _nameCtrl.text = _draft.identity['display_name_ar'] ?? '';
    _taglineCtrl.text = _draft.identity['tagline_ar'] ?? '';
  }

  RestaurantThemeCustomization _liveTheme() {
    return _draft.copyWith(
      identity: {
        ..._draft.identity,
        'display_name_ar': _nameCtrl.text.trim(),
        'tagline_ar': _taglineCtrl.text.trim(),
      },
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await _repo.getOrCreate();
      final draft = RestaurantThemeCustomization.fromJsonString(row.draftJson);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _draftVersion = row.draftVersion;
        _publishedVersion = row.publishedVersion;
        _hasPublished =
            row.publishedJson != null && row.publishedJson!.isNotEmpty;
        _loading = false;
      });
      _syncControllers();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _saveDraft() async {
    final next = _liveTheme();
    final err = ThemeSchemaValidator.validate(next.toJson());
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    try {
      final row = await _repo.saveDraft(next);
      if (!mounted) return;
      setState(() {
        _draft = next;
        _draftVersion = row.draftVersion;
        _publishedVersion = row.publishedVersion;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ المسودة')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _publish() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نشر الثيم؟'),
        content: const Text(
          'سيظهر التصميم للزبائن على رابط المنيو وQR الطاولة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نشر'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _saveDraft();
    try {
      final row = await _repo.publish();
      if (!mounted) return;
      setState(() {
        _draftVersion = row.draftVersion;
        _publishedVersion = row.publishedVersion;
        _hasPublished = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم النشر')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _rollback() async {
    try {
      final row = await _repo.rollbackToPublished();
      final draft = RestaurantThemeCustomization.fromJsonString(row.draftJson);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _draftVersion = row.draftVersion;
        _publishedVersion = row.publishedVersion;
      });
      _syncControllers();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إعادة المسودة للمنشور')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _applyGalleryEntry(MenuGalleryEntry entry) {
    final arch = kRestaurantPresets[entry.preset]!;
    final colors = Map<String, String>.from(arch.defaultColors);
    if (entry.colorOverride != null) {
      colors.addAll(entry.colorOverride!);
    }
    setState(() {
      _draft = _draft.copyWith(
        presetKey: entry.preset,
        colors: colors,
        fontFamily: arch.defaultFont,
        layout: {
          ..._draft.layout,
          'item_layout': arch.defaultItemLayout.key,
        },
      );
    });
  }

  Future<void> _pickBrandImage({required bool logo}) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: logo ? 1024 : 2048,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final path = await persistLocalBytes(
      bytes: bytes,
      relativeDir: 'restaurant/brand',
      fileName:
          '${logo ? 'logo' : 'cover'}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    if (path.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ الصورة')),
      );
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        identity: {
          ..._draft.identity,
          if (logo) 'logo_url': path else 'cover_url': path,
        },
      );
    });
  }

  Future<void> _pickColor(String key, String label) async {
    final result = await showMenuColorPickerSheet(
      context: context,
      initialKey: key,
      colors: _draft.colors,
      onLiveChange: (live) {
        if (!mounted) return;
        setState(() {
          _draft = _draft.copyWith(colors: live);
        });
      },
    );
    if (!mounted || result == null) return;
    setState(() {
      _draft = _draft.copyWith(colors: result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final unpublished = _draftVersion != _publishedVersion || !_hasPublished;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('تصميم المنيو العام', style: TextStyle(fontSize: 18)),
            Text(
              'كما يظهر عبر QR والرابط على الهاتف',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: _saveDraft, child: const Text('حفظ مسودة')),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton(
              onPressed: _publish,
              child: const Text('نشر'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 880;
                    final editor = _buildEditor(unpublished);
                    final previewHeight = math.min(
                      640.0,
                      MediaQuery.sizeOf(context).height * 0.72,
                    );
                    final previewPane = Padding(
                      padding: const EdgeInsetsDirectional.all(12),
                      child: Column(
                        children: [
                          Text(
                            'معاينة تفاعلية · طبق · سلة · توصيل',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'جرّب الضغط على طبق، السلة، وبيانات التوصيل كما يراها الزبون',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF64748B),
                                ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: previewHeight,
                            child: RestaurantMenuInteractivePreview(
                              theme: _liveTheme(),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(child: editor),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: SingleChildScrollView(child: previewPane),
                          ),
                        ],
                      );
                    }
                    return ListView(
                      children: [
                        previewPane,
                        const Divider(),
                        editor,
                      ],
                    );
                  },
                ),
    );
  }

  Widget _buildEditor(bool unpublished) {
    final theme = Theme.of(context);
    final live = _liveTheme();
    final displayName = (_nameCtrl.text.trim().isEmpty)
        ? 'اسم مطعمك'
        : _nameCtrl.text.trim();
    return Padding(
      padding: const EdgeInsetsDirectional.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (unpublished)
            Chip(
              avatar: const Icon(Icons.info_outline, size: 18),
              label: Text(
                _hasPublished
                    ? 'تعديلات غير منشورة (مسودة $_draftVersion / منشور $_publishedVersion)'
                    : 'لم يُنشر بعد',
              ),
            ),
          if (_cloudPublishedVersion != null)
            Text(
              'آخر نشر سحابي: $_cloudPublishedVersion',
              style: theme.textTheme.labelMedium,
            ),
          if (_hasPublished)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _rollback,
                child: const Text('رجوع للمنشور'),
              ),
            ),
          // —— هوية المطعم أولاً ——
          Container(
            padding: const EdgeInsetsDirectional.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [
                  _parseHex(live.colors['primary'] ?? '#1E293B')
                      .withValues(alpha: 0.12),
                  _parseHex(live.colors['accent'] ?? '#B8960C')
                      .withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(
                color: _parseHex(live.colors['accent'] ?? '#B8960C')
                    .withValues(alpha: 0.35),
              ),
            ),
            child: _identityCardBody(displayName, live, theme),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم العرض',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _taglineCtrl,
            decoration: const InputDecoration(
              labelText: 'شعار قصير',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickBrandImage(logo: true),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('شعار المطعم'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickBrandImage(logo: false),
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('صورة ترحيب'),
                ),
              ),
            ],
          ),
          if (_draft.identity['logo_url'] != null ||
              _draft.identity['cover_url'] != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  if (_draft.identity['logo_url'] != null)
                    _thumb(_draft.identity['logo_url']!),
                  if (_draft.identity['cover_url'] != null)
                    _thumb(_draft.identity['cover_url']!, wide: true),
                ],
              ),
            ),
          const SizedBox(height: 14),
          MenuTemplateTrainPicker<MenuBrandLogoAlign>(
            title: 'موقع اللوجو',
            hint: 'اسحب القطار — اللوجو ينبض في مكانه قبل الاختيار',
            items: MenuBrandLogoAlign.values,
            selected: _draft.brandLogoAlign,
            labelOf: (v) => v.labelAr,
            cardWidth: 108,
            cardHeight: 118,
            previewBuilder: (_, v, __) =>
                MenuBrandLogoAlignTrainPreview(align: v),
            onSelected: (align) => setState(() {
              _draft = _draft.copyWith(
                layout: {
                  ..._draft.layout,
                  'brand_logo_align': align.key,
                },
              );
            }),
          ),
          const SizedBox(height: 14),
          MenuTemplateTrainPicker<MenuBrandTextPlacement>(
            title: 'موضع اسم المطعم',
            hint: 'بجانب اللوجو أو تحته — الشعار القصير دائماً تحت الاسم',
            items: MenuBrandTextPlacement.values,
            selected: _draft.brandTextPlacement,
            labelOf: (v) => v.labelAr,
            cardWidth: 124,
            cardHeight: 118,
            previewBuilder: (_, v, __) =>
                MenuBrandTextPlacementTrainPreview(placement: v),
            onSelected: (place) => setState(() {
              _draft = _draft.copyWith(
                layout: {
                  ..._draft.layout,
                  'brand_text_placement': place.key,
                },
              );
            }),
          ),
          const SizedBox(height: 14),
          MenuTemplateTrainPicker<MenuBrandTextAlign>(
            title: 'محاذاة الاسم والشعار القصير',
            hint: 'شاهد محاذاة الاسم والشعار القصير قبل التثبيت',
            items: MenuBrandTextAlign.values,
            selected: _draft.brandTextAlign,
            labelOf: (v) => v.labelAr,
            cardWidth: 108,
            cardHeight: 118,
            previewBuilder: (_, v, __) =>
                MenuBrandTextAlignTrainPreview(align: v),
            onSelected: (align) => setState(() {
              _draft = _draft.copyWith(
                layout: {
                  ..._draft.layout,
                  'brand_text_align': align.key,
                },
              );
            }),
          ),
          const SizedBox(height: 4),
          Text(
            'الشعار القصير يظهر دائماً تحت اسم المطعم',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'معرض التصاميم الجاهزة',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${kMenuGalleryEntries.length} بصمة هيكلية — كل بطاقة من إلهام Figma منفصل (ليس لوناً فقط)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 720
                  ? 4
                  : c.maxWidth >= 480
                      ? 3
                      : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: kMenuGalleryEntries.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemBuilder: (context, i) {
                  final entry = kMenuGalleryEntries[i];
                  final selected = _draft.presetKey == entry.preset;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: MenuPresetThumb(
                          presetKey: entry.preset,
                          selected: selected,
                          showCaption: false,
                          displayName: displayName,
                          logoUrl: live.identity['logo_url'],
                          colorOverride: entry.colorOverride,
                          onTap: () => _applyGalleryEntry(entry),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.labelAr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              selected ? FontWeight.w900 : FontWeight.w700,
                          color: selected
                              ? _parseHex(live.colors['accent'] ?? '#B8960C')
                              : null,
                        ),
                      ),
                      Text(
                        entry.familyLabelAr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'الألوان',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'اضغط أي لون لفتح لوحة الاختيار',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _colorChip('primary', 'أساسي'),
              _colorChip('accent', 'تمييز'),
              _colorChip('bg', 'خلفية'),
              _colorChip('text', 'نص'),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<RestaurantFontFamily>(
            value: _draft.fontFamily,
            decoration: const InputDecoration(
              labelText: 'الخط',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final f in RestaurantFontFamily.values)
                DropdownMenuItem(
                  value: f,
                  child: Text(
                    f.labelAr,
                    style: TextStyle(fontFamily: f.flutterFamily),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _draft = _draft.copyWith(fontFamily: v));
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<RestaurantMenuLanguage>(
            value: _draft.menuLanguage,
            decoration: const InputDecoration(
              labelText: 'لغة المنيو',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: RestaurantMenuLanguage.ar,
                child: Text('عربي'),
              ),
              DropdownMenuItem(
                value: RestaurantMenuLanguage.en,
                child: Text('English'),
              ),
              DropdownMenuItem(
                value: RestaurantMenuLanguage.bilingual,
                child: Text('ثنائي'),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _draft = _draft.copyWith(menuLanguage: v));
            },
          ),
          const SizedBox(height: 8),
          Text(
            'الاتجاه تلقائي: ${_draft.menuLanguage.layoutDirection.toUpperCase()} · مناسب للهواتف',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            initiallyExpanded: _advancedOpen,
            onExpansionChanged: (v) => setState(() => _advancedOpen = v),
            title: const Text(
              'إعدادات متقدمة',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'قطارات حيّة لشكل العرض والبحث والشريط والملف والحركة',
            ),
            children: [
              MenuTemplateTrainPicker<MenuHomeLayoutSlot>(
                title: 'شكل العرض',
                hint:
                    'قالب الصفحة وعرض الأصناف معاً — قائمة، شبكة، مجلّة، غلاف…',
                items: MenuHomeLayoutSlot.values,
                selected: _draft.homeLayoutSlot,
                labelOf: (v) => v.labelAr,
                cardWidth: 128,
                previewBuilder: (_, v, __) => MenuHomeTrainPreview(slot: v),
                onSelected: (slot) => setState(() {
                  final paired = slot.pairedItemLayoutKey ??
                      _draft.architecture.defaultItemLayout.key;
                  _draft = _draft.copyWith(
                    layout: {
                      ..._draft.layout,
                      'home_layout': slot.key,
                      'item_layout': paired,
                    },
                  );
                }),
              ),
              const SizedBox(height: 16),
              MenuTemplateTrainPicker<MenuSearchStyleSlot>(
                title: 'شكل البحث',
                hint: 'من Figma Search Kit — اسحب القطار وشاهد الشكل الحي',
                items: MenuSearchStyleSlot.values,
                selected: _draft.searchStyleSlot,
                labelOf: (v) => v.labelAr,
                previewBuilder: (_, v, __) => MenuSearchTrainPreview(slot: v),
                onSelected: (slot) => setState(() {
                  _draft = _draft.copyWith(
                    layout: {
                      ..._draft.layout,
                      'search_style': slot.key,
                    },
                  );
                }),
              ),
              const SizedBox(height: 16),
              MenuTemplateTrainPicker<MenuBottomNavSlot>(
                title: 'الشريط السفلي',
                hint: 'من مكتبات Figma للشريط السفلي — اسحب وشاهد الشكل الحي',
                items: MenuBottomNavSlot.values,
                selected: _draft.bottomNavSlot,
                labelOf: (v) => v.labelAr,
                previewBuilder: (_, v, __) =>
                    MenuBottomNavTrainPreview(slot: v),
                onSelected: (slot) => setState(() {
                  _draft = _draft.copyWith(
                    layout: {
                      ..._draft.layout,
                      'bottom_nav': slot.key,
                    },
                  );
                }),
              ),
              const SizedBox(height: 16),
              MenuTemplateTrainPicker<MenuProfileSheetSlot>(
                title: 'الملف الشخصي',
                hint: 'كيف يفتح ملف الضيف — بطاقة، ورقة، درج…',
                items: MenuProfileSheetSlot.values,
                selected: _draft.profileSheetSlot,
                labelOf: (v) => v.labelAr,
                previewBuilder: (_, v, __) => MenuProfileTrainPreview(slot: v),
                onSelected: (slot) => setState(() {
                  _draft = _draft.copyWith(
                    layout: {
                      ..._draft.layout,
                      'profile_sheet': slot.key,
                    },
                  );
                }),
              ),
              const SizedBox(height: 16),
              MenuTemplateTrainPicker<MenuMotionSlot>(
                title: 'حركة البطاقات',
                hint: 'كل قالب يتحرّك بنفسه — شاهد الحركة قبل الاختيار',
                items: MenuMotionSlot.values,
                selected: _draft.motionSlot,
                labelOf: (v) => v.labelAr,
                cardHeight: 140,
                previewBuilder: (_, v, __) => MenuMotionTrainPreview(slot: v),
                onSelected: (slot) => setState(() {
                  _draft = _draft.copyWith(
                    layout: {
                      ..._draft.layout,
                      'motion': slot.key,
                    },
                  );
                }),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'سرعة الحركة: ${_draft.motionDurationMs}ms',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'أقل مدة = أسرع · أعلى مدة = أبطأ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Slider(
                  value: _draft.motionDurationMs.toDouble().clamp(120, 1000),
                  min: 120,
                  max: 1000,
                  divisions: 44,
                  label: '${_draft.motionDurationMs}ms',
                  onChanged: (v) {
                    final ms = v.round();
                    final nearest = MenuMotionSpeedSlotX.nearestForMs(ms);
                    setState(() {
                      _draft = _draft.copyWith(
                        layout: {
                          ..._draft.layout,
                          'motion_ms': '$ms',
                          'motion_speed': nearest.key,
                          'motion_stagger_ms':
                              '${(ms * 0.14).round().clamp(8, 90)}',
                        },
                      );
                    });
                  },
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final speed in MenuMotionSpeedSlot.values)
                    ChoiceChip(
                      label: Text(speed.labelAr),
                      selected: _draft.motionDurationMs ==
                          speed.resolvedDurationMs,
                      onSelected: (_) => setState(() {
                        _draft = _draft.copyWith(
                          layout: {
                            ..._draft.layout,
                            'motion_speed': speed.key,
                            'motion_ms': '${speed.resolvedDurationMs}',
                            'motion_stagger_ms': '${speed.staggerMs}',
                          },
                        );
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              MenuTemplateTrainPicker<RestaurantWelcomeMode>(
                title: 'قبل الدخول للمنيو',
                hint: 'ماذا يرى الضيف قبل فتح المنيو',
                items: RestaurantWelcomeMode.values,
                selected: _draft.welcomeMode,
                labelOf: (v) => v.labelAr,
                previewBuilder: (_, v, __) => MenuWelcomeTrainPreview(mode: v),
                onSelected: (mode) => setState(() {
                  _draft = _draft.copyWith(
                    layout: {
                      ..._draft.layout,
                      'welcome_mode': mode.key,
                    },
                  );
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إظهار الأسعار'),
                value: _draft.toggles['show_prices'] ?? true,
                onChanged: (v) => setState(() {
                  _draft = _draft.copyWith(
                    toggles: {..._draft.toggles, 'show_prices': v},
                  );
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إظهار الأوصاف'),
                value: _draft.toggles['show_item_descriptions'] ?? true,
                onChanged: (v) => setState(() {
                  _draft = _draft.copyWith(
                    toggles: {
                      ..._draft.toggles,
                      'show_item_descriptions': v,
                    },
                  );
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('شعار في الترويسة'),
                value: _draft.toggles['show_logo_in_header'] ?? true,
                onChanged: (v) => setState(() {
                  _draft = _draft.copyWith(
                    toggles: {..._draft.toggles, 'show_logo_in_header': v},
                  );
                }),
              ),
              const SizedBox(height: 8),
              MenuTemplateTrainPicker<MenuCategoryNavSlot>(
                title: 'شريط التصنيفات',
                hint: 'اسحب القطار — كل قالب يرسم شكل شريط الأصناف',
                items: MenuCategoryNavSlot.values,
                selected: _draft.categoryNavSlot,
                labelOf: (v) => v.labelAr,
                cardWidth: 128,
                previewBuilder: (_, v, __) =>
                    MenuCategoryTrainPreview(slot: v),
                onSelected: (slot) => setState(() {
                  _draft = _draft.copyWith(
                    layout: {
                      ..._draft.layout,
                      'category_nav': slot.key,
                    },
                    toggles: {
                      ..._draft.toggles,
                      'show_category_nav':
                          slot != MenuCategoryNavSlot.hidden,
                    },
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _parseHex(String hex) {
    final clean = hex.replaceFirst('#', '').trim();
    if (clean.length != 6) return const Color(0xFF1E293B);
    return Color(0xFF000000 | int.parse(clean, radix: 16));
  }

  Widget _identityCardBody(
    String displayName,
    RestaurantThemeCustomization live,
    ThemeData theme,
  ) {
    final tagline = _taglineCtrl.text.trim();
    final avatar = _identityAvatar(displayName, live);
    final textCross = switch (live.brandTextAlign) {
      MenuBrandTextAlign.end => CrossAxisAlignment.end,
      MenuBrandTextAlign.center => CrossAxisAlignment.center,
      MenuBrandTextAlign.start => CrossAxisAlignment.start,
    };
    final nameAlign = switch (live.brandTextAlign) {
      MenuBrandTextAlign.end => TextAlign.end,
      MenuBrandTextAlign.center => TextAlign.center,
      MenuBrandTextAlign.start => TextAlign.start,
    };
    final texts = Column(
      crossAxisAlignment: textCross,
      children: [
        Text(
          'هوية المطعم',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: nameAlign,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: _parseHex(live.colors['primary'] ?? '#1E293B'),
          ),
        ),
        if (tagline.isNotEmpty)
          Text(
            tagline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: nameAlign,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475569),
            ),
          )
        else
          Text(
            'تظهر فوراً في المعاينة والمنيو المنشور',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
      ],
    );

    if (live.brandTextPlacement == MenuBrandTextPlacement.under) {
      final colCross = switch (live.brandLogoAlign) {
        MenuBrandLogoAlign.start => CrossAxisAlignment.start,
        MenuBrandLogoAlign.center => CrossAxisAlignment.center,
        MenuBrandLogoAlign.end => CrossAxisAlignment.end,
      };
      return SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: colCross,
          children: [
            avatar,
            const SizedBox(height: 10),
            texts,
          ],
        ),
      );
    }

    switch (live.brandLogoAlign) {
      case MenuBrandLogoAlign.start:
        return Row(
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(child: texts),
          ],
        );
      case MenuBrandLogoAlign.end:
        return Row(
          children: [
            Expanded(child: texts),
            const SizedBox(width: 12),
            avatar,
          ],
        );
      case MenuBrandLogoAlign.center:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            avatar,
            const SizedBox(width: 12),
            Flexible(child: texts),
          ],
        );
    }
  }

  Widget _identityAvatar(String name, RestaurantThemeCustomization live) {
    final logo = live.identity['logo_url'];
    final accent = _parseHex(live.colors['accent'] ?? '#B8960C');
    final bg = _parseHex(live.colors['bg'] ?? '#0F172A');
    if (logo != null && logo.isNotEmpty) {
      return _thumb(logo);
    }
    return _monogramBox(name, accent, bg);
  }

  Widget _monogramBox(String name, Color accent, Color bg) {
    final initial = name.trim().isEmpty ? 'م' : name.trim().substring(0, 1);
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 22,
          color: bg,
        ),
      ),
    );
  }

  Widget _colorChip(String key, String label) {
    final hex = _draft.colors[key] ?? '#111827';
    final c = Color(int.parse('FF${hex.substring(1)}', radix: 16));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _pickColor(key, label),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 112,
          padding: const EdgeInsetsDirectional.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            color: const Color(0xFFFFFBF8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 36,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  boxShadow: [
                    BoxShadow(
                      color: c.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                hex.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(String path, {bool wide = false}) {
    Widget child;
    if (path.startsWith('http')) {
      child = Image.network(path, fit: BoxFit.cover);
    } else if (!kIsWeb && File(path).existsSync()) {
      child = Image.file(File(path), fit: BoxFit.cover);
    } else {
      child = const ColoredBox(color: Color(0xFF334155));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: wide ? 120 : 56,
        height: 56,
        child: child,
      ),
    );
  }
}
