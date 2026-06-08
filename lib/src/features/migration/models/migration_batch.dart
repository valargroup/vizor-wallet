/// User-facing error for the migration flow. Its [message] is safe to show
/// directly.
class MigrationBatchError implements Exception {
  MigrationBatchError(this.message);
  final String message;
  @override
  String toString() => message;
}
