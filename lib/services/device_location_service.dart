import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/app_logger.dart';

const _tag = 'DeviceLocation';

/// سبب تعذّر قراءة الموقع — لكل سبب رسالة عربية وإجراء مختلف في الواجهة.
enum DeviceLocationFailure {
  /// خدمة الموقع (GPS) مطفأة على الجهاز.
  serviceDisabled,

  /// المستخدم رفض الإذن هذه المرة.
  permissionDenied,

  /// المستخدم رفض الإذن نهائياً — لا تُعرض النافذة ثانية، يلزم فتح الإعدادات.
  permissionDeniedForever,

  /// انتهت المهلة قبل التقاط إشارة كافية.
  timeout,

  /// خطأ غير متوقّع من نظام التشغيل.
  unknown,
}

extension DeviceLocationFailureMessage on DeviceLocationFailure {
  String get messageAr => switch (this) {
        DeviceLocationFailure.serviceDisabled =>
          'خدمة الموقع مطفأة. شغّل GPS من إعدادات الهاتف ثم أعد المحاولة.',
        DeviceLocationFailure.permissionDenied =>
          'لم يُمنح إذن الموقع. اسمح للتطبيق بالوصول إلى موقعك ثم أعد المحاولة.',
        DeviceLocationFailure.permissionDeniedForever =>
          'إذن الموقع مرفوض نهائياً. فعّله يدوياً من إعدادات التطبيق.',
        DeviceLocationFailure.timeout =>
          'تعذّر التقاط إشارة GPS. اخرج إلى مكان مكشوف أو حدّد الموقع من الخريطة.',
        DeviceLocationFailure.unknown =>
          'تعذّر تحديد الموقع. حدّده من الخريطة يدوياً.',
      };

  /// هل يستحق عرض زر «فتح الإعدادات» بجانب الرسالة؟
  bool get needsSettings =>
      this == DeviceLocationFailure.serviceDisabled ||
      this == DeviceLocationFailure.permissionDeniedForever;
}

sealed class DeviceLocationResult {
  const DeviceLocationResult();
}

class DeviceLocationSuccess extends DeviceLocationResult {
  const DeviceLocationSuccess({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });

  final double latitude;
  final double longitude;

  /// دقّة القراءة بالأمتار — نعرضها للمستخدم كي يعرف هل الموقع موثوق.
  final double accuracyMeters;
}

class DeviceLocationError extends DeviceLocationResult {
  const DeviceLocationError(this.failure);

  final DeviceLocationFailure failure;
}

/// قراءة موقع الجهاز وتحويله إلى عنوان مقروء — الغلاف الوحيد فوق geolocator.
class DeviceLocationService {
  DeviceLocationService._();

  static final DeviceLocationService instance = DeviceLocationService._();

  /// يطلب الإذن عند الحاجة ثم يقرأ الموقع الحالي.
  Future<DeviceLocationResult> currentPosition({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const DeviceLocationError(
          DeviceLocationFailure.serviceDisabled,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const DeviceLocationError(
          DeviceLocationFailure.permissionDeniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        return const DeviceLocationError(
          DeviceLocationFailure.permissionDenied,
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return DeviceLocationSuccess(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } on TimeoutException {
      return const DeviceLocationError(DeviceLocationFailure.timeout);
    } catch (e, s) {
      AppLogger.error(_tag, 'currentPosition failed', e, s);
      return const DeviceLocationError(DeviceLocationFailure.unknown);
    }
  }

  /// عنوان نصّي تقريبي للإحداثيات — `null` إن تعذّر، والإحداثيات تبقى صالحة.
  Future<String?> describeCoordinates(double latitude, double longitude) async {
    try {
      await setLocaleIdentifier('ar');
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      return formatPlacemarkParts([
        p.street,
        p.subLocality,
        p.locality,
        p.subAdministrativeArea,
        p.administrativeArea,
        p.country,
      ]);
    } catch (e) {
      AppLogger.warn(_tag, 'reverse geocoding unavailable: $e');
      return null;
    }
  }

  /// يفتح إعدادات الموقع في النظام حين يكون الرفض نهائياً أو GPS مطفأ.
  Future<void> openSettingsFor(DeviceLocationFailure failure) async {
    if (failure == DeviceLocationFailure.serviceDisabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    await Geolocator.openAppSettings();
  }
}

/// يدمج أجزاء العنوان في سطر واحد بلا فراغات أو تكرار — دالة نقية للاختبار.
String? formatPlacemarkParts(List<String?> parts) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in parts) {
    final t = part?.trim() ?? '';
    if (t.isEmpty) continue;
    // بعض المزوّدين يعيدون رمز plus code أو رقم بلا معنى للمستخدم.
    if (RegExp(r'^[0-9+\-\s]+$').hasMatch(t)) continue;
    if (!seen.add(t)) continue;
    out.add(t);
  }
  if (out.isEmpty) return null;
  return out.join('، ');
}

/// نص الإحداثيات كما يُعرض للمستخدم — ست خانات عشرية تكفي لدقّة ~11 سم.
String formatCoordinates(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
