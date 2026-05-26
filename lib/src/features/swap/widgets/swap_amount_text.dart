const swapDisplayMaxFractionDigits = 6;
const _swapReviewSummaryMaxChars = 13;

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

bool isLongSwapSummaryAmountText(String value) {
  return compactSwapAmountText(value).length > _swapReviewSummaryMaxChars;
}

String compactSwapSummaryAmountText(
  String value, {
  bool forceCompactThousands = false,
}) {
  final base = compactSwapAmountText(value);
  final match = RegExp(
    r'^([<>+\-]?)([\d,]+(?:\.\d+)?)(\s+.+)$',
  ).firstMatch(base.trim());
  if (match == null) return base;

  final amount = double.tryParse(match[2]!.replaceAll(',', ''));
  if (amount == null || !amount.isFinite) return base;

  final prefix = match[1] ?? '';
  final suffix = match[3]!;
  if (amount >= 1000000) {
    return '$prefix${_truncatedCompactNumber(amount / 1000000)}M$suffix';
  }
  if (forceCompactThousands && amount >= 1000) {
    return '$prefix${_truncatedCompactNumber(amount / 1000)}K$suffix';
  }
  return base;
}

String _truncatedCompactNumber(double value) {
  const fractionDigits = 3;
  const factor = 1000.0;
  final truncated = (value * factor).truncateToDouble() / factor;
  var text = truncated.toStringAsFixed(fractionDigits);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}
