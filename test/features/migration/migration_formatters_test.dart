import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/migration_formatters.dart';

void main() {
  test('formatRemaining', () {
    expect(formatRemaining(const Duration(hours: 16)),
        'About 16 hours remaining');
    expect(formatRemaining(const Duration(hours: 1)), 'About 1 hour remaining');
    expect(formatRemaining(const Duration(minutes: 40)),
        'About 40 minutes remaining');
    expect(formatRemaining(Duration.zero), 'Wrapping up');
  });

  test('formatStartedAgo', () {
    expect(formatStartedAgo(const Duration(hours: 8)), 'started 8h ago');
    expect(formatStartedAgo(const Duration(minutes: 5)), 'started 5m ago');
    expect(formatStartedAgo(const Duration(seconds: 10)), 'started just now');
  });

  test('formatTransferEta', () {
    expect(formatTransferEta(const Duration(hours: 4)), '~4h');
    expect(formatTransferEta(const Duration(minutes: 30)), '~30m');
    expect(formatTransferEta(Duration.zero), 'Soon');
  });
}
