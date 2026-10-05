import Foundation
import MediaCore
import UniformTypeIdentifiers

struct LibraryEntry: Codable, Hashable, Identifiable, Sendable {
    let url: URL
    var favorite = false
    var id: String { url.standardizedFileURL.path }
    var isVideo: Bool { LibraryFiles.isVideo(url) }
}

struct EditorSnapshot: Equatable, Sendable {
    var edits: MediaEdits
    var clip: ClipSettings?
    var hdrPreview: Bool
}

struct BatchChange: Sendable {
    let stamp: SourceStamp
    let companion: SourceStamp?
    let before: EditRecipe
    let after: EditRecipe
}

enum LibraryFiles {
    static let movieExtensions: Set<String> = ["mp4", "mov", "m4v", "mts", "m2ts", "avi"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "webp", "gif", "dng"]
    static func isVideo(_ url: URL) -> Bool {
        movieExtensions.contains(url.pathExtension.lowercased()) || UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
    }
    static func supported(_ url: URL) -> Bool {
        if isVideo(url) || imageExtensions.contains(url.pathExtension.lowercased()) { return true }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
    }
    static func collect(_ folder: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            if supported(url), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { files.append(url) }
            if files.count >= 5000 { break }
        }
        return files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
