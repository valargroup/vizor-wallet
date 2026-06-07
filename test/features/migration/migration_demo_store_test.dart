import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_demo_state.dart';
import 'package:zcash_wallet/src/features/migration/services/migration_demo_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MigrationDemoStore store;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    final secure = AppSecureStore.instance;
    await secure.deleteAll();
    store = MigrationDemoStore(store: secure);
  });

  tearDown(() async {
    await AppSecureStore.instance.deleteAll();
  });

  MigrationDemoState sample(String acc) => MigrationDemoState(
        accountUuid: acc,
        startedAtEpochMs: 1,
        totalDurationMs: 10,
        displayAmountZatoshi: BigInt.from(99),
        transferOffsetsMs: const [0, 4, 7],
        txids: const ['a'],
      );

  test('read returns null before any write', () async {
    expect(await store.read('acc-1'), isNull);
  });

  test('write then read round-trips, scoped per account', () async {
    await store.write(sample('acc-1'));
    final got = await store.read('acc-1');
    expect(got, isNotNull);
    expect(got!.displayAmountZatoshi, BigInt.from(99));
    expect(await store.read('acc-2'), isNull);
  });

  test('clear removes the account entry', () async {
    await store.write(sample('acc-1'));
    await store.clear('acc-1');
    expect(await store.read('acc-1'), isNull);
  });
}
