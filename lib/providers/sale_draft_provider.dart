import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// ينسّق إضافة منتجات من البحث العام إلى شاشة البيع المفتوحة
/// دون فتح نافذة بيع جديدة في كل مرة.
class SaleDraftProvider extends ChangeNotifier {
  bool isSaleScreenOpen = false;

  final List<Map<String, dynamic>> _pendingProductLines = [];

  /// لـ `context.select` أو للتحقق دون الاستماع لكل إشعارات [notifyListeners].
  int get pendingProductLinesCount => _pendingProductLines.length;

  void enqueueProductLine(Map<String, dynamic> line) {
    _pendingProductLines.add(Map<String, dynamic>.from(line));
    // تأجيل الإشعار لتفادي «setState during build» إذا وُلدت شاشة البيع أثناء بناء أصل.
    // جدولة إطار صريحة: وإلا قد لا يُنفَّذ الـ callback حتى حدث إدخال (مثل تحريك الماوس) بعد async.
    SchedulerBinding.instance.scheduleFrame();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  /// يُستدعى من بناء شاشة البيع: يفرّغ الطابور ويعيد ما كان فيه.
  List<Map<String, dynamic>> takePendingProductLines() {
    if (_pendingProductLines.isEmpty) return [];
    final out = List<Map<String, dynamic>>.from(_pendingProductLines);
    _pendingProductLines.clear();
    return out;
  }

  void registerSaleScreenOpen() {
    if (isSaleScreenOpen) return;
    isSaleScreenOpen = true;
    // لا تستدعِ notifyListeners متزامناً من didChangeDependencies — يسبب تعارضاً مع البناء (مثلاً داخل LayoutBuilder).
    SchedulerBinding.instance.scheduleFrame();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  void registerSaleScreenClosed() {
    if (!isSaleScreenOpen) return;
    isSaleScreenOpen = false;
    // لا نستدعي notifyListeners أثناء dispose/unmount — الشجرة مقفلة.
    SchedulerBinding.instance.scheduleFrame();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }
}
