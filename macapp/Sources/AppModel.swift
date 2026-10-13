import AppKit
import Foundation

enum CopyFormat: String, CaseIterable {
    case auto, latex, markdown

    var title: String {
        switch self {
        case .auto: return L("Auto (formulas → LaTeX, others → Markdown)")
        case .latex: return L("Always LaTeX")
        case .markdown: return L("Always Markdown")
        }
    }
}

enum ServerState {
    case starting, ready, failed

    var title: String {
        switch self {
        case .starting: return L("Model service: starting…")
        case .ready: return L("Model service: running")
        case .failed: return L("Model service: failed to start (see ~/Library/Application Support/Formulens/model_server.log)")
        }
    }
}

final class AppModel: ObservableObject {
    @Published var history: [OCRResult] = []
    @Published var selectedID: String?
    @Published var busy = false
    @Published var pendingImage: NSImage?
    @Published var serverState: ServerState = .starting
    @Published var toast: String?

    @Published var mode: RecognizeMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    /// 界面语言；修改后界面立即刷新（SwiftUI 视图依赖本对象，会重新取文字）
    @Published private(set) var language = Localizer.language
    var onLanguageChange: (() -> Void)?

    func setLanguage(_ lang: AppLanguage) {
        Localizer.set(lang)
        language = lang
        onLanguageChange?()
    }

    @Published var copyFormat: CopyFormat {
        didSet { UserDefaults.standard.set(copyFormat.rawValue, forKey: "copyFormat") }
    }

    let store = HistoryStore()
    let server = ModelServer()
    // 不用 lazy：识别器会在多个后台线程中使用，lazy 初始化不是线程安全的
    let recognizer: Recognizer
    var onServerStateChange: (() -> Void)?
    private var toastWork: DispatchWorkItem?
    private var serverStarting = false

    init() {
        recognizer = Recognizer(server: server, modelPath: Paths.modelDir.path)
        mode = RecognizeMode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .auto
        copyFormat = CopyFormat(rawValue: UserDefaults.standard.string(forKey: "copyFormat") ?? "") ?? .auto
        history = store.load()
        selectedID = history.first?.id
    }

    var selected: OCRResult? { history.first { $0.id == selectedID } }

    // MARK: 推理服务

    /// 主线程调用
    func startServer() {
        guard !serverStarting else { return }
        serverStarting = true
        serverState = .starting
        onServerStateChange?()
        DispatchQueue.global(qos: .utility).async {
            let ok = self.server.ensureRunning()
            if ok { self.recognizer.warmUp() }
            let error = self.server.lastError
            DispatchQueue.main.async {
                self.serverStarting = false
                self.serverState = ok ? .ready : .failed
                self.onServerStateChange?()
                if !ok, let error { self.showToast(L("Model service failed to start: %@", error)) }
            }
        }
    }

    // MARK: 识别

    func recognize(imageData: Data, mode: RecognizeMode? = nil) {
        guard !busy else { return }
        guard serverState == .ready else {
            showToast(serverState == .starting ? L("The model service is starting, please wait…") : L("The model service failed to start. See ~/Library/Application Support/Formulens/model_server.log"))
            return
        }
        do {
            try ImagePrep.validate(imageData)
        } catch {
            showToast(error.localizedDescription)
            return
        }
        let mode = mode ?? self.mode
        busy = true
        pendingImage = NSImage(data: imageData)
        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            do {
                let png = try ImagePrep.png(from: imageData)
                let r = try self.recognizer.recognize(png: png, mode: mode)
                let seconds = (Date().timeIntervalSince(start) * 100).rounded() / 100
                let result = OCRResult(id: HistoryStore.newID(), time: HistoryStore.now(), mode: mode.rawValue,
                                       kind: r.kind, latex: r.latex, markdown: r.markdown, raw: r.raw,
                                       seconds: seconds)
                let original = NSBitmapImageRep(data: imageData)?.representation(using: .png, properties: [:])
                self.store.save(result, png: original ?? png)
                DispatchQueue.main.async {
                    self.history.insert(result, at: 0)
                    self.selectedID = result.id
                    self.busy = false
                    self.pendingImage = nil
                    self.copy(self.defaultCopyText(result), label: L("Copied %@ (%@ s)", self.defaultCopyLabel(result), String(result.seconds)))
                }
            } catch {
                let alive = self.server.isAlive()
                DispatchQueue.main.async {
                    self.busy = false
                    self.pendingImage = nil
                    self.showToast(L("Recognition failed: %@", error.localizedDescription))
                    if !alive { self.startServer() }
                }
            }
        }
    }

    func rerun(_ r: OCRResult, mode: RecognizeMode) {
        guard let data = try? Data(contentsOf: store.imageURL(r.id)) else { return }
        recognize(imageData: data, mode: mode)
    }

    // MARK: 复制 / 编辑 / 删除

    private func useLatex(_ r: OCRResult) -> Bool {
        switch copyFormat {
        case .latex: return true
        case .markdown: return false
        case .auto: return r.kind == "formula"
        }
    }

    func defaultCopyText(_ r: OCRResult) -> String { useLatex(r) ? r.latex : r.markdown }
    func defaultCopyLabel(_ r: OCRResult) -> String { useLatex(r) ? "LaTeX" : "Markdown" }

    func copy(_ text: String, label: String = L("Copied")) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        showToast(label)
    }

    func update(_ id: String, latex: String? = nil, markdown: String? = nil) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        if let latex { history[i].latex = latex }
        if let markdown { history[i].markdown = markdown }
        store.save(history[i], png: nil)
    }

    func delete(_ id: String) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        store.delete(id)
        history.remove(at: i)
        selectedID = history.isEmpty ? nil : history[min(i, history.count - 1)].id
    }

    func showToast(_ text: String) {
        toastWork?.cancel()
        toast = text
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
