import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/global_barcode_route_bridge.dart';

/// يستمع لضربات لوحة المفاتيح السريعة (قارئ HID) ويُجمّع الباركود حتى Enter.
///
/// يُسجَّل بعد [IdleSessionShell] ليُستدعى قبل معالج السكون (LIFO).
/// الحرف الأول قد يظهر في الحقل المُركَّز؛ باقي الرموز تُستهلك هنا حتى لا يُفسد المسح الحقول.
class GlobalBarcodeKeyboardListener extends StatefulWidget {
  const GlobalBarcodeKeyboardListener({super.key, required this.child});

  final Widget child;

  @override
  State<GlobalBarcodeKeyboardListener> createState() =>
      _GlobalBarcodeKeyboardListenerState();
}

class _GlobalBarcodeKeyboardListenerState
    extends State<GlobalBarcodeKeyboardListener> {
  /// رموز شائعة في الباركود — يُكمّلها [_charFromPhysicalUsLayout] حتى لا تعتمد على لغة لوحة النظام.
  static final RegExp _sym = RegExp(r'^[A-Za-z0-9.\-/]$');

  final StringBuffer _buf = StringBuffer();
  DateTime? _lastTs;
  bool _capturing = false;

  String? _lastDispatched;
  DateTime? _lastDispatchAt;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        HardwareKeyboard.instance.addHandler(_onKey);
      }
    });
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }

  void _reset() {
    _buf.clear();
    _lastTs = null;
    _capturing = false;
  }

  /// قارئ HID يرسل ضربات كأنها لوحة **إنجليزية فيزيائية**؛ [KeyEvent.character] يتبع لغة الإدخال (عربي…)
  /// فيُنتج حروفاً لا تمرّ عبر [_sym]. نقرأ بدل ذلك [PhysicalKeyboardKey] (موضع المفتاح).
  String? _charFromPhysicalUsLayout(KeyEvent event) {
    final pk = event.physicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    String letter(bool upper, String lower) => upper ? lower.toUpperCase() : lower;

    // أرقام الصف العلوي والنمط الرقمي
    final topDigits = <PhysicalKeyboardKey, String>{
      PhysicalKeyboardKey.digit0: '0',
      PhysicalKeyboardKey.digit1: '1',
      PhysicalKeyboardKey.digit2: '2',
      PhysicalKeyboardKey.digit3: '3',
      PhysicalKeyboardKey.digit4: '4',
      PhysicalKeyboardKey.digit5: '5',
      PhysicalKeyboardKey.digit6: '6',
      PhysicalKeyboardKey.digit7: '7',
      PhysicalKeyboardKey.digit8: '8',
      PhysicalKeyboardKey.digit9: '9',
      PhysicalKeyboardKey.numpad0: '0',
      PhysicalKeyboardKey.numpad1: '1',
      PhysicalKeyboardKey.numpad2: '2',
      PhysicalKeyboardKey.numpad3: '3',
      PhysicalKeyboardKey.numpad4: '4',
      PhysicalKeyboardKey.numpad5: '5',
      PhysicalKeyboardKey.numpad6: '6',
      PhysicalKeyboardKey.numpad7: '7',
      PhysicalKeyboardKey.numpad8: '8',
      PhysicalKeyboardKey.numpad9: '9',
    };
    final d = topDigits[pk];
    if (d != null) return d;

    final punct = <PhysicalKeyboardKey, String>{
      PhysicalKeyboardKey.minus: '-',
      PhysicalKeyboardKey.period: '.',
      PhysicalKeyboardKey.slash: '/',
    };
    final p = punct[pk];
    if (p != null) return p;

    final letters = <PhysicalKeyboardKey, String>{
      PhysicalKeyboardKey.keyA: 'a',
      PhysicalKeyboardKey.keyB: 'b',
      PhysicalKeyboardKey.keyC: 'c',
      PhysicalKeyboardKey.keyD: 'd',
      PhysicalKeyboardKey.keyE: 'e',
      PhysicalKeyboardKey.keyF: 'f',
      PhysicalKeyboardKey.keyG: 'g',
      PhysicalKeyboardKey.keyH: 'h',
      PhysicalKeyboardKey.keyI: 'i',
      PhysicalKeyboardKey.keyJ: 'j',
      PhysicalKeyboardKey.keyK: 'k',
      PhysicalKeyboardKey.keyL: 'l',
      PhysicalKeyboardKey.keyM: 'm',
      PhysicalKeyboardKey.keyN: 'n',
      PhysicalKeyboardKey.keyO: 'o',
      PhysicalKeyboardKey.keyP: 'p',
      PhysicalKeyboardKey.keyQ: 'q',
      PhysicalKeyboardKey.keyR: 'r',
      PhysicalKeyboardKey.keyS: 's',
      PhysicalKeyboardKey.keyT: 't',
      PhysicalKeyboardKey.keyU: 'u',
      PhysicalKeyboardKey.keyV: 'v',
      PhysicalKeyboardKey.keyW: 'w',
      PhysicalKeyboardKey.keyX: 'x',
      PhysicalKeyboardKey.keyY: 'y',
      PhysicalKeyboardKey.keyZ: 'z',
    };
    final low = letters[pk];
    if (low != null) return letter(shift, low);

    return null;
  }

  /// إن فشل المسار الفيزيائي (منصّة نادرة): نستخدم الحرف إن وافق نمط الباركود (مثلاً لوحة إنجليزية).
  String? _charFromLocalizedFallback(KeyEvent event) {
    final ch = event.character;
    if (ch == null || ch.isEmpty || ch.length != 1) return null;
    if (ch == '\r' || ch == '\n') return null;
    if (!_sym.hasMatch(ch)) return null;
    return ch;
  }

  bool _isDupScan(String code) {
    final now = DateTime.now();
    if (_lastDispatched == code &&
        _lastDispatchAt != null &&
        now.difference(_lastDispatchAt!) < const Duration(milliseconds: 700)) {
      return true;
    }
    _lastDispatched = code;
    _lastDispatchAt = now;
    return false;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!mounted) return false;

    if (!Provider.of<AuthProvider>(context, listen: false).isLoggedIn) {
      return false;
    }
    final bridge = Provider.of<GlobalBarcodeRouteBridge>(context, listen: false);

    final hk = HardwareKeyboard.instance;
    if (hk.isControlPressed || hk.isMetaPressed || hk.isAltPressed) {
      _reset();
      return false;
    }

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;

    if (isEnter) {
      if (_buf.isEmpty) {
        return false;
      }
      final code = _buf.toString().trim();
      _reset();
      if (code.length < 4) return false;
      if (_isDupScan(code)) return true;
      unawaited(bridge.dispatch(code));
      // يضمن بدء سلسلة async + إطار رسم دون انتظار حدث إدخال آخر.
      SchedulerBinding.instance.scheduleFrame();
      return true;
    }

    final ch = _charFromPhysicalUsLayout(event) ?? _charFromLocalizedFallback(event);
    if (ch == null) {
      _reset();
      return false;
    }

    final now = DateTime.now();

    if (!_capturing) {
      if (_buf.isEmpty) {
        _buf.write(ch);
        _lastTs = now;
        return false;
      }
      final gap = _lastTs == null
          ? Duration.zero
          : now.difference(_lastTs!);
      if (gap < const Duration(milliseconds: 110)) {
        _capturing = true;
        _buf.write(ch);
        _lastTs = now;
        return true;
      }
      _buf
        ..clear()
        ..write(ch);
      _lastTs = now;
      return false;
    }

    final gap = _lastTs == null ? Duration.zero : now.difference(_lastTs!);
    if (gap > const Duration(milliseconds: 140)) {
      _reset();
      _buf.write(ch);
      _lastTs = now;
      return false;
    }
    _lastTs = now;
    _buf.write(ch);
    if (_buf.length > 96) _reset();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
