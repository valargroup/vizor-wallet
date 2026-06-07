/// User-facing copy for the migration showcase. Sentence case per AGENTS.md.
abstract final class MigrationCopy {
  static const tabLabel = 'Migration';

  // Idle / landing
  static const idleTitle = 'Migration';
  static const idleBody =
      "Move your shielded ZEC to Ironwood, Zcash's next-generation shielded "
      'pool. Your Keystone approves the whole migration in one signature.';
  static const fromPoolName = 'Orchard';
  static const fromPoolTag = 'Current pool';
  static const toPoolName = 'Ironwood';
  static const toPoolTag = 'New pool';
  static const readyToMigrateLabel = 'Ready to migrate';
  static const poolFlow = 'Orchard pool → Ironwood pool';
  static const bullet1 = 'Funds move in small batches over random intervals.';
  static const bullet2 = 'Migration can take up to 24 hours to finish.';
  static const bullet3 = 'Keep Vizor open until it completes.';
  static const startCta = 'Start migration';

  // Software-account (no Keystone) state
  static const keystoneRequiredTitle = 'Migration';
  static const keystoneRequiredBody =
      'Migration is available for Keystone accounts. Switch to or add a '
      'Keystone account to try it.';

  // Signing
  static const signTitle = 'Approve your migration';
  static const signSubtitle = 'Scan this code with your Keystone';
  static const signInstruction =
      'Your Keystone signs all 3 transfers in one step. Approve on the device, '
      'then scan the result.';
  static const signPrimary = 'Scan signed result';
  static const signCancel = 'Cancel';
  static const broadcastingTitle = 'Broadcasting migration';
  static const broadcastingSubtitle = 'Sending your transfers';
  static const broadcastingInstruction =
      'Keep Vizor open while your transfers are sent.';
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
      'Your funds are on their way to the Ironwood pool. Transfers go out in '
      'small batches over random intervals across the next 24 hours.\n\n'
      'Keep Vizor open so the migration can finish.';
  static const completeButton = 'Got it';

  // In progress
  static const inProgressTitle = 'Migration in progress';
  static const inProgressBody =
      'Your funds are moving from Orchard to Ironwood. This finishes on its '
      'own — just keep Vizor open.';
  static String migratingAmount(String amount) => 'Migrating $amount';
  static String transferLabel(int index) => 'Transfer $index of 3';
  static const transferSent = 'Sent';
  static const keepOpenWarning =
      'Keep Vizor open. Closing the app pauses the remaining transfers until '
      'you reopen it.';
  static const resetCta = 'Reset demo';

  // Done
  static const doneTitle = 'Migration complete';
  static const doneBody =
      'Your funds have finished moving to the Ironwood pool.';
  static const doneButton = 'Done';

  // Errors
  static const genericError =
      'Migration could not be started. Please try again.';
}
