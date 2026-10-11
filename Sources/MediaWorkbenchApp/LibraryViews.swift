import AppKit
import MediaCore
import SwiftUI

/// Loads a thumbnail on appear and reloads when the item's recipe changes.
struct ThumbnailImage: View {
    let entry: LibraryEntry
    let store: ThumbnailStore
    var contentMode: ContentMode = .fill
    @UIState private var image: CGImage?

    var body: some View {
        let version = store.version(entry.id)
        ZStack {
            Rectangle().fill(WorkbenchTheme.well)
            if let image = image ?? store.cached(entry.id) {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: entry.isVideo ? "video" : "photo").foregroundStyle(.tertiary)
            }
        }
        .clipped()
        .task(id: "\(version)#\(entry.id)") {
            if let hit = store.cached(entry.id) { image = hit; return }
            image = await store.load(entry)
        }
    }
}

/// Small overlay badges: Live / video length / edited.
struct MediaBadges: View {
    let entry: LibraryEntry
    let store: ThumbnailStore
    var body: some View {
        HStack(spacing: 4) {
            if entry.hasLiveCompanion {
                Label("LIVE", systemImage: "livephoto").labelStyle(.titleAndIcon)
            } else if entry.isVideo {
                if let duration = store.durations[entry.id] { Text(durationLabel(duration)).monospacedDigit() }
                else { Image(systemName: "video.fill") }
            }
            if store.edited.contains(entry.id) { Image(systemName: "slider.horizontal.3").help("已编辑") }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(.black.opacity(0.55), in: Capsule())
    }
}

struct LibraryContextMenu: View {
    let app: AppModel
    let entry: LibraryEntry
    var body: some View {
        if app.library.missing.contains(entry.id) {
            Button("重新定位…") { app.relocate(entry.id) }
        }
        Button("打开编辑") { app.open(entry.id) }
        Divider()
        Menu("评级") {
            ForEach(0...5, id: \.self) { value in
                Button(value == 0 ? "无评级" : String(repeating: "★", count: value)) { app.rate(value) }
            }
        }
        Button("选用") { app.flag(.pick) }
        Button("排除") { app.flag(.reject) }
        Button("取消标记") { app.flag(.none) }
        Divider()
        Button("粘贴调色设置") { app.pasteSettings() }.disabled(!app.hasClipboard)
        Button("同步调色…") { app.sheet = .sync }.disabled(!app.editor.isLoaded || app.library.selection.subtracting([app.library.currentID ?? ""]).isEmpty)
        Button("导出…") { app.exportSelection() }
        Button("拼图 Live…") { app.openCollage() }
        Divider()
        Button("在 Finder 中显示") { app.revealSelection() }
        Button("从素材库移除") { app.removeSelectionFromLibrary() }
    }
}

// MARK: - Sidebar

struct LibrarySidebar: View {
    let app: AppModel
    var library: LibraryModel { app.library }

    var body: some View {
        VStack(spacing: 0) {
            header
            if library.entries.isEmpty {
                emptyState
            } else {
                list
                footer
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("素材库").font(.headline)
                Text("\(library.visible.count)" + (library.filter.isActive ? " / \(library.entries.count)" : ""))
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if app.isImporting { ProgressView().controlSize(.small) }
                Menu {
                    Button("添加照片或视频…") { app.importMedia() }
                    Button("导入文件夹…") { app.importMedia(folders: true) }
                } label: { Image(systemName: "plus").foregroundStyle(.primary) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(.primary)
                    .help("添加素材")
            }
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("搜索文件名", text: Binding(get: { library.filter.search }, set: { library.filter.search = $0 }))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 7).frame(height: 24)
                .background(WorkbenchTheme.well, in: RoundedRectangle(cornerRadius: 6))
                FilterMenu(library: library)
            }
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 30)).foregroundStyle(.tertiary)
            Text("还没有素材").font(.headline)
            Text("导入后，照片和视频会列在这里。也可以把文件直接拖进窗口。")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(20)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(library.visible) { entry in
                        SidebarRow(entry: entry, store: app.thumbnails,
                                   selected: library.selection.contains(entry.id),
                                   current: entry.id == library.currentID,
                                   missing: library.missing.contains(entry.id))
                            .id(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture { click(entry) }
                            .contextMenu { LibraryContextMenu(app: app, entry: entry) }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .onChange(of: library.currentID) { _, id in
                if let id { withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) } }
            }
            .onChange(of: library.anchorID) { _, id in
                if let id, app.mode == .browse { proxy.scrollTo(id) }
            }
        }
    }

    private func click(_ entry: LibraryEntry) {
        endTextEditing()
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { app.open(entry.id); return }
        let flags = NSEvent.modifierFlags
        let command = flags.contains(.command), shift = flags.contains(.shift)
        library.click(entry.id, command: command, shift: shift)
        // In the editor a plain click switches photos, like Lightroom's filmstrip.
        if app.mode == .edit, !command, !shift { app.open(entry.id) }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(library.selection.count > 1 ? "已选 \(library.selection.count) 项" : "⌘/⇧ 点按多选")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Menu {
                LibraryContextMenu(app: app, entry: library.entry(library.anchorID) ?? library.visible[0])
            } label: { Text("操作").foregroundStyle(.primary) }
                .menuStyle(.borderlessButton).fixedSize().tint(.primary)
                .disabled(library.selection.isEmpty)
        }
        .padding(.horizontal, 12).frame(height: 34)
        .overlay(alignment: .top) { WorkbenchTheme.hairline.frame(height: 1) }
    }
}

struct SidebarRow: View {
    let entry: LibraryEntry
    let store: ThumbnailStore
    let selected: Bool
    let current: Bool
    var missing = false

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailImage(entry: entry, store: store)
                .frame(width: 58, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .bottomTrailing) {
                    if entry.isVideo || entry.hasLiveCompanion {
                        Image(systemName: entry.hasLiveCompanion ? "livephoto" : "video.fill")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                            .padding(2).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 3)).padding(2)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.callout).lineLimit(1).truncationMode(.middle)
                if missing {
                    Label("找不到原文件", systemImage: "questionmark.folder")
                        .font(.caption).foregroundStyle(.orange).labelStyle(.titleAndIcon)
                } else {
                HStack(spacing: 5) {
                    FlagBadge(flag: entry.flag).font(.system(size: 10))
                    if entry.rating > 0 { RatingStars(rating: entry.rating) }
                    if store.edited.contains(entry.id) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 11)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(current ? WorkbenchTheme.selection : selected ? Color.white.opacity(0.07) : .clear)
        }
        .overlay {
            if current { RoundedRectangle(cornerRadius: 7).strokeBorder(WorkbenchTheme.selectionStroke, lineWidth: 1) }
        }
        .opacity(entry.flag == .reject ? 0.5 : 1)
    }
}

struct FilterMenu: View {
    let library: LibraryModel
    var body: some View {
        Menu {
            Picker("类型", selection: Binding(get: { library.filter.kind }, set: { library.filter.kind = $0 })) {
                ForEach(LibraryFilter.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("评级", selection: Binding(get: { library.filter.minimumRating }, set: { library.filter.minimumRating = $0 })) {
                Text("全部评级").tag(0)
                ForEach(1...5, id: \.self) { Text("≥ " + String(repeating: "★", count: $0)).tag($0) }
            }
            Picker("标记", selection: Binding(get: { library.filter.flags }, set: { library.filter.flags = $0 })) {
                ForEach(LibraryFilter.Flags.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Divider()
            Button("清除筛选") { library.filter = LibraryFilter() }.disabled(!library.filter.isActive)
        } label: {
            Image(systemName: library.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundStyle(library.filter.isActive ? WorkbenchTheme.accent : .secondary)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("筛选：类型、评级、选用 / 排除")
    }
}

// MARK: - Browse grid

struct BrowseGrid: View {
    let app: AppModel
    @AppStorage("grid.cellWidth") private var cellWidth = 190.0
    var library: LibraryModel { app.library }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if library.visible.isEmpty {
                empty
            } else {
                GeometryReader { geometry in
                    let spacing = 10.0
                    let columns = max(1, Int((geometry.size.width - 24 + spacing) / (cellWidth + spacing)))
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns), spacing: spacing) {
                                ForEach(library.visible) { entry in
                                    GridCell(entry: entry, store: app.thumbnails,
                                             selected: library.selection.contains(entry.id),
                                             current: entry.id == library.currentID,
                                             missing: library.missing.contains(entry.id))
                                        .id(entry.id)
                                        .onTapGesture {
                                            // One handler (no double-tap recognizer) keeps single clicks instant.
                                            endTextEditing()
                                            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { app.open(entry.id); return }
                                            let flags = NSEvent.modifierFlags
                                            library.click(entry.id, command: flags.contains(.command), shift: flags.contains(.shift))
                                        }
                                        .contextMenu { LibraryContextMenu(app: app, entry: entry) }
                                }
                            }
                            .padding(12)
                        }
                        .onChange(of: library.anchorID) { _, id in if let id { proxy.scrollTo(id) } }
                        .onAppear {
                            app.gridColumns = columns
                            if let id = library.currentID ?? library.anchorID { proxy.scrollTo(id, anchor: .center) }
                        }
                        .onChange(of: columns) { _, value in app.gridColumns = value }
                    }
                }
            }
        }
        .background(WorkbenchTheme.canvas)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(library.filter.isActive ? "筛选结果 \(library.visible.count) 项" : "全部 \(library.entries.count) 项")
                .font(.callout).foregroundStyle(.secondary)
            if library.filter.isActive {
                Button("清除筛选") { library.filter = LibraryFilter() }.buttonStyle(.borderless).font(.callout)
            }
            Spacer()
            Image(systemName: "square.grid.3x3").foregroundStyle(.tertiary)
            Slider(value: $cellWidth, in: 130...360).frame(width: 110).controlSize(.small).help("缩略图大小")
            Image(systemName: "square.grid.2x2").foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).frame(height: 36)
        .overlay(alignment: .bottom) { WorkbenchTheme.hairline.frame(height: 1) }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            BrandEmptyIllustration().frame(width: 240, height: 160)
            if library.entries.isEmpty {
                Text("让每一个瞬间，自有光彩。").font(.title2.weight(.medium))
                Text("导入照片、视频或 Live Photo 文件夹，开始浏览、评级与调色。").foregroundStyle(.secondary)
                HStack {
                    Button("导入文件夹…") { app.importMedia(folders: true) }.primaryButton()
                    Button("添加文件…") { app.importMedia() }.glassButton()
                }
            } else {
                Text("没有符合筛选条件的素材").font(.title3)
                Button("清除筛选") { library.filter = LibraryFilter() }.glassButton()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GridCell: View {
    let entry: LibraryEntry
    let store: ThumbnailStore
    let selected: Bool
    let current: Bool
    var missing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailImage(entry: entry, store: store, contentMode: .fit)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottomTrailing) {
                    if entry.isVideo || entry.hasLiveCompanion || store.edited.contains(entry.id) {
                        MediaBadges(entry: entry, store: store).padding(6)
                    }
                }
                .overlay(alignment: .topLeading) { FlagBadge(flag: entry.flag).font(.system(size: 13)).padding(6) }
                .overlay {
                    if missing {
                        VStack(spacing: 4) {
                            Image(systemName: "questionmark.folder").font(.system(size: 20)).foregroundStyle(.orange)
                            Text("找不到原文件").font(.caption.weight(.medium))
                            Text("右键可重新定位").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            HStack(spacing: 4) {
                Text(entry.name).font(.callout).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 2)
                if entry.rating > 0 { RatingStars(rating: entry.rating, size: 9) }
            }
            .padding(.horizontal, 2)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 9).fill(selected ? WorkbenchTheme.selection : Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.white.opacity(0.85) : current ? WorkbenchTheme.selectionStroke : .clear, lineWidth: selected ? 2 : 1))
        .opacity(entry.flag == .reject ? 0.45 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
