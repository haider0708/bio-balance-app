import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Offline business data remains on this installation, including pending work.
    // Do not copy account caches or the outbox into iCloud/device backups.
    for directory in [FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory] {
      if var url = FileManager.default.urls(for: directory, in: .userDomainMask).first {
        do {
          try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try url.setResourceValues(values)
        } catch {
          NSLog("BioBalance: local backup exclusion could not be configured")
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
