import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../models/oil_change_rating.dart';
import '../services/oil_change_ratings_repository.dart';
import '../widgets/oil_change_form_theme.dart';
import '../widgets/oil_change_rating_widgets.dart';
import '../../../navigation/content_navigation.dart';

/// سجل فني واحد: كل رد وصل من واتساب، مجمّعاً حسب رقم العميل.
class OilChangeEmployeeRatingsScreen extends StatefulWidget {
  const OilChangeEmployeeRatingsScreen({
    super.key,
    required this.summary,
    this.unassigned = false,
  });

  final OilChangeEmployeeRatingSummary summary;

  /// ردود لم تُسنَد لأي فني.
  final bool unassigned;

  static Future<void> open(
    BuildContext context, {
    required OilChangeEmployeeRatingSummary summary,
    bool unassigned = false,
  }) {
    return Navigator.of(context).push<void>(
      FastContentPageRoute<void>(
        builder: (_) => OilChangeEmployeeRatingsScreen(
          summary: summary,
          unassigned: unassigned,
        ),
      ),
    );
  }

  @override
  State<OilChangeEmployeeRatingsScreen> createState() =>
      _OilChangeEmployeeRatingsScreenState();
}

class _OilChangeEmployeeRatingsScreenState
    extends State<OilChangeEmployeeRatingsScreen> {
  final _scrollController = ScrollController();
  final _dateFormat = DateFormat('d MMMM · h:mm a', 'ar_SA');

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  final List<OilChangeRatingEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      unawaited(_loadMore());
    }
  }

  Future<List<OilChangeRatingEntry>> _fetch({DateTime? before}) {
    return OilChangeRatingsRepository.instance.loadEntries(
      employeeName: widget.unassigned ? null : widget.summary.employeeName,
      unassignedOnly: widget.unassigned,
      beforeCreatedAt: before,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _fetch();
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(rows);
        _hasMore = rows.length >= OilChangeRatingsRepository.pageSize;
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

  Future<void> _loadMore() async {
    final last = _entries.isEmpty ? null : _entries.last.createdAt;
    if (last == null) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _fetch(before: last);
      if (!mounted) return;
      setState(() {
        _entries.addAll(more);
        _hasMore = more.length >= OilChangeRatingsRepository.pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasMore = false;
        _loadingMore = false;
      });
    }
  }

  /// الردود مرتّبة من الأحدث، فأول ردّ لكل بطاقة هو المعتمد في المتوسط.
  Set<String> get _countedEntryIds {
    final seenCards = <String>{};
    final counted = <String>{};
    for (final entry in _entries) {
      if (entry.score == null) continue;
      final cardKey = entry.orderRef ?? 'entry:${entry.id}';
      if (seenCards.add(cardKey)) counted.add(entry.id);
    }
    return counted;
  }

  /// تجميع حسب رقم العميل مع الحفاظ على ترتيب الأحدث.
  List<MapEntry<String, List<OilChangeRatingEntry>>> get _byPhone {
    final groups = <String, List<OilChangeRatingEntry>>{};
    for (final entry in _entries) {
      groups.putIfAbsent(entry.customerPhone, () => []).add(entry);
    }
    return groups.entries.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OilChangeFormTheme.appBar(
        context: context,
        title: widget.unassigned ? 'ردود غير منسوبة' : widget.summary.employeeName,
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

    final counted = _countedEntryIds;
    final groups = _byPhone;

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 20),
          if (_entries.isEmpty)
            const Padding(
              padding: EdgeInsetsDirectional.only(top: 24),
              child: Text(
                'لم يصل أي رد لهذا الفني بعد.',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final group in groups) ...[
              _buildPhoneHeader(group.key, group.value),
              const SizedBox(height: 8),
              ...group.value.map(
                (e) => _buildEntryTile(e, counted: counted.contains(e.id)),
              ),
              const SizedBox(height: 16),
            ],
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final theme = Theme.of(context);
    final s = widget.summary;
    return Container(
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          OilChangeScoreBadge(score: s.averageScore, size: 62),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.averageScore == null
                      ? 'لا يوجد متوسط بعد'
                      : 'المتوسط ${s.averageScore!.toStringAsFixed(1)} من 10',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.ratingsCount} بطاقة مُقيَّمة · ${s.repliesCount} رد '
                  '· ${s.notesCount} ملاحظة',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.start,
                ),
                if (s.lastRatingAt != null)
                  Text(
                    'آخر رد: ${_dateFormat.format(s.lastRatingAt!.toLocal())}',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.start,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneHeader(String phone, List<OilChangeRatingEntry> rows) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.phone_iphone_rounded, size: 18, color: theme.hintColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            phone,
            style: const TextStyle(fontWeight: FontWeight.w900),
            textAlign: TextAlign.start,
            textDirection: TextDirection.ltr,
          ),
        ),
        Text(
          '${rows.length} رسالة',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.start,
        ),
      ],
    );
  }

  Widget _buildEntryTile(
    OilChangeRatingEntry entry, {
    required bool counted,
  }) {
    final theme = Theme.of(context);
    final when = entry.createdAt == null
        ? '—'
        : _dateFormat.format(entry.createdAt!.toLocal());

    return Card(
      elevation: 0,
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OilChangeScoreBadge(score: entry.score?.toDouble()),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(when, textAlign: TextAlign.start),
                  if (entry.orderRef != null)
                    Text(
                      'بطاقة رقم ${entry.orderRef}',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.start,
                    ),
                  if (entry.note != null) ...[
                    const SizedBox(height: 6),
                    Text(entry.note!, textAlign: TextAlign.start),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    entry.score == null
                        ? 'ملاحظة بلا تقييم رقمي'
                        : counted
                            ? 'معتمد في المتوسط'
                            : 'رد سابق لنفس البطاقة',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: entry.score != null && counted
                          ? Colors.green.shade700
                          : theme.hintColor,
                      fontWeight: entry.score != null && counted
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                    textAlign: TextAlign.start,
                  ),
                ],
              ),
            ),
            if (!entry.isExactMatch)
              Tooltip(
                message: 'إسناد تقديري لآخر بطاقة خلال 72 ساعة',
                child: Icon(
                  Icons.help_outline_rounded,
                  size: 18,
                  color: theme.hintColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
