import UIKit
import WebKit
import Capacitor

/// Tela principal: abre o painel e injeta o script do app (esconde a vitrine e liga as notificações).
class MainViewController: CAPBridgeViewController {

    override func capacitorDidLoad() {
        super.capacitorDidLoad()

        bridge?.registerPluginInstance(LinkGuardPlugin())

        if let url = Bundle.main.url(forResource: "inject", withExtension: "js", subdirectory: "public"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            webView?.configuration.userContentController.addUserScript(script)
        }
    }
}

/// Bloqueia, no nível nativo, qualquer navegação para páginas de compra (regra 3.1.1 da Apple).
/// Nada de checkout abre dentro do app nem é jogado para o Safari.
@objc(LinkGuardPlugin)
public class LinkGuardPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "LinkGuardPlugin"
    public let jsName = "LinkGuard"
    public let pluginMethods: [CAPPluginMethod] = []

    private let hostsBloqueados = try! NSRegularExpression(
        pattern: "(^|\\.)(seguro|checkout|pay|pagamento)\\.|kavoo|hotmart|eduzz|kiwify|doppus|mercadopago|pagseguro|^(www\\.)?atividadesanosiniciais\\.com\\.br$",
        options: [.caseInsensitive])

    override public func shouldOverrideLoad(_ navigationAction: WKNavigationAction) -> NSNumber? {
        guard let url = navigationAction.request.url else { return nil }
        let host = url.host ?? ""
        let range = NSRange(host.startIndex..., in: host)
        if hostsBloqueados.firstMatch(in: host, options: [], range: range) != nil {
            return true // cancela
        }
        if url.path.hasPrefix("/vitrine") {
            return true
        }
        return nil // segue o comportamento normal do Capacitor
    }
}
