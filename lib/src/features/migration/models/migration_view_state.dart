import 'migration_demo_state.dart';

/// Which of the Migration tab's four resting states to render.
enum MigrationViewState { softwareRequired, idle, inProgress, complete }

/// Pure selector for the tab state. Kept out of the widget so it is trivially
/// testable without stubbing the account/sync provider stack.
MigrationViewState migrationViewState({
  required bool isHardware,
  required MigrationDemoState? demo,
  required DateTime now,
}) {
  if (isHardware) return MigrationViewState.softwareRequired;
  if (demo == null) return MigrationViewState.idle;
  if (demo.isComplete(now)) return MigrationViewState.complete;
  return MigrationViewState.inProgress;
}
