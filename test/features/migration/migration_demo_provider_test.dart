import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/features/migration/providers/migration_demo_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('provider yields null when there is no active account', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final value = await container.read(migrationDemoProvider.future);
    expect(value, isNull);
  });
}
