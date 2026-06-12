import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/migration_copy.dart';

void main() {
  test('migration window text reads naturally at common windows', () {
    expect(MigrationCopy.migrationWindowText(60), 'about one minute');
    expect(MigrationCopy.migrationWindowText(45), 'about 45 seconds');
    expect(MigrationCopy.migrationWindowText(180), 'about 3 minutes');
  });

  test('key copy is sentence case', () {
    expect(MigrationCopy.migrateCta, 'Migrate');
    expect(MigrationCopy.warningTitle, 'Keep Vizor open during migration');
    expect(MigrationCopy.warningStartCta, 'Start migration');
    expect(MigrationCopy.splitTitle, 'Split funds');
    expect(MigrationCopy.sendTitle, 'Send shares');
    expect(MigrationCopy.shareLabel(1), 'Share 1');
  });

  test('warning body interpolates the window', () {
    expect(
      MigrationCopy.warningBody('about 3 minutes'),
      contains('about 3 minutes'),
    );
  });
}
