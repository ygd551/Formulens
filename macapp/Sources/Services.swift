import AppKit
import Foundation
import Security

/// 路径：安装包版使用包内自带的 Python 和模型；开发版使用项目目录（models/ + env.sh 中的 Python）
enum Paths {
    static let resources = Bundle.main.resourceURL!
    static let bundledPython = resources.appendingPathComponent("python/bin/python3")
    static let bundledModel = resources.appendingPathComponent("models/PaddleOCR-VL-1.6")

    static let isBundled =
        FileManager.default.isExecutableFile(atPath: bundledPython.path)
        && FileManager.default.fileExists(atPath: bundledModel.appendingPathComponent("model.safetensors").path)

    /// 开发版的项目目录，构建时写入 Info.plist
    static let projectDir: URL = {
        if let p = Bundle.main.object(forInfoDictionaryKey: "FormulensProjectDir") as? String {
            return URL(fileURLWithPath: p)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }()

    static var modelDir: URL {
        isBundled ? bundledModel : projectDir.appendingPathComponent("models/PaddleOCR-VL-1.6")
    }

    /// 历史记录、日志、缓存：~/Library/Application Support/Formulens
    static let dataDir: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Formulens")
        // 改名前（Snip OCR）的数据目录：首次启动时整体迁移过来
        let legacy = base.appendingPathComponent("SnipOCR")
        if !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: dir)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // 历史截图、访问密钥、日志只允许当前用户访问
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }()
}

/// 后台 MLX-VLM 推理服务：未运行时由本应用启动，退出时关闭。
/// 服务只监听 127.0.0.1，并要求随机访问密钥：mlx-vlm 允许任意网页跨域访问，
/// 没有密钥时，浏览器里的网页或本机其他程序都能调用它。
final class ModelServer {
    let apiKey = ModelServer.loadOrCreateKey()
    private(set) var lastError: String?

    // baseURL 会在后台线程更新、在识别线程读取，用锁保护
    private let lock = NSLock()
    private var _baseURL = URL(string: "http://127.0.0.1:8111/")!
    var baseURL: URL {
        get { lock.lock(); defer { lock.unlock() }; return _baseURL }
        set { lock.lock(); _baseURL = newValue; lock.unlock() }
    }
    private var process: Process?
    // 同一时间只允许一次启动流程（菜单「重新启动推理服务」和识别失败重试可能同时触发）
    private let startLock = NSLock()

    private static let ports = 8111...8119

    private enum Probe { case ours, down, foreign }

    /// 访问密钥保存在 ~/Library/Application Support/Formulens/server.key（仅本用户可读）。
    /// 跨启动复用，应用异常退出后残留的服务仍能被识别和复用。
    private static func loadOrCreateKey() -> String {
        let url = Paths.dataDir.appendingPathComponent("server.key")
        if let s = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           s.count >= 32, s.allSatisfy(\.isHexDigit) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return s
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Failed to generate a random key")
        let key = bytes.map { String(format: "%02x", $0) }.joined()
        // 直接以 0600 权限创建，避免文件短暂地对其他用户可读
        try? FileManager.default.removeItem(at: url)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        if fd >= 0 {
            _ = key.withCString { write(fd, $0, strlen($0)) }
            close(fd)
        }
        return key
    }

    func authorize(_ req: inout URLRequest) {
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    /// 请求 /health，返回状态码；连不上返回 nil
    private func healthStatus(_ url: URL, withKey: Bool) -> Int? {
        var req = URLRequest(url: url.appendingPathComponent("health"))
        req.timeoutInterval = 1
        if withKey { authorize(&req) }
        var status: Int?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            status = (resp as? HTTPURLResponse)?.statusCode
            sem.signal()
        }.resume()
        sem.wait()
        return status
    }

    /// ours：带本应用密钥能访问、不带密钥被拒绝（确认是用本应用密钥启动的服务，
    /// 避免把截图发给碰巧占用该端口的其他程序）；foreign：端口被其他服务占用；down：端口空闲
    private func probe(_ url: URL) -> Probe {
        guard let withKey = healthStatus(url, withKey: true) else { return .down }
        guard withKey == 200 else { return .foreign }
        return healthStatus(url, withKey: false) == 401 ? .ours : .foreign
    }

    func isAlive() -> Bool { probe(baseURL) == .ours }

    /// 后台线程调用；返回是否就绪
    func ensureRunning() -> Bool {
        startLock.lock()
        defer { startLock.unlock() }
        lastError = nil
        if process?.isRunning == true { return waitUntilReady() }
        for port in Self.ports {
            let url = URL(string: "http://127.0.0.1:\(port)/")!
            switch probe(url) {
            case .ours:
                baseURL = url
                return true
            case .foreign:
                continue
            case .down:
                baseURL = url
                guard launch(port: port) else { return false }
                return waitUntilReady()
            }
        }
        lastError = L("Ports %@–%@ are all in use by other programs", String(Self.ports.lowerBound), String(Self.ports.upperBound))
        return false
    }

    private func launch(port: Int) -> Bool {
        let logURL = Paths.dataDir.appendingPathComponent("model_server.log")
        // 日志超过 5MB 时清空重写
        if let size = try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int, size > 5_000_000 {
            try? FileManager.default.removeItem(at: logURL)
        }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
        let log = try? FileHandle(forWritingTo: logURL)
        log?.seekToEndOfFile()

        let p = Process()
        if Paths.isBundled {
            // 包内自带的 Python；-I 隔离用户环境，-B 不写 .pyc（保持应用签名完整）。
            // 通过 watchdog 启动：应用退出（包括崩溃、强制退出）后，推理服务随之退出，不会残留占用内存。
            p.executableURL = Paths.bundledPython
            p.arguments = ["-I", "-B", "-c", Self.watchdog, "--host", "127.0.0.1", "--port", "\(port)"]
            p.environment = [
                "HOME": NSHomeDirectory(),
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "HF_HOME": Paths.dataDir.appendingPathComponent("hf_cache").path,
                "HF_HUB_OFFLINE": "1",
                "TRANSFORMERS_OFFLINE": "1",
                "MLX_VLM_SERVER_API_KEY": apiKey,
            ]
        } else {
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [Paths.projectDir.appendingPathComponent("start_server.sh").path]
            var env = ProcessInfo.processInfo.environment
            env["VL_SERVER_PORT"] = "\(port)"
            env["MLX_VLM_SERVER_API_KEY"] = apiKey
            p.environment = env
        }
        p.standardOutput = log
        p.standardError = log
        do { try p.run() } catch {
            lastError = L("Cannot start the model service: %@", error.localizedDescription)
            return false
        }
        process = p
        return true
    }

    private func waitUntilReady() -> Bool {
        for _ in 0..<120 {
            if isAlive() { return true }
            if process?.isRunning != true {
                lastError = L("The model service exited unexpectedly. See model_server.log")
                return false
            }
            Thread.sleep(forTimeInterval: 1)
        }
        lastError = L("The model service timed out while starting")
        return false
    }

    /// 父进程（本应用）退出后自动退出，然后以 `python -m mlx_vlm.server` 的方式运行服务
    private static let watchdog = """
    import os, runpy, sys, threading, time
    ppid = os.getppid()
    def watch():
        while os.getppid() == ppid:
            time.sleep(2)
        os._exit(0)
    threading.Thread(target=watch, daemon=True).start()
    sys.argv = ["mlx_vlm.server"] + sys.argv[1:]
    runpy.run_module("mlx_vlm.server", run_name="__main__", alter_sys=True)
    """

    var ownsProcess: Bool { process?.isRunning == true }

    /// 退出时关闭推理服务。正在生成时服务会等生成结束才退出，最多等 3 秒，之后强制结束
    func stop() {
        guard let p = process, p.isRunning else { return }
        p.terminate()
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if p.isRunning {
            kill(p.processIdentifier, SIGKILL)
            p.waitUntilExit()
        }
    }
}

/// 历史记录：~/Library/Application Support/Formulens/history/<id>.png + <id>.json
final class HistoryStore {
    let dir = Paths.dataDir.appendingPathComponent("history")
    private var thumbCache: [String: NSImage] = [:]

    init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func load() -> [OCRResult] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap { try? JSONDecoder().decode(OCRResult.self, from: Data(contentsOf: $0)) }
    }

    func imageURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).png") }

    func image(_ id: String) -> NSImage? {
        if let img = thumbCache[id] { return img }
        let img = NSImage(contentsOf: imageURL(id))
        thumbCache[id] = img
        return img
    }

    func save(_ r: OCRResult, png: Data?) {
        if let png { try? png.write(to: imageURL(r.id)) }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try? enc.encode(r).write(to: dir.appendingPathComponent("\(r.id).json"))
    }

    func delete(_ id: String) {
        thumbCache[id] = nil
        try? FileManager.default.removeItem(at: imageURL(id))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).json"))
    }

    static func newID() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date()) + "-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
    }

    static func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
