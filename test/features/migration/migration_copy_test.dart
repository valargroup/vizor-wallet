import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/migration_copy.dart';

void main() {
  test('migrationWindowText formats seconds and minutes', () {
    expect(MigrationCopy.migrationWindowText(60), 'about one minute');
    expect(MigrationCopy.migrationWindowText(45), 'about 45 seconds');
    expect(MigrationCopy.migrationWindowText(89), 'about 89 seconds');
    expect(MigrationCopy.migrationWindowText(120), 'about 2 minutes');
    expect(MigrationCopy.migrationWindowText(150), 'about 3 minutes');
  });

  test('step copy formatters interpolate counts', () {
    expect(MigrationCopy.stepOneDone(8), '8 prepared notes ready.');
    expect(
      MigrationCopy.stepOnePreparedCounts(3, 8),
      'Prepared notes: 3 of 8',
    );
    expect(
      MigrationCopy.stepTwoReady(8, 'about one minute'),
      'Vizor signs 8 migration transactions and submits them over '
      'about one minute.',
    );
    expect(
      MigrationCopy.stepTwoSubmitting(3, 8),
      'Submitting migration transaction 3 of 8...',
    );
  });
}
