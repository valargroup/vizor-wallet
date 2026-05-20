const swapDisplayMaxFractionDigits = 6;

String compactSwapAmountText(
  String value, {
  int maxFractionDigits = swapDisplayMaxFractionDigits,
}) {
  if (maxFractionDigits < 0) {
    throw ArgumentError.value(
      maxFractionDigits,
      'maxFractionDigits',
      'must not be negative',
    );
  }
  final withoutApproximationPrefix = value.replaceAllMapped(
    RegExp(r'~(?=\d)'),
    (_) => '',
  );
  if (maxFractionDigits == 0) {
    return withoutApproximationPrefix.replaceAllMapped(
      RegExp(r'([<>+\-]?)(\d+)\.(\d+)'),
      (match) => '${match[1]}${match[2]}',
    );
  }
  final expression = RegExp(
    '([<>+\\-]?)(\\d+)\\.(\\d{$maxFractionDigits})(\\d+)',
  );
  return withoutApproximationPrefix.replaceAllMapped(
    expression,
    (match) => '${match[1]}${match[2]}.${match[3]}',
  );
}
