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
    registerAppIconChannel(engineBridge.pluginRegistry.registrar(forPlugin: "AppIcon")!.messenger())
  }

  /// Ícone que muda com o mês (RN-49). Os ícones alternativos são os conjuntos AppIcon-Atencao e
  /// AppIcon-Alerta do Assets.xcassets (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES no projeto).
  /// O iOS mostra um aviso a cada troca, e só troca com o app aberto.
  private func registerAppIconChannel(_ messenger: FlutterBinaryMessenger) {
    let names = ["atencao": "AppIcon-Atencao", "alerta": "AppIcon-Alerta"]
    FlutterMethodChannel(name: "economizze/app_icon", binaryMessenger: messenger).setMethodCallHandler { call, result in
      let app = UIApplication.shared
      switch call.method {
      case "supported":
        result(app.supportsAlternateIcons)
      case "current":
        result(names.first { $0.value == app.alternateIconName }?.key ?? "padrao")
      case "set":
        let key = call.arguments as? String ?? "padrao"
        guard key == "padrao" || names[key] != nil else {
          result(FlutterError(code: "icone", message: "Ícone desconhecido", details: nil))
          return
        }
        app.setAlternateIconName(names[key]) { error in
          result(error == nil ? nil : FlutterError(code: "icone", message: error!.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
