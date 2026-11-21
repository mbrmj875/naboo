import 'dart:convert';

import '../models/pharmacy_rx_schedule.dart';
import 'drug_catalog_repository.dart';

/// نتيجة استيراد CSV لمراجع الأدوية.
class PharmacyDrugReferenceCsvImportResult {
  const PharmacyDrugReferenceCsvImportResult({
    required this.importedCount,
    required this.skippedCount,
    this.errors = const [],
  });

  final int importedCount;
  final int skippedCount;
  final List<String> errors;
}

/// استيراد مراجع أدوية من CSV — قالب فارغ بدون بيانات حقيقية.
class PharmacyDrugReferenceCsvImporter {
  PharmacyDrugReferenceCsvImporter({DrugCatalogRepository? repository})
      : _repo = repository ?? DrugCatalogRepository();

  final DrugCatalogRepository _repo;

  /// رؤوس الأعمدة المتوقعة (يمكن تضمينها في assets/pharmacy/…).
  static const expectedHeaders = [
    'name_ar',
    'name_en',
    'atc_code',
    'indications_pipe',
    'indications_free_text',
    'age_band',
    'interactions_placeholder_pipe',
  ];

  /// قالب CSV فارغ — للتوثيق والاستيراد اليدوي.
  static String buildEmptyTemplate() {
    return '${expectedHeaders.join(',')}\n';
  }

  Future<PharmacyDrugReferenceCsvImportResult> importFromCsv({
    required int tenantId,
    required String csvContent,
  }) async {
    await _repo.ensureSchema();
    final lines = LineSplitter().convert(csvContent.trim());
    if (lines.isEmpty) {
      return const PharmacyDrugReferenceCsvImportResult(
        importedCount: 0,
        skippedCount: 0,
        errors: ['csv_empty'],
      );
    }

    final header = _splitCsvLine(lines.first);
    if (!_headersMatch(header)) {
      return PharmacyDrugReferenceCsvImportResult(
        importedCount: 0,
        skippedCount: lines.length > 1 ? lines.length - 1 : 0,
        errors: ['invalid_csv_headers: expected ${expectedHeaders.join('|')}'],
      );
    }

    var imported = 0;
    var skipped = 0;
    final errors = <String>[];

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) {
        skipped++;
        continue;
      }
      final cols = _splitCsvLine(line);
      if (cols.every((c) => c.trim().isEmpty)) {
        skipped++;
        continue;
      }
      while (cols.length < expectedHeaders.length) {
        cols.add('');
      }
      final nameAr = cols[0].trim();
      final nameEn = cols[1].trim();
      if (nameAr.isEmpty && nameEn.isEmpty) {
        skipped++;
        continue;
      }
      try {
        await _repo.insertDrugReference(
          tenantId: tenantId,
          nameAr: nameAr,
          nameEn: nameEn,
          atcCode: _emptyToNull(cols[2]),
          indications: _pipeList(cols[3]),
          indicationsFreeText: _emptyToNull(cols[4]),
          ageBand: _normalizeAgeBand(cols[5]),
          interactionsPlaceholder: _pipeList(cols[6]),
        );
        imported++;
      } catch (e) {
        errors.add('row_${i + 1}: $e');
        skipped++;
      }
    }

    return PharmacyDrugReferenceCsvImportResult(
      importedCount: imported,
      skippedCount: skipped,
      errors: errors,
    );
  }

  bool _headersMatch(List<String> header) {
    if (header.length < expectedHeaders.length) return false;
    for (var i = 0; i < expectedHeaders.length; i++) {
      if (header[i].trim().toLowerCase() != expectedHeaders[i]) {
        return false;
      }
    }
    return true;
  }

  List<String> _splitCsvLine(String line) {
    return line.split(',').map((s) => s.trim()).toList();
  }

  List<String> _pipeList(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return const [];
    return t.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  String? _emptyToNull(String raw) {
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  String _normalizeAgeBand(String raw) {
    final v = raw.trim().toLowerCase();
    if (PharmacyAgeBand.all.contains(v)) return v;
    return PharmacyAgeBand.both;
  }
}
