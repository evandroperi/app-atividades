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

            var nomeArquivo = (nome?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? url.lastPathComponent
            nomeArquivo = nomeArquivo.replacingOccurrences(of: "/", with: "-")
            if (nomeArquivo as NSString).pathExtension.isEmpty, !url.pathExtension.isEmpty {
                nomeArquivo += "." + url.pathExtension
            }

            let aviso = AvisoDownload(nome: nomeArquivo)
            aviso.mostrar(em: vc.view)

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

                // Sem compressão: o servidor manda o arquivo direto e o progresso fica certo.
                req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

                let baixador = Baixador()
                aviso.aoCancelar = { baixador.cancelar() }
                baixador.progresso = { p in aviso.atualizar(p) }
                baixador.baixar(req, tentativas: 2) { tmp, erro in
                    aviso.esconder()
                    self.baixando = false
                    if let erro = erro as NSError? {
                        if erro.code == NSURLErrorCancelled { return }
                        self.avisar(vc, "Não foi possível baixar o arquivo. Confira sua internet e tente de novo. (erro \(erro.code))")
                        return
                    }
                    guard let tmp = tmp else { return }
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

/// Baixa arquivos grandes (PowerPoint de 20, 50, 100 MB) com paciência: tempo longo, progresso e 1 nova tentativa.
final class Baixador: NSObject, URLSessionDownloadDelegate {
    var progresso: ((Double) -> Void)?
    private var concluir: ((URL?, Error?) -> Void)?
    private var sessao: URLSession?
    private var tarefa: URLSessionDownloadTask?
    private var requisicao: URLRequest?
    private var tentativasRestantes = 0
    private var cancelado = false

    func baixar(_ req: URLRequest, tentativas: Int, concluir: @escaping (URL?, Error?) -> Void) {
        self.requisicao = req
        self.tentativasRestantes = tentativas
        self.concluir = concluir
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 30
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessao = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        iniciar()
    }

    private func iniciar() {
        guard let req = requisicao else { return }
        tentativasRestantes -= 1
        tarefa = sessao?.downloadTask(with: req)
        tarefa?.resume()
    }

    func cancelar() {
        cancelado = true
        tarefa?.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            progresso?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // O arquivo temporário some quando este método termina: move para um lugar seguro antes.
        let seguro = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: seguro)
            if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                finalizar(nil, NSError(domain: "http", code: http.statusCode))
            } else {
                finalizar(seguro, nil)
            }
        } catch {
            finalizar(nil, error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        if !cancelado, tentativasRestantes > 0 {
            iniciar()
            return
        }
        finalizar(nil, error)
    }

    private func finalizar(_ url: URL?, _ erro: Error?) {
        let fim = concluir
        concluir = nil
        sessao?.finishTasksAndInvalidate()
        fim?(url, erro)
    }
}

/// Aviso no centro da tela enquanto baixa. Cobre a tela inteira para ninguém tocar de novo.
final class AvisoDownload {
    var aoCancelar: (() -> Void)?
    private let fundo = UIView()
    private let barra = UIProgressView(progressViewStyle: .default)
    private let porcentagem = UILabel()

    init(nome: String) {
        let azul = UIColor(red: 0.22, green: 0.62, blue: 0.89, alpha: 1)
        fundo.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        fundo.translatesAutoresizingMaskIntoConstraints = false

        let caixa = UIView()
        caixa.backgroundColor = .white
        caixa.layer.cornerRadius = 18
        caixa.translatesAutoresizingMaskIntoConstraints = false

        let girando = UIActivityIndicatorView(style: .large)
        girando.color = azul
        girando.startAnimating()

        let titulo = UILabel()
        titulo.text = "Baixando arquivo…"
        titulo.font = .boldSystemFont(ofSize: 19)
        titulo.textColor = .black
        titulo.textAlignment = .center

        let nomeLabel = UILabel()
        nomeLabel.text = nome
        nomeLabel.font = .systemFont(ofSize: 14)
        nomeLabel.textColor = .darkGray
        nomeLabel.textAlignment = .center
        nomeLabel.numberOfLines = 2

        barra.progressTintColor = azul
        barra.progress = 0

        porcentagem.text = "Aguarde, arquivos grandes podem demorar um pouco"
        porcentagem.font = .systemFont(ofSize: 13)
        porcentagem.textColor = .gray
        porcentagem.textAlignment = .center
        porcentagem.numberOfLines = 2

        let cancelar = UIButton(type: .system)
        cancelar.setTitle("Cancelar", for: .normal)
        cancelar.titleLabel?.font = .systemFont(ofSize: 16)
        cancelar.addTarget(self, action: #selector(tocouCancelar), for: .touchUpInside)

        let pilha = UIStackView(arrangedSubviews: [girando, titulo, nomeLabel, barra, porcentagem, cancelar])
        pilha.axis = .vertical
        pilha.spacing = 12
        pilha.alignment = .fill
        pilha.translatesAutoresizingMaskIntoConstraints = false

        caixa.addSubview(pilha)
        fundo.addSubview(caixa)
        NSLayoutConstraint.activate([
            caixa.centerXAnchor.constraint(equalTo: fundo.centerXAnchor),
            caixa.centerYAnchor.constraint(equalTo: fundo.centerYAnchor),
            caixa.widthAnchor.constraint(equalToConstant: 290),
            pilha.topAnchor.constraint(equalTo: caixa.topAnchor, constant: 24),
            pilha.bottomAnchor.constraint(equalTo: caixa.bottomAnchor, constant: -12),
            pilha.leadingAnchor.constraint(equalTo: caixa.leadingAnchor, constant: 20),
            pilha.trailingAnchor.constraint(equalTo: caixa.trailingAnchor, constant: -20)
        ])
    }

    func mostrar(em view: UIView) {
        view.addSubview(fundo)
        NSLayoutConstraint.activate([
            fundo.topAnchor.constraint(equalTo: view.topAnchor),
            fundo.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fundo.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fundo.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func atualizar(_ p: Double) {
        barra.setProgress(Float(p), animated: true)
        porcentagem.text = "\(Int(p * 100))%"
    }

    func esconder() {
        fundo.removeFromSuperview()
    }

    @objc private func tocouCancelar() {
        aoCancelar?()
        esconder()
    }
}
