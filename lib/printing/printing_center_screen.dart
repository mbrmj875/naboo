import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/print_settings_data.dart';
import '../providers/print_settings_provider.dart';
import '../providers/auth_provider.dart';
import '../screens/settings/store_info_screen.dart';
import '../services/effective_store_branding.dart';
import 'printer_connection.dart';
import 'receipt_builders.dart';
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
    _loadConnection();
  }

  Future<void> _loadConnection() async {
    final prov = context.read<PrintSettingsProvider>();
    if (!prov.isReady) await prov.load();
    final c = await PrinterConnection.load(legacy: prov.data);
    if (mounted) setState(() => _conn = c);
  }

  /// يعيد حساب بيانات المحل عند تغيّر الإعدادات أو بعد الرجوع من «بيانات المحل».
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

  Future<void> _openStoreInfo() async {
    final isOwner = context.read<AuthProvider>().isOwner;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StoreInfoScreen(
          scope: isOwner ? StoreInfoScope.workspace : StoreInfoScope.myBranch,
        ),
      ),
    );
    if (!mounted) return;
    final prov = context.read<PrintSettingsProvider>();
    await prov.load();
    if (mounted) await _refreshBranding(prov.data);
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

  Future<void> _saveStyle(ReceiptStyle st) async {
    final prov = context.read<PrintSettingsProvider>();
    await prov.save(
      prov.data.copyWith(
        receiptTemplates: ReceiptTemplates(
          prov.data.receiptTemplates,
        ).withStyle(st),
      ),
    );
  }

  Future<void> _testPrint() async {
    final conn = _conn;
    if (conn == null) return;
    setState(() => _testing = true);
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
        appBar: AppBar(
          title: const Text('الطباعة'),
          actions: [
            // لون أزرار الشريط نفسه، فلا يختفي الزر على الشريط الداكن.
            Builder(
              builder: (ctx) => TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: IconTheme.of(ctx).color,
                ),
                onPressed: _openStoreInfo,
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('بيانات المحل'),
              ),
            ),
          ],
        ),
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
              style: ReceiptTemplates(settings.receiptTemplates).style,
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
              _StyleCard(
                style: ReceiptTemplates(settings.receiptTemplates).style,
                thermal: conn.isThermal,
                onChanged: _saveStyle,
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in PrinterType.values)
                  if (t != PrinterType.bluetooth || BluetoothTransport.supported)
                    ChoiceChip(
                      label: Text(t.label),
                      selected: c.type == t,
                      onSelected: (_) =>
                          widget.onChanged(c.copyWith(type: t)),
                    ),
              ],
            ),
            if (c.type != PrinterType.none) ...[
              const SizedBox(height: 14),
              Text('مقاس الورق', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // الحرارية لفافة فقط؛ A5/A4 لطابعات المكتب عبر طابعة النظام.
                  for (final p in c.isThermal
                      ? ReceiptPaper.rolls
                      : ReceiptPaper.values)
                    ChoiceChip(
                      label: Text(p.label),
                      selected: c.effectivePaper == p,
                      onSelected: (_) =>
                          widget.onChanged(c.copyWith(paper: p)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                c.isThermal
                    ? '${c.effectivePaper.hint}. للورق الكبير A4/A5 اختر «طابعة النظام».'
                    : c.effectivePaper.hint,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (c.type == PrinterType.bluetooth) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _scanning ? null : _pickBluetooth,
                icon: _scanning
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bluetooth_searching),
                label: Text(
                  c.btAddress.isEmpty ? 'اختر الطابعة' : 'تغيير الطابعة',
                ),
              ),
            ],
            if (c.type == PrinterType.lan) ...[
              const SizedBox(height: 14),
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
                      ),
                      onChanged: (_) => _saveLan(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'اطبع ورقة الإعداد من الطابعة (اضغط زر التغذية عند تشغيلها) لمعرفة عنوانها.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (c.type == PrinterType.system) ...[
              const SizedBox(height: 10),
              Text(
                'تفتح نافذة الطباعة في كل مرة على الهاتف. على الحاسوب تطبع تلقائياً على الطابعة الافتراضية.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (c.type != PrinterType.none) ...[
              const SizedBox(height: 14),
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
  });

  final ReceiptKind kind;
  final ReceiptTemplate template;
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
    ReceiptKind.sale => Icons.receipt_outlined,
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _footer.dispose();
    super.dispose();
  }

  void _set(ReceiptTemplate t) => widget.onChanged(t);

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final cs = Theme.of(context).colorScheme;
    final summary = [
      t.autoPrint ? 'طباعة تلقائية بعد الحفظ' : 'طباعة يدوية',
      if (t.copies > 1) '${t.copies} نسخ',
    ].join(' · ');
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
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('طباعة تلقائية بعد الحفظ'),
            subtitle: const Text('إن لم توجد طابعة، يُحفظ العمل دون أي رسالة'),
            value: t.autoPrint,
            onChanged: (v) => _set(t.copyWith(autoPrint: v)),
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              const Text('عدد النسخ'),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                ],
                selected: {t.copies},
                onSelectionChanged: (s) => _set(t.copyWith(copies: s.first)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('ما يظهر في الإيصال', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('الشعار'),
                selected: t.showLogo,
                onSelected: (v) => _set(t.copyWith(showLogo: v)),
              ),
              FilterChip(
                label: const Text('العنوان والهاتف'),
                selected: t.showStoreContact,
                onSelected: (v) => _set(t.copyWith(showStoreContact: v)),
              ),
              FilterChip(
                label: const Text('رمز QR'),
                selected: t.showQr,
                onSelected: (v) => _set(t.copyWith(showQr: v)),
              ),
              for (final s in widget.kind.sections)
                FilterChip(
                  label: Text(s.label),
                  selected: t.shows(s),
                  onSelected: (v) => _set(
                    t.copyWith(
                      hidden: v ? ({...t.hidden}..remove(s)) : {...t.hidden, s},
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
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
    required this.style,
    required this.monochrome,
  });

  final ReceiptStyle style;
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
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final k in kinds)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text(k.workLabel),
                    selected: k == kind,
                    onSelected: (_) => onKind(k),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ReceiptPreview(
          document: document,
          settings: settings,
          template: template,
          paper: paper,
          style: style,
          monochrome: monochrome,
          maxWidth: paper.isRoll ? 340 : 380,
        ),
        if (settings.storeTitleLine.trim().isEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'اسم المحل فارغ. أضفه من «بيانات المحل» أعلى الشاشة.',
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
    required this.style,
    required this.thermal,
    required this.onChanged,
  });

  final ReceiptStyle style;
  final bool thermal;
  final ValueChanged<ReceiptStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelLarge;
    Widget gap() => const SizedBox(height: 14);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.palette_outlined,
              title: 'مظهر الإيصال',
              subtitle: 'لكل إيصالات المحل. التغيير يظهر في المعاينة فوراً.',
            ),
            gap(),
            Text('الخط', style: label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in ReceiptFont.values)
                  ChoiceChip(
                    label: Text(
                      f.label,
                      style: TextStyle(fontFamily: f.family),
                    ),
                    selected: style.font == f,
                    onSelected: (_) => onChanged(style.copyWith(font: f)),
                  ),
              ],
            ),
            gap(),
            Text('حجم الخط', style: label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final z in ReceiptTextSize.values)
                  ChoiceChip(
                    label: Text(z.label),
                    selected: style.size == z,
                    onSelected: (_) => onChanged(style.copyWith(size: z)),
                  ),
              ],
            ),
            gap(),
            Text('شكل العنوان والإجمالي', style: label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sh in ReceiptHeaderShape.values)
                  ChoiceChip(
                    label: Text(sh.label),
                    selected: style.shape == sh,
                    onSelected: (_) => onChanged(style.copyWith(shape: sh)),
                  ),
              ],
            ),
            gap(),
            _ColorRow(
              title: 'لون العنوان والإجمالي',
              value: style.accent,
              onChanged: (c) => onChanged(style.copyWith(accent: c)),
            ),
            gap(),
            _ColorRow(
              title: 'لون النص',
              value: style.ink,
              onChanged: (c) => onChanged(style.copyWith(ink: c)),
            ),
            if (thermal) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'الطابعة الحرارية تطبع بالأسود فقط، فلا تظهر الألوان عليها. '
                      'الخط والحجم والشكل تظهر في كل الطابعات.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
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

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final ReceiptColor value;
  final ValueChanged<ReceiptColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title: ${value.label}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in ReceiptColor.values)
              Semantics(
                button: true,
                selected: c == value,
                label: c.label,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onChanged(c),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(c.argb),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == value ? cs.primary : cs.outlineVariant,
                        width: c == value ? 3 : 1,
                      ),
                    ),
                    child: c == value
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
