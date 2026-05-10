import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let callChannel = FlutterMethodChannel(
      name: "com.lumos/call",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    callChannel.setMethodCallHandler { (call, result) in
      guard call.method == "makeCall" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let args = call.arguments as? [String: Any]
      let phone = (args?["phone"] as? String) ?? ""
      guard !phone.isEmpty else {
        result(FlutterError(code: "EMPTY_PHONE", message: "Telefon numarasi bos", details: nil))
        return
      }

      let allowedCharacters = CharacterSet(charactersIn: "+0123456789#*,;")
      let cleaned = String(phone.unicodeScalars.filter { allowedCharacters.contains($0) })
      guard !cleaned.isEmpty else {
        result(FlutterError(code: "BAD_PHONE", message: "Numara gecersiz", details: nil))
        return
      }

      guard let url = URL(string: "tel://\(cleaned)") else {
        result(FlutterError(code: "BAD_URL", message: "Numara gecersiz", details: nil))
        return
      }

      DispatchQueue.main.async {
        if UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url, options: [:]) { ok in
            result(ok ? "called" : "failed")
          }
        } else {
          result(FlutterError(code: "CANT_OPEN", message: "Cihaz arama yapamiyor", details: nil))
        }
      }
    }
  }
}
