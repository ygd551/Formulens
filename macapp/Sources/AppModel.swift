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
    case unloaded, starting, ready, stopping, failed

    var title: String {
        switch self {
        case .unloaded: return L("Model service: unloaded")
        case .stopping: return L("Model service: unloading…")
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
    @Published var serverState: ServerState = .unloaded
    @Published var toast: String?
    @Published private(set) var serviceError: String?

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

    let store: HistoryStore
    let server: ModelServer
    let catalog: ModelCatalog
    @Published private(set) var selectedModelID: String
    var modelProfiles: [ModelProfile] { catalog.profiles }
    private let serviceQueue = DispatchQueue(label: "Formulens.service", qos: .utility)
    private let generation = ServiceGeneration()
    var serviceTransitioning: Bool { serverState == .starting || serverState == .stopping }
    var canManageModels: Bool { !busy && !serviceTransitioning }
    // 不用 lazy：识别器会在多个后台线程中使用，lazy 初始化不是线程安全的
    private(set) var recognizer: Recognizer
    var onServerStateChange: (() -> Void)?
    private var toastWork: DispatchWorkItem?

    init(store: HistoryStore = HistoryStore(), server: ModelServer = ModelServer(),
         catalog: ModelCatalog = ModelCatalog()) {
        self.store = store
        self.server = server
        self.catalog = catalog
        selectedModelID = catalog.selectedID
        recognizer = Recognizer(server: server, modelPath: catalog.selected.path, promptStyle: catalog.selected.style)
        mode = RecognizeMode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .auto
        copyFormat = CopyFormat(rawValue: UserDefaults.standard.string(forKey: "copyFormat") ?? "") ?? .auto
        history = store.load()
        selectedID = history.first?.id
        server.onExit = { [weak self] pid in
            DispatchQueue.main.async {
                guard let self, self.serverState == .ready, self.server.processID == pid else { return }
                self.serverState = .failed
                self.serviceError = L("The model service exited unexpectedly. See model_server.log")
                self.onServerStateChange?()
                self.showToast(L("The model service exited unexpectedly. See model_server.log"))
            }
        }
    }

    var selected: OCRResult? { history.first { $0.id == selectedID } }

    // MARK: 推理服务

    /// All state publication is on the main queue; process work stays serialized.
    func startServer() {
        guard !busy, !serviceTransitioning else { return }
        let token = generation.advance()
        let profile = catalog.selected
        let next = Recognizer(server: server, modelPath: profile.path, promptStyle: profile.style)
        recognizer = next
        serverState = .starting
        serviceError = nil
        onServerStateChange?()
        serviceQueue.async {
            self.server.stop()
            guard self.generation.isCurrent(token) else { return }
            do {
                try profile.validate()
                guard self.server.ensureRunning(cancelled: { !self.generation.isCurrent(token) }) else {
                    throw RecognizeError(message: self.server.lastError ?? L("Model service failed to start"))
                }
                try next.warmUp(cancelled: { !self.generation.isCurrent(token) })
                guard self.server.ownsProcess else {
                    throw RecognizeError(message: L("The model service exited unexpectedly. See model_server.log"))
                }
                DispatchQueue.main.async {
                    guard self.generation.isCurrent(token) else { return }
                    self.serverState = self.server.ownsProcess ? .ready : .failed
                    if self.serverState == .failed { self.serviceError = L("The model service exited unexpectedly. See model_server.log") }
                    self.onServerStateChange?()
                }
            } catch {
                self.server.stop()
                DispatchQueue.main.async {
                    guard self.generation.isCurrent(token) else { return }
                    self.serverState = .failed
                    self.serviceError = error.localizedDescription
                    self.onServerStateChange?()
                    self.showToast(L("Model service failed to start: %@", error.localizedDescription))
                }
            }
        }
    }

    func unloadServer() {
        guard !busy, serverState != .stopping, serverState != .unloaded else { return }
        let token = generation.advance()
        serverState = .stopping
        serviceError = nil
        onServerStateChange?()
        server.cancelStartup()
        recognizer.cancelRequests()
        serviceQueue.async {
            self.server.stop()
            DispatchQueue.main.async {
                guard self.generation.isCurrent(token) else { return }
                self.serverState = .unloaded
                self.onServerStateChange?()
            }
        }
    }

    func shutdown() {
        generation.advance()
        server.cancelStartup()
        recognizer.cancelRequests()
        server.stop()
    }

    func selectModel(_ id: String) {
        guard canManageModels, id != selectedModelID else { return }
        do {
            try catalog.select(id)
            selectedModelID = catalog.selectedID
            if serverState != .unloaded { unloadServer() }
        } catch { showToast(error.localizedDescription) }
    }

    func addModel(_ url: URL, style: ModelPromptStyle) throws {
        guard canManageModels else { throw RecognizeError(message: L("Wait for the current operation to finish")) }
        let profile = try catalog.register(url, style: style)
        objectWillChange.send()
        selectModel(profile.id)
    }

    func removeModel(_ id: String) {
        guard canManageModels else { return }
        do {
            if id == selectedModelID, serverState != .unloaded { unloadServer() }
            try catalog.remove(id)
            selectedModelID = catalog.selectedID
            objectWillChange.send()
        } catch { showToast(error.localizedDescription) }
    }

    // MARK: 识别

    func recognize(imageData: Data, mode: RecognizeMode? = nil) {
        guard !busy else { return }
        guard serverState == .ready else {
            showToast(serverState == .starting ? L("The model service is starting, please wait…") : L("Load a model before recognizing"))
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
                try self.store.save(result, png: original ?? png)
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
                    if !alive {
                        self.serverState = .failed
                        self.onServerStateChange?()
                    }
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
        var result = history[i]
        if let latex {
            result.latex = latex
            if result.kind == "formula" { result.markdown = "$$\n\(latex)\n$$" }
        }
        if let markdown {
            result.markdown = markdown
            if result.kind == "formula", let pure = TextFormat.stripMath(markdown) { result.latex = pure }
        }
        // Keep the draft even if disk writes fail. Returning the old binding
        // value here would overwrite the editor and move its caret backwards.
        history[i] = result
        saveEdits(id)
    }

    @Published private(set) var editErrors: [String: String] = [:]

    func saveEdits(_ id: String) {
        guard let result = history.first(where: { $0.id == id }) else { return }
        do {
            try store.save(result, png: nil)
            editErrors[id] = nil
        } catch {
            editErrors[id] = error.localizedDescription
            showToast(L("Edits are kept in memory but could not be saved: %@", error.localizedDescription))
        }
    }

    @Published var deletionIDs: Set<String> = []
    @Published var showDeletionConfirmation = false
    @Published var markedIDs: Set<String> = []

    func requestDeletion(_ ids: Set<String>) {
        deletionIDs = ids.intersection(Set(history.map(\.id)))
        showDeletionConfirmation = !deletionIDs.isEmpty
    }

    func delete(_ id: String) { requestDeletion([id]) }

    func confirmDeletion() {
        let ids = deletionIDs
        showDeletionConfirmation = false
        deletionIDs = []
        let oldIndex = history.firstIndex { $0.id == selectedID } ?? 0
        var deleted = Set<String>()
        var errors: [String] = []
        for id in ids where history.contains(where: { $0.id == id }) {
            do { try store.delete(id); deleted.insert(id) }
            catch { errors.append("\(id): \(error.localizedDescription)") }
        }
        history.removeAll { deleted.contains($0.id) }
        markedIDs.subtract(deleted)
        for id in deleted { editErrors[id] = nil }
        if let selectedID, deleted.contains(selectedID) {
            self.selectedID = history.isEmpty ? nil : history[min(oldIndex, history.count - 1)].id
        }
        if !errors.isEmpty { showToast(L("Some history files could not be deleted: %@", errors.joined(separator: "; "))) }
    }

    func showToast(_ text: String) {
        toastWork?.cancel()
        toast = text
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
