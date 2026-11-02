import AppKit
import Foundation

/// Only regular <id>.json/<id>.png files in the original history directory are writable.
final class HistoryStore {
    let dir: URL
    private let realDirectory: URL
    private let removeFile: (URL) throws -> Void
    private let lock = NSRecursiveLock()
    private var thumbCache: [String: NSImage] = [:]

    init(dir: URL = Paths.dataDir.appendingPathComponent("history"),
         removeFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.removeFile = removeFile
        self.dir = dir.standardizedFileURL
        realDirectory = dir.resolvingSymlinksInPath().standardizedFileURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    private func validateDirectory() throws {
        let values = try dir.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true,
              dir.resolvingSymlinksInPath().standardizedFileURL.path == realDirectory.path else {
            throw RecognizeError(message: L("History directory is unsafe or unavailable"))
        }
    }

    private func validateID(_ id: String) throws {
        guard !id.isEmpty, id.utf8.count <= 128,
              id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw RecognizeError(message: L("Invalid history identifier"))
        }
    }

    private func checkedFiles(_ id: String) throws -> [URL] {
        try validateID(id)
        try validateDirectory()
        let urls = [dir.appendingPathComponent("\(id).json"), imageURL(id)]
        for url in urls {
            var info = stat()
            if lstat(url.path, &info) == 0 {
                guard (info.st_mode & S_IFMT) == S_IFREG else {
                    throw RecognizeError(message: L("History entry is not a regular file: %@", url.lastPathComponent))
                }
            } else if errno != ENOENT {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        }
        return urls
    }

    func load() -> [OCRResult] {
        lock.lock(); defer { lock.unlock() }
        guard (try? validateDirectory()) != nil,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap { url in
                let id = url.deletingPathExtension().lastPathComponent
                guard (try? checkedFiles(id)) != nil,
                      let data = try? Data(contentsOf: url),
                      let result = try? JSONDecoder().decode(OCRResult.self, from: data), result.id == id else { return nil }
                return result
            }
    }

    func imageURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).png") }

    func image(_ id: String) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard (try? checkedFiles(id)) != nil else { return nil }
        if let image = thumbCache[id] { return image }
        let image = NSImage(contentsOf: imageURL(id))
        thumbCache[id] = image
        return image
    }

    func save(_ result: OCRResult, png: Data?) throws {
        lock.lock(); defer { lock.unlock() }
        let files = try checkedFiles(result.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let json = try encoder.encode(result)
        if let png { try png.write(to: files[1], options: .atomic) }
        try json.write(to: files[0], options: .atomic)
    }

    func delete(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }
        let files = try checkedFiles(id)
        // Stage both files before removal. A failed move rolls back the first file,
        // so the UI can retain the failed record and retry without a broken pair.
        var staged: [(URL, URL)] = []
        do {
            for file in files where FileManager.default.fileExists(atPath: file.path) {
                let trash = dir.appendingPathComponent(".delete-\(UUID().uuidString).\(file.pathExtension)")
                try FileManager.default.moveItem(at: file, to: trash)
                staged.append((file, trash))
            }
        } catch {
            for (file, trash) in staged.reversed() { try? FileManager.default.moveItem(at: trash, to: file) }
            throw error
        }
        do {
            // Delete the image first and the JSON index last. On failure the
            // index can still be restored, keeping the record visible on restart.
            for (_, trash) in staged.reversed() { try removeFile(trash) }
        } catch {
            // Report the failure, and restore any file that still exists.
            for (file, trash) in staged where FileManager.default.fileExists(atPath: trash.path) {
                try? FileManager.default.moveItem(at: trash, to: file)
            }
            throw error
        }
        thumbCache[id] = nil
    }

    static func newID() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date()) + "-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
    }

    static func now() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}
