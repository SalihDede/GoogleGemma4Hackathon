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

    // make_call MethodChannel — Android tarafıyla aynı isim/sözleşme.
    let messenger = engineBridge.binaryMessenger
    let callChannel = FlutterMethodChannel(
      name: "com.lumos/call",
      binaryMessenger: messenger
    )
    callChannel.setMethodCallHandler { (call, result) in
      guard call.method == "makeCall" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let phone = (args?["phone"] as? String) ?? ""
      guard !phone.isEmpty else {
        result(FlutterError(code: "EMPTY_PHONE", message: "Telefon numarası boş", details: nil))
        return
      }
      // iOS sandbox: tel:// kullanıcı onayıyla aramayı başlatır (ACTION_CALL eşdeğeri).
      // telprompt:// daha çok eski iOS'larda; tel:// modern davranıştır.
      let allowedCharacters = CharacterSet(charactersIn: "+0123456789#*,;")
      let cleaned = String(phone.unicodeScalars.filter { allowedCharacters.contains($0) })
      guard !cleaned.isEmpty else {
        result(FlutterError(code: "BAD_PHONE", message: "Numara geÃ§ersiz", details: nil))
        return
      }
      guard let url = URL(string: "tel://\(cleaned)") else {
        result(FlutterError(code: "BAD_URL", message: "Numara geçersiz", details: nil))
        return
      }
      DispatchQueue.main.async {
        if UIApplication.shared.canOpenURL(url) {
          UIApplication.shared.open(url, options: [:]) { ok in
            result(ok ? "called" : "failed")
          }
        } else {
          result(FlutterError(code: "CANT_OPEN", message: "Cihaz arama yapamıyor", details: nil))
        }
      }
    }
  }
}
