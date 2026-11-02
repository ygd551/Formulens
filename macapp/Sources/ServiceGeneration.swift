import Foundation

/// A load completion may publish state only while it still owns this generation.
final class ServiceGeneration {
    private let lock = NSLock()
    private var value = 0
    @discardableResult func advance() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
    func isCurrent(_ generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return value == generation
    }
}
