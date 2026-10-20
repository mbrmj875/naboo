import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/device_location_service.dart';
import '../../verticals/oil_change/widgets/oil_change_form_theme.dart';
import '../../widgets/feedback/app_messenger.dart';

const _tileUrl =
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

/// مركز البصرة — نقطة بداية معقولة حين لا يتوفّر موقع محفوظ ولا GPS.
const _fallbackCenter = LatLng(30.5085, 47.7835);

/// اختيار موقع المتجر على الخريطة — يُعيد [LatLng] عند التأكيد أو `null` عند الإلغاء.
class StoreLocationPickerScreen extends StatefulWidget {
  const StoreLocationPickerScreen({super.key, this.initial});

  final LatLng? initial;

  @override
  State<StoreLocationPickerScreen> createState() =>
      _StoreLocationPickerScreenState();
}

class _StoreLocationPickerScreenState extends State<StoreLocationPickerScreen> {
  final _mapController = MapController();

  /// يتغيّر مع كل إطار أثناء السحب — ValueNotifier كي لا نعيد بناء الخريطة.
  late final ValueNotifier<LatLng> _center =
      ValueNotifier(widget.initial ?? _fallbackCenter);

  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useMyLocation());
    }
  }

  @override
  void dispose() {
    _center.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    final result = await DeviceLocationService.instance.currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);

    switch (result) {
      case DeviceLocationSuccess(:final latitude, :final longitude):
        final target = LatLng(latitude, longitude);
        _center.value = target;
        _mapController.move(target, 17);
      case DeviceLocationError(:final failure):
        AppMessenger.warning(context, message: failure.messageAr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: OilChangeFormTheme.appBar(
          context: context,
          title: 'تحديد موقع المتجر',
          actions: const [],
        ),
        body: Stack(
          alignment: Alignment.center,
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center.value,
                initialZoom: 16,
                onPositionChanged: (position, _) {
                  _center.value = position.center;
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileUrl,
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.naboo.store',
                  retinaMode: RetinaMode.isHighDensity(context),
                ),
              ],
            ),
            // الدبوس ثابت في المركز؛ الخريطة هي التي تتحرّك تحته.
            const IgnorePointer(
              child: Padding(
                // نصف ارتفاع الأيقونة كي يقع طرفها السفلي على مركز الخريطة.
                padding: EdgeInsets.only(bottom: 48),
                child: Icon(
                  Icons.location_on,
                  size: 48,
                  color: OilChangeFormTheme.gold,
                  shadows: [
                    Shadow(blurRadius: 6, color: Colors.black38),
                  ],
                ),
              ),
            ),
            PositionedDirectional(
              top: 12,
              end: 12,
              child: FloatingActionButton.small(
                heroTag: 'store_location_my_location',
                tooltip: 'موقعي الحالي',
                onPressed: _locating ? null : _useMyLocation,
                child: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
            ),
            PositionedDirectional(
              start: 16,
              end: 16,
              bottom: 16,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                color: cs.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'حرّك الخريطة حتى يقع الدبوس على باب المتجر',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: OilChangeFormTheme.secondaryText(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ValueListenableBuilder<LatLng>(
                        valueListenable: _center,
                        builder: (context, value, _) => Text(
                          formatCoordinates(value.latitude, value.longitude),
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: OilChangeFormTheme.emphasisText(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () =>
                            Navigator.pop(context, _center.value),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('تأكيد هذا الموقع'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
