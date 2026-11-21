import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/oil_change_rating.dart';
import '../services/oil_change_ratings_repository.dart';
import '../services/oil_change_technicians_store.dart';
import '../widgets/oil_change_form_theme.dart';
import '../widgets/oil_change_rating_widgets.dart';
import '../../../navigation/content_navigation.dart';
import 'oil_change_employee_ratings_screen.dart';

/// تقييمات العملاء لكل فني — مصدرها ردود واتساب على بطاقة الغيار.
///
/// القائمة الأساسية هي فنيو المحل المسجّلون فقط؛ أي اسم قديم غير مسجّل
/// يظهر منفصلاً مع إمكانية ضمّه للقائمة.
class OilChangeRatingsScreen extends StatefulWidget {
  const OilChangeRatingsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      FastContentPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const OilChangeRatingsScreen(),
      ),
    );
  }

  @override
  State<OilChangeRatingsScreen> createState() => _OilChangeRatingsScreenState();
}

class _OilChangeRatingsScreenState extends State<OilChangeRatingsScreen> {
  static const _unassignedLabel = 'غير محدد';

  final _dateFormat = DateFormat('d MMMM · h:mm a', 'ar_SA');
  final _store = OilChangeTechniciansStore.instance;

  bool _loading = true;
  Object? _error;
  List<String> _technicians = const [];
  Map<String, OilChangeEmployeeRatingSummary> _summaryByName = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final technicians = await _store.load();
      final rows =
          await OilChangeRatingsRepository.instance.loadEmployeeSummary();
      if (!mounted) return;
      setState(() {
        _technicians = technicians;
        _summaryByName = {
          for (final row in rows) _key(row.employeeName): row,
        };
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String _key(String name) =>
      OilChangeTechniciansStore.normalize(name).toLowerCase();

  OilChangeEmployeeRatingSummary _summaryFor(String technician) {
    return _summaryByName[_key(technician)] ??
        OilChangeEmployeeRatingSummary.empty(technician);
  }

  /// أسماء لها ردود لكنها ليست ضمن فنيي المحل — بيانات قديمة أو كتابة حرة.
  List<OilChangeEmployeeRatingSummary> get _unregistered {
    final known = _technicians.map(_key).toSet();
    return _summaryByName.entries
        .where((e) => e.key != _key(_unassignedLabel) && !known.contains(e.key))
        .map((e) => e.value)
        .toList();
  }

  OilChangeEmployeeRatingSummary? get _unassigned =>
      _summaryByName[_key(_unassignedLabel)];

  Future<void> _addToTechnicians(String name) async {
    final names = await _store.add(name);
    if (!mounted) return;
    setState(() => _technicians = names);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('أُضيف «$name» إلى قائمة الفنيين')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OilChangeFormTheme.appBar(
        context: context,
        title: 'تقييمات الفنيين',
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : () => unawaited(_reload()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return OilChangeRatingErrorState(onRetry: () => unawaited(_reload()));
    }
    if (_technicians.isEmpty && _summaryByName.isEmpty) {
      return const _EmptyState();
    }

    final unregistered = _unregistered;
    final unassigned = _unassigned;

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
        children: [
          const _SectionTitle('فنيو المحل'),
          const SizedBox(height: 4),
          Text(
            'التقييم من ردود العملاء على واتساب. المتوسط يحتسب آخر رد لكل بطاقة.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 10),
          if (_technicians.isEmpty)
            const _NoTechniciansHint()
          else
            ..._technicians.map((name) => _buildTechnicianCard(_summaryFor(name))),
          if (unregistered.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('أسماء غير مسجّلة'),
            const SizedBox(height: 4),
            Text(
              'وردت تقييمات بأسماء ليست في قائمة فنييك — أضفها لتتابعها معهم.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 10),
            ...unregistered.map(_buildUnregisteredCard),
          ],
          if (unassigned != null) ...[
            const SizedBox(height: 20),
            const _SectionTitle('ردود غير منسوبة'),
            const SizedBox(height: 4),
            Text(
              'ردود وصلت دون معرفة البطاقة أو الفني — غالباً رسالة قديمة أو '
              'رقم لم تُرسل له بطاقة خلال 72 ساعة.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 10),
            _buildTechnicianCard(unassigned, unassignedGroup: true),
          ],
        ],
      ),
    );
  }

  Widget _buildTechnicianCard(
    OilChangeEmployeeRatingSummary summary, {
    bool unassignedGroup = false,
  }) {
    final theme = Theme.of(context);
    final subtitle = summary.hasReplies
        ? '${summary.ratingsCount} بطاقة مُقيَّمة · ${summary.repliesCount} رد'
            '${summary.notesCount > 0 ? ' · ${summary.notesCount} ملاحظة' : ''}'
        : 'لا توجد ردود بعد';
    final last = summary.lastRatingAt;

    return Card(
      elevation: 0,
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ListTile(
        onTap: summary.hasReplies
            ? () => unawaited(
                  OilChangeEmployeeRatingsScreen.open(
                    context,
                    summary: summary,
                    unassigned: unassignedGroup,
                  ),
                )
            : null,
        leading: OilChangeScoreBadge(score: summary.averageScore),
        title: Text(
          unassignedGroup ? 'بلا فني محدد' : summary.employeeName,
          style: const TextStyle(fontWeight: FontWeight.w700),
          textAlign: TextAlign.start,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, textAlign: TextAlign.start),
            if (last != null)
              Text(
                'آخر رد: ${_dateFormat.format(last.toLocal())}',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.start,
              ),
          ],
        ),
        trailing: summary.hasReplies
            ? const Icon(Icons.chevron_left_rounded)
            : null,
      ),
    );
  }

  Widget _buildUnregisteredCard(OilChangeEmployeeRatingSummary summary) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ListTile(
        onTap: () => unawaited(
          OilChangeEmployeeRatingsScreen.open(context, summary: summary),
        ),
        leading: OilChangeScoreBadge(score: summary.averageScore),
        title: Text(
          summary.employeeName,
          style: const TextStyle(fontWeight: FontWeight.w700),
          textAlign: TextAlign.start,
        ),
        subtitle: Text(
          '${summary.ratingsCount} بطاقة مُقيَّمة · ${summary.repliesCount} رد',
          textAlign: TextAlign.start,
        ),
        trailing: TextButton(
          onPressed: () => unawaited(_addToTechnicians(summary.employeeName)),
          child: const Text('إضافة'),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
      textAlign: TextAlign.start,
    );
  }
}

class _NoTechniciansHint extends StatelessWidget {
  const _NoTechniciansHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: const Text(
        'لم تُضف فنيين بعد. افتح بطاقة غيار جديدة واضغط زر + بجانب '
        '«اسم الفني المسؤول» لإضافتهم، ثم ستظهر تقييماتهم هنا.',
        textAlign: TextAlign.start,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_border_rounded,
              size: 56,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(height: 12),
            const Text(
              'لا توجد تقييمات بعد',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'تظهر هنا ردود العملاء على بطاقة الغيار عبر واتساب الرسمي، '
              'منسوبة للفني المذكور في البطاقة.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
