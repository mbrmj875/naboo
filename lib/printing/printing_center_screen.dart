import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/print_settings_data.dart';
import '../providers/print_settings_provider.dart';
import '../services/effective_store_branding.dart';
import '../widgets/app_color_picker_dialog.dart';
import 'printer_connection.dart';
import 'receipt_builders.dart';
import 'receipt_design.dart';
import 'receipt_gallery.dart';
import 'receipt_model.dart';
import 'receipt_preview.dart';
import 'receipt_printer.dart';
import 'receipt_renderer.dart';
import 'transports/bluetooth_transport.dart';

/// قسم «الطباعة»: ربط طابعة هذا الجهاز، وقالب إيصال لكل عمل مع معاينة حية.
class PrintingCenterScreen extends StatefulWidget {
  const PrintingCenterScreen({super.key, this.kinds = ReceiptKind.oilShop});

  /// الأعمال الظاهرة في هذا التخصص.
  final List<ReceiptKind> kinds;

  @override
  State<PrintingCenterScreen> createState() => _PrintingCenterScreenState();
}

class _PrintingCenterScreenState extends State<PrintingCenterScreen> {
  PrinterConnection? _conn;
  late ReceiptKind _kind = widget.kinds.first;
  final _samples = <ReceiptKind, ReceiptDocument>{};
  bool _testing = false;

  /// بيانات المحل كما تُطبع: فرع الموظف إن كان له فرع، وإلا بيانات المتجر.
  PrintSettingsData? _branded;
  PrintSettingsData? _brandedFrom;

  /// أقل عرض تظهر فيه المعاينة بجانب الإعدادات.
  static const _sideBySide = 900.0;

  @override
  void initState() {
    super.initState();
    _provider;
    _loadConnection();
  }

  Future<void> _loadConnection() async {
    final prov = context.read<PrintSettingsProvider>();
    if (!prov.isReady) await prov.load();
    final c = await PrinterConnection.load(legacy: prov.data);
    if (mounted) setState(() => _conn = c);
  }

  /// يعيد حساب بيانات المحل عند تغيّر الإعدادات .
  Future<void> _refreshBranding(PrintSettingsData base) async {
    _brandedFrom = base;
    PrintSettingsData b;
    try {
      b = await EffectiveStoreBranding.resolveFromContext(context, base: base);
    } catch (_) {
      b = base;
    }
    if (mounted && identical(_brandedFrom, base)) setState(() => _branded = b);
  }

  /// الإعدادات للرسم: القوالب من إعدادات المحل، والرأس من بيانات المحل الفعلية.
  PrintSettingsData _effective(PrintSettingsData base) {
    final b = _branded;
    if (b == null) return base;
    return b.copyWith(receiptTemplates: base.receiptTemplates);
  }

  Future<void> _setConn(PrinterConnection c) async {
    setState(() => _conn = c);
    await c.save();
  }

  ReceiptDocument _sample(ReceiptKind k) =>
      _samples.putIfAbsent(k, () => ReceiptBuilders.sample(k));

  ReceiptTemplate _template(PrintSettingsData d, ReceiptKind k) =>
      ReceiptTemplates(d.receiptTemplates).of(k);

  Future<void> _saveTemplate(ReceiptKind k, ReceiptTemplate t) async {
    final prov = context.read<PrintSettingsProvider>();
    await prov.save(
      prov.data.copyWith(
        receiptTemplates: ReceiptTemplates(
          prov.data.receiptTemplates,
        ).withTemplate(k, t),
      ),
    );
  }

  /// آخر تصميم اختاره المستخدم ولم يُحفظ بعد (يظهر في المعاينة فوراً).
  ReceiptDesign? _pendingDesign;
  Timer? _designTimer;

  /// الأشرطة ترسل تغييراً مع كل حركة: نعرضه فوراً ونحفظ مرة واحدة عند التوقف
  /// حتى لا يُرسل كل تغيير صغير للمزامنة.
  void _changeDesign(ReceiptDesign d) {
    setState(() => _pendingDesign = d);
    _designTimer?.cancel();
    _designTimer = Timer(
      const Duration(milliseconds: 450),
      () => _saveDesign(d),
    );
  }

  @override
  void dispose() {
    final pending = _pendingDesign;
    _designTimer?.cancel();
    if (pending != null) unawaited(_saveDesignWith(_provider, pending));
    super.dispose();
  }

  late final PrintSettingsProvider _provider = context
      .read<PrintSettingsProvider>();

  static Future<void> _saveDesignWith(
    PrintSettingsProvider prov,
    ReceiptDesign d,
  ) => prov.save(
    prov.data.copyWith(
      receiptTemplates: ReceiptTemplates(
        prov.data.receiptTemplates,
      ).withDesign(d),
    ),
  );

  Future<void> _saveDesign(ReceiptDesign d) async {
    await _saveDesignWith(_provider, d);
    if (mounted && identical(_pendingDesign, d)) {
      setState(() => _pendingDesign = null);
    }
  }

  ReceiptDesign _designFor(PrintSettingsData s, ReceiptKind k) {
    final t = ReceiptTemplates(s.receiptTemplates);
    final pending = _pendingDesign;
    if (pending != null && !t.hasOwnDesign(k)) return pending;
    return t.designFor(k);
  }

  Future<void> _testPrint() async {
    final conn = _conn;
    if (conn == null) return;
    setState(() => _testing = true);
    // الطباعة بآخر تصميم اختير حتى لو لم ينتهِ انتظار الحفظ.
    final pending = _pendingDesign;
    if (pending != null) {
      _designTimer?.cancel();
      await _saveDesign(pending);
      if (!mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final r = await ReceiptPrinter.printDocument(
      _sample(_kind),
      connection: conn,
      settings: _effective(context.read<PrintSettingsProvider>().data),
    );
    if (!mounted) return;
    setState(() => _testing = false);
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          r.ok
              ? 'أُرسل إيصال تجريبي (${_kind.workLabel}). إن لم يخرج ورق، راجع الطابعة والورق.'
              : r.message ?? 'تعذرت الطباعة.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الطباعة')),
        body: Consumer<PrintSettingsProvider>(
          builder: (context, prov, _) {
            final conn = _conn;
            if (!prov.isReady || conn == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!identical(_brandedFrom, prov.data)) {
              _brandedFrom = prov.data;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _refreshBranding(prov.data),
              );
            }
            final settings = _effective(prov.data);
            final preview = _PreviewPanel(
              kind: _kind,
              kinds: widget.kinds,
              onKind: (k) => setState(() => _kind = k),
              document: _sample(_kind),
              settings: settings,
              template: _template(settings, _kind),
              paper: conn.effectivePaper,
              design: _designFor(settings, _kind),
              monochrome: conn.isThermal,
            );
            final controls = [
              _PrinterCard(
                conn: conn,
                testing: _testing,
                onChanged: _setConn,
                onTest: conn.isConfigured ? _testPrint : null,
              ),
              const SizedBox(height: 20),
              _GalleryCard(
                design:
                    _pendingDesign ??
                    ReceiptTemplates(settings.receiptTemplates).design,
                settings: settings,
                document: _sample(_kind),
                onPick: _changeDesign,
              ),
              const SizedBox(height: 20),
              _StyleCard(
                design:
                    _pendingDesign ??
                    ReceiptTemplates(settings.receiptTemplates).design,
                thermal: conn.isThermal,
                onChanged: _changeDesign,
                logoBytes: settings.storeLogoBytes,
              ),
              const SizedBox(height: 20),
              const _SectionHeader(
                icon: Icons.receipt_long_outlined,
                title: 'قوالب الإيصالات',
                subtitle:
                    'لكل عمل إيصاله. القوالب مشتركة لكل أجهزة المحل، والطابعة خاصة بهذا الجهاز.',
              ),
              const SizedBox(height: 8),
              for (final k in widget.kinds)
                _TemplateCard(
                  kind: k,
                  template: _template(settings, k),
                  storeFooter: settings.footerExtra,
                  selected: k == _kind,
                  onSelect: () => setState(() => _kind = k),
                  onChanged: (t) => _saveTemplate(k, t),
                ),
            ];
            return LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth >= _sideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: controls,
                        ),
                      ),
                      SizedBox(
                        width: c.maxWidth >= 1200 ? 460 : 400,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                            border: BorderDirectional(
                              start: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: preview,
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    ...controls.take(1),
                    const SizedBox(height: 20),
                    preview,
                    const SizedBox(height: 4),
                    ...controls.skip(1),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------ عناصر مشتركة

/// صندوق اختيار: يُضغط فتنفتح القائمة. يعمل على الهاتف والحاسوب.
class _Drop<T> extends StatelessWidget {
  const _Drop({
    required this.label,
    required this.value,
    required this.values,
    required this.text,
    required this.onChanged,
    this.leading,
    this.itemStyle,
    super.key,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) text;
  final ValueChanged<T> onChanged;
  final Widget? Function(T)? leading;
  final TextStyle? Function(T)? itemStyle;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 420,
      borderRadius: BorderRadius.circular(12),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      items: [
        for (final v in values)
          DropdownMenuItem<T>(
            value: v,
            child: Row(
              children: [
                if (leading?.call(v) case final w?) ...[
                  w,
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    text(v),
                    overflow: TextOverflow.ellipsis,
                    style: itemStyle?.call(v),
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// صندوقان في صف على الشاشة العريضة، وتحت بعض على الهاتف.
class _Pair extends StatelessWidget {
  const _Pair(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 440) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// قسم يُطوى، وعنوانه يلخّص ما بداخله.
class _Fold extends StatelessWidget {
  const _Fold({
    required this.icon,
    required this.title,
    required this.summary,
    required this.children,
    super.key,
  });

  final IconData icon;
  final String title;
  final String summary;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 10, bottom: 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        leading: Icon(icon, color: cs.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      ),
    );
  }
}

String _hex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// صف لون: مربع اللون واسمه؛ الضغط يفتح مربع الألوان المتدرج.
class _ColorTile extends StatelessWidget {
  const _ColorTile({
    required this.slot,
    required this.palette,
    required this.onChanged,
  });

  final ReceiptColorSlot slot;
  final ReceiptPalette palette;
  final ValueChanged<int?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final c = await showAppColorPickerDialog(
      context: context,
      initialColor: Color(palette.of(slot)),
      title: slot.label,
      subtitle: 'اختر من المربع المتدرج أو اكتب الرمز.',
    );
    if (c != null) onChanged(c.toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = palette.of(slot);
    final auto = !palette.isSet(slot);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('receipt-color-${slot.name}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pick(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Color(v),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outline),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      auto ? 'تلقائي · ${_hex(v)}' : _hex(v),
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!slot.isCore && !auto)
                IconButton(
                  tooltip: 'رجوع للتلقائي',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: () => onChanged(null),
                )
              else
                Icon(Icons.colorize_outlined, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط قيمة بعنوان ونسبة.
class _Slide extends StatelessWidget {
  const _Slide({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${(value * 100).round()}%'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ الطابعة

class _PrinterCard extends StatefulWidget {
  const _PrinterCard({
    required this.conn,
    required this.testing,
    required this.onChanged,
    required this.onTest,
  });

  final PrinterConnection conn;
  final bool testing;
  final ValueChanged<PrinterConnection> onChanged;
  final VoidCallback? onTest;

  @override
  State<_PrinterCard> createState() => _PrinterCardState();
}

class _PrinterCardState extends State<_PrinterCard> {
  late final _host = TextEditingController(text: widget.conn.lanHost);
  late final _port = TextEditingController(text: '${widget.conn.lanPort}');
  bool _scanning = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _saveLan() {
    widget.onChanged(
      widget.conn.copyWith(
        lanHost: _host.text.trim(),
        lanPort: int.tryParse(_port.text.trim()) ?? 9100,
      ),
    );
  }

  Future<void> _pickBluetooth() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _scanning = true);
    final problem = await BluetoothTransport.checkReady();
    final list = problem == null
        ? await BluetoothTransport.paired()
        : const <BtPrinter>[];
    if (!mounted) return;
    setState(() => _scanning = false);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    final picked = await showModalBottomSheet<BtPrinter>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'الطابعات المقترنة',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'لا تظهر طابعتك؟ اقترنها أولاً من إعدادات البلوتوث في الهاتف (الرمز غالباً 0000 أو 1234).',
                ),
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'لا توجد أجهزة مقترنة.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final d in list)
                ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: Text(d.name.isEmpty ? 'بلا اسم' : d.name),
                  subtitle: Text(
                    d.address,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.end,
                  ),
                  selected: d.address == widget.conn.btAddress,
                  onTap: () => Navigator.of(ctx).pop(d),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      widget.onChanged(
        widget.conn.copyWith(btAddress: picked.address, btName: picked.name),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = widget.conn;
    final ok = c.isConfigured;
    final hint = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final types = [
      for (final t in PrinterType.values)
        if (t != PrinterType.bluetooth || BluetoothTransport.supported) t,
    ];
    final papers = c.isThermal ? ReceiptPaper.rolls : ReceiptPaper.values;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.print_rounded : Icons.print_disabled_outlined,
                  color: ok ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'طابعة هذا الجهاز',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        c.summary,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Pair([
              _Drop<PrinterType>(
                key: const ValueKey('printer-type'),
                label: 'نوع الطابعة',
                value: types.contains(c.type) ? c.type : PrinterType.none,
                values: types,
                text: (t) => t.label,
                onChanged: (t) => widget.onChanged(c.copyWith(type: t)),
              ),
              if (c.type != PrinterType.none)
                _Drop<ReceiptPaper>(
                  key: ValueKey('printer-paper-${c.isThermal}'),
                  label: 'مقاس الورق',
                  value: papers.contains(c.effectivePaper)
                      ? c.effectivePaper
                      : papers.first,
                  values: papers,
                  text: (p) => p.label,
                  onChanged: (p) => widget.onChanged(c.copyWith(paper: p)),
                ),
            ]),
            if (c.type != PrinterType.none) ...[
              const SizedBox(height: 6),
              Text(
                c.isThermal
                    ? '${c.effectivePaper.hint}. للورق الكبير A4/A5 اختر «طابعة النظام».'
                    : c.effectivePaper.hint,
                style: hint,
              ),
            ],
            if (c.type == PrinterType.bluetooth) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _scanning ? null : _pickBluetooth,
                icon: _scanning
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bluetooth_searching),
                label: Text(
                  c.btAddress.isEmpty
                      ? 'اختر الطابعة'
                      : 'تغيير الطابعة (${c.btName.isEmpty ? c.btAddress : c.btName})',
                ),
              ),
            ],
            if (c.type == PrinterType.lan) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _host,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'عنوان الطابعة (IP)',
                        hintText: '192.168.1.100',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _saveLan(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _port,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'المنفذ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _saveLan(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'اطبع ورقة الإعداد من الطابعة (اضغط زر التغذية عند تشغيلها) لمعرفة عنوانها.',
                style: hint,
              ),
            ],
            if (c.type == PrinterType.system) ...[
              const SizedBox(height: 8),
              Text(
                'تفتح نافذة الطباعة في كل مرة على الهاتف. على الحاسوب تطبع تلقائياً على الطابعة الافتراضية.',
                style: hint,
              ),
            ],
            if (c.type != PrinterType.none) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.testing ? null : widget.onTest,
                icon: widget.testing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_outlined),
                label: const Text('طباعة تجريبية'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- القوالب

class _TemplateCard extends StatefulWidget {
  const _TemplateCard({
    required this.kind,
    required this.template,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
    this.storeFooter = '',
  });

  final ReceiptKind kind;
  final ReceiptTemplate template;

  /// نص التذييل العام للمحل (لمعرفة حالة سطر الشكر الفعلية).
  final String storeFooter;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<ReceiptTemplate> onChanged;

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  late final _footer = TextEditingController(text: widget.template.footer);
  Timer? _debounce;

  static IconData _icon(ReceiptKind k) => switch (k) {
    ReceiptKind.oilChange => Icons.oil_barrel_outlined,
    ReceiptKind.directSale => Icons.point_of_sale_outlined,
    ReceiptKind.carWash => Icons.local_car_wash_outlined,
    ReceiptKind.debtPayment => Icons.account_balance_wallet_outlined,
    ReceiptKind.expense => Icons.payments_outlined,
    ReceiptKind.customerStatement => Icons.person_search_outlined,
    ReceiptKind.supplierStatement => Icons.local_shipping_outlined,
    ReceiptKind.saleReturn => Icons.assignment_return_outlined,
    ReceiptKind.sale => Icons.receipt_outlined,
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _footer.dispose();
    super.dispose();
  }

  void _set(ReceiptTemplate t) => widget.onChanged(t);

  Widget _check(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    Key? key,
  }) => CheckboxListTile(
    key: key,
    dense: true,
    contentPadding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(label),
    value: value,
    onChanged: (v) => onChanged(v ?? false),
  );

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final cs = Theme.of(context).colorScheme;
    final summary = [
      t.autoPrint ? 'طباعة تلقائية بعد الحفظ' : 'طباعة يدوية',
      if (t.copies > 1) '${t.copies} نسخ',
    ].join(' · ');
    final checks = [
      _check('الشعار', t.showLogo, (v) => _set(t.copyWith(showLogo: v))),
      _check(
        'العنوان والهاتف',
        t.showStoreContact,
        (v) => _set(t.copyWith(showStoreContact: v)),
      ),
      _check('رمز QR', t.showQr, (v) => _set(t.copyWith(showQr: v))),
      _check(
        'سطر «شكراً لزيارتكم»',
        t.thanksShown(
          hasFooterText:
              widget.storeFooter.trim().isNotEmpty ||
              t.footer.trim().isNotEmpty,
        ),
        (v) => _set(t.copyWith(showThanks: v)),
        key: ValueKey('template-thanks-${widget.kind.name}'),
      ),
      for (final s in widget.kind.sections)
        _check(
          s.label,
          t.shows(s),
          (v) => _set(
            t.copyWith(
              hidden: v ? ({...t.hidden}..remove(s)) : {...t.hidden, s},
            ),
          ),
        ),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.selected ? cs.primary : cs.outlineVariant,
          width: widget.selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        leading: Icon(_icon(widget.kind), color: cs.primary),
        title: Text(
          widget.kind.workLabel,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(summary),
        onExpansionChanged: (open) {
          if (open) widget.onSelect();
        },
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('طباعة تلقائية بعد الحفظ'),
            subtitle: const Text('إن لم توجد طابعة، يُحفظ العمل دون أي رسالة'),
            value: t.autoPrint,
            onChanged: (v) => _set(t.copyWith(autoPrint: v)),
          ),
          const SizedBox(height: 8),
          _Drop<int>(
            label: 'عدد النسخ',
            value: t.copies.clamp(1, 3),
            values: const [1, 2, 3],
            text: (n) => n == 1 ? 'نسخة واحدة' : '$n نسخ',
            onChanged: (n) => _set(t.copyWith(copies: n)),
          ),
          if (widget.kind == ReceiptKind.oilChange) ...[
            const SizedBox(height: 12),
            _Drop<int>(
              key: const ValueKey('template-next-months'),
              label: 'تاريخ تقريبي للغيار القادم',
              value: const [0, 1, 2, 3, 4, 6, 12].contains(t.nextServiceMonths)
                  ? t.nextServiceMonths
                  : 0,
              values: const [0, 1, 2, 3, 4, 6, 12],
              text: (n) => switch (n) {
                0 => 'لا يُطبع',
                1 => 'بعد شهر',
                2 => 'بعد شهرين',
                _ when n <= 10 => 'بعد $n أشهر',
                _ => 'بعد $n شهراً',
              },
              onChanged: (n) => _set(t.copyWith(nextServiceMonths: n)),
            ),
          ],
          const SizedBox(height: 12),
          _Drop<ReceiptSheetStyle>(
            key: const ValueKey('template-sheet-style'),
            label: 'على ورق A5 وA4',
            value: t.sheetStyle,
            values: ReceiptSheetStyle.values,
            text: (s) => s.label,
            onChanged: (s) => _set(t.copyWith(sheetStyle: s)),
          ),
          const SizedBox(height: 12),
          Text(
            'ما يظهر في الإيصال',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 520 ? 2 : 1;
              if (cols == 1) return Column(children: checks);
              return Wrap(
                children: [
                  for (final w in checks)
                    SizedBox(width: c.maxWidth / 2, child: w),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _footer,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'نص أسفل هذا الإيصال',
              hintText: 'مثال: الضمان على الزيت 5000 كم',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 600),
                () => _set(widget.template.copyWith(footer: v.trim())),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- المعاينة

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.kind,
    required this.kinds,
    required this.onKind,
    required this.document,
    required this.settings,
    required this.template,
    required this.paper,
    required this.design,
    required this.monochrome,
  });

  final ReceiptDesign design;
  final bool monochrome;
  final ReceiptKind kind;
  final List<ReceiptKind> kinds;
  final ValueChanged<ReceiptKind> onKind;
  final ReceiptDocument document;
  final PrintSettingsData settings;
  final ReceiptTemplate template;
  final ReceiptPaper paper;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.visibility_outlined,
          title: 'المعاينة',
          subtitle: monochrome
              ? 'هذا ما ستطبعه الطابعة بالضبط، على ورق ${paper.label} بالأسود.'
              : 'هذا ما ستطبعه الطابعة بالضبط، على ورق ${paper.label}.',
        ),
        const SizedBox(height: 12),
        if (kinds.length > 1)
          _Drop<ReceiptKind>(
            key: const ValueKey('preview-kind'),
            label: 'الإيصال المعروض',
            value: kind,
            values: kinds,
            text: (k) => k.workLabel,
            onChanged: onKind,
          ),
        const SizedBox(height: 14),
        ReceiptPreview(
          document: document,
          settings: settings,
          template: template,
          paper: paper,
          design: design,
          monochrome: monochrome,
          maxWidth: paper.isRoll ? 340 : 380,
        ),
        if (settings.storeTitleLine.trim().isEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'اسم المحل فارغ. أضفه من الإعدادات ← «بيانات المتجر».',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.error),
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------- المظهر

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.design,
    required this.thermal,
    required this.onChanged,
    this.logoBytes,
  });

  final ReceiptDesign design;
  final bool thermal;
  final ValueChanged<ReceiptDesign> onChanged;

  /// شعار المحل لمعاينة رمز QR بالشعار.
  final Uint8List? logoBytes;

  static const _colorGroups = <(String, List<ReceiptColorSlot>)>[
    (
      'الأساسية',
      [
        ReceiptColorSlot.accent,
        ReceiptColorSlot.onAccent,
        ReceiptColorSlot.ink,
        ReceiptColorSlot.muted,
      ],
    ),
    (
      'أجزاء الورقة',
      [
        ReceiptColorSlot.topBg,
        ReceiptColorSlot.topInk,
        ReceiptColorSlot.paper,
        ReceiptColorSlot.bottomBg,
        ReceiptColorSlot.bottomInk,
      ],
    ),
    (
      'الجدول',
      [
        ReceiptColorSlot.tableHead,
        ReceiptColorSlot.tableHeadInk,
        ReceiptColorSlot.grid,
      ],
    ),
  ];

  Widget _colors(BuildContext context, List<ReceiptColorSlot> slots) {
    final pal = design.palette;
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 520 ? 2 : 1;
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in slots)
              SizedBox(
                width: w,
                child: _ColorTile(
                  slot: s,
                  palette: pal,
                  onChanged: (v) =>
                      onChanged(design.copyWith(palette: pal.withSlot(s, v))),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = design;
    final warnings = thermal ? const <String>[] : d.contrastWarnings();
    final wmOn = d.watermark != ReceiptWatermark.none;
    final setColors = ReceiptColorSlot.values
        .where((s) => !s.isCore && d.palette.isSet(s))
        .length;
    final small = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader(
              icon: Icons.palette_outlined,
              title: 'مظهر الإيصال',
              subtitle: 'لكل إيصالات المحل. التغيير يظهر في المعاينة فوراً.',
            ),
            if (thermal) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'الطابعة الحرارية تطبع بالأسود على أبيض فقط: الألوان تظهر في '
                      'الطابعة الملوّنة والصورة المرسلة. الخط والأشكال والعلامة '
                      'المائية (نقاطاً خفيفة) وشكل QR تظهر في كل الطابعات.',
                      style: small,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            _Fold(
              key: const ValueKey('receipt-fold-font'),
              icon: Icons.text_fields,
              title: 'الخط والحجم',
              summary: '${d.font.label} · ${d.size.label} · ${d.density.label}',
              children: [
                _Drop<ReceiptFont>(
                  key: const ValueKey('receipt-font'),
                  label: 'الخط',
                  value: d.font,
                  values: ReceiptFont.values,
                  text: (f) => '${f.label} — مركز البصرة 0780',
                  itemStyle: (f) =>
                      TextStyle(fontFamily: f.family, fontSize: 16),
                  onChanged: (f) => onChanged(d.copyWith(font: f)),
                ),
                _Pair([
                  _Drop<ReceiptTextSize>(
                    label: 'حجم الخط',
                    value: d.size,
                    values: ReceiptTextSize.values,
                    text: (z) => z.label,
                    onChanged: (z) => onChanged(d.copyWith(size: z)),
                  ),
                  _Drop<ReceiptDensity>(
                    label: 'الكثافة',
                    value: d.density,
                    values: ReceiptDensity.values,
                    text: (z) => z.label,
                    onChanged: (z) => onChanged(d.copyWith(density: z)),
                  ),
                ]),
              ],
            ),
            _Fold(
              key: const ValueKey('receipt-design-parts'),
              icon: Icons.dashboard_customize_outlined,
              title: 'أشكال الأجزاء',
              summary:
                  'الرأس: ${d.header.label} · المعلومات: ${d.info.label} · الأصناف: ${d.items.label}',
              children: [
                _Pair([
                  _Drop<ReceiptHeaderLayout>(
                    label: 'رأس المحل',
                    value: d.header,
                    values: ReceiptHeaderLayout.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(header: v)),
                  ),
                  _Drop<ReceiptHeaderShape>(
                    label: 'شكل العنوان',
                    value: d.title,
                    values: ReceiptHeaderShape.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(title: v)),
                  ),
                ]),
                _Pair([
                  _Drop<ReceiptInfoStyle>(
                    key: const ValueKey('receipt-info'),
                    label: 'أسطر المعلومات',
                    value: d.info,
                    values: ReceiptInfoStyle.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(info: v)),
                  ),
                  _Drop<ReceiptItemsStyle>(
                    key: const ValueKey('receipt-items'),
                    label: 'جدول الأصناف',
                    value: d.items,
                    values: ReceiptItemsStyle.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(items: v)),
                  ),
                ]),
                _Pair([
                  _Drop<ReceiptHeaderShape>(
                    label: 'شكل الإجمالي',
                    value: d.totals,
                    values: ReceiptHeaderShape.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(totals: v)),
                  ),
                  _Drop<ReceiptHighlightStyle>(
                    label: 'الصناديق البارزة',
                    value: d.highlight,
                    values: ReceiptHighlightStyle.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(highlight: v)),
                  ),
                ]),
                _Pair([
                  _Drop<ReceiptFrame>(
                    label: 'زخرفة الورقة',
                    value: d.frame,
                    values: ReceiptFrame.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(frame: v)),
                  ),
                  _Drop<ReceiptTopEdge>(
                    key: const ValueKey('receipt-top-edge'),
                    label: 'حافة الجزء العلوي',
                    value: d.topEdge,
                    values: ReceiptTopEdge.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(topEdge: v)),
                  ),
                ]),
                _Pair([
                  _Drop<ReceiptSectionTitles>(
                    key: const ValueKey('receipt-section-titles'),
                    label: 'عناوين الأقسام',
                    value: d.sectionTitles,
                    values: ReceiptSectionTitles.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(sectionTitles: v)),
                  ),
                  _Drop<ReceiptSectionBox>(
                    label: 'إطار الأقسام',
                    value: d.sectionBox,
                    values: ReceiptSectionBox.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(sectionBox: v)),
                  ),
                ]),
                _Pair([
                  _Drop<ReceiptItemMarker>(
                    label: 'علامة الأصناف',
                    value: d.itemMarker,
                    values: ReceiptItemMarker.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(itemMarker: v)),
                  ),
                  _Drop<ReceiptTotalLayout>(
                    key: const ValueKey('receipt-total-layout'),
                    label: 'عرض الإجمالي',
                    value: d.totalLayout,
                    values: ReceiptTotalLayout.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(totalLayout: v)),
                  ),
                ]),
                _Drop<ReceiptEdges>(
                  label: 'حواف الورقة',
                  value: d.edges,
                  values: ReceiptEdges.values,
                  text: (v) => v.label,
                  onChanged: (v) => onChanged(d.copyWith(edges: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('receipt-side-strip'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('شريط جانبي ملوّن'),
                  value: d.sideStrip,
                  onChanged: (v) => onChanged(d.copyWith(sideStrip: v)),
                ),
              ],
            ),
            _Fold(
              key: const ValueKey('receipt-fold-colors'),
              icon: Icons.color_lens_outlined,
              title: 'الألوان',
              summary: setColors == 0
                  ? 'العنوان ${_hex(d.palette.accent)} · النص ${_hex(d.palette.ink)} · الورقة ${_hex(d.palette.paper)}'
                  : 'العنوان ${_hex(d.palette.accent)} · $setColors لون مخصص',
              children: [
                for (final (title, slots) in _colorGroups) ...[
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  _colors(context, slots),
                ],
              ],
            ),
            _Fold(
              key: const ValueKey('receipt-fold-watermark'),
              icon: Icons.branding_watermark_outlined,
              title: 'العلامة المائية',
              summary: wmOn
                  ? '${d.watermark.label} · ${d.watermarkPattern.label}'
                  : 'بلا علامة مائية',
              children: [
                _Pair([
                  _Drop<ReceiptWatermark>(
                    key: const ValueKey('receipt-wm'),
                    label: 'الشعار',
                    value: d.watermark,
                    values: ReceiptWatermark.values,
                    text: (v) => v.label,
                    onChanged: (v) => onChanged(d.copyWith(watermark: v)),
                  ),
                  if (wmOn)
                    _Drop<ReceiptWatermarkPattern>(
                      key: const ValueKey('receipt-wm-pattern'),
                      label: 'التوزيع',
                      value: d.watermarkPattern,
                      values: ReceiptWatermarkPattern.values,
                      text: (v) => v.label,
                      onChanged: (v) =>
                          onChanged(d.copyWith(watermarkPattern: v)),
                    ),
                ]),
                if (wmOn) ...[
                  _Slide(
                    label: 'الحجم',
                    value: d.watermarkSize,
                    min: 0.12,
                    max: 0.8,
                    onChanged: (v) => onChanged(d.copyWith(watermarkSize: v)),
                  ),
                  if (d.watermarkPattern.tiled)
                    _Slide(
                      label: 'المسافة بين الشعارات',
                      value: d.watermarkGap / 2,
                      min: 0.05,
                      max: 1,
                      onChanged: (v) =>
                          onChanged(d.copyWith(watermarkGap: v * 2)),
                    ),
                  _Slide(
                    label: 'الوضوح',
                    value: d.watermarkOpacity,
                    min: 0.02,
                    max: 0.3,
                    onChanged: (v) =>
                        onChanged(d.copyWith(watermarkOpacity: v)),
                  ),
                ],
              ],
            ),
            _Fold(
              key: const ValueKey('receipt-fold-qr'),
              icon: Icons.qr_code_2,
              title: 'رمز QR',
              summary: '${d.qrStyle.label}${d.qrLogo ? ' · بالشعار' : ''}',
              children: [
                _Drop<ReceiptQrStyle>(
                  key: const ValueKey('receipt-qr-style'),
                  label: 'شكل الرمز',
                  value: d.qrStyle,
                  values: ReceiptQrStyle.values,
                  text: (v) => v.label,
                  leading: (v) => _QrThumb(
                    design: d.copyWith(qrStyle: v, qrLogo: false),
                    monochrome: thermal,
                  ),
                  onChanged: (v) => onChanged(d.copyWith(qrStyle: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('receipt-qr-logo'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('شعار المحل داخل الرمز'),
                  subtitle: Text(
                    logoBytes == null
                        ? 'أضف شعار المحل من «بيانات المتجر» أولاً.'
                        : 'يبقى الرمز مقروءاً: يُرفع تصحيح الأخطاء تلقائياً.',
                  ),
                  value: d.qrLogo,
                  onChanged: (v) => onChanged(d.copyWith(qrLogo: v)),
                ),
                _ColorTile(
                  slot: ReceiptColorSlot.qr,
                  palette: d.palette,
                  onChanged: (v) => onChanged(
                    d.copyWith(
                      palette: d.palette.withSlot(ReceiptColorSlot.qr, v),
                    ),
                  ),
                ),
                Center(
                  child: _QrThumb(
                    design: d,
                    monochrome: thermal,
                    size: 120,
                    logoBytes: logoBytes,
                  ),
                ),
              ],
            ),
            for (final w in warnings) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(w, style: TextStyle(color: cs.error)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// القوالب الجاهزة: عائلات ألوان وهياكل؛ الضغط على قالب يطبّقه كاملاً
/// ويبقى كل جزء فيه قابلاً للتعديل من «مظهر الإيصال».
class _GalleryCard extends StatefulWidget {
  const _GalleryCard({
    required this.design,
    required this.settings,
    required this.document,
    required this.onPick,
  });

  final ReceiptDesign design;
  final PrintSettingsData settings;
  final ReceiptDocument document;
  final ValueChanged<ReceiptDesign> onPick;

  @override
  State<_GalleryCard> createState() => _GalleryCardState();
}

class _GalleryCardState extends State<_GalleryCard> {
  late ReceiptGalleryFamily _family =
      ReceiptGallery.byId(widget.design.preset)?.family ??
      ReceiptGalleryFamily.sky;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = ReceiptGallery.byId(widget.design.preset);
    final entries = ReceiptGallery.of(_family);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: _Fold(
          key: const ValueKey('receipt-fold-gallery'),
          icon: Icons.auto_awesome_mosaic_outlined,
          title: 'القوالب الجاهزة',
          summary: current == null
              ? '${ReceiptGallery.all.length} قالباً جاهزاً. اختر واحداً ثم عدّل ما تشاء.'
              : 'المختار: ${current.name}',
          children: [
            _Drop<ReceiptGalleryFamily>(
              key: const ValueKey('receipt-gallery-family'),
              label: 'العائلة',
              value: _family,
              values: ReceiptGalleryFamily.values,
              text: (f) => '${f.label} (${ReceiptGallery.of(f).length})',
              onChanged: (f) => setState(() => _family = f),
            ),
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 700
                    ? 5
                    : c.maxWidth >= 440
                    ? 3
                    : 2;
                final w = (c.maxWidth - (cols - 1) * 10) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final e in entries)
                      SizedBox(
                        width: w,
                        child: _GalleryTile(
                          key: ValueKey('gallery-${e.id}'),
                          entry: e,
                          selected: e.id == current?.id,
                          settings: widget.settings,
                          document: widget.document,
                          onTap: () => widget.onPick(e.design),
                        ),
                      ),
                  ],
                );
              },
            ),
            Text(
              'القالب يغيّر الخط والألوان والأشكال فقط، وبيانات المحل كما هي. '
              'بعد اختياره عدّل أي جزء من «مظهر الإيصال».',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryTile extends StatefulWidget {
  const _GalleryTile({
    required this.entry,
    required this.selected,
    required this.settings,
    required this.document,
    required this.onTap,
    super.key,
  });

  final ReceiptGalleryEntry entry;
  final bool selected;
  final PrintSettingsData settings;
  final ReceiptDocument document;
  final VoidCallback onTap;

  @override
  State<_GalleryTile> createState() => _GalleryTileState();
}

class _GalleryTileState extends State<_GalleryTile> {
  ui.Image? _img;

  /// ما يظهر من بيانات المحل في الصورة المصغرة؛ لا نعيد الرسم إلا إن تغيّر.
  static Object _brandKey(PrintSettingsData s) => (
    s.storeTitleLine,
    s.storeAddress,
    s.storePhones.join(','),
    s.storeLogoBase64.length,
  );

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(_GalleryTile old) {
    super.didUpdateWidget(old);
    if (old.entry.id != widget.entry.id ||
        _brandKey(old.settings) != _brandKey(widget.settings) ||
        !identical(old.document, widget.document)) {
      _render();
    }
  }

  Future<void> _render() async {
    final id = widget.entry.id;
    final r = await ReceiptRenderer.render(
      widget.document,
      settings: widget.settings,
      template: ReceiptTemplate.defaultsFor(widget.document.kind),
      paper: ReceiptPaper.mm58,
      design: widget.entry.design,
      monochrome: false,
    );
    if (!mounted || id != widget.entry.id) {
      r.dispose();
      return;
    }
    setState(() {
      _img?.dispose();
      _img = r.image;
    });
  }

  @override
  void dispose() {
    _img?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final img = _img;
    final e = widget.entry;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: 'قالب ${e.name}',
      child: Material(
        color: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: widget.selected ? cs.primary : cs.outlineVariant,
            width: widget.selected ? 2.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 0.62,
                child: img == null
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.fitWidth,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.hardEdge,
                        child: RawImage(image: img),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  children: [
                    if (widget.selected) ...[
                      Icon(Icons.check_circle, size: 18, color: cs.primary),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        '${e.family.label} ${e.number}\n${e.skeleton.label}',
                        maxLines: 2,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: widget.selected ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// معاينة صغيرة لرمز QR بالشكل واللون المختارين.
class _QrThumb extends StatefulWidget {
  const _QrThumb({
    required this.design,
    required this.monochrome,
    this.size = 34,
    this.logoBytes,
  });

  final ReceiptDesign design;
  final bool monochrome;
  final double size;
  final Uint8List? logoBytes;

  @override
  State<_QrThumb> createState() => _QrThumbState();
}

class _QrThumbState extends State<_QrThumb> {
  ui.Image? _img;
  Object? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _render();
  }

  @override
  void didUpdateWidget(_QrThumb old) {
    super.didUpdateWidget(old);
    _render();
  }

  Future<void> _render() async {
    final key = (
      widget.design.qrStyle,
      widget.design.qrLogo,
      widget.design.palette.of(ReceiptColorSlot.qr),
      widget.design.palette.paper,
      widget.monochrome,
      widget.size,
      widget.logoBytes?.length,
    );
    if (key == _key) return;
    _key = key;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final img = await ReceiptRenderer.qrImage(
      'https://naboo.fun/r/0000',
      design: widget.design,
      side: (widget.size * dpr).roundToDouble(),
      monochrome: widget.monochrome,
      logoBytes: widget.logoBytes,
    );
    if (!mounted || key != _key) {
      img.dispose();
      return;
    }
    setState(() {
      _img?.dispose();
      _img = img;
    });
  }

  @override
  void dispose() {
    _img?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    return SizedBox.square(
      dimension: widget.size,
      child: img == null
          ? null
          : RawImage(image: img, filterQuality: FilterQuality.medium),
    );
  }
}
