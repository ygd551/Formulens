import AppKit
import Foundation
import WebKit
import SwiftUI

var passed = 0
var failed = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw RecognizeError(message: message) }
}
func test(_ name: String, _ body: () throws -> Void) {
    do { try body(); passed += 1; print("PASS \(name)") }
    catch { failed += 1; print("FAIL \(name): \(error)") }
}
func rejects(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw RecognizeError(message: "Expected rejection")
}
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("FormulensTests-\(UUID())").resolvingSymlinksInPath()
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
func fixture(_ id: String = "20261102-120000-abc123") -> OCRResult {
    OCRResult(id: id, time: "2026-11-02 12:00:00", mode: "formula", kind: "formula", latex: "a+b", markdown: "$$\na+b\n$$", raw: "a+b", seconds: 1)
}

test("history deletes JSON and PNG, tolerates missing pairs") {
    let store = HistoryStore(dir: root.appendingPathComponent("history"))
    let result = fixture()
    try store.save(result, png: Data([1, 2]))
    try check(store.load() == [result], "saved history must load")
    try store.delete(result.id)
    try check(!fm.fileExists(atPath: store.imageURL(result.id).path), "PNG remains")
    try check(store.load().isEmpty, "JSON remains")
    try store.delete(result.id)
}
test("history rejects traversal and mismatched record IDs") {
    let store = HistoryStore(dir: root.appendingPathComponent("safe"))
    let sentinel = root.appendingPathComponent("outside.json")
    try Data("keep".utf8).write(to: sentinel)
    try rejects { try store.delete("../outside") }
    try rejects { try store.save(fixture("../outside"), png: nil) }
    let encoded = try JSONEncoder().encode(fixture("../outside"))
    try encoded.write(to: store.dir.appendingPathComponent("legit.json"))
    try check(store.load().isEmpty, "untrusted record IDs loaded")
    try check(try Data(contentsOf: sentinel) == Data("keep".utf8), "outside modified")
}
test("history refuses symbolic-link root and files") {
    let outside = root.appendingPathComponent("elsewhere")
    try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    let link = root.appendingPathComponent("linked-history")
    try fm.createSymbolicLink(at: link, withDestinationURL: outside)
    let store = HistoryStore(dir: link)
    try rejects { try store.save(fixture(), png: Data([1])) }
    let normal = HistoryStore(dir: root.appendingPathComponent("links"))
    let target = outside.appendingPathComponent("keep.png")
    try Data([42]).write(to: target)
    try fm.createSymbolicLink(at: normal.imageURL(fixture().id), withDestinationURL: target)
    try rejects { try normal.delete(fixture().id) }
    try check(try Data(contentsOf: target) == Data([42]), "followed symlink")
}

test("source editor preserves middle cursor on SwiftUI echo and supports Unicode") {
    _ = NSApplication.shared
    let editor = SourceTextView()
    editor.apply(text: "α+b", editable: true)
    editor.setSelectedRange(NSRange(location: 2, length: 0))
    editor.insertText("X", replacementRange: editor.selectedRange())
    try check(editor.string == "α+Xb", "middle insertion went to end")
    editor.apply(text: "α+Xb", editable: true)
    try check(editor.selectedRange() == NSRange(location: 3, length: 0), "echo moved cursor")
    editor.apply(text: "raw", editable: false)
    try check(!editor.isEditable, "raw output is editable")
}

test("model catalog validates local assets and persists registrations without deleting weights") {
    let folder = root.appendingPathComponent("model")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(#"{"model_type":"paddleocr_vl"}"#.utf8).write(to: folder.appendingPathComponent("config.json"))
    let defaults = UserDefaults(suiteName: "FormulensTests-\(UUID())")!
    let catalog = ModelCatalog(defaultModel: root.appendingPathComponent("builtin"), defaults: defaults)
    try rejects { _ = try catalog.register(folder, style: .paddleOCR) }
    for name in ["tokenizer_config.json", "preprocessor_config.json"] {
        try Data("{}".utf8).write(to: folder.appendingPathComponent(name))
    }
    try Data([1]).write(to: folder.appendingPathComponent("model.safetensors"))
    let profile = try catalog.register(folder, style: .paddleOCR)
    try catalog.select(profile.id)
    let reloaded = ModelCatalog(defaultModel: root.appendingPathComponent("builtin"), defaults: defaults)
    try check(reloaded.selected.id == profile.id, "selected model was lost")
    try rejects { _ = try reloaded.register(folder, style: .generalVLM) }
    try reloaded.remove(profile.id)
    try check(fm.fileExists(atPath: folder.appendingPathComponent("model.safetensors").path), "removed user's model files")
    try check(reloaded.selected.id == ModelCatalog.builtinID, "removed selection did not reset")
}
test("general vision model profile supplies actual OCR instructions") {
    try check(ModelPromptStyle.generalVLM.prompt(for: "formula").contains("LaTeX"), "formula prompt missing")
    try check(ModelPromptStyle.generalVLM.prompt(for: "table").contains("Markdown"), "table prompt missing")
    try check(ModelPromptStyle.paddleOCR.prompt(for: "formula") == "Formula Recognition:", "existing OCR prompt changed")
}

test("service cancellation invalidates stale load completions") {
    let gate = ServiceGeneration()
    let first = gate.advance()
    try check(gate.isCurrent(first), "new generation is invalid")
    _ = gate.advance()
    try check(!gate.isCurrent(first), "stale load can publish ready")
}
test("model warmup errors propagate instead of falsely reporting ready") {
    let server = ModelServer(apiKey: "test-fixture", dataDir: root)
    server.baseURL = URL(string: "http://127.0.0.1:1/")!
    let recognizer = Recognizer(server: server, modelPath: "/missing")
    try rejects { try recognizer.warmUp() }
}

func waitFor(_ message: String, timeout: TimeInterval = 15, _ condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    try check(condition(), message)
}
func serviceFixture(_ behavior: String = "ok", port: Int = 28111) throws -> (AppModel, ModelServer) {
    let folder = root.appendingPathComponent("model")
    let defaults = UserDefaults(suiteName: "FormulensTests-\(UUID())")!
    let catalog = ModelCatalog(defaultModel: folder, defaults: defaults)
    let data = root.appendingPathComponent("service-\(UUID())")
    try fm.createDirectory(at: data, withIntermediateDirectories: true)
    let server = ModelServer(apiKey: "fixture", dataDir: data, ports: port...(port + 2)) { chosenPort in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-I", "-B", URL(fileURLWithPath: "Tests/fake_server.py").path, String(chosenPort), behavior, catalog.selected.path]
        return p
    }
    return (AppModel(store: HistoryStore(dir: data.appendingPathComponent("history")), server: server, catalog: catalog), server)
}
test("service load, unload, reload and unexpected exit synchronize state and reap processes") {
    let (model, server) = try serviceFixture()
    defer { model.shutdown() }
    model.startServer()
    try waitFor("load did not reach ready") { model.serverState == .ready }
    try check(server.ownsProcess, "ready without owned process")
    let pid = server.processID!
    model.unloadServer()
    try waitFor("unload did not complete") { model.serverState == .unloaded }
    try check(!server.ownsProcess && kill(pid, 0) == -1, "model process still resident")
    model.startServer()
    try waitFor("reload did not reach ready") { model.serverState == .ready }
    kill(server.processID!, SIGKILL)
    try waitFor("unexpected exit left stale ready state") { model.serverState == .failed }
}
test("failed warmup never becomes ready and terminates process") {
    let (model, server) = try serviceFixture("failure", port: 28121)
    defer { model.shutdown() }
    model.startServer()
    try waitFor("failed warmup did not fail") { model.serverState == .failed }
    try check(!server.ownsProcess, "failed warmup retained model process")
    try check(model.toast?.contains("fixture model cannot load") == true, "model error was lost")
}
test("unload during warmup cancels request and cannot resurrect loaded state") {
    let (model, server) = try serviceFixture("slow", port: 28131)
    defer { model.shutdown() }
    model.startServer()
    try waitFor("server never started") { server.ownsProcess }
    // Let health/warmup start, then cancel the in-flight HTTP request.
    RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    model.unloadServer()
    try waitFor("cancel load did not finish", timeout: 6) { model.serverState == .unloaded }
    try check(!server.ownsProcess, "cancelled warmup retained process")
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    try check(model.serverState == .unloaded, "stale completion resurrected ready")
}
test("batch deletion snapshots IDs, preserves unrelated detail and keeps failed records visible") {
    let (model, _) = try serviceFixture(port: 28141)
    defer { model.shutdown() }
    let a = fixture("a"), b = fixture("b"), c = fixture("c")
    for r in [a, b, c] { try model.store.save(r, png: Data([1])) }
    model.history = [a, b, c]
    model.selectedID = "c"
    model.markedIDs = ["a", "b"]
    // Make b unsafe. The batch must still delete a and leave b visible.
    try fm.removeItem(at: model.store.imageURL("b"))
    try fm.createDirectory(at: model.store.imageURL("b"), withIntermediateDirectories: false)
    model.requestDeletion(model.markedIDs)
    model.markedIDs = ["c"]
    model.showDeletionConfirmation = false // SwiftUI dismisses the alert before its action.
    model.confirmDeletion()
    try check(model.history.map(\.id) == ["b", "c"], "failed or unrelated record removed")
    try check(model.selectedID == "c", "detail selection jumped")
    try check(model.store.load().map(\.id) == ["c"], "successful JSON file remains")
    try check(fm.fileExists(atPath: model.store.dir.appendingPathComponent("b.json").path), "failed JSON removed")
}
test("formula editing persists source and synchronizes Markdown; deleting before next update cannot resurrect") {
    let (model, _) = try serviceFixture(port: 28151)
    defer { model.shutdown() }
    let result = fixture()
    try model.store.save(result, png: nil)
    model.history = [result]
    model.update(result.id, latex: "a+Xb")
    try check(model.history[0].latex == "a+Xb", "editor still shows old source")
    try check(model.history[0].markdown == "$$\na+Xb\n$$", "formula Markdown stale")
    try check(model.store.load()[0].latex == "a+Xb", "edit not persisted")
    model.requestDeletion([result.id]); model.confirmDeletion()
    model.update(result.id, latex: "late edit")
    try check(model.store.load().isEmpty, "late editor callback recreated history")
}

test("source editor preserves marked text during stale binding updates") {
    let editor = SourceTextView()
    editor.apply(text: "a+b", editable: true)
    editor.setSelectedRange(NSRange(location: 2, length: 0))
    editor.setMarkedText("中", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
    try check(editor.hasMarkedText(), "test did not create marked text")
    editor.apply(text: "stale", editable: true)
    try check(editor.hasMarkedText() && editor.string == "a+中b", "binding destroyed composition")
    editor.unmarkText()
}
test("preview debounces to latest formula, survives initial navigation and renders tables") {
    let web = WKWebView()
    let coordinator = MathPreview.Coordinator(previewURL: URL(fileURLWithPath: "Resources/preview.html"))
    coordinator.web = web
    web.navigationDelegate = coordinator
    let url = URL(fileURLWithPath: "Resources/preview.html")
    web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    coordinator.render(kind: "formula", text: "old")
    coordinator.render(kind: "formula", text: "x^2+1")
    var annotation: String?
    try waitFor("latest formula never rendered", timeout: 15) {
        web.evaluateJavaScript("document.querySelector('annotation')?.textContent") { value, _ in annotation = value as? String }
        return annotation == "x^2+1"
    }
    coordinator.render(kind: "table", text: "| a | b |\n| --- | --- |\n| 1 | 2 |")
    var cells: Int?
    try waitFor("table rendering regressed") {
        web.evaluateJavaScript("document.querySelectorAll('td').length") { value, _ in cells = value as? Int }
        return cells == 2
    }
}

test("failed edit save preserves draft, cursor-facing source and retryable error") {
    let (model, _) = try serviceFixture(port: 28171)
    defer { model.shutdown() }
    let record = fixture()
    try model.store.save(record, png: nil)
    model.history = [record]
    let png = model.store.imageURL(record.id)
    try fm.createDirectory(at: png, withIntermediateDirectories: false)
    model.update(record.id, latex: "a+draft+b")
    try check(model.history[0].latex == "a+draft+b", "failed save discarded typed draft")
    try check(model.editErrors[record.id] != nil, "save failure not visible")
    try fm.removeItem(at: png)
    model.update(record.id, latex: model.history[0].latex)
    try check(model.store.load()[0].latex == "a+draft+b", "retry did not persist retained draft")
    try check(model.editErrors[record.id] == nil, "successful retry left stale save error")
}
test("general vision model Markdown tables keep the rendered table kind") {
    let (_, server) = try serviceFixture("table", port: 28181)
    defer { server.stop() }
    try check(server.ensureRunning(), "fixture server failed")
    let recognizer = Recognizer(server: server, modelPath: root.appendingPathComponent("model").path, promptStyle: .generalVLM)
    let data = try Data(contentsOf: URL(fileURLWithPath: "../samples/table_demo.png"))
    let result = try recognizer.recognize(png: ImagePrep.png(from: data), mode: .table)
    try check(result.kind == "table", "Markdown table classified as text")
    try check(result.markdown.contains("| 1 | 2 |"), "table content lost")
}
test("late PNG unlink failure preserves recoverable JSON history") {
    let store = HistoryStore(dir: root.appendingPathComponent("delete-failure"), removeFile: { url in
        if url.pathExtension == "png" { throw RecognizeError(message: "fixture unlink failure") }
        try fm.removeItem(at: url)
    })
    let record = fixture()
    try store.save(record, png: Data([1]))
    try rejects { try store.delete(record.id) }
    try check(store.load() == [record], "failed deletion destroyed JSON index")
    try check(fm.fileExists(atPath: store.imageURL(record.id).path), "failed PNG not restored")
}

test("switching models unloads first, requires explicit load and protects active recognition") {
    let (model, server) = try serviceFixture(port: 28201)
    defer { model.shutdown() }
    let other = root.appendingPathComponent("other-model")
    try fm.copyItem(at: root.appendingPathComponent("model"), to: other)
    model.startServer()
    try waitFor("initial model not ready") { model.serverState == .ready }
    let pid = server.processID!
    try model.addModel(other, style: .generalVLM)
    try waitFor("model switch did not unload") { model.serverState == .unloaded }
    try check(kill(pid, 0) == -1, "previous model process remains")
    try check(model.catalog.selected.path == other.path, "new model not selected")
    model.startServer()
    try waitFor("selected model did not load") { model.serverState == .ready }
    try check(model.recognizer.modelPath == other.path && model.recognizer.promptStyle == .generalVLM, "recognizer uses old model")
    model.busy = true
    model.unloadServer(); model.selectModel(ModelCatalog.builtinID)
    try check(model.serverState == .ready && model.catalog.selected.path == other.path, "active recognition was interrupted")
    model.busy = false
    model.removeModel(model.selectedModelID)
    try waitFor("removing active registration did not unload") { model.serverState == .unloaded }
    try check(fm.fileExists(atPath: other.appendingPathComponent("model.safetensors").path), "removed user weights")
}
test("an authenticated externally owned server is skipped and left running") {
    let external = Process()
    external.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    external.arguments = ["-I", "-B", URL(fileURLWithPath: "Tests/fake_server.py").path, "28211", "ok", root.appendingPathComponent("model").path]
    external.standardOutput = FileHandle.nullDevice
    external.standardError = FileHandle.nullDevice
    try external.run()
    defer { if external.isRunning { external.terminate(); external.waitUntilExit() } }
    let (model, server) = try serviceFixture(port: 28211)
    defer { model.shutdown() }
    server.baseURL = URL(string: "http://127.0.0.1:28211/")!
    try waitFor("external fixture not ready") { server.isAlive() }
    model.startServer()
    try waitFor("own process not ready") { model.serverState == .ready }
    try check(server.baseURL.port != 28211, "adopted externally owned server")
    model.unloadServer()
    try waitFor("own unload did not complete") { model.serverState == .unloaded }
    try check(external.isRunning, "unload terminated another process")
}

test("development default model validates through its symbolic-link directory") {
    let target = root.appendingPathComponent("model")
    let alias = root.appendingPathComponent("development-default-model")
    try fm.createSymbolicLink(at: alias, withDestinationURL: target)
    let profile = ModelProfile(id: "alias", name: "Linked default", path: alias.path, style: .paddleOCR)
    try profile.validate()
}

if let python = ProcessInfo.processInfo.environment["FORMULENS_TEST_PYTHON"],
   let modelPath = ProcessInfo.processInfo.environment["FORMULENS_TEST_MODEL"] {
    test("REAL MLX: load, sample inference, unload releases resident process, reload") {
        let data = root.appendingPathComponent("real-service")
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        let profile = ModelProfile(id: "real", name: "Real model", path: modelPath, style: .paddleOCR)
        try profile.validate()
        let directServer = ModelServer(apiKey: "fixture", dataDir: data, ports: 28161...28169) { port in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = ["-I", "-B", "-m", "mlx_vlm.server", "--host", "127.0.0.1", "--port", String(port)]
            process.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "HF_HOME": data.appendingPathComponent("cache").path,
                                   "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "MLX_TRUST_REMOTE_CODE": "false", "MLX_VLM_SERVER_API_KEY": "fixture"]
            return process
        }
        let server: ModelServer
        if let project = ProcessInfo.processInfo.environment["FORMULENS_TEST_PROJECT_DIR"] {
            server = ModelServer(apiKey: "fixture", dataDir: data, ports: 28161...28169,
                                 projectDirectory: URL(fileURLWithPath: project))
            print("REAL launch route: development start_server.sh + parent watchdog")
        } else { server = directServer }
        defer { server.stop() }
        let recognizer = Recognizer(server: server, modelPath: modelPath)
        // Synchronous networking blocks the main thread; run inference off-main
        // while pumping the app run loop, as the actual app does.
        var done = false
        var outcome: Result<String, Error>?
        DispatchQueue.global().async {
            do {
                guard server.ensureRunning() else { throw RecognizeError(message: server.lastError ?? "server failed") }
                try recognizer.warmUp()
                let image = try Data(contentsOf: URL(fileURLWithPath: "../samples/formula_demo.png"))
                let result = try recognizer.recognize(png: ImagePrep.png(from: image), mode: .formula)
                outcome = .success(result.latex)
            } catch { outcome = .failure(error) }
            DispatchQueue.main.async { done = true }
        }
        try waitFor("real model inference timed out", timeout: 180) { done }
        let latex = try outcome!.get()
        try check(!latex.isEmpty, "empty real recognition")
        print("REAL LaTeX: \(latex)")
        let pid = server.processID!
        let metric = Process()
        metric.executableURL = URL(fileURLWithPath: "/bin/ps")
        metric.arguments = ["-o", "rss=", "-p", String(pid)]
        let pipe = Pipe(); metric.standardOutput = pipe
        try metric.run(); metric.waitUntilExit()
        let rss = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
        print("REAL loaded process RSS: \(rss) KiB")
        server.stop()
        try check(kill(pid, 0) == -1 && errno == ESRCH, "real model process remains after unload")
        done = false; outcome = nil
        DispatchQueue.global().async {
            do {
                guard server.ensureRunning() else { throw RecognizeError(message: "reload failed") }
                try recognizer.warmUp()
                outcome = .success("reloaded")
            } catch { outcome = .failure(error) }
            DispatchQueue.main.async { done = true }
        }
        try waitFor("real reload timed out", timeout: 180) { done }
        _ = try outcome!.get()
        print("REAL reload ready; first PID reaped")
    }
}

if let path = ProcessInfo.processInfo.environment["FORMULENS_TEST_SNAPSHOT"] {
    test("native result window layout snapshot with synthetic history") {
        let (model, _) = try serviceFixture(port: 28221)
        defer { model.shutdown() }
        let result = OCRResult(id: "layout", time: "2026-11-02 12:00:00", mode: "formula", kind: "formula",
                               latex: #"\int_0^1 x^2\,dx = \frac{1}{3}"#,
                               markdown: #"$$\int_0^1 x^2\,dx = \frac{1}{3}$$"#, raw: "fixture", seconds: 1.2)
        let image = try Data(contentsOf: URL(fileURLWithPath: "../samples/formula_demo.png"))
        try model.store.save(result, png: image)
        model.history = [result]; model.selectedID = result.id; model.markedIDs = [result.id]
        let host = NSHostingView(rootView: ContentView().environmentObject(model).background(Color.white).environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw RecognizeError(message: "cannot capture layout") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RecognizeError(message: "cannot encode layout") }
        try png.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
    }
}

print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
