import Foundation

final class RingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [(event: NetInspectEvent, bytes: Int)] = []
    private var totalBytes = 0
    private let maxEvents: Int
    private let maxBytes: Int

    init(configuration: StorageConfiguration) {
        maxEvents = configuration.maxEvents
        maxBytes = configuration.maxBytes
    }

    func append(_ event: NetInspectEvent) {
        let bytes = (try? JSONEncoder().encode(event).count) ?? 0
        lock.lock()
        events.append((event, bytes))
        totalBytes += bytes
        while events.count > maxEvents || totalBytes > maxBytes {
            guard !events.isEmpty else { break }
            totalBytes -= events.removeFirst().bytes
        }
        lock.unlock()
    }

    func snapshot() -> [NetInspectEvent] {
        lock.lock(); defer { lock.unlock() }
        return events.map(\.event)
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        events.removeAll(keepingCapacity: true)
        totalBytes = 0
    }
}
