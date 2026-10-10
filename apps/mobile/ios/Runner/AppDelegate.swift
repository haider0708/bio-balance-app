import Flutter
import UIKit
import UserNotifications
import workmanager_apple

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
    // Alerts are shown while the app is open too (each plugin answers for its own alerts).
    UNUserNotificationCenter.current().delegate = self
    // The background check for new alerts (lib/core/alerts/background_alerts.dart): iOS runs
    // it when it sees fit, at most every fifteen minutes.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "biobalance.alerts",
      earliestBeginInSeconds: NSNumber(value: 15 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BioBalancePush") {
      PushPlugin.register(with: registrar)
    }
  }
}

/// Apple push alerts (lib/core/alerts/push.dart): asks permission, gives the device token to
/// the app, keeps the icon number, shows alerts that arrive while the app is open, and tells
/// the app when one is tapped.
final class PushPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var waiting: [FlutterResult] = []
  /// An alert was tapped before the app asked (it started the app).
  private var opened = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PushPlugin()
    let channel = FlutterMethodChannel(name: "biobalance/push", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "register":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
        granted, _ in
        DispatchQueue.main.async {
          guard granted else {
            result(nil)
            return
          }
          self.waiting.append(result)
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    case "badge":
      let count = (call.arguments as? Int) ?? 0
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
      } else {
        UIApplication.shared.applicationIconBadgeNumber = count
      }
      result(nil)
    case "takeOpened":
      result(opened)
      opened = false
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func answer(_ value: Any?) {
    let results = waiting
    waiting.removeAll()
    for result in results { result(value) }
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    answer(deviceToken.map { String(format: "%02x", $0) }.joined())
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    answer(nil)
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Local alerts belong to flutter_local_notifications, which answers for them.
    guard notification.request.trigger is UNPushNotificationTrigger else { return }
    completionHandler([.banner, .list, .sound, .badge])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard response.notification.request.trigger is UNPushNotificationTrigger else { return }
    opened = true
    channel?.invokeMethod("opened", arguments: nil)
    completionHandler()
  }
}
