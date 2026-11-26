import UIKit
import WebKit
import QuickLook
import Capacitor

/// Tela principal: abre o painel e injeta o script do app (esconde a vitrine, notificações, downloads).
class MainViewController: CAPBridgeViewController {

    override func capacitorDidLoad() {
        super.capacitorDidLoad()

        bridge?.registerPluginInstance(LinkGuardPlugin())

        // Deslizar da borda esquerda volta para a página anterior.
        webView?.allowsBackForwardNavigationGestures = true

        if let url = Bundle.main.url(forResource: "inject", withExtension: "js", subdirectory: "public"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            webView?.configuration.userContentController.addUserScript(script)
        }
    }
}

/// - Bloqueia navegação para páginas de compra (regra 3.1.1 da Apple).
/// - Arquivos (PDF etc.) não abrem mais por cima do app: são baixados e mostrados numa
///   tela própria com "OK" para voltar e o botão de compartilhar (Salvar em Arquivos, imprimir, WhatsApp...).
@objc(LinkGuardPlugin)
public class LinkGuardPlugin: CAPPlugin, CAPBridgedPlugin, QLPreviewControllerDataSource {
    public let identifier = "LinkGuardPlugin"
    public let jsName = "LinkGuard"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "openFile", returnType: CAPPluginReturnPromise)
    ]

    private let hostsBloqueados = try! NSRegularExpression(
        pattern: "(^|\\.)(seguro|checkout|pay|pagamento)\\.|kavoo|hotmart|eduzz|kiwify|doppus|mercadopago|pagseguro|^(www\\.)?atividadesanosiniciais\\.com\\.br$",
        options: [.caseInsensitive])

    private let extensoesDeArquivo: Set<String> = [
        "pdf", "ppt", "pptx", "doc", "docx", "xls", "xlsx", "zip", "png", "jpg", "jpeg", "mp3", "mp4"
    ]

    private var arquivoAtual: URL?
    private var baixando = false

    override public func shouldOverrideLoad(_ navigationAction: WKNavigationAction) -> NSNumber? {
        guard let url = navigationAction.request.url else { return nil }
        let host = url.host ?? ""
        let range = NSRange(host.startIndex..., in: host)
        if hostsBloqueados.firstMatch(in: host, options: [], range: range) != nil {
            return true
        }
        if url.path.hasPrefix("/vitrine") {
            return true
        }

        var ehDownload = extensoesDeArquivo.contains(url.pathExtension.lowercased())
        if #available(iOS 14.5, *), navigationAction.shouldPerformDownload { ehDownload = true }
        if ehDownload, url.scheme?.hasPrefix("http") == true {
            baixarEMostrar(url, nome: nil)
            return true
        }
        return nil
    }

    @objc func openFile(_ call: CAPPluginCall) {
        guard let texto = call.getString("url"), let url = URL(string: texto) else {
            call.reject("URL inválida")
            return
        }
        baixarEMostrar(url, nome: call.getString("name"))
        call.resolve()
    }

    private func baixarEMostrar(_ url: URL, nome: String?) {
        DispatchQueue.main.async {
            guard !self.baixando,
                  let webView = self.bridge?.webView,
                  let vc = self.bridge?.viewController else { return }
            self.baixando = true

            let carregando = UIActivityIndicatorView(style: .large)
            carregando.color = UIColor(red: 0.22, green: 0.62, blue: 0.89, alpha: 1)
            carregando.center = vc.view.center
            carregando.startAnimating()
            vc.view.addSubview(carregando)

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                var req = URLRequest(url: url)
                let host = url.host ?? ""
                let doSite = cookies.filter { c in
                    let dominio = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                    return host == dominio || host.hasSuffix("." + dominio)
                }
                for (campo, valor) in HTTPCookie.requestHeaderFields(with: doSite) {
                    req.setValue(valor, forHTTPHeaderField: campo)
                }

                URLSession.shared.downloadTask(with: req) { tmp, resp, erro in
                    DispatchQueue.main.async {
                        carregando.removeFromSuperview()
                        self.baixando = false
                        guard let tmp = tmp, erro == nil else {
                            self.avisar(vc, "Não foi possível baixar o arquivo. Confira sua internet e tente de novo.")
                            return
                        }
                        var nomeArquivo = (nome?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                            ?? resp?.suggestedFilename
                            ?? url.lastPathComponent
                        nomeArquivo = nomeArquivo.replacingOccurrences(of: "/", with: "-")
                        if (nomeArquivo as NSString).pathExtension.isEmpty, !url.pathExtension.isEmpty {
                            nomeArquivo += "." + url.pathExtension
                        }
                        let pasta = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString, isDirectory: true)
                        do {
                            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
                            let destino = pasta.appendingPathComponent(nomeArquivo)
                            try FileManager.default.moveItem(at: tmp, to: destino)
                            self.arquivoAtual = destino
                            let previa = QLPreviewController()
                            previa.dataSource = self
                            vc.present(previa, animated: true)
                        } catch {
                            self.avisar(vc, "Não foi possível abrir o arquivo.")
                        }
                    }
                }.resume()
            }
        }
    }

    private func avisar(_ vc: UIViewController, _ texto: String) {
        let alerta = UIAlertController(title: nil, message: texto, preferredStyle: .alert)
        alerta.addAction(UIAlertAction(title: "OK", style: .default))
        vc.present(alerta, animated: true)
    }

    // MARK: QLPreviewControllerDataSource
    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return arquivoAtual == nil ? 0 : 1
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return arquivoAtual! as NSURL
    }
}
