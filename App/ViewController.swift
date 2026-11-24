import UIKit
import WebKit

class ViewController: UIViewController, WKScriptMessageHandler, UIDocumentPickerDelegate {
    var webView: WKWebView!

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 9/255, green: 13/255, blue: 22/255, alpha: 1.0)

        let contentController = WKUserContentController()
        contentController.add(self, name: "iosBridge")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.scrollView.bounces = false
        view.addSubview(webView)

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "import":
            let types = ["public.json", "public.text", "public.plain-text", "public.data", "public.item"]
            let picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
            picker.delegate = self
            if #available(iOS 11.0, *) {
                picker.allowsMultipleSelection = false
            }
            present(picker, animated: true)

        case "export":
            if let jsonString = body["data"] as? String {
                let fileName = (body["filename"] as? String) ?? "SmartTimer_Backup.json"
                exportJSONFile(content: jsonString, fileName: fileName)
            }

        case "paste":
            let clipText = UIPasteboard.general.string ?? ""
            let autoInject = (body["autoInject"] as? Bool) ?? false
            sendClipboardToJS(text: clipText, autoInject: autoInject)

        case "copy":
            if let textToCopy = body["data"] as? String {
                UIPasteboard.general.string = textToCopy
            }

        case "keepAwake":
            let enabled = (body["enabled"] as? Bool) ?? true
            UIApplication.shared.isIdleTimerDisabled = enabled

        default:
            break
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        guard let jsonString = try? String(contentsOf: url, encoding: .utf8) else { return }
        let fileName = url.lastPathComponent
        if let jsonEncoded = jsStringLiteral(jsonString),
           let nameEncoded = jsStringLiteral(fileName) {
            webView.evaluateJavaScript("window.receiveInjectedJSON(\(jsonEncoded), \(nameEncoded))", completionHandler: nil)
        }
    }

    private func sendClipboardToJS(text: String, autoInject: Bool) {
        guard let encoded = jsStringLiteral(text) else { return }
        let flag = autoInject ? "true" : "false"
        webView.evaluateJavaScript("window.receiveClipboardText(\(encoded), \(flag))", completionHandler: nil)
    }

    private func exportJSONFile(content: String, fileName: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            present(activityVC, animated: true)
        } catch {}
    }

    private func jsStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let arrayStr = String(data: data, encoding: .utf8),
              arrayStr.count >= 2 else { return nil }
        return String(arrayStr.dropFirst().dropLast())
    }
}