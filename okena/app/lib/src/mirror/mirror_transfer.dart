import 'package:okena_core/okena_core.dart';

/// App boundary for scheduling and cancelling background mirror transfers.
abstract class MirrorTransfer {
  /// Ensures a task exists for [entry], or reattaches to its existing task.
  ///
  /// Implementations must be idempotent for `entry.backgroundTaskId`: calling
  /// this more than once must not enqueue duplicate native work. Native
  /// completion is delivered separately to [MirrorEngine]. Adapters must use
  /// [MirrorTransferRejected] only when they know no task was scheduled, and
  /// [MirrorTransferUncertain] whenever scheduling may have happened.
  Future<TainaResult<void>> ensureStarted({
    required MirrorEntry entry,
    required String folderRkey,
  });

  /// Cancels an existing task. Cancellation must be idempotent because a
  /// persisted cancellation intent can be retried after restart.
  Future<TainaResult<void>> cancel(String backgroundTaskId);
}
