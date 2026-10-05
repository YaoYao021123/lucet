import AppKit
import AVFoundation
import CoreImage
import MediaCore
import Observation
import Photos
import UniformTypeIdentifiers

@MainActor
@Observable
final class WorkbenchModel {
    var url: URL?
    var metadata: MediaMetadata?
    var frame: GradeFrame?
    var player: AVPlayer?
    var livePhoto: PHLivePhoto?
    var exportedLive: LivePhotoResources?
    var liveInput = false
    var geometry = GeometryAdjustments() { didSet { if geometry != oldValue { updatePreview() } } }
    var adjustments = BasicAdjustments() { didSet { if adjustments != oldValue { updatePreview() } } }
    var degrees: Double = 0 { didSet { if degrees != oldValue { updatePreview() } } }
    var selectedLUT: CreativeLUT? { didSet { if selectedLUT?.id != oldValue?.id { updatePreview() } } }
    var importedLUT: CreativeLUT?
    var strength: Double = 1 { didSet { if strength != oldValue { updatePreview() } } }
    var hdrPreview = true { didSet { if hdrPreview != oldValue { updatePreview() } } }
    var hdrEffect = false { didSet { if hdrEffect != oldValue { updatePreview() } } }
    var screenHeadroom: CGFloat = 1
    var comparing = false { didSet { if isVideo { updatePreview() } else { refreshHistogram() } } }
    var grid = false
    var library: [LibraryEntry] = []
    var selectedSources: Set<String> = []
    var showFavorites = false
    var showingSync = false
    var showingSnapshots = false
    var showingCollage = false
    var collageDrafts: [CollageDraftPane] = []
    var savedSnapshots: [SavedSnapshot] = []
    var snapshotName = ""
    var history: EditHistory<EditorSnapshot>?
    var lastBatch: [BatchChange] = []
    var histogram: PreviewHistogram?
    var histogramLabel = "SDR 显示直方图"
    @ObservationIgnored private var histogramTask: Task<Void, Never>?
    var draftStatus = "原片保留"
    var exportProgress: Double?
    var canCancel = false
    @ObservationIgnored private var applyingSnapshot = false
    @ObservationIgnored private var recipeNotice: String?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var sourceStamp: SourceStamp?
    @ObservationIgnored private var companionStamp: SourceStamp?
    @ObservationIgnored private var lutReferences: [UUID: LUTReference] = [:]
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    private let drafts = DraftStore(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Guangji"))
    var busy = false
    var message = "打开图片、视频或 Live Photo，开始编辑。"
    var assessment: StraighteningAssessment?
    var clipStart = 0.0
    var clipEnd = 0.0
    var cover = 0.0
    var position = 0.0
    var playing = false
    var playbackSpeed: Double = 1 { didSet { if playbackSpeed != oldValue { updatePreview() } } }
    @ObservationIgnored private var appliedPlaybackSpeed = 1.0
    @ObservationIgnored private var videoPreviewState: VideoPreviewState?
    @ObservationIgnored private var appliedPreviewKey: PreviewKey?
    @ObservationIgnored private var appliedOriginalVolume: Float = 1
    @ObservationIgnored private var appliedMusicVolume: Float = 0.5
    @ObservationIgnored private var editingSpeed = false
    @ObservationIgnored private var seekTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSeek: (value: Double, exact: Bool)?
    @ObservationIgnored private var seekGeneration = UUID()

    private struct PreviewKey: Equatable {
        let start: Double
        let end: Double
        let speed: Double
        let music: URL?
        let sdr: Bool
        let hdrEffect: Bool
    }
    private var previewKey: PreviewKey {
        PreviewKey(start: clipStart, end: clipEnd, speed: playbackSpeed,
                   music: musicURL, sdr: videoSDR, hdrEffect: !comparing && hdrEffect)
    }
    var thumbnails: [CGImage] = []
    var thumbnailsLoading = false
    var thumbnailNotice: String?
    var originalVolume: Float = 1 { didSet { if originalVolume != oldValue { updatePreview() } } }
    var musicURL: URL? { didSet { if musicURL != oldValue { updatePreview() } } }
    var musicVolume: Float = 0.5 { didSet { if musicVolume != oldValue { updatePreview() } } }
    @ObservationIgnored private var mediaURL: URL?
    @ObservationIgnored private var accessURLs: [URL] = []
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var exportGeneration = UUID()
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var imageSession: ImageGradeSession?
    @ObservationIgnored private var analysisCache: StraighteningAssessment?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?

    var isVideo: Bool { metadata?.kind == .video }
    var loaded: Bool { frame != nil || player != nil }
    var duration: Double { metadata?.durationSeconds ?? 0 }
    var sourceHDR: Bool {
        if let frame { return frame.sourceHeadroom > 1 }
        return metadata?.transferFunction == AVVideoTransferFunction_ITU_R_2100_HLG || metadata?.transferFunction == AVVideoTransferFunction_SMPTE_ST_2084_PQ
    }
    var edits: MediaEdits { MediaEdits(degrees: degrees, lut: selectedLUT, strength: strength, hdrEffect: isVideo && hdrEffect, adjustments: adjustments, geometry: geometry) }
    var clip: ClipSettings { ClipSettings(start: clipStart, end: clipEnd, cover: cover,
        originalVolume: originalVolume, musicURL: musicURL, musicVolume: musicVolume, speed: playbackSpeed) }
    var videoSDR: Bool { if !comparing && hdrEffect { return false }; return !hdrPreview || (!comparing && (edits.hasLUT || edits.hasAdjustments || edits.hasGeometry)) }
    var previewLabel: String {
        guard loaded else { return "" }
        if isVideo, !comparing, hdrEffect { return "HDR 效果 · HLG" }
        if !sourceHDR { return "SDR" }
        if isVideo { return videoSDR ? "SDR 预览" : "HDR 原片" }
        if !comparing && (edits.hasLUT || edits.hasAdjustments) { return "调色 · SDR 预览" }
        return hdrPreview && screenHeadroom > 1 ? "HDR · EDR 画布" : "HDR → SDR 预览"
    }
    var lutChoice: String {
        get { selectedLUT?.id.uuidString ?? "none" }
        set {
            let choices = [CreativeLUT.warm, .soft] + (importedLUT.map { [$0] } ?? [])
            selectedLUT = choices.first { $0.id.uuidString == newValue }
        }
    }

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie, .mpeg4Movie, .quickTimeMovie]
        // Third-party players can register nonconforming file types for standard video extensions.
        panel.allowsOtherFileTypes = true; panel.allowsMultipleSelection = true
        present(panel) { [weak self] selected in
            if selected != nil { self?.addSources(panel.urls) }
        }
    }

    /// A window-attached asynchronous sheet avoids nested modal run loops and
    /// makes repeated clicks harmless while the file picker is on screen.
    private func present(_ panel: NSSavePanel, completion: @escaping @MainActor (URL?) -> Void) {
        guard !busy else { return }
        busy = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self, panel] response in
            self?.busy = false
            completion(response == .OK ? panel.url : nil)
        }
        if let window = NSApplication.shared.mainWindow ?? NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "workbench" && $0.isVisible }) {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else { panel.begin(completionHandler: handler) }
    }

    func load(_ selected: URL) {
        flushDraft(); saveTask?.cancel(); saveTask = nil
        applyingSnapshot = true; history = nil; sourceStamp = nil; companionStamp = nil
        histogramTask?.cancel(); histogramTask = nil; histogram = nil
        operation?.cancel(); previewTask?.cancel(); previewTask = nil; thumbnailTask?.cancel()
        thumbnails = []; thumbnailsLoading = false; thumbnailNotice = nil
        session = UUID(); imageSession = nil; mediaURL = nil
        seekTask?.cancel(); seekTask = nil; pendingSeek = nil; seekGeneration = UUID()
        videoPreviewState = nil; appliedPreviewKey = nil; editingSpeed = false
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil; statusObserver = nil
        for file in accessURLs { file.stopAccessingSecurityScopedResource() }; accessURLs.removeAll()
        if selected.startAccessingSecurityScopedResource() { accessURLs.append(selected) }
        url = selected; metadata = nil; frame = nil; player = nil; livePhoto = nil; exportedLive = nil
        adjustments = .init(); geometry = .init(); degrees = 0; selectedLUT = nil; strength = 1; comparing = false
        musicURL = nil; originalVolume = 1; musicVolume = 0.5
        playbackSpeed = 1; appliedPlaybackSpeed = 1
        hdrEffect = false
        assessment = nil; analysisCache = nil; playing = false; position = 0; liveInput = false
        busy = true; message = "正在读取素材…"; draftStatus = "正在读取配方…"
        applyingSnapshot = false
        let token = session
        operation = Task {
            do {
                var input = selected
                var importNotice: String?
                var liveCover: Double?
                let info = try await MediaInspector.inspect(selected)
                if info.kind == .image, let pair = try await LivePhotoPipeline.pairedMovie(for: selected) {
                    do {
                        _ = try await LivePhotoPipeline.load(imageURL: selected, videoURL: pair)
                        liveCover = try await LivePhotoPipeline.coverTime(in: pair)
                        input = pair
                        if pair.startAccessingSecurityScopedResource() { accessURLs.append(pair) }
                        liveInput = true
                    } catch { importNotice = "Live 配对未通过系统检查，先打开静态图片。" }
                }
                let meta = input == selected ? info : try await MediaInspector.inspect(input)
                guard session == token, !Task.isCancelled else { return }
                mediaURL = input; metadata = meta
                if meta.kind == .image {
                    let renderer = try await Task.detached(priority: .userInitiated) { [input] in try ImageGradeSession(url: input) }.value
                    let first = try await renderer.frame(edits: .init())
                    guard session == token, !Task.isCancelled else { return }
                    imageSession = renderer; frame = first
                } else {
                    guard let seconds = meta.durationSeconds, seconds >= 0.1 else { throw VideoWorkError.invalidRange }
                    clipStart = 0; clipEnd = seconds; cover = min(seconds / 2, max(0, seconds - 0.05))
                    if let liveCover { cover = min(max(0, liveCover), max(0, seconds - 0.05)) }
                    let prepared = try await VideoPipeline.prepare(input, clip: clip, edits: .init(), sdr: false)
                    guard session == token, !Task.isCancelled else { return }
                    let item = AVPlayerItem(asset: prepared.asset); item.audioMix = prepared.audioMix
                    let playback = AVPlayer(playerItem: item); player = playback
                    appliedPreviewKey = previewKey
                    appliedOriginalVolume = originalVolume; appliedMusicVolume = musicVolume
                    observe(item)
                    if liveInput {
                        await playback.seek(to: CMTime(seconds: cover, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        position = cover
                    }
                    timeObserver = playback.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self = self] time in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            if self.seekTask == nil {
                                self.position = max(0, time.seconds * self.appliedPlaybackSpeed)
                            }
                            if playback.rate == 0 { self.playing = false }
                        }
                    }
                }
                sourceStamp = try SourceStamp(selected)
                companionStamp = input == selected ? nil : try SourceStamp(input)
                var restored = false
                do {
                    if let recipe = try drafts.load(selected) {
                        try restoreRecipe(recipe); restored = true
                        if let recipeNotice { importNotice = recipeNotice }
                    }
                    draftStatus = restored ? "配方已恢复" : "配方自动保存"
                } catch { draftStatus = "旧配方未载入"; importNotice = error.localizedDescription }
                history = EditHistory(snapshot)
                message = importNotice ?? (restored ? "已恢复这份素材的调色与片段配方。" : liveInput ? "已识别 Live 配对。重制封面来自动态视频，原静态图片保留。" : "调整 LUT、角度，或选取视频片段制作 Live。")
            } catch { if session == token { message = error.localizedDescription } }
            if session == token {
                busy = false
                if loaded { loadThumbnails(token: token); updatePreview() }
            }
        }
    }

    private func loadThumbnails(token: UUID) {
        guard let input = mediaURL else { return }
        thumbnailsLoading = true
        let sourceFrame = frame, seconds = duration
        thumbnailTask = Task {
            do {
                let images: [CGImage]
                if let sourceFrame {
                    images = try await Task.detached(priority: .utility) { [try MediaThumbnails.image(sourceFrame)] }.value
                } else { images = try await MediaThumbnails.video(input, duration: seconds) }
                guard token == session, !Task.isCancelled else { return }
                thumbnails = images
            } catch {
                if token == session, !Task.isCancelled { thumbnailNotice = "缩略图暂不可用，仍可调整片段。" }
            }
            if token == session { thumbnailsLoading = false }
        }
    }

    private func observe(_ item: AVPlayerItem) {
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let description = item.error?.localizedDescription ?? "视频预览失败。"
            Task { @MainActor [weak self] in self?.message = description }
        }
    }

    func updatePreview() {
        revision += 1
        guard !applyingSnapshot else { return }
        if loaded, !busy { history?.record(snapshot); scheduleDraft() }
        guard loaded, !busy, !editingSpeed, let input = mediaURL else { return }
        if message.hasPrefix("已载入"), selectedLUT?.id != importedLUT?.id {
            message = "已切换至 \(selectedLUT?.name ?? "原片")。"
        }
        guard previewTask == nil else { return }
        let token = session
        previewTask = Task {
            do {
                while session == token, !Task.isCancelled {
                    guard !editingSpeed else { break }
                    let version = revision
                    let settings = edits
                    let rangeSettings = clip
                    if let renderer = imageSession {
                        let next = try await renderer.frame(edits: settings)
                        guard session == token, !Task.isCancelled else { return }
                        frame = next
                    } else if let player {
                        let key = previewKey
                        let visibleEdits: MediaEdits = comparing ? .init() : settings
                        if appliedPreviewKey == key, let item = player.currentItem {
                            videoPreviewState?.update(visibleEdits)
                            if appliedOriginalVolume != originalVolume || appliedMusicVolume != musicVolume {
                                let mix = AVMutableAudioMix()
                                let inputs = item.audioMix?.inputParameters ?? []
                                mix.inputParameters = inputs.enumerated().map { index, input in
                                    let parameter = AVMutableAudioMixInputParameters()
                                    parameter.trackID = input.trackID
                                    let music = musicURL != nil && index == inputs.count - 1
                                    parameter.setVolume(music ? musicVolume : originalVolume, at: .zero)
                                    return parameter
                                }
                                item.audioMix = mix
                                appliedOriginalVolume = originalVolume; appliedMusicVolume = musicVolume
                            }
                            if let composition = item.videoComposition, !playing {
                                // Apple QA1966: a new composition instance redraws
                                // a paused frame without tearing down the decoder.
                                item.videoComposition = composition.mutableCopy() as? AVVideoComposition
                            }
                            break
                        }
                        let wasPlaying = playing
                        let oldPosition = position
                        let state = VideoPreviewState(edits: visibleEdits)
                        let prepared = try await VideoPipeline.prepare(input, clip: rangeSettings,
                            edits: visibleEdits, sdr: key.sdr, preview: state)
                        guard session == token, !Task.isCancelled else { return }
                        // Skip obsolete compositions; never queue one item per tick.
                        if version == revision {
                            let item = AVPlayerItem(asset: prepared.asset)
                            item.videoComposition = prepared.videoComposition; item.audioMix = prepared.audioMix
                            item.audioTimePitchAlgorithm = .spectral
                            appliedPlaybackSpeed = rangeSettings.speed
                            videoPreviewState = state; appliedPreviewKey = key
                            appliedOriginalVolume = rangeSettings.originalVolume; appliedMusicVolume = rangeSettings.musicVolume
                            seekTask?.cancel(); seekTask = nil; pendingSeek = nil; seekGeneration = UUID()
                            player.currentItem?.cancelPendingSeeks()
                            player.replaceCurrentItem(with: item); observe(item)
                            await player.seek(to: CMTime(seconds: min(oldPosition / rangeSettings.speed, max(0, prepared.duration - 0.05)), preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
                            if wasPlaying { player.play(); playing = true }
                        }
                    }
                    if version == revision { break }
                }
            } catch is CancellationError { }
            catch { if session == token { message = error.localizedDescription } }
            if session == token { previewTask = nil; refreshHistogram() }
        }
    }

    func importLUT() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "cube") ?? .plainText]
        present(panel) { [weak self] selected in
            if let selected { self?.readLUT(selected) }
        }
    }
    func setImportedLUTEncoding(_ encoding: LUTEncoding) {
        guard let previous = importedLUT, previous.encoding != encoding else { return }
        let active = selectedLUT?.id == previous.id
        let next = CreativeLUT(cube: previous.cube, name: previous.name, encoding: encoding)
        importedLUT = next
        if active { selectedLUT = next }
        message = "已载入 \(next.name)，按 \(encoding.rawValue) 创意 LUT 处理。Log 输入需先完成相机色彩转换。"
    }
    private func readLUT(_ selected: URL) {
        let token = session
        busy = true; message = "正在读取 LUT…"
        operation = Task {
            do {
                let lut = try await Task.detached(priority: .userInitiated) {
                    let access = selected.startAccessingSecurityScopedResource()
                    defer { if access { selected.stopAccessingSecurityScopedResource() } }
                    let attributes = try FileManager.default.attributesOfItem(atPath: selected.path)
                    guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 100_000_000 else { throw VideoWorkError.failed("LUT 超过 100 MB") }
                    let cube = try CubeLUT(text: String(contentsOf: selected, encoding: .utf8))
                    return CreativeLUT(cube: cube, name: cube.title ?? selected.deletingPathExtension().lastPathComponent)
                }.value
                guard token == session else { return }
                importedLUT = lut; selectedLUT = lut
                message = "已载入 \(lut.name)，按 sRGB 创意 LUT 处理。Log 输入请先完成相机色彩转换。"
            } catch { if token == session { message = error.localizedDescription } }
            if token == session { busy = false; updatePreview() }
        }
    }

    func autoStraighten() {
        guard let input = mediaURL, !isVideo, loaded, !busy else { return }
        if let result = analysisCache { apply(result); return }
        let token = session; busy = true; message = "正在识别地平线…"
        operation = Task {
            do {
                let result = try await ImageStraightener.analyze(input)
                guard session == token else { return }
                analysisCache = result; apply(result)
            } catch is CancellationError { if session == token { message = "已取消，原片保留。" } }
            catch { if session == token { message = Task.isCancelled ? "已取消，原片保留。" : error.localizedDescription } }
            if session == token { busy = false; canCancel = false; exportProgress = nil; updatePreview() }
        }
    }
    private func apply(_ result: StraighteningAssessment) {
        assessment = result; message = result.message
        if let plan = result.plan { degrees = plan.rotationDegrees }
    }
    func reset() {
        beginEditing(true)
        adjustments = .init(); geometry = .init(); degrees = 0; selectedLUT = nil; strength = 1; comparing = false; assessment = nil; hdrEffect = false
        beginEditing(false)
        message = "已恢复原片画面，可撤销。"
    }
    func setStart(_ value: Double) {
        clipStart = min(max(0, value), clipEnd - 0.1)
        cover = min(max(cover, clipStart), clipEnd - 0.05)
        position = 0; updatePreview()
    }
    func setEnd(_ value: Double) {
        clipEnd = max(clipStart + 0.1, min(duration, value))
        cover = min(max(cover, clipStart), clipEnd - 0.05)
        position = min(position, clipEnd - clipStart - 0.05); updatePreview()
    }
    /// Commit both trim handles once, after dragging ends. Keep source time stable.
    func setRange(start: Double, end: Double) {
        guard !busy, duration >= 0.1 else { return }
        let absolutePosition = clipStart + position
        player?.pause(); playing = false
        clipStart = min(max(0, start), duration - 0.1)
        clipEnd = min(duration, max(clipStart + 0.1, end))
        cover = min(max(cover, clipStart), clipEnd - 0.05)
        position = min(max(0, absolutePosition - clipStart), clipEnd - clipStart - 0.05)
        updatePreview()
    }
    func moveCover(to seconds: Double, exact: Bool = true) {
        guard !busy else { return }
        cover = min(max(seconds, clipStart), clipEnd - 0.05)
        scrubSeek(cover - clipStart, exact: exact)
        if exact { history?.record(snapshot); scheduleDraft() }
    }
    func moveRange(by delta: Double) {
        guard !busy else { return }
        let next = clip.shifted(by: delta, duration: duration)
        let relativePosition = position
        player?.pause(); playing = false
        clipStart = next.start; clipEnd = next.end; cover = next.cover
        position = min(relativePosition, max(0, next.sourceDuration - 0.05))
        updatePreview()
    }
    func fitLiveSpeed() {
        guard !busy else { return }
        playbackSpeed = min(4, max(0.5, (clipEnd - clipStart) / 3))
        message = clip.outputDuration <= 3.001 ? "已压缩为 3 秒 Live，原片保留。" : "当前范围过长；4× 速度下仍超过 3 秒，请缩短选取范围。"
    }
    func stepFrame(_ direction: Double) {
        let rate = Double(metadata?.nominalFrameRate ?? 30)
        seek(min(max(0, position + direction / max(1, rate)), max(0, clipEnd - clipStart - 0.01)))
    }
    func liveRange() {
        guard !busy else { return }
        let center = min(duration - 0.05, max(0, clipStart + position))
        let length = 3 * playbackSpeed
        clipStart = max(0, center - length / 2); clipEnd = min(duration, clipStart + length)
        clipStart = max(0, clipEnd - length); cover = min(max(center, clipStart), clipEnd - 0.05)
        position = cover - clipStart; updatePreview()
    }
    func setCover() { cover = min(clipEnd - 0.05, max(clipStart, clipStart + position)); history?.record(snapshot); scheduleDraft() }
    func speedEditingChanged(_ editing: Bool) {
        editingSpeed = editing
        beginEditing(editing)
        if !editing { updatePreview() }
    }
    func seek(_ value: Double) { scrubSeek(value, exact: true) }
    func scrubSeek(_ value: Double, exact: Bool = false) {
        player?.pause(); playing = false
        position = min(max(0, value), max(0, clipEnd - clipStart - 0.01))
        pendingSeek = (position, exact)
        guard seekTask == nil, let player else { return }
        let token = session
        let generation = seekGeneration
        seekTask = Task {
            while session == token, seekGeneration == generation, !Task.isCancelled, let request = pendingSeek {
                pendingSeek = nil
                let tolerance = request.exact ? CMTime.zero : CMTime(seconds: 1 / 30, preferredTimescale: 60000)
                await player.seek(to: CMTime(seconds: request.value / appliedPlaybackSpeed, preferredTimescale: 60000),
                                  toleranceBefore: tolerance, toleranceAfter: tolerance)
            }
            if session == token, seekGeneration == generation { seekTask = nil }
        }
    }
    func togglePlayback() {
        guard let player else { return }
        if playing { player.pause(); playing = false }
        else {
            if position >= clipEnd - clipStart - 0.05 { seek(0) }
            player.play(); playing = true
        }
    }
    func chooseMusic() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]
        present(panel) { [weak self] selected in
            guard let self, let selected else { return }
            if selected.startAccessingSecurityScopedResource() { self.accessURLs.append(selected) }
            self.musicURL = selected
        }
    }

    func export() {
        guard let input = mediaURL, loaded, !busy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = isVideo ? [.quickTimeMovie] : [.png]
        panel.nameFieldStringValue = input.deletingPathExtension().lastPathComponent + "-编辑." + (isVideo ? "mov" : "png")
        panel.message = hdrEffect && isVideo ? "另存 HDR 效果副本（HEVC 10-bit HLG），保留原片。" : "另存 SDR 副本，保留原片。"
        present(panel) { [weak self] output in
            if let output { self?.saveCopy(input, to: output) }
        }
    }
    private func saveCopy(_ input: URL, to output: URL) {
        let settings = edits, clip = clip, video = isVideo, token = session
        let progressID = UUID(); exportGeneration = progressID
        busy = true; canCancel = true; exportProgress = nil; player?.pause(); playing = false; message = settings.hdrEffect ? "正在导出 HDR 效果副本…" : "正在导出 SDR 副本…"
        operation = Task {
            do {
                if video { try await VideoPipeline.export(input, to: output, clip: clip, edits: settings, progress: { [weak model = self] value in
                    Task { @MainActor in if model?.session == token, model?.exportGeneration == progressID, model?.canCancel == true { model?.exportProgress = value } }
                }) }
                else { try await ColorPipeline.exportPNGAsync(input, to: output, edits: settings) }
                if session == token { message = "已保存 \(output.lastPathComponent) · \(settings.hdrEffect ? "HDR 效果" : "SDR")副本" }
            } catch is CancellationError { if session == token { message = "已取消，原片保留。" } }
            catch { if session == token { message = Task.isCancelled ? "已取消，原片保留。" : error.localizedDescription } }
            if session == token { busy = false; canCancel = false; exportProgress = nil; updatePreview() }
        }
    }
    func exportLive() {
        guard let input = mediaURL, isVideo, !busy else { return }
        do { try clip.validate(duration: duration, live: true) }
        catch { message = "Live 输出需为 0.5–3 秒；可以缩短范围或提高速度。"; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = input.deletingPathExtension().lastPathComponent + "-Live"
        panel.message = hdrEffect ? "创建 HDR 效果 Live 文件夹，包含 HEIC 增益图封面、10-bit HLG 配对 MOV 和参数记录。" : "创建新的 Live 文件夹，包含封面 JPEG、配对 MOV 和参数记录。"
        present(panel) { [weak self] output in
            if let output { self?.saveLive(input, to: output) }
        }
    }
    private func saveLive(_ input: URL, to output: URL) {
        let settings = edits, clip = clip, token = session
        let progressID = UUID(); exportGeneration = progressID
        busy = true; canCancel = true; exportProgress = nil; player?.pause(); playing = false; message = "正在制作并检查 Live Photo…"
        operation = Task {
            do {
                let resources = try await LivePhotoPipeline.export(input, to: output, clip: clip, edits: settings, progress: { [weak model = self] value in
                    Task { @MainActor in if model?.session == token, model?.exportGeneration == progressID, model?.canCancel == true { model?.exportProgress = value } }
                })
                let photo = try await LivePhotoPipeline.load(imageURL: resources.imageURL, videoURL: resources.videoURL)
                guard session == token else { return }
                exportedLive = resources; livePhoto = photo
                message = "已生成 Live Photo · 系统配对检查通过 · \(output.lastPathComponent)"
            } catch is CancellationError { if session == token { message = "已取消，原片保留。" } }
            catch { if session == token { message = Task.isCancelled ? "已取消，原片保留。" : error.localizedDescription } }
            if session == token { busy = false; canCancel = false; exportProgress = nil; updatePreview() }
        }
    }
    func openCollage() {
        guard !busy else { return }
        flushDraft()
        var entries = library.filter { selectedSources.contains($0.id) }
        if entries.isEmpty, let url, let entry = library.first(where: { $0.url == url }) { entries = [entry] }
        guard (1...3).contains(entries.count) else { message = "先在素材栏选择 1–3 个视频或 Live，再打开拼图制作。"; return }
        busy = true; player?.pause(); playing = false
        operation = Task {
            do {
                var items: [CollageDraftPane] = []
                for entry in entries {
                    var input = entry.url
                    var info = try await MediaInspector.inspect(input)
                    if info.kind == .image, let movie = try await LivePhotoPipeline.pairedMovie(for: input) {
                        input = movie; info = try await MediaInspector.inspect(movie)
                    }
                    guard info.kind == .video, let duration = info.durationSeconds, duration >= 1.5 else {
                        throw VideoWorkError.failed("\(entry.url.lastPathComponent)：拼图当前需至少 1.5 秒的视频或 Live 动态资源。")
                    }
                    let recipe = try drafts.load(entry.url) ?? EditRecipe()
                    let lut = try recipe.lut.map { try drafts.loadLUT($0) }
                    let settings = MediaEdits(degrees: recipe.degrees, lut: lut, strength: recipe.strength,
                        adjustments: recipe.adjustments, geometry: recipe.geometry)
                    let speed = min(recipe.clip?.speed ?? 1, duration / 3)
                    let start = min(max(0, recipe.clip?.start ?? 0), max(0, duration - 3 * speed))
                    items.append(.init(url: input, duration: duration, start: start, speed: speed, edits: settings))
                }
                collageDrafts = items; showingCollage = true
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
    func exportCollage(_ items: [CollageDraftPane]) {
        guard !busy else { return }
        let panes = items.map { LiveCollagePane(url: $0.url,
            clip: .init(start: $0.start, end: $0.start + 3 * $0.speed, cover: $0.start + 1.5 * $0.speed, originalVolume: 0, speed: $0.speed), edits: $0.edits) }
        do { _ = try LiveCollagePipeline.validate(panes) } catch { message = error.localizedDescription; return }
        showingCollage = false
        Task {
            // Present the save panel only after the configuration sheet has closed.
            try? await Task.sleep(for: .milliseconds(300))
            let panel = NSSavePanel(); panel.nameFieldStringValue = "光集-\(panes.count)画面-Live"
            panel.message = "新建 Live 文件夹：静音 SDR，3 秒，各画面独立调色与变速。"
            present(panel) { [weak self] output in
                guard let self, let output else { return }
                self.busy = true; self.canCancel = true; self.exportProgress = 0
                self.message = "正在制作 \(panes.count) 画面拼图 Live…"
                self.operation = Task {
                    do {
                        let resources = try await LiveCollagePipeline.export(panes, to: output, progress: { [weak model = self] value in
                            Task { @MainActor in if model?.canCancel == true { model?.exportProgress = value } }
                        })
                        self.exportedLive = resources
                        self.livePhoto = try await LivePhotoPipeline.load(imageURL: resources.imageURL, videoURL: resources.videoURL)
                        self.message = "拼图 Live 已生成 · 系统配对检查通过 · 原片保留"
                    } catch { self.message = Task.isCancelled ? "拼图制作已取消，原片保留。" : error.localizedDescription }
                    self.busy = false; self.canCancel = false; self.exportProgress = nil
                }
            }
        }
    }
    init() {
        if let data = UserDefaults.standard.data(forKey: "guangji.library"),
           let entries = try? JSONDecoder().decode([LibraryEntry].self, from: data) { library = Array(entries.prefix(5000)) }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.flushDraft() } }
    }
    private var snapshot: EditorSnapshot { EditorSnapshot(edits: edits, clip: isVideo ? clip : nil, hdrPreview: hdrPreview) }
    var canUndo: Bool { history?.canUndo == true }
    var canRedo: Bool { history?.canRedo == true }
    func beginEditing(_ editing: Bool) {
        if editing { history?.beginGroup() }
        else { history?.endGroup(); flushDraft() }
    }
    func undoEdit() { if let value = history?.undo() { restoreSnapshot(value); message = "已撤销编辑。" } }
    func redoEdit() { if let value = history?.redo() { restoreSnapshot(value); message = "已重做编辑。" } }
    private func restoreSnapshot(_ value: EditorSnapshot) {
        applyingSnapshot = true
        adjustments = value.edits.adjustments; geometry = value.edits.geometry; degrees = value.edits.degrees; strength = value.edits.strength
        selectedLUT = value.edits.lut
        if let lut = selectedLUT, lut.id != CreativeLUT.warm.id, lut.id != CreativeLUT.soft.id { importedLUT = lut }
        hdrEffect = value.edits.hdrEffect; hdrPreview = value.hdrPreview
        if let clip = value.clip {
            clipStart = clip.start; clipEnd = clip.end; cover = clip.cover; playbackSpeed = clip.speed
            originalVolume = clip.originalVolume; musicURL = clip.musicURL; musicVolume = clip.musicVolume
            position = min(position, max(0, clip.sourceDuration - 0.05))
        }
        applyingSnapshot = false; updatePreview()
    }
    func resetGroup(_ group: AdjustmentGroup) {
        beginEditing(true)
        var next = adjustments
        for p in AdjustmentParameter.allCases where p.group == group { next[p] = 0 }
        adjustments = next; beginEditing(false)
    }
    private func currentRecipe() throws -> EditRecipe {
        var recipe = EditRecipe()
        recipe.adjustments = adjustments; recipe.geometry = geometry; recipe.degrees = degrees; recipe.strength = strength
        recipe.hdrEffect = hdrEffect; recipe.hdrPreview = hdrPreview; recipe.clip = isVideo ? clip : nil
        if let lut = selectedLUT {
            if let reference = lutReferences[lut.id] { recipe.lut = reference }
            else { let reference = try drafts.storeLUT(lut); lutReferences[lut.id] = reference; recipe.lut = reference }
        }
        return recipe
    }
    private func restoreRecipe(_ recipe: EditRecipe) throws {
        try recipe.validate()
        recipeNotice = nil
        let lut = try recipe.lut.map { try drafts.loadLUT($0) }
        if let lut, let reference = recipe.lut { lutReferences[lut.id] = reference }
        var range = recipe.clip
        if let clip = range {
            try clip.validate(duration: duration)
            if let music = clip.musicURL, !FileManager.default.fileExists(atPath: music.path) {
                range?.musicURL = nil; recipeNotice = "背景音乐离线，已恢复其他配方；重新选择音乐后再导出。"
            }
        }
        restoreSnapshot(EditorSnapshot(edits: MediaEdits(degrees: recipe.degrees, lut: lut, strength: recipe.strength,
                          hdrEffect: recipe.hdrEffect, adjustments: recipe.adjustments, geometry: recipe.geometry), clip: range, hdrPreview: recipe.hdrPreview))
    }
    private func scheduleDraft() {
        guard sourceStamp != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flushDraft()
        }
    }
    func flushDraft() {
        guard !applyingSnapshot, let sourceStamp, loaded else { return }
        do { try drafts.save(currentRecipe(), source: sourceStamp, companion: companionStamp); draftStatus = "配方已保存" }
        catch { draftStatus = "配方保存失败"; message = error.localizedDescription }
    }
    func saveDraft() { flushDraft(); message = draftStatus + " · 原片保留" }
    private func persistLibrary() {
        if let data = try? JSONEncoder().encode(library) { UserDefaults.standard.set(data, forKey: "guangji.library") }
    }
    func addSources(_ urls: [URL]) {
        for file in urls.prefix(5000) where !library.contains(where: { $0.id == file.standardizedFileURL.path }) {
            library.append(LibraryEntry(url: file)); if library.count >= 5000 { break }
        }
        selectedSources = Set(urls.map { $0.standardizedFileURL.path }); persistLibrary()
        if let first = urls.first { load(first) }
    }
    func toggleFavorite(_ entry: LibraryEntry) {
        if let index = library.firstIndex(where: { $0.id == entry.id }) { library[index].favorite.toggle(); persistLibrary() }
    }
    func openFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        present(panel) { [weak self] folder in
            guard let self, let folder else { return }
            if folder.startAccessingSecurityScopedResource() { self.accessURLs.append(folder) }
            self.busy = true; self.message = "正在索引文件夹…"
            self.operation = Task {
                do {
                    let files = try await Task.detached(priority: .utility) { try LibraryFiles.collect(folder) }.value
                    self.busy = false
                    if files.isEmpty { self.message = "没有找到支持的图片或视频。" }
                    else { self.addSources(files); if files.count == 5000 { self.message = "已读取前 5000 项，可选择更小的目录。" } }
                } catch { self.busy = false; self.message = error.localizedDescription }
            }
        }
    }
    func synchronize(groups: Set<AdjustmentGroup>, includeLUT: Bool) {
        guard loaded, !busy else { return }
        flushDraft()
        let targets = library.filter { selectedSources.contains($0.id) && $0.url != url }
        guard !targets.isEmpty, !groups.isEmpty || includeLUT else { return }
        do {
            let source = try currentRecipe(), store = drafts
            busy = true; showingSync = false; message = "正在同步所选调色参数…"
            operation = Task {
                let result = await Task.detached(priority: .utility) { () -> ([BatchChange], Int) in
                    var changes: [BatchChange] = []; var skipped = 0
                    for target in targets {
                        do {
                            let stamp = try SourceStamp(target.url)
                            let record = try store.loadRecord(target.url)
                            let before = record?.recipe ?? EditRecipe()
                            let after = before.applying(from: source, groups: groups, includeLUT: includeLUT)
                            try store.save(after, source: stamp, companion: record?.companion)
                            changes.append(BatchChange(stamp: stamp, companion: record?.companion, before: before, after: after))
                        } catch { skipped += 1 }
                    }
                    return (changes, skipped)
                }.value
                lastBatch = result.0; busy = false
                message = "已同步 \(result.0.count) 项；跳过 \(result.1) 项离线、已变化或无效素材。片段与声音保留。"
            }
        } catch { message = error.localizedDescription }
    }
    func undoBatch() {
        guard !busy, !lastBatch.isEmpty else { return }
        flushDraft()
        let batch = lastBatch, store = drafts, activeURL = url
        busy = true
        operation = Task {
            let count = await Task.detached(priority: .utility) {
                var count = 0
                var restored: EditRecipe?
                for change in batch {
                    do {
                        let file = URL(fileURLWithPath: change.stamp.path)
                        guard try store.load(file) == change.after else { continue }
                        try store.save(change.before, source: change.stamp, companion: change.companion); count += 1
                        if file == activeURL { restored = change.before }
                    } catch { continue }
                }
                return (count, restored)
            }.value
            busy = false; lastBatch = []
            if let restored = count.1 { try? restoreRecipe(restored) }
            message = "已撤回 \(count.0) 项同步；之后单独编辑或已变化的素材保留。"
        }
    }
    func cancelOperation() {
        guard canCancel else { return }
        operation?.cancel(); message = "正在取消…"
    }

    func refreshHistogram() {
        histogramTask?.cancel()
        guard loaded, !busy else { return }
        let token = session, version = revision, imageFrame = frame
        let item = player?.currentItem, outputTime = position / appliedPlaybackSpeed
        let original = comparing
        histogramTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                let data: PreviewHistogram
                if let imageFrame {
                    data = await Task.detached(priority: .utility) {
                        PreviewHistogram.analyze(original ? imageFrame.original : imageFrame.image,
                            headroom: original ? imageFrame.sourceHeadroom : imageFrame.headroom)
                    }.value
                } else if let item {
                    let generator = AVAssetImageGenerator(asset: item.asset)
                    generator.videoComposition = item.videoComposition
                    generator.maximumSize = CGSize(width: 256, height: 256)
                    generator.dynamicRangePolicy = .forceSDR; generator.appliesPreferredTrackTransform = true
                    let (bitmap, _) = try await generator.image(at: CMTime(seconds: outputTime, preferredTimescale: 60000))
                    data = await Task.detached(priority: .utility) { PreviewHistogram.analyze(CIImage(cgImage: bitmap)) }.value
                } else { return }
                guard token == session, version == revision, !Task.isCancelled else { return }
                histogram = data
                histogramLabel = isVideo ? "源 \(timeLabel(clipStart + outputTime * appliedPlaybackSpeed)) · SDR 显示" : "当前画面 · SDR 显示"
            } catch { /* Optional statistics never interrupt editing. */ }
        }
    }

    func exportSelected(liveOnly: Bool = false) {
        guard !busy, !selectedSources.isEmpty else { return }
        flushDraft()
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = liveOnly ? "选择保存位置。只导出已设为 0.5–3 秒输出的片段；其他项跳过。" : "选择保存位置。图片另存 PNG、视频另存 MOV、完整 Live 重制资源对。"
        present(panel) { [weak self] directory in
            guard let self, let directory else { return }
            self.runBatchExport(to: directory, liveOnly: liveOnly)
        }
    }
    private func runBatchExport(to directory: URL, liveOnly: Bool) {
        let entries = library.filter { selectedSources.contains($0.id) }, store = drafts
        let destination = directory.appendingPathComponent("光集-导出-" + String(UUID().uuidString.prefix(8)))
        let token = session
        busy = true; canCancel = true; exportProgress = nil; player?.pause(); playing = false
        operation = Task {
            var completed = 0, skipped = 0
            var report = ["光集批量导出记录", "原片保留；下列路径仅记录本次结果。", ""]
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                var luts: [String: CreativeLUT] = [:]
                for (index, entry) in entries.enumerated() {
                    try Task.checkCancellation()
                    message = "导出 \(index + 1)/\(entries.count) · \(entry.url.lastPathComponent)"
                    do {
                        let recipe = try store.load(entry.url) ?? EditRecipe()
                        var lut: CreativeLUT?
                        if let reference = recipe.lut {
                            let key = reference.file + reference.encoding.rawValue
                            if let cached = luts[key] { lut = cached }
                            else { let loaded = try store.loadLUT(reference); luts[key] = loaded; lut = loaded }
                        }
                        var info = try await MediaInspector.inspect(entry.url)
                        var input = entry.url
                        var liveInput = false
                        if info.kind == .image, let movie = try await LivePhotoPipeline.pairedMovie(for: entry.url) {
                            _ = try await LivePhotoPipeline.load(imageURL: entry.url, videoURL: movie)
                            input = movie; info = try await MediaInspector.inspect(movie); liveInput = true
                        }
                        let settings = MediaEdits(degrees: recipe.degrees, lut: lut, strength: recipe.strength,
                            hdrEffect: info.kind == .video && recipe.hdrEffect, adjustments: recipe.adjustments, geometry: recipe.geometry)
                        let stem = entry.url.deletingPathExtension().lastPathComponent + "-" + String(DraftStore.digest(entry.id).prefix(8))
                        if info.kind == .video {
                            let duration = info.durationSeconds ?? 0
                            let range = recipe.clip ?? ClipSettings(start: 0, end: duration, cover: min(duration / 2, max(0, duration - 0.05)))
                            try range.validate(duration: duration, live: liveOnly || liveInput)
                            if liveOnly || liveInput { _ = try await LivePhotoPipeline.export(input, to: destination.appendingPathComponent(stem + "-Live"), clip: range, edits: settings) }
                            else { try await VideoPipeline.export(input, to: destination.appendingPathComponent(stem + ".mov"), clip: range, edits: settings) }
                        } else if !liveOnly {
                            let output = destination.appendingPathComponent(stem + ".png")
                            try await ColorPipeline.exportPNGAsync(input, to: output, edits: settings)
                        } else { skipped += 1; report.append("跳过 · \(entry.url.lastPathComponent) · 图片没有可导出的动态片段"); continue }
                        completed += 1
                        report.append("完成 · \(entry.url.lastPathComponent) · \(stem)")
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        skipped += 1
                        report.append("失败/跳过 · \(entry.url.lastPathComponent) · \(error.localizedDescription)")
                    }
                }
                message = "导出完成 \(completed) 项，跳过或失败 \(skipped) 项 · \(destination.lastPathComponent)"
            } catch {
                message = Task.isCancelled ? "已取消；保留 \(completed) 项已完成成品，原片不改。" : error.localizedDescription
            }
            report.append("完成 \(completed) 项；跳过/失败 \(skipped) 项。" + (Task.isCancelled ? "操作已取消。" : ""))
            try? report.joined(separator: "\n").write(to: destination.appendingPathComponent("导出记录.txt"), atomically: true, encoding: .utf8)
            if token == session { busy = false; canCancel = false; exportProgress = nil; updatePreview() }
        }
    }

    func openSnapshots() {
        guard loaded, let url, !busy else { return }
        savedSnapshots = drafts.snapshots(for: url); showingSnapshots = true
    }
    func saveSnapshot() {
        guard let sourceStamp, loaded else { return }
        do {
            let name = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
            let automatic = Date().formatted(date: .abbreviated, time: .shortened)
            _ = try drafts.saveSnapshot(currentRecipe(), name: name.isEmpty ? automatic : name, source: sourceStamp, companion: companionStamp)
            snapshotName = ""; if let url { savedSnapshots = drafts.snapshots(for: url) }
            message = "已保存参数快照，原片保留。"
        } catch { message = error.localizedDescription }
    }
    func restoreSavedSnapshot(_ value: SavedSnapshot) {
        guard let url, !busy else { return }
        do {
            try restoreRecipe(drafts.restoreSnapshot(value, for: url))
            showingSnapshots = false; message = recipeNotice ?? "已恢复快照：\(value.name) · 可撤销"
        } catch { message = error.localizedDescription }
    }

}
