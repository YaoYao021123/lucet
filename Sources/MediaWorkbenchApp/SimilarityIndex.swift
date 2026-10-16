import Foundation
import MediaCore
import Observation

/// Finds similar shots and bursts in the library (Library › Similar & Bursts).
/// Fingerprints are cached on disk by file size and date, so only new or changed photos
/// are read again.
@MainActor
@Observable
final class SimilarityIndex {
    private(set) var groups: [PhotoGroup] = []
    /// Photos fingerprinted so far while a scan runs.
    private(set) var progress: (done: Int, total: Int)?
    private(set) var hasScanned = false

    private struct Record: Codable {
        var size: Int
        var modified: Date
        var print: PhotoFingerprint
    }
    @ObservationIgnored private var cache: [String: Record] = [:]
    @ObservationIgnored private let file: URL
    @ObservationIgnored private var task: Task<Void, Never>?

    init(root: URL) {
        file = root.appendingPathComponent("fingerprints.json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: Record].self, from: data) {
            cache = saved
        }
    }

    /// Fingerprints any photos that need it, then regroups. Videos are skipped.
    func refresh(_ entries: [LibraryEntry], missing: Set<String>) {
        task?.cancel()
        let photos = entries.filter { !$0.isVideo && !missing.contains($0.id) }
        let known = cache
        task = Task { [weak self] in
            let stamps = await Task.detached(priority: .utility) {
                photos.map { entry -> (LibraryEntry, Int, Date) in
                    let values = try? entry.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    return (entry, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
                }
            }.value
            let stale = stamps.filter { entry, size, modified in
                guard let record = known[entry.id] else { return true }
                return record.size != size || record.modified != modified
            }
            guard let self else { return }
            self.progress = stale.isEmpty ? nil : (0, stale.count)
            var fresh: [String: Record] = [:]
            // Four decoders at a time: each is a small, subsampled decode (a few ms).
            for start in stride(from: 0, to: stale.count, by: 32) {
                if Task.isCancelled { return }
                let chunk = Array(stale[start..<min(stale.count, start + 32)])
                let read = await withTaskGroup(of: (String, Record?).self) { group in
                    var results: [(String, Record?)] = []
                    var iterator = chunk.makeIterator()
                    func add(_ item: (LibraryEntry, Int, Date)) {
                        group.addTask(priority: .utility) {
                            (item.0.id, PhotoFingerprint.read(item.0.url).map { Record(size: item.1, modified: item.2, print: $0) })
                        }
                    }
                    for _ in 0..<4 { if let next = iterator.next() { add(next) } }
                    while let result = await group.next() {
                        results.append(result)
                        if let next = iterator.next() { add(next) }
                    }
                    return results
                }
                for (id, record) in read { if let record { fresh[id] = record } }
                self.progress = (min(stale.count, start + chunk.count), stale.count)
            }
            self.cache.merge(fresh) { $1 }
            let items = photos.compactMap { entry in
                self.cache[entry.id].map { SimilarPhotos.Item(id: entry.id, folder: entry.url.deletingLastPathComponent().path, print: $0.print) }
            }
            let cache = self.cache, file = self.file
            let groups = await Task.detached(priority: .utility) { () -> [PhotoGroup] in
                if !fresh.isEmpty, let data = try? JSONEncoder().encode(cache) { try? data.write(to: file, options: .atomic) }
                return SimilarPhotos.groups(items)
            }.value
            guard !Task.isCancelled else { return }
            self.groups = groups
            self.progress = nil
            self.hasScanned = true
        }
    }

    func capture(_ id: String) -> Date? { cache[id]?.print.captured }
}
