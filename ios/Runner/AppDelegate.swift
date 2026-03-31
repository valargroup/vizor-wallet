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

    // Register MethodChannel via plugin registry (works with UISceneDelegate)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundSyncPlugin")
    let channel = FlutterMethodChannel(
      name: "com.zcash.wallet/background_sync",
      binaryMessenger: registrar.messenger()
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
