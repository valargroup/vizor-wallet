import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show Uint64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_step_state.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_view_state.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

rust_sync.MigrationStatus _status({
  String phase = 'ready_to_migrate',
  int pendingTxCount = 0,
  int broadcastedTxCount = 0,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    targetValuesZatoshi: Uint64List(0),
    preparedNoteCount: 0,
    pendingTxCount: pendingTxCount,
    broadcastedTxCount: broadcastedTxCount,
    confirmedTxCount: 0,
    totalCount: 0,
    canAbandon: false,
    signingBatchLimit: 8,
    broadcastWindowSeconds: BigInt.from(60),
    maxPreparedNotesPerRun: 64,
  );
}

MigrationStepsModel _map(
  MigrationViewState viewState, {
  rust_sync.MigrationStatus? status,
  bool runInFlight = false,
  MigrationRunIntent intent = MigrationRunIntent.none,
}) {
  return migrationStepsModel(
    viewState: viewState,
    status: status,
    runInFlight: runInFlight,
    intent: intent,
  );
}

void main() {
  test('in-flight intent wins over provider-derived state', () {
    final preparing = _map(
      MigrationViewState.planningDenominations,
      runInFlight: true,
      intent: MigrationRunIntent.preparing,
    );
    expect(preparing.stepOne, MigrationStepOneState.running);
    expect(preparing.stepTwo, MigrationStepTwoState.locked);

    final migrating = _map(
      MigrationViewState.readyToMigrate,
      runInFlight: true,
      intent: MigrationRunIntent.migrating,
    );
    expect(migrating.stepOne, MigrationStepOneState.done);
    expect(migrating.stepTwo, MigrationStepTwoState.running);
  });

  test('balance-derived phases map to step one states', () {
    expect(
      _map(MigrationViewState.noOrchardFunds).stepOne,
      MigrationStepOneState.blocked,
    );
    expect(
      _map(MigrationViewState.waitingForSpendableOrchard).stepOne,
      MigrationStepOneState.blocked,
    );
    expect(
      _map(MigrationViewState.planningDenominations).stepOne,
      MigrationStepOneState.active,
    );
    expect(
      _map(MigrationViewState.preparingDenominations).stepOne,
      MigrationStepOneState.running,
    );
    expect(
      _map(MigrationViewState.waitingDenomConfirmations).stepOne,
      MigrationStepOneState.waiting,
    );
    expect(
      _map(MigrationViewState.planningDenominations).stepTwo,
      MigrationStepTwoState.locked,
    );
  });

  test('run phases map to step two states with step one done', () {
    final ready = _map(MigrationViewState.readyToMigrate);
    expect(ready.stepOne, MigrationStepOneState.done);
    expect(ready.stepTwo, MigrationStepTwoState.ready);

    expect(
      _map(MigrationViewState.paused).stepTwo,
      MigrationStepTwoState.ready,
    );

    for (final running in [
      MigrationViewState.buildingSigningBatch,
      MigrationViewState.signingBatch,
      MigrationViewState.broadcastScheduled,
      MigrationViewState.broadcasting,
    ]) {
      expect(_map(running).stepOne, MigrationStepOneState.done);
      expect(_map(running).stepTwo, MigrationStepTwoState.running);
    }

    expect(
      _map(MigrationViewState.waitingMigrationConfirmations).stepTwo,
      MigrationStepTwoState.confirming,
    );
    expect(
      _map(MigrationViewState.complete).stepTwo,
      MigrationStepTwoState.done,
    );
  });

  test('failedRecoverable routes to the step that actually failed', () {
    final beforeMigrationTxs = _map(
      MigrationViewState.failedRecoverable,
      status: _status(phase: 'failed_recoverable'),
    );
    expect(beforeMigrationTxs.stepOne, MigrationStepOneState.error);
    expect(beforeMigrationTxs.stepTwo, MigrationStepTwoState.locked);

    final withPending = _map(
      MigrationViewState.failedRecoverable,
      status: _status(phase: 'failed_recoverable', pendingTxCount: 3),
    );
    expect(withPending.stepOne, MigrationStepOneState.done);
    expect(withPending.stepTwo, MigrationStepTwoState.error);

    final withBroadcasted = _map(
      MigrationViewState.failedRecoverable,
      status: _status(phase: 'failed_recoverable', broadcastedTxCount: 1),
    );
    expect(withBroadcasted.stepTwo, MigrationStepTwoState.error);
  });

  test('terminal phases are step two errors', () {
    expect(
      _map(MigrationViewState.failedTerminal).stepTwo,
      MigrationStepTwoState.error,
    );
    expect(
      _map(MigrationViewState.abandoned).stepTwo,
      MigrationStepTwoState.error,
    );
  });
}
