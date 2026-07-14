/// وضع محرّر عائلة السوائل: زيت أو هيدروليك.
enum FluidFamilyEditorMode {
  oil,
  hydraulic,
}

extension FluidFamilyEditorModeLabels on FluidFamilyEditorMode {
  bool get isOil => this == FluidFamilyEditorMode.oil;

  String get familyNoun => isOil ? 'الزيت' : 'الهيدروليك';

  String get gradeNoun => isOil ? 'لزوجة' : 'درجة';

  String get gradesTitle => isOil
      ? 'لزوجات الزيت (كل لزوجة مخزون وسعر وعبوات خاصة)'
      : 'درجات الهيدروليك (كل درجة مخزون وسعر وعبوات خاصة)';

  String get addGradeLabel => isOil ? 'لزوجة' : 'درجة';

  String get emptyHint => isOil
      ? 'أضف لزوجة واحدة على الأقل (مثال: 10W40).'
      : 'أضف درجة واحدة على الأقل (مثال: ISO VG 46).';

  String get gradeCardTitlePrefix => isOil ? 'لزوجة' : 'درجة';

  String get deleteGradeTooltip => isOil ? 'حذف اللزوجة' : 'حذف الدرجة';

  String get gradeFieldLabel =>
      isOil ? 'اللزوجة (Viscosity)' : 'الدرجة (نوع الهيدروليك)';

  String get gradeFieldHint => isOil ? 'مثال: 10W40' : 'مثال: ISO VG 46';

  String get packsForGradeTitle =>
      isOil ? 'عبوات البيع لهذه اللزوجة' : 'عبوات البيع لهذه الدرجة';

  String get familyNameExample =>
      isOil ? 'موبيل 1' : 'كاسترول هيدروليك';
}
