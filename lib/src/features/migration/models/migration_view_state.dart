/// Which migration phase the tab should render.
enum MigrationViewState {
  noOrchardFunds,
  waitingForSpendableOrchard,
  planningDenominations,
  preparingDenominations,
  waitingDenomConfirmations,
  readyToMigrate,
  buildingSigningBatch,
  signingBatch,
  broadcastScheduled,
  broadcasting,
  waitingMigrationConfirmations,
  complete,
  paused,
  failedRecoverable,
  failedTerminal,
  abandoned,
}

extension MigrationViewStateX on MigrationViewState {
  bool get hasActiveRun => switch (this) {
    MigrationViewState.preparingDenominations ||
    MigrationViewState.waitingDenomConfirmations ||
    MigrationViewState.readyToMigrate ||
    MigrationViewState.buildingSigningBatch ||
    MigrationViewState.signingBatch ||
    MigrationViewState.broadcastScheduled ||
    MigrationViewState.broadcasting ||
    MigrationViewState.waitingMigrationConfirmations ||
    MigrationViewState.paused ||
    MigrationViewState.failedRecoverable => true,
    _ => false,
  };

  bool get shouldPollProgress => switch (this) {
    MigrationViewState.waitingDenomConfirmations ||
    MigrationViewState.broadcastScheduled ||
    MigrationViewState.broadcasting ||
    MigrationViewState.waitingMigrationConfirmations => true,
    _ => false,
  };
}

final _txidHexPattern = RegExp(r'^[0-9a-f]{64}$');

/// Pure selector for the tab state. Kept out of the widget so it is trivially
/// testable without stubbing the account/sync provider stack.
MigrationViewState migrationViewState({
  String? rustPhase,
  required bool hasPendingMigration,
  required bool hasCompletedMigration,
  required BigInt orchardBalance,
  required BigInt ironwoodBalance,
}) {
  final phaseState = migrationViewStateFromRustPhase(rustPhase);
  if (phaseState != null) return phaseState;
  if (hasPendingMigration) {
    return MigrationViewState.waitingMigrationConfirmations;
  }
  if (orchardBalance > BigInt.zero) {
    return MigrationViewState.planningDenominations;
  }
  if (hasCompletedMigration || ironwoodBalance > BigInt.zero) {
    return MigrationViewState.complete;
  }
  return MigrationViewState.noOrchardFunds;
}

MigrationViewState? migrationViewStateFromRustPhase(String? phase) {
  return switch (phase) {
    'no_orchard_funds' => MigrationViewState.noOrchardFunds,
    'waiting_for_spendable_orchard' =>
      MigrationViewState.waitingForSpendableOrchard,
    'ready_to_prepare' => MigrationViewState.planningDenominations,
    'planning_denominations' => MigrationViewState.planningDenominations,
    'preparing_denominations' => MigrationViewState.preparingDenominations,
    'waiting_denom_confirmations' =>
      MigrationViewState.waitingDenomConfirmations,
    'ready_to_migrate' => MigrationViewState.readyToMigrate,
    'building_signing_batch' => MigrationViewState.buildingSigningBatch,
    'signing_batch' => MigrationViewState.signingBatch,
    'broadcast_scheduled' => MigrationViewState.broadcastScheduled,
    'broadcasting' => MigrationViewState.broadcasting,
    'waiting_migration_confirmations' =>
      MigrationViewState.waitingMigrationConfirmations,
    'complete' => MigrationViewState.complete,
    'paused' => MigrationViewState.paused,
    'failed_recoverable' => MigrationViewState.failedRecoverable,
    'failed_terminal' => MigrationViewState.failedTerminal,
    'abandoned' => MigrationViewState.abandoned,
    _ => null,
  };
}

int migrationFirstTransactionIndex({
  required Iterable<String> transactionTxids,
  required String firstTxid,
}) {
  var index = 0;
  for (final txid in transactionTxids) {
    if (migrationTxidsMatch(txid, firstTxid)) return index;
    index += 1;
  }
  return -1;
}

bool migrationTxidsMatch(String left, String right) {
  final normalizedLeft = _normalizeTxid(left);
  final normalizedRight = _normalizeTxid(right);
  if (normalizedLeft == null || normalizedRight == null) return false;
  if (normalizedLeft == normalizedRight) return true;
  return _reverseTxidByteOrder(normalizedLeft) == normalizedRight;
}

String? _normalizeTxid(String txid) {
  final normalized = txid.trim().toLowerCase();
  if (!_txidHexPattern.hasMatch(normalized)) return null;
  return normalized;
}

String _reverseTxidByteOrder(String txid) {
  final reversed = StringBuffer();
  for (var i = txid.length; i > 0; i -= 2) {
    reversed.write(txid.substring(i - 2, i));
  }
  return reversed.toString();
}
