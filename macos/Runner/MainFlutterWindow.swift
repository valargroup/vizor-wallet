import Cocoa
import FlutterMacOS
import desktop_window_bootstrap

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let desktopWindowViewController = DesktopWindowBootstrapMacOS.start(
      mainFlutterWindow: self
    )
    RegisterGeneratedPlugins(registry: desktopWindowViewController.flutterViewController)

    super.awakeFromNib()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
