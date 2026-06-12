import '../../../rust/api/sync.dart' as rust_sync;
import 'migration_view_state.dart';

/// Which run action the controller is currently (or was last) executing.
/// Relocated from the deleted `migration_step_state.dart`; still used by the
/// run controller and the Keystone signing flow.
enum MigrationRunIntent { none, preparing, migrating }

/// The three user-facing stages of a migration, in order.
enum MigrationNodeId { split, confirm, send }

/// Visual state of a single timeline node.
enum MigrationNodeStatus { pending, active, done, error }

/// Pure, widget-free description of the three timeline nodes for the current
/// migration phase. Mirrors the old `migrationStepsModel` so it is trivially
/// testable without the account/sync provider stack.
class MigrationTimelineModel {
  const MigrationTimelineModel({
    required this.split,
    required this.confirm,
    required this.send,
    this.sendNeedsScan = false,
    this.sendCanResume = false,
  });

  final MigrationNodeStatus split;
  final MigrationNodeStatus confirm;
  final MigrationNodeStatus send;

  /// True only for the oversized Keystone staged fallback: the Send stage is
  /// blocked on a manual "Scan to sign the sends" action rather than running
  /// automatically.
  final bool sendNeedsScan;
  final bool sendCanResume;

  MigrationNodeStatus statusFor(MigrationNodeId id) => switch (id) {
    MigrationNodeId.split => split,
    MigrationNodeId.confirm => confirm,
    MigrationNodeId.send => send,
  };
}

MigrationTimelineModel migrationTimelineModel({
  required MigrationViewState viewState,
  required rust_sync.MigrationStatus? status,
  required bool runInFlight,
  required MigrationRunIntent intent,
  bool sendNeedsScan = false,
}) {
  // A run call in flight wins over (lagging) provider state.
  if (runInFlight && intent == MigrationRunIntent.preparing) {
    return const MigrationTimelineModel(
      split: MigrationNodeStatus.active,
      confirm: MigrationNodeStatus.pending,
      send: MigrationNodeStatus.pending,
    );
  }
  if (runInFlight && intent == MigrationRunIntent.migrating) {
    return MigrationTimelineModel(
      split: MigrationNodeStatus.done,
      confirm: MigrationNodeStatus.done,
      send: MigrationNodeStatus.active,
      sendNeedsScan: sendNeedsScan,
    );
  }

  final hasMigrationTxs =
      (status?.pendingTxCount ?? 0) > 0 ||
      (status?.broadcastedTxCount ?? 0) > 0;

  return switch (viewState) {
    MigrationViewState.noOrchardFunds ||
    MigrationViewState.waitingForSpendableOrchard ||
    MigrationViewState.planningDenominations => const MigrationTimelineModel(
      split: MigrationNodeStatus.pending,
      confirm: MigrationNodeStatus.pending,
      send: MigrationNodeStatus.pending,
    ),
    MigrationViewState.preparingDenominations => const MigrationTimelineModel(
      split: MigrationNodeStatus.active,
      confirm: MigrationNodeStatus.pending,
      send: MigrationNodeStatus.pending,
    ),
    MigrationViewState.waitingDenomConfirmations =>
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.active,
        send: MigrationNodeStatus.pending,
      ),
    MigrationViewState.readyToMigrate ||
    MigrationViewState.buildingSigningBatch ||
    MigrationViewState.signingBatch ||
    MigrationViewState.broadcastScheduled ||
    MigrationViewState.broadcasting ||
    MigrationViewState.waitingMigrationConfirmations => MigrationTimelineModel(
      split: MigrationNodeStatus.done,
      confirm: MigrationNodeStatus.done,
      send: MigrationNodeStatus.active,
      sendNeedsScan: sendNeedsScan,
    ),
    MigrationViewState.paused => MigrationTimelineModel(
      split: MigrationNodeStatus.done,
      confirm: MigrationNodeStatus.done,
      send: MigrationNodeStatus.active,
      sendCanResume: true,
    ),
    MigrationViewState.complete => const MigrationTimelineModel(
      split: MigrationNodeStatus.done,
      confirm: MigrationNodeStatus.done,
      send: MigrationNodeStatus.done,
    ),
    MigrationViewState.failedRecoverable =>
      hasMigrationTxs
          ? const MigrationTimelineModel(
              split: MigrationNodeStatus.done,
              confirm: MigrationNodeStatus.done,
              send: MigrationNodeStatus.error,
            )
          : const MigrationTimelineModel(
              split: MigrationNodeStatus.error,
              confirm: MigrationNodeStatus.pending,
              send: MigrationNodeStatus.pending,
            ),
    MigrationViewState.failedTerminal ||
    MigrationViewState.abandoned => const MigrationTimelineModel(
      split: MigrationNodeStatus.done,
      confirm: MigrationNodeStatus.done,
      send: MigrationNodeStatus.error,
    ),
  };
}
