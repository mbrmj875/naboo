import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../services/marketplace/marketplace_store_settings_service.dart';

const _tileUrl =
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

/// إعداد نقطة الاستلام (PVZ) للتاجر — يظهر على خريطة تطبيق Market.
class MarketPickupSettingsScreen extends StatefulWidget {
  const MarketPickupSettingsScreen({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  final String storeId;
  final String storeName;

  @override
  State<MarketPickupSettingsScreen> createState() =>
      _MarketPickupSettingsScreenState();
}

class _MarketPickupSettingsScreenState extends State<MarketPickupSettingsScreen> {
  final _service = MarketplaceStoreSettingsService();
  final _mapController = MapController();
  final _addressController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  String? _error;

  MerchantMarketMode _mode = MerchantMarketMode.sellAndPickup;
  LatLng _mapCenter = const LatLng(
    MarketplaceStoreSettingsService.defaultLat,
    MarketplaceStoreSettingsService.defaultLng,
  );

  bool get _needsPickupFields =>
      _mode == MerchantMarketMode.pickupOnly ||
      _mode == MerchantMarketMode.sellAndPickup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _service.fetchStoreSettings(widget.storeId);
      if (!mounted) return;
      setState(() {
        _mode = settings.mode;
        _addressController.text = settings.pickupAddress ?? '';
        if (settings.hasCoordinates) {
          _mapCenter = LatLng(
            settings.pickupLatitude!,
            settings.pickupLongitude!,
          );
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يُمنح إذن الموقع')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final target = LatLng(pos.latitude, pos.longitude);
      setState(() => _mapCenter = target);
      _mapController.move(target, 17);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.saveMarketSettings(
        storeId: widget.storeId,
        mode: _mode,
        latitude: _mapCenter.latitude,
        longitude: _mapCenter.longitude,
        pickupAddress: _addressController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            switch (_mode) {
              MerchantMarketMode.sellOnly =>
                'تم حفظ وضع البيع أونلاين — منتجاتك تظهر في Market',
              MerchantMarketMode.pickupOnly =>
                'تم حفظ وضع نقطة الاستلام — pin على خريطة Market',
              MerchantMarketMode.sellAndPickup =>
                'تم حفظ البيع + نقطة الاستلام',
            },
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('إعداد Market — ${widget.storeName}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'نوع نشاطك على Market',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<MerchantMarketMode>(
                            segments: const [
                              ButtonSegment(
                                value: MerchantMarketMode.sellOnly,
                                label: Text('بيع فقط'),
                                icon: Icon(Icons.storefront_outlined),
                              ),
                              ButtonSegment(
                                value: MerchantMarketMode.pickupOnly,
                                label: Text('PVZ فقط'),
                                icon: Icon(Icons.place_outlined),
                              ),
                              ButtonSegment(
                                value: MerchantMarketMode.sellAndPickup,
                                label: Text('كلاهما'),
                                icon: Icon(Icons.store_mall_directory_outlined),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (values) {
                              setState(() => _mode = values.first);
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_needsPickupFields) ...[
                      Expanded(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _mapCenter,
                                initialZoom: 16,
                                onPositionChanged: (pos, _) {
                                  _mapCenter = pos.center;
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: _tileUrl,
                                  subdomains: const ['a', 'b', 'c', 'd'],
                                  userAgentPackageName: 'com.naboo.store',
                                ),
                              ],
                            ),
                            const IgnorePointer(
                              child: Icon(
                                Icons.location_on,
                                size: 48,
                                color: Colors.redAccent,
                              ),
                            ),
                            PositionedDirectional(
                              top: 12,
                              end: 12,
                              child: FloatingActionButton.small(
                                heroTag: 'merchant_my_location',
                                onPressed: _locating ? null : _useMyLocation,
                                child: _locating
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.my_location),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 16,
                              right: 16,
                              child: Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    'حرّك الخريطة حتى يقع الدبوس على موقع الاستلام',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _addressController,
                          decoration: const InputDecoration(
                            labelText: 'عنوان الاستلام (يظهر للزبون)',
                            hintText: 'مثال: قرب سوق الجملة، العشار',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                      ),
                    ] else
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'وضع «بيع فقط»: منتجاتك تظهر في Market بدون pin على الخريطة.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('حفظ إعدادات Market'),
                      ),
                    ),
                  ],
                ),
    );
  }
}
