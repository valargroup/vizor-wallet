import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register background task
    BackgroundSyncManager.shared.registerBackgroundTask()

    // Set up MethodChannel for background sync
    if let controller = window?.rootViewController as? FlutterViewController {
      setupMethodChannel(controller: controller)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Retry MethodChannel setup if not done in didFinishLaunching
    if let controller = window?.rootViewController as? FlutterViewController {
      setupMethodChannel(controller: controller)
    }
  }

  private var channelConfigured = false

  private func setupMethodChannel(controller: FlutterViewController) {
    guard !channelConfigured else { return }
    channelConfigured = true

    let channel = FlutterMethodChannel(
      name: "com.zcash.wallet/background_sync",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "isAvailable":
        result(BackgroundSyncManager.shared.isAvailable())
      case "startBackgroundSync":
        let success = BackgroundSyncManager.shared.startBackgroundSync()
        result(success)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
