import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/migration_copy.dart';

void main() {
  test('migration window text reads naturally at common windows', () {
    expect(MigrationCopy.migrationWindowText(60), 'about one minute');
    expect(MigrationCopy.migrationWindowText(45), 'about 45 seconds');
    expect(MigrationCopy.migrationWindowText(180), 'about 3 minutes');
  });
}
