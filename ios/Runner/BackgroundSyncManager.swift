import Foundation
import BackgroundTasks

/// Manages iOS background sync via BGContinuedProcessingTask (iOS 26+).
/// On older iOS versions, this class is available but methods are no-ops.
class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()
    static let taskIdentifier = "com.zcash.zcashWallet.sync"

    private init() {}

    /// Register the background task with the system.
    /// Call this in AppDelegate.didFinishLaunchingWithOptions.
    func registerBackgroundTask() {
        if #available(iOS 17.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Self.taskIdentifier,
                using: nil
            ) { task in
                // This handler is called when the system grants background time
                // The actual sync runs in the Dart isolate, not here
                // We just need to keep the task alive while Dart syncs
                task.expirationHandler = {
                    task.setTaskCompleted(success: false)
                }
            }
        }
    }

    /// Submit a background processing task request.
    /// On iOS 26+, this uses BGContinuedProcessingTask.
    /// On older versions, this is a no-op.
    func startBackgroundSync() -> Bool {
        // BGContinuedProcessingTask is iOS 26+
        // For now, use BGProcessingTaskRequest as a baseline (iOS 13+)
        if #available(iOS 13.0, *) {
            let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false

            do {
                try BGTaskScheduler.shared.submit(request)
                return true
            } catch {
                print("BackgroundSync: Failed to submit task: \(error)")
                return false
            }
        }
        return false
    }

    /// Check if background sync is available on this iOS version.
    func isAvailable() -> Bool {
        if #available(iOS 26.0, *) {
            return true  // BGContinuedProcessingTask
        }
        return false
    }
}
