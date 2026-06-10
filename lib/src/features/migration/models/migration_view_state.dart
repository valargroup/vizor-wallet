/// Which of the Migration tab's four resting states to render.
enum MigrationViewState { softwareRequired, idle, inProgress, complete }

final _txidHexPattern = RegExp(r'^[0-9a-f]{64}$');

/// Pure selector for the tab state. Kept out of the widget so it is trivially
/// testable without stubbing the account/sync provider stack.
MigrationViewState migrationViewState({
  required bool isHardware,
  required bool hasPendingMigration,
  required bool hasCompletedMigration,
  required BigInt orchardBalance,
  required BigInt ironwoodBalance,
}) {
  if (isHardware) return MigrationViewState.softwareRequired;
  if (hasPendingMigration) return MigrationViewState.inProgress;
  if (orchardBalance > BigInt.zero) return MigrationViewState.idle;
  if (hasCompletedMigration || ironwoodBalance > BigInt.zero) {
    return MigrationViewState.complete;
  }
  return MigrationViewState.idle;
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
