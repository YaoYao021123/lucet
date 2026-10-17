import AppKit
import Foundation
import MediaCore
import Observation
import Photos
import SwiftUI

/// Reads the user's Photos library (iCloud Photos included) and copies originals into the
/// app's own folder, so they can be browsed and edited like any other file. Photos itself is never changed.
enum PhotosImporter {
    struct Album: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let count: Int
    }

    static let allPhotosID = "all"

    static func authorize() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// "All photos", then the useful smart albums, then the user's own albums.
    static func albums() -> [Album] {
        var result: [Album] = []
        let all = PHAsset.fetchAssets(with: nil)
        result.append(Album(id: allPhotosID, title: L("全部照片"), count: all.count))
        let smartTypes: [PHAssetCollectionSubtype] = [.smartAlbumFavorites, .smartAlbumSelfPortraits, .smartAlbumScreenshots,
                                                      .smartAlbumLivePhotos, .smartAlbumVideos, .smartAlbumPanoramas]
        for type in smartTypes {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: type, options: nil).enumerateObjects { collection, _, _ in
                let count = PHAsset.fetchAssets(in: collection, options: nil).count
                if count > 0 { result.append(Album(id: collection.localIdentifier, title: collection.localizedTitle ?? "", count: count)) }
            }
        }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil).enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            if count > 0 { result.append(Album(id: collection.localIdentifier, title: collection.localizedTitle ?? "", count: count)) }
        }
        return result
    }

    static func assets(in albumID: String, newest limit: Int?) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let limit { options.fetchLimit = limit }
        let fetched: PHFetchResult<PHAsset>
        if albumID == allPhotosID {
            fetched = PHAsset.fetchAssets(with: options)
        } else if let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject {
            fetched = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            return []
        }
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    static var folder: URL { AppPaths.dataRoot.appendingPathComponent("PhotosImport", isDirectory: true) }

    /// Copies one asset's original (downloading it from iCloud if needed). Live Photos also bring
    /// their motion part, named alike so the library folds them into one item. Returns the still/video file.
    static func export(_ asset: PHAsset) async throws -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        let main = resources.first { $0.type == .photo && asset.mediaType == .image }
            ?? resources.first { $0.type == .video && asset.mediaType == .video }
            ?? resources.first { $0.type == .fullSizePhoto }
        guard let main else { return nil }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The identifier prefix keeps IMG_0001 from different years apart and makes re-imports idempotent.
        let prefix = asset.localIdentifier.split(separator: "/").first.map { String($0.prefix(8)) } ?? UUID().uuidString.prefix(8).description
        let base = "\(prefix)-\((main.originalFilename as NSString).deletingPathExtension)"
        let target = folder.appendingPathComponent(base).appendingPathExtension((main.originalFilename as NSString).pathExtension)
        try await write(main, to: target)
        if let paired = resources.first(where: { $0.type == .pairedVideo }) {
            try await write(paired, to: folder.appendingPathComponent(base).appendingPathExtension("mov"))
        }
        return target
    }

    private static func write(_ resource: PHAssetResource, to url: URL) async throws {
        if FileManager.default.fileExists(atPath: url.path) { return }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let partial = url.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partial)
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: partial, options: options)
        try FileManager.default.moveItem(at: partial, to: url)
    }
}

@MainActor
@Observable
final class PhotosImportModel {
    enum Phase: Equatable {
        case loading
        case denied
        case ready
        case importing(done: Int, total: Int)
    }

    enum Amount: Int, CaseIterable, Identifiable {
        case latest100 = 100, latest500 = 500, latest2000 = 2000, everything = 0
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .latest100: L("最新 100 张")
            case .latest500: L("最新 500 张")
            case .latest2000: L("最新 2000 张")
            case .everything: L("全部")
            }
        }
    }

    private(set) var phase = Phase.loading
    private(set) var albums: [PhotosImporter.Album] = []
    var albumID = PhotosImporter.allPhotosID
    var amount = Amount.latest100
    private(set) var failed = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    func load() async {
        guard await PhotosImporter.authorize() else { phase = .denied; return }
        albums = PhotosImporter.albums()
        phase = .ready
    }

    var selectedAlbum: PhotosImporter.Album? { albums.first { $0.id == albumID } }
    var plannedCount: Int {
        guard let album = selectedAlbum else { return 0 }
        return amount == .everything ? album.count : min(album.count, amount.rawValue)
    }

    func start(into app: AppModel, finished: @escaping () -> Void) {
        let assets = PhotosImporter.assets(in: albumID, newest: amount == .everything ? nil : amount.rawValue)
        guard !assets.isEmpty else { return }
        failed = 0
        phase = .importing(done: 0, total: assets.count)
        task = Task {
            var files: [URL] = []
            var live: Set<String> = []
            for (index, asset) in assets.enumerated() {
                if Task.isCancelled { break }
                do {
                    if let url = try await PhotosImporter.export(asset) {
                        files.append(url)
                        if asset.mediaSubtypes.contains(.photoLive) { live.insert(url.standardizedFileURL.path) }
                    }
                } catch { failed += 1 }
                phase = .importing(done: index + 1, total: assets.count)
            }
            let ids = app.library.add(files, liveCompanions: live)
            app.library.filter = LibraryFilter()
            if let first = ids.first { app.library.select(first) }
            app.mode = .browse
            var message = L("已从「照片」读入 \(ids.count) 项。")
            if failed > 0 { message += L("有 \(failed) 项没能读取（可能还在 iCloud 上，或网络中断）。") }
            app.show(message)
            finished()
        }
    }

    func cancel() { task?.cancel() }
}

struct PhotosImportSheet: View {
    let app: AppModel
    @UIState private var model = PhotosImportModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("从「照片」导入").font(.title3.weight(.semibold))
                Text("读取你的「照片」图库（包括 iCloud 照片），把原图复制一份到光集里编辑。「照片」里的内容不会被改动或删除。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            switch model.phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            case .denied:
                Text("光集没有读取「照片」的权限。请在 系统设置 › 隐私与安全性 › 照片 中允许光集。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("打开系统设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") { NSWorkspace.shared.open(url) }
                    }.glassButton()
                    Button("关闭") { app.sheet = nil }.primaryButton()
                }
            case .ready:
                Picker("相簿", selection: $model.albumID) {
                    ForEach(model.albums) { album in Text(verbatim: "\(album.title) (\(album.count))").tag(album.id) }
                }
                Picker("数量", selection: $model.amount) {
                    ForEach(PhotosImportModel.Amount.allCases) { Text($0.title).tag($0) }
                }
                Text("iCloud 里的原图会先下载到这台 Mac，数量多时需要一些时间和空间。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("取消") { app.sheet = nil }.glassButton()
                    Button("导入 \(model.plannedCount) 项") { model.start(into: app) { app.sheet = nil } }
                        .primaryButton().disabled(model.plannedCount == 0)
                }
            case .importing(let done, let total):
                ProgressView(value: Double(done), total: Double(max(1, total)))
                Text("正在读取 \(done) / \(total)…").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                HStack {
                    Spacer()
                    Button("停止") { model.cancel() }.glassButton()
                }
            }
        }
        .padding(22)
        .frame(width: 440)
        .task { await model.load() }
    }
}
