import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    BackgroundSyncManager.shared.registerBackgroundTask()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Set up MethodChannel via applicationRegistrar (UISceneDelegate compatible)
    let channel = FlutterMethodChannel(
      name: "com.zcash.wallet/background_sync",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
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
