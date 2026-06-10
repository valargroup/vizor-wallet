/// User-facing copy for the migration showcase. Sentence case per AGENTS.md.
abstract final class MigrationCopy {
  static const tabLabel = 'Migration';

  // Idle / landing
  static const idleTitle = 'Migration';
  static const idleBody =
      'Prepare Orchard funds as standard note amounts, then migrate those '
      'notes to Ironwood over a short submission window.';
  static const fromPoolName = 'Orchard';
  static const fromPoolTag = 'Current pool';
  static const toPoolName = 'Ironwood';
  static const toPoolTag = 'New pool';
  static const readyToMigrateLabel = 'Ready to prepare';
  static const poolFlow = 'Orchard pool → Ironwood pool';
  static const bullet1 =
      'Vizor first creates standard Orchard denomination notes.';
  static const bullet2 =
      'Once those notes confirm, Vizor migrates them to Ironwood.';
  static const bullet3 =
      'Signed migration transactions are submitted over about one minute.';
  static const startCta = 'Start preparation';

  // Two-step layout
  static const stepOneTitle = 'Prepare denominations';
  static const stepOneBody =
      'Split your Orchard funds into standard note amounts in a single '
      'transaction.';
  static const stepOneCta = 'Prepare denominations';
  static const stepOneRunning =
      'Creating and submitting the denomination transaction...';
  static const stepOneWaiting =
      'Denomination transaction submitted. The prepared notes need to '
      'confirm before migration can start.';
  static String stepOneDone(int count) => '$count prepared notes ready.';
  static const stepOneDoneGeneric = 'Prepared notes ready.';
  static String stepOnePreparedCounts(int prepared, int total) =>
      'Prepared notes: $prepared of $total';
  static const stepOneNoFunds = 'No Orchard funds to prepare.';
  static const stepOneUnspendable =
      'Waiting for Orchard funds to become spendable. Keep Vizor syncing.';
  static const stepTwoTitle = 'Migrate to Ironwood';
  static const stepTwoLocked = 'Available once the prepared notes confirm.';
  static String stepTwoReady(int count, String window) =>
      'Vizor signs $count migration transactions and submits them over '
      '$window.';
  static const stepTwoCta = 'Start migration';
  static const stepTwoSigning = 'Signing migration transactions...';
  static String stepTwoSubmitting(int index, int total) =>
      'Submitting migration transaction $index of $total...';
  static const stepTwoPausedNote =
      'Migration paused. Start migration to resume this run.';
  static const stepTwoKeepOpen =
      'Keep Vizor open while the migration transactions are created and '
      'broadcast.';
  static const partialBroadcastError =
      'Migration transactions were created locally but not fully broadcast. '
      'Keep Vizor open and do not start another migration.';

  static String migrationWindowText(int seconds) {
    if (seconds == 60) return 'about one minute';
    if (seconds < 90) return 'about $seconds seconds';
    return 'about ${(seconds / 60).round()} minutes';
  }

  // Hardware-account state
  static const softwareRequiredTitle = 'Migration';
  static const softwareRequiredBody =
      'Migration is available for software accounts in this build. Switch to '
      'a software account to test it. Keystone migration stays disabled until '
      'Ironwood PCZT support is proven.';

  // Status
  static const checkingTitle = 'Checking migration';
  static const checkingBody = 'Checking the current Orchard migration state.';
  static const noOrchardFundsTitle = 'No Orchard funds to migrate';
  static const noOrchardFundsBody =
      'This account has no Orchard funds that need migration.';
  static const waitingForSpendableTitle = 'Waiting for Orchard funds';
  static const waitingForSpendableBody =
      'Orchard funds are present but not spendable yet. Sync until they confirm.';
  static const preparingDenominationsTitle = 'Preparing denominations';
  static const preparingDenominationsBody =
      'Vizor is creating standard Orchard note amounts for this migration run.';
  static const waitingDenomTitle = 'Waiting for denomination confirmations';
  static const waitingDenomBody =
      'The denomination transaction was submitted. Sync until the prepared '
      'Orchard notes are spendable.';
  static const readyPreparedTitle = 'Prepared notes are ready';
  static const readyPreparedBody =
      'Vizor can now sign and submit the prepared migration transactions over '
      'the broadcast window.';
  static const readyPreparedCta = 'Resume migration';
  static const buildingBatchTitle = 'Building signing batch';
  static const buildingBatchBody =
      'Vizor is building the migration signing batch for the prepared notes.';
  static const signingBatchTitle = 'Signing migration batch';
  static const signingBatchBody =
      'Vizor is signing the prepared migration transactions.';
  static const broadcastScheduledTitle = 'Broadcast scheduled';
  static const broadcastScheduledBody =
      'Signed migration transactions are scheduled across the broadcast window.';
  static const broadcastingStatusTitle = 'Broadcasting migration';
  static const broadcastingStatusBody =
      'Vizor is submitting scheduled migration transactions.';
  static const pausedTitle = 'Migration paused';
  static const pausedBody =
      'This migration run is paused and can be resumed from this account.';
  static const retryCta = 'Retry migration';
  static const failedRecoverableTitle = 'Migration needs attention';
  static const failedRecoverableBody =
      'This migration run can be retried after the wallet is synced.';
  static const failedTerminalTitle = 'Migration stopped';
  static const failedTerminalBody =
      'This migration run cannot continue automatically.';
  static const abandonedTitle = 'Migration abandoned';
  static const abandonedBody =
      'This migration run was abandoned. Future starts will reconcile wallet '
      'state from scratch.';

  // Broadcast
  static const signTitle = 'Starting migration';
  static const signSubtitle = 'Creating Ironwood transactions';
  static const signInstruction =
      'Keep Vizor open while the migration transactions are created and broadcast.';
  static const signCancel = 'Cancel';
  static const broadcastingTitle = 'Broadcasting migration';
  static const broadcastingSubtitle = 'Sending your transactions';
  static const broadcastingInstruction =
      'Keep Vizor open while your migration transactions are sent over about one minute.';
  static const signBack = 'Back';

  // Scan
  static const scanTitle = 'Scan the signed migration';
  static const scanBody =
      'Point your camera at the signed result QR on your Keystone.';
  static const scanDecodingLabel = 'Reading signed migration...';
  static const scanUnavailable =
      'Scanning the signed migration uses camera QR scanning only. Connect a '
      'camera and try again.';

  // Completion popup
  static const completeTitle = 'Migration started';
  static const completeBody =
      'Your migration transactions were created and sent to the selected '
      'testnet endpoint.';
  static const completeButton = 'Got it';

  // In progress
  static const inProgressTitle = 'Migration in progress';
  static const inProgressBody =
      'Prepared notes are being submitted and confirmed on Ironwood.';
  static String migratingAmount(String amount) => 'Migrating $amount';
  static String transferLabel(int index, int total) =>
      'Transfer $index of $total';
  static const keepOpenWarning =
      'Keep Vizor connected to the Ironwood testnet while these transactions confirm.';

  // Done
  static const doneTitle = 'Migration complete';
  static const doneBody = 'Your migration transactions have finished.';

  // Errors
  static const genericError =
      'Migration could not be started. Please try again.';
}
