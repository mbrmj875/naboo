import 'package:flutter/widgets.dart';

/// العنصر المفتوح على الشاشة (ق67، م2-21): بطاقة غيار، منتج، زبون، فاتورة.
/// الهاتف يرسل النوع والمعرّف فقط، والمساعد يجلب التفاصيل بأدواته، فتمر
/// بفحص الصلاحية كأي سؤال. [label] للشريط فوق حقل الإدخال فقط ولا يُرسل.
@immutable
class AssistantContextItem {
  const AssistantContextItem({required this.kind, required this.id, required this.label});

  /// oil_card | product | customer | invoice
  final String kind;
  final int id;
  final String label;

  static const kinds = {'oil_card', 'product', 'customer', 'invoice'};

  @override
  bool operator ==(Object other) => other is AssistantContextItem && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// مكدس العناصر المفتوحة: آخر شاشة فُتحت هي السياق. كل شاشة تضيف عنصرها عند
/// الفتح وتزيله عند الإغلاق، فلا يبقى سياق شاشة مغلقة.
abstract final class AssistantScreenContext {
  static final ValueNotifier<AssistantContextItem?> current = ValueNotifier(null);
  static final List<AssistantContextItem> _stack = [];

  /// أزاله المستخدم من الشريط: لا يعود حتى تُفتح الشاشة من جديد.
  static AssistantContextItem? _dismissed;

  static void push(AssistantContextItem item) {
    if (!AssistantContextItem.kinds.contains(item.kind) || item.id <= 0) return;
    _stack
      ..remove(item)
      ..add(item);
    if (_dismissed == item) _dismissed = null;
    _publish();
  }

  static void pop(AssistantContextItem item) {
    _stack.remove(item);
    _publish();
  }

  /// زر الإزالة في الشريط.
  static void dismiss() {
    _dismissed = current.value;
    _publish();
  }

  static void _publish() {
    final top = _stack.isEmpty ? null : _stack.last;
    current.value = top == _dismissed ? null : top;
  }

  @visibleForTesting
  static void reset() {
    _stack.clear();
    _dismissed = null;
    current.value = null;
  }
}

/// يعلن عنصر الشاشة طوال بقائها. للشاشات التي يسهل تغليف جسمها؛ وإلا
/// تُستدعى [AssistantScreenContext.push] و[AssistantScreenContext.pop] مباشرة.
class AssistantContextScope extends StatefulWidget {
  const AssistantContextScope({super.key, required this.item, required this.child});

  final AssistantContextItem? item;
  final Widget child;

  @override
  State<AssistantContextScope> createState() => _AssistantContextScopeState();
}

class _AssistantContextScopeState extends State<AssistantContextScope> {
  @override
  void initState() {
    super.initState();
    final i = widget.item;
    if (i != null) AssistantScreenContext.push(i);
  }

  @override
  void didUpdateWidget(AssistantContextScope old) {
    super.didUpdateWidget(old);
    if (old.item == widget.item) return;
    final o = old.item;
    if (o != null) AssistantScreenContext.pop(o);
    final i = widget.item;
    if (i != null) AssistantScreenContext.push(i);
  }

  @override
  void dispose() {
    final i = widget.item;
    if (i != null) AssistantScreenContext.pop(i);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
