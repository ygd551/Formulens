import Foundation

enum ModelPromptStyle: String, Codable, CaseIterable {
    case paddleOCR, generalVLM
    var title: String { self == .paddleOCR ? L("PaddleOCR compatible") : L("General vision-language model") }
    func prompt(for task: String) -> String {
        if self == .paddleOCR { return Recognizer.prompts[task] ?? "OCR:" }
        switch task {
        case "formula": return "Read the mathematical formula in this image. Return only its LaTeX source, without explanation or code fences."
        case "table": return "Read the table in this image. Return only a Markdown table. Preserve math using $LaTeX$."
        default: return "Transcribe this image accurately as Markdown. Use $LaTeX$ for inline math and $$LaTeX$$ for display math. Return only the transcription."
        }
    }
}

struct ModelProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var path: String
    var style: ModelPromptStyle

    func validate() throws {
        let root = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard root.path.hasPrefix("/"), FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else {
            throw RecognizeError(message: L("Model directory does not exist: %@", path))
        }
        func json(_ name: String) throws -> [String: Any] {
            guard let data = try? Data(contentsOf: root.appendingPathComponent(name)), data.count <= 10_000_000,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RecognizeError(message: L("Missing or invalid model file: %@", name))
            }
            return obj
        }
        let config = try json("config.json")
        guard let type = config["model_type"] as? String, !type.isEmpty else {
            throw RecognizeError(message: L("Model config has no model_type"))
        }
        if style == .paddleOCR, type != "paddleocr_vl" {
            throw RecognizeError(message: L("Choose the general vision-language prompt style for this model"))
        }
        _ = try json("tokenizer_config.json")
        let processorFiles = ["preprocessor_config.json", "processor_config.json"]
        guard processorFiles.contains(where: { (try? json($0)) != nil }) else {
            throw RecognizeError(message: L("Missing or invalid model file: %@", processorFiles.joined(separator: " / ")))
        }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        let weights = files.filter { $0.pathExtension == "safetensors" }
        guard !weights.isEmpty, weights.allSatisfy({
            guard let values = try? $0.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]) else { return false }
            return values.isRegularFile == true && (values.fileSize ?? 0) > 0
        }) else { throw RecognizeError(message: L("Model directory has no readable safetensors weights")) }
        let index = root.appendingPathComponent("model.safetensors.index.json")
        if FileManager.default.fileExists(atPath: index.path) {
            let obj = try json(index.lastPathComponent)
            guard let map = obj["weight_map"] as? [String: String], !map.isEmpty,
                  map.values.allSatisfy({ name in
                      !name.contains("/" ) && !name.contains("\\") && weights.contains { $0.lastPathComponent == name }
                  }) else { throw RecognizeError(message: L("Model weight index contains missing or unsafe shards")) }
        }
        // auto_map is common in Paddle checkpoints. It is metadata only: the
        // inference server is always launched without trust_remote_code.
    }
}

final class ModelCatalog {
    static let builtinID = "bundled"
    private let defaults: UserDefaults
    private let profilesKey = "localModelProfiles"
    private let selectionKey = "selectedLocalModel"
    private(set) var profiles: [ModelProfile]
    private(set) var selectedID: String
    var selected: ModelProfile { profiles.first { $0.id == selectedID } ?? profiles[0] }

    init(defaultModel: URL = Paths.modelDir, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let builtin = ModelProfile(id: Self.builtinID, name: "PaddleOCR-VL-1.6", path: defaultModel.path, style: .paddleOCR)
        let saved = defaults.data(forKey: profilesKey).flatMap { try? JSONDecoder().decode([ModelProfile].self, from: $0) } ?? []
        var ids: Set<String> = [Self.builtinID]
        profiles = [builtin] + saved.filter { $0.path.hasPrefix("/") && ids.insert($0.id).inserted }
        let id = defaults.string(forKey: selectionKey) ?? Self.builtinID
        selectedID = profiles.contains { $0.id == id } ? id : Self.builtinID
    }

    @discardableResult func register(_ url: URL, style: ModelPromptStyle) throws -> ModelProfile {
        let url = url.resolvingSymlinksInPath().standardizedFileURL
        let profile = ModelProfile(id: UUID().uuidString, name: url.lastPathComponent, path: url.path, style: style)
        try profile.validate()
        guard !profiles.contains(where: { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == url.path }) else {
            throw RecognizeError(message: L("This model directory is already registered"))
        }
        profiles.append(profile)
        persist()
        return profile
    }

    func select(_ id: String) throws {
        guard profiles.contains(where: { $0.id == id }) else { throw RecognizeError(message: L("Unknown model")) }
        selectedID = id
        persist()
    }

    func remove(_ id: String) throws {
        guard id != Self.builtinID else { throw RecognizeError(message: L("The bundled model cannot be removed")) }
        profiles.removeAll { $0.id == id }
        if selectedID == id { selectedID = Self.builtinID }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(profiles.filter { $0.id != Self.builtinID }), forKey: profilesKey)
        defaults.set(selectedID, forKey: selectionKey)
    }
}
