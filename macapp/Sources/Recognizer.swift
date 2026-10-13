import AppKit
import Foundation

enum RecognizeMode: String, CaseIterable {
    case auto, formula, text, table

    var title: String {
        switch self {
        case .auto: return L("Auto")
        case .formula: return L("Formula")
        case .text: return L("Text + formulas")
        case .table: return L("Table")
        }
    }
}

struct RecognizeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 一次识别的结果（与 data/history/*.json 的格式一致）
struct OCRResult: Codable, Identifiable, Equatable {
    var id: String
    var time: String
    var mode: String
    var kind: String  // formula / text / table
    var latex: String
    var markdown: String
    var raw: String
    var seconds: Double

    var kindTitle: String {
        switch kind {
        case "formula": return L("Formula")
        case "table": return L("Table")
        default: return L("Text")
        }
    }
}

/// 调用本地 MLX-VLM 推理服务（OpenAI 兼容接口），并把输出整理成 LaTeX / Markdown。
final class Recognizer {
    let server: ModelServer
    let modelPath: String

    static let prompts = [
        "formula": "Formula Recognition:",
        "text": "OCR:",
        "table": "Table Recognition:",
    ]

    init(server: ModelServer, modelPath: String) {
        self.server = server
        self.modelPath = modelPath
    }

    /// 同步调用，需在后台线程使用
    func recognize(png: Data, mode: RecognizeMode) throws -> (kind: String, latex: String, markdown: String, raw: String) {
        var raw: String
        var asFormula = false
        switch mode {
        case .table:
            raw = try call(png, task: "table")
        case .formula:
            raw = try call(png, task: "formula")
            asFormula = true
        case .text:
            raw = try call(png, task: "text")
        case .auto:
            raw = try call(png, task: "text")
            if raw.contains("<fcel>") {
                raw = try call(png, task: "table")
            } else if TextFormat.isMostlyMath(raw) {
                // 除公式外没有正常文字：用公式模式重识别，精度更高
                raw = try call(png, task: "formula")
                asFormula = true
            }
        }

        if raw.contains("<fcel>") {
            let md = TextFormat.otslToMarkdown(raw)
            return ("table", md, md, raw)
        }
        if let found = TextFormat.stripMath(raw) ?? (asFormula ? TextFormat.trimDelimiters(raw) : nil) {
            let pure = TextFormat.dropNumberingCommands(found)
            return ("formula", pure, "$$\n\(pure)\n$$", raw)
        }
        return ("text", raw, TextFormat.toMarkdownMath(raw), raw)
    }

    /// 预热：让模型提前加载进内存。用一张小公式图，限制输出长度
    func warmUp() {
        let size = NSSize(width: 160, height: 48)
        let img = NSImage(size: size, flipped: false) { r in
            NSColor.white.setFill()
            r.fill()
            NSAttributedString(string: "x² + 1", attributes: [.font: NSFont.systemFont(ofSize: 28)])
                .draw(at: NSPoint(x: 20, y: 8))
            return true
        }
        guard let tiff = img.tiffRepresentation, let png = try? ImagePrep.png(from: tiff) else { return }
        _ = try? call(png, task: "formula", maxTokens: 16)
    }

    private func call(_ png: Data, task: String, maxTokens: Int? = nil) throws -> String {
        // 公式通常很短；限制长度，防止模型陷入重复输出
        let maxTokens = maxTokens ?? (task == "formula" ? 1024 : 4096)
        var req = URLRequest(url: server.baseURL.appendingPathComponent("chat/completions"))
        server.authorize(&req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300
        let body: [String: Any] = [
            "model": modelPath,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64," + png.base64EncodedString()]],
                    ["type": "text", "text": Self.prompts[task]!],
                ],
            ]],
            "max_tokens": maxTokens,
            "temperature": 0,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        var result: Result<String, Error> = .failure(RecognizeError(message: L("No response")))
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err {
                result = .failure(RecognizeError(message: L("Cannot connect to the model service: %@", err.localizedDescription)))
                return
            }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String
            else {
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                result = .failure(RecognizeError(message: L("The model service returned error %@: %@", String(status), String(text.prefix(200)))))
                return
            }
            result = .success(content.trimmingCharacters(in: .whitespacesAndNewlines))
        }.resume()
        sem.wait()
        return try result.get()
    }
}

/// 识别结果的格式整理
enum TextFormat {
    private static let singleMath = try! NSRegularExpression(
        pattern: #"^\s*(\\\(|\\\[|\$\$|\$)(.*)(\\\)|\\\]|\$\$|\$)\s*$"#,
        options: [.dotMatchesLineSeparators])
    private static let innerDelimiter = try! NSRegularExpression(pattern: #"\\\)|\\\(|\\\[|\\\]"#)
    private static let displayMath = try! NSRegularExpression(pattern: #"\\\[(.+?)\\\]"#, options: [.dotMatchesLineSeparators])
    private static let inlineMath = try! NSRegularExpression(pattern: #"\\\((.+?)\\\)"#, options: [.dotMatchesLineSeparators])
    private static let otslTag = try! NSRegularExpression(pattern: #"<(fcel|ecel|lcel|ucel|xcel)>"#)

    /// 整段只是一个公式时，返回去掉定界符的 LaTeX；否则返回 nil
    static func stripMath(_ s: String) -> String? {
        let ns = s as NSString
        guard let m = singleMath.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let inner = ns.substring(with: m.range(at: 2))
        // 防止把 "\(a\) and \(b\)" 误判为单个公式
        if innerDelimiter.firstMatch(in: inner, range: NSRange(location: 0, length: (inner as NSString).length)) != nil {
            return nil
        }
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let latinWord = try! NSRegularExpression(pattern: #"(?<![\\A-Za-z])[A-Za-z]{3,}"#)
    private static let cjkChar = try! NSRegularExpression(pattern: #"[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]"#)
    private static let mathCommandArg = try! NSRegularExpression(pattern: #"\\[A-Za-z]+\{[^{}]*\}"#)

    /// 识别结果里除公式外基本没有正常文字（即使定界符不配对也能判断）
    static func isMostlyMath(_ s: String) -> Bool {
        var outside = replace(s, displayMath) { _ in " " }
        outside = replace(outside, inlineMath) { _ in " " }
        let hasMath = outside != s || s.contains("\\(") || s.contains("\\[") || s.contains("$")
        guard hasMath else { return false }
        // 去掉残留的定界符和 \mathrm{...} 这类命令，再统计自然语言内容
        for d in ["\\(", "\\)", "\\[", "\\]", "$"] {
            outside = outside.replacingOccurrences(of: d, with: " ")
        }
        let ns = NSMutableString(string: outside)
        mathCommandArg.replaceMatches(in: ns, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        let range = NSRange(location: 0, length: ns.length)
        return latinWord.numberOfMatches(in: ns as String, range: range) == 0
            && cjkChar.numberOfMatches(in: ns as String, range: range) == 0
    }

    /// 模型偶尔会在单个公式开头输出 \nonumber / \notag，单独使用时在 KaTeX 等环境中会报错
    static func dropNumberingCommands(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for cmd in ["\\nonumber", "\\notag"] where t.hasPrefix(cmd) {
            // 后面紧跟字母时是另一个命令（如 \nonumberx），不处理
            if let next = t.dropFirst(cmd.count).first, next.isLetter { continue }
            t.removeFirst(cmd.count)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 去掉首尾的公式定界符
    static func trimDelimiters(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for (l, r) in [("\\[", "\\]"), ("\\(", "\\)"), ("$$", "$$"), ("$", "$")] {
            if t.hasPrefix(l) { t.removeFirst(l.count) }
            if t.hasSuffix(r) { t.removeLast(r.count) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// \( \) → $ $，\[ \] → $$ $$
    static func toMarkdownMath(_ s: String) -> String {
        var out = replace(s, displayMath) { "$$" + $0 + "$$" }
        out = replace(out, inlineMath) { "$" + $0 + "$" }
        return out
    }

    private static func replace(_ s: String, _ re: NSRegularExpression, _ wrap: (String) -> String) -> String {
        let ns = NSMutableString(string: s)
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        for m in matches.reversed() {
            let inner = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            ns.replaceCharacters(in: m.range, with: wrap(inner))
        }
        return ns as String
    }

    /// PaddleOCR-VL 的表格输出（OTSL）→ Markdown 表格；合并单元格留空
    static func otslToMarkdown(_ s: String) -> String {
        var rows: [[String]] = []
        for line in s.components(separatedBy: "<nl>") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let ns = line as NSString
            let tags = otslTag.matches(in: line, range: NSRange(location: 0, length: ns.length))
            var row: [String] = []
            for (i, t) in tags.enumerated() {
                let start = t.range.location + t.range.length
                let end = i + 1 < tags.count ? tags[i + 1].range.location : ns.length
                let text = ns.substring(with: NSRange(location: start, length: end - start))
                let tag = ns.substring(with: t.range(at: 1))
                row.append(tag == "fcel" ? toMarkdownMath(text.trimmingCharacters(in: .whitespaces)) : "")
            }
            rows.append(row)
        }
        guard let first = rows.first else { return s }
        let n = rows.map(\.count).max() ?? first.count
        let padded = rows.map { $0 + Array(repeating: "", count: n - $0.count) }
        var out = ["| " + padded[0].joined(separator: " | ") + " |",
                   "|" + String(repeating: " --- |", count: n)]
        out += padded.dropFirst().map { "| " + $0.joined(separator: " | ") + " |" }
        return out.joined(separator: "\n")
    }
}

/// 图片预处理：小图放大、大图缩小，统一转为 RGB PNG
enum ImagePrep {
    static let maxFileBytes = 50 * 1024 * 1024
    static let maxPixels = 100_000_000

    /// 解码前检查大小，防止超大或恶意构造的图片（文件很小但尺寸巨大）耗尽内存
    static func validate(_ data: Data) throws {
        guard data.count <= maxFileBytes else {
            throw RecognizeError(message: L("Image is too large (over 50 MB)"))
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0
        else { throw RecognizeError(message: L("Cannot read the image")) }
        guard w * h <= maxPixels else {
            throw RecognizeError(message: L("Image dimensions are too large (%@×%@)", String(w), String(h)))
        }
    }

    /// 读取拖入或粘贴的图片文件，超过大小上限时返回 nil
    static func readImageFile(_ url: URL) -> Data? {
        guard url.isFileURL,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maxFileBytes
        else { return nil }
        return try? Data(contentsOf: url)
    }

    static func png(from data: Data) throws -> Data {
        try validate(data)
        guard let rep = NSBitmapImageRep(data: data), let cg = rep.cgImage else {
            throw RecognizeError(message: L("Cannot read the image"))
        }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let longest = max(w, h)
        var scale: CGFloat = 1
        if longest < 200 { scale = 200 / longest }
        if longest > 2400 { scale = 2400 / longest }
        let nw = Int((w * scale).rounded()), nh = Int((h * scale).rounded())
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw RecognizeError(message: L("Failed to process the image")) }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: nw, height: nh))
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        guard let out = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
        else { throw RecognizeError(message: L("Failed to process the image")) }
        return png
    }

    /// 从剪贴板取图片（PNG / TIFF / 图片文件）
    static func pngFromPasteboard(_ pb: NSPasteboard) -> Data? {
        if let d = pb.data(forType: .png) { return d }
        if let d = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: d) {
            return rep.representation(using: .png, properties: [:])
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first, let d = ImagePrep.readImageFile(url), (try? validate(d)) != nil {
            return d
        }
        return nil
    }
}
