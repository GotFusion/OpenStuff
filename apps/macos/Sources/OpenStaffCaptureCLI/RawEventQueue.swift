import Foundation

final class RawEventQueue {
    private var totalCount = 0
    private let lock = NSLock()

    @discardableResult
    func enqueue(_ event: RawEvent) -> Int {
        lock.lock()
        defer { lock.unlock() }

        _ = event
        totalCount += 1
        return totalCount
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }

        return totalCount
    }
}
