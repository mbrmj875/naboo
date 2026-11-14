import 'dart:async';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../providers/print_settings_provider.dart';
import '../../models/staff_branch_profile.dart';
import '../../services/device_location_service.dart';
import '../../services/print_settings_repository.dart';
import '../../services/staff_branch_profile_repository.dart';
import '../../services/store_logo_processor.dart';
import '../../utils/screen_layout.dart';
import '../../verticals/oil_change/widgets/oil_change_form_theme.dart';
import '../../widgets/feedback/app_messenger.dart';
import 'store_location_picker_screen.dart';

const _previewTileUrl =
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

/// نطاق شاشة البيانات: متجر عام أو فرع المستخدم الحالي.
enum StoreInfoScope {
  /// بيانات المتجر المشتركة (صاحب العمل) — [print_settings].
  workspace,

  /// بيانات فرع الموظف الحالي — واتساب + إيصال باسمه.
  myBranch,
}

/// بيانات المتجر أو فرع الموظف — تظهر على إيصال البيع وواتساب.
class StoreInfoScreen extends StatefulWidget {
  const StoreInfoScreen({
    super.key,
    this.scope = StoreInfoScope.workspace,
  });

  final StoreInfoScope scope;

  @override
  State<StoreInfoScreen> createState() => _StoreInfoScreenState();
}

class _StoreInfoScreenState extends State<StoreInfoScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final List<TextEditingController> _phones = [TextEditingController()];

  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  String? _error;

  double? _latitude;
  double? _longitude;

  final _picker = ImagePicker();
  Uint8List? _logoBytes;
  bool _processingLogo = false;

  bool get _isMyBranch => widget.scope == StoreInfoScope.myBranch;

  String get _screenTitle =>
      _isMyBranch ? 'بيانات فرعي' : 'بيانات المتجر';

  String get _hintText => _isMyBranch
      ? 'هذه بياناتك أنت: اسم فرعك وشعارك وهاتفك. تظهر على واتساب '
          'وإيصال البيع عندما تعمل بهذا الحساب.'
      : 'تُستخدم هذه البيانات على إيصال البيع بعد كل عملية طباعة.';

  String get _nameLabel => _isMyBranch ? 'اسم الفرع / المحل' : 'اسم المتجر';

  String get _emptyNameError =>
      _isMyBranch ? 'أدخل اسم فرعك أو محلك' : 'أدخل اسم المتجر';

  String get _savedMessage => _isMyBranch
      ? 'تم حفظ بيانات فرعك — ستظهر على واتساب وإيصال البيع'
      : 'تم حفظ بيانات المتجر — ستظهر على إيصال البيع';

  String get _loadError =>
      _isMyBranch ? 'تعذّر تحميل بيانات فرعك' : 'تعذّر تحميل بيانات المتجر';

  bool get _hasLocation => _latitude != null && _longitude != null;

  /// الكاميرا متاحة على الهاتف فقط — سطح المكتب والويب يختاران ملفاً.
  bool get _cameraAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    for (final c in _phones) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isMyBranch) {
        final auth = context.read<AuthProvider>();
        final p = await StaffBranchProfileRepository.instance.loadForUser(
          userGlobalId: auth.userGlobalId,
          userId: auth.userId,
        );
        if (!mounted) return;
        _applyIdentity(
          name: p.storeTitleLine,
          address: p.storeAddress,
          phones: p.storePhones,
          latitude: p.storeLatitude,
          longitude: p.storeLongitude,
          logoBytes: p.storeLogoBytes,
        );
      } else {
        final p = await PrintSettingsRepository.instance.load();
        if (!mounted) return;
        _applyIdentity(
          name: p.storeTitleLine,
          address: p.storeAddress,
          phones: p.storePhones,
          latitude: p.storeLatitude,
          longitude: p.storeLongitude,
          logoBytes: p.storeLogoBytes,
        );
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _loadError;
      });
    }
  }

  void _applyIdentity({
    required String name,
    required String address,
    required List<String> phones,
    required double? latitude,
    required double? longitude,
    required Uint8List? logoBytes,
  }) {
    _name.text = name.trim();
    _address.text = address.trim();
    _latitude = latitude;
    _longitude = longitude;
    _logoBytes = logoBytes;
    for (final c in _phones) {
      c.dispose();
    }
    _phones
      ..clear()
      ..addAll(
        phones.isEmpty
            ? [TextEditingController()]
            : phones.map((p) => TextEditingController(text: p)),
      );
  }

  void _addPhoneField() {
    setState(() => _phones.add(TextEditingController()));
  }

  void _removePhoneField(int index) {
    if (_phones.length <= 1) {
      _phones.first.clear();
      return;
    }
    setState(() {
      _phones.removeAt(index).dispose();
    });
  }

  List<String> _collectPhones() =>
      _phones.map((c) => c.text.trim()).where((p) => p.isNotEmpty).toList();

  /// يقرأ الصورة بأي صيغة ثم يصغّرها خارج خيط الواجهة قبل عرضها.
  Future<void> _pickLogo(ImageSource source) async {
    final XFile? picked;
    try {
      // بلا maxWidth كي لا يعيد المُلتقِط الترميز ويُفقد شفافية الشعار —
      // التصغير يتم عندنا مع الحفاظ على الصيغة المناسبة.
      picked = await _picker.pickImage(source: source);
    } catch (e) {
      if (!mounted) return;
      AppMessenger.error(context, message: 'تعذّر فتح مصدر الصور');
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _processingLogo = true);
    final raw = await picked.readAsBytes();
    final processed = await prepareStoreLogo(raw);
    if (!mounted) return;

    if (processed == null) {
      setState(() => _processingLogo = false);
      AppMessenger.error(
        context,
        message: 'تعذّر قراءة هذه الصورة. جرّب صورة أخرى.',
      );
      return;
    }
    setState(() {
      _logoBytes = processed;
      _processingLogo = false;
    });
  }

  Future<void> _showLogoOptions() async {
    final hasLogo = _logoBytes != null;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: OilChangeFormTheme.gold,
                ),
                title: Text(
                  _cameraAvailable ? 'اختيار من الاستوديو' : 'اختيار ملف صورة',
                ),
                subtitle: const Text('PNG أو JPG أو WebP أو أي صيغة شائعة'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickLogo(ImageSource.gallery);
                },
              ),
              if (_cameraAvailable)
                ListTile(
                  leading: const Icon(
                    Icons.photo_camera_outlined,
                    color: OilChangeFormTheme.gold,
                  ),
                  title: const Text('التقاط بالكاميرا'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickLogo(ImageSource.camera);
                  },
                ),
              if (hasLogo)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: const Text('حذف الشعار'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() => _logoBytes = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// يلتقط الموقع من GPS ثم يحاول اشتقاق عنوان نصّي منه.
  Future<void> _captureGpsLocation() async {
    setState(() => _locating = true);
    final result = await DeviceLocationService.instance.currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);

    switch (result) {
      case DeviceLocationError(:final failure):
        AppMessenger.error(context, message: failure.messageAr);
      case DeviceLocationSuccess(
          :final latitude,
          :final longitude,
          :final accuracyMeters,
        ):
        setState(() {
          _latitude = latitude;
          _longitude = longitude;
        });
        AppMessenger.success(
          context,
          message: 'تم تحديد الموقع بدقّة ±${accuracyMeters.round()} متر',
        );
        await _suggestAddressFor(latitude, longitude);
    }
  }

  /// يعرض العنوان المشتق من الإحداثيات: يملأ الحقل الفارغ، ويستأذن قبل الاستبدال.
  Future<void> _suggestAddressFor(double latitude, double longitude) async {
    final suggestion = await DeviceLocationService.instance
        .describeCoordinates(latitude, longitude);
    if (!mounted || suggestion == null) return;

    final existing = _address.text.trim();
    if (existing.isEmpty) {
      setState(() => _address.text = suggestion);
      return;
    }
    if (existing == suggestion) return;

    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('عنوان مقترح من الموقع'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(suggestion),
              const SizedBox(height: 12),
              Text(
                'هل تستبدل العنوان المكتوب حالياً بهذا العنوان؟',
                style: TextStyle(
                  color: OilChangeFormTheme.secondaryText(context),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إبقاء المكتوب'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('استبدال'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || replace != true) return;
    setState(() => _address.text = suggestion);
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => StoreLocationPickerScreen(
          initial: _hasLocation ? LatLng(_latitude!, _longitude!) : null,
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _latitude = picked.latitude;
      _longitude = picked.longitude;
    });
    await _suggestAddressFor(picked.latitude, picked.longitude);
  }

  void _clearLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
    });
  }

  Future<void> _openInMaps() async {
    if (!_hasLocation) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$_latitude,$_longitude',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      AppMessenger.error(context, message: 'تعذّر فتح تطبيق الخرائط');
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_emptyNameError)),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final phones = _collectPhones();
      final logoB64 = _logoBytes == null ? '' : base64Encode(_logoBytes!);

      if (_isMyBranch) {
        final auth = context.read<AuthProvider>();
        final profile = StaffBranchProfile(
          storeTitleLine: name,
          storeAddress: _address.text.trim(),
          storePhones: phones,
          storeLatitude: _latitude,
          storeLongitude: _longitude,
          storeLogoBase64: logoB64,
        );
        await StaffBranchProfileRepository.instance.saveForUser(
          profile: profile,
          userGlobalId: auth.userGlobalId,
          userId: auth.userId,
        );
        await auth.refreshLocalUserIdentity();
      } else {
        final current = await PrintSettingsRepository.instance.load();
        final next = current.copyWith(
          storeTitleLine: name,
          storeAddress: _address.text.trim(),
          storePhones: phones,
          storeLatitude: _latitude,
          storeLongitude: _longitude,
          clearStoreLocation: !_hasLocation,
          storeLogoBase64: logoB64,
        );
        if (mounted) {
          await context.read<PrintSettingsProvider>().save(next);
        } else {
          await PrintSettingsRepository.instance.save(next);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_savedMessage)),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر الحفظ. حاول مرة أخرى.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layout = ScreenLayout.of(context);
    final pad = layout.pageHorizontalGap;

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: OilChangeFormTheme.appBar(
            context: context,
            title: _screenTitle,
            actions: [
              TextButton(
                onPressed: _loading || _saving ? null : _save,
                child: Text(
                  _saving ? 'جارٍ الحفظ…' : 'حفظ',
                  style: const TextStyle(
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
                        _hintText,
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
                      Center(child: _buildLogoPicker()),
                      const SizedBox(height: 24),
                      _StoreField(
                        controller: _name,
                        label: _nameLabel,
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
                      const SizedBox(height: 14),
                      _buildLocationSection(cs),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Icon(
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

  /// شعار المتجر — الضغط عليه يفتح خيارات المصدر، ويظهر عليه شارة تعديل.
  Widget _buildLogoPicker() {
    final logo = _logoBytes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: logo == null ? 'إضافة شعار المتجر' : 'تغيير شعار المتجر',
          child: InkWell(
            onTap: _saving || _processingLogo ? null : _showLogoOptions,
            customBorder: const CircleBorder(),
            child: Stack(
              alignment: AlignmentDirectional.bottomEnd,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: OilChangeFormTheme.gold.withValues(alpha: 0.12),
                    border: Border.all(
                      color: OilChangeFormTheme.gold.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _processingLogo
                      ? const Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      : logo == null
                          ? const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 40,
                              color: OilChangeFormTheme.gold,
                            )
                          : Image.memory(
                              logo,
                              fit: BoxFit.cover,
                              width: 96,
                              height: 96,
                              gaplessPlayback: true,
                            ),
                ),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: OilChangeFormTheme.gold,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          logo == null ? 'اضغط لإضافة شعار المتجر' : 'اضغط لتغيير الشعار',
          style: TextStyle(
            color: OilChangeFormTheme.secondaryText(context),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSection(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: OilChangeFormTheme.gold.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.my_location_rounded,
                size: 20,
                color: OilChangeFormTheme.gold,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isMyBranch
                      ? 'موقع فرعك على الخريطة'
                      : 'موقع المتجر على الخريطة',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: OilChangeFormTheme.emphasisText(context),
                  ),
                  textAlign: TextAlign.start,
                ),
              ),
              if (_hasLocation)
                IconButton(
                  tooltip: 'حذف الموقع',
                  onPressed: _saving ? null : _clearLocation,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: cs.error.withValues(alpha: 0.85),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _hasLocation
                ? 'يمكنك مشاركة هذا الموقع مع الزبائن أو استخدامه في التوصيل.'
                : 'حدّد موقعك عبر GPS أو اختره من الخريطة — إضافةً إلى العنوان المكتوب.',
            style: TextStyle(
              color: OilChangeFormTheme.secondaryText(context),
              height: 1.4,
            ),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 12),
          if (_hasLocation) ...[
            _buildMapPreview(),
            const SizedBox(height: 10),
            Text(
              formatCoordinates(_latitude!, _longitude!),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: OilChangeFormTheme.emphasisText(context),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving || _locating ? null : _captureGpsLocation,
                    icon: _locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.gps_fixed_rounded, size: 18),
                    label: const Text('تحديث'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _openInMaps,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('فتح بالخرائط'),
                  ),
                ),
              ],
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _saving || _locating ? null : _captureGpsLocation,
              icon: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.gps_fixed_rounded, size: 20),
              label: Text(
                _locating ? 'جارٍ تحديد موقعك…' : 'تحديد موقعي عبر GPS',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickOnMap,
              icon: const Icon(Icons.map_outlined, size: 20),
              label: const Text('اختيار من الخريطة'),
            ),
          ],
        ],
      ),
    );
  }

  /// معاينة غير تفاعلية — الضغط عليها يفتح شاشة الاختيار لضبط الدبوس.
  Widget _buildMapPreview() {
    final center = LatLng(_latitude!, _longitude!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 150,
        child: Stack(
          alignment: Alignment.center,
          children: [
            FlutterMap(
              // مفتاح مرتبط بالإحداثيات كي تُعاد البناء عند تغيّر الموقع.
              key: ValueKey('$_latitude,$_longitude'),
              options: MapOptions(
                initialCenter: center,
                initialZoom: 16,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: _previewTileUrl,
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.naboo.store',
                  retinaMode: RetinaMode.isHighDensity(context),
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_on,
                        size: 40,
                        color: OilChangeFormTheme.gold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _saving ? null : _pickOnMap,
                child: const SizedBox.expand(),
              ),
            ),
          ],
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
