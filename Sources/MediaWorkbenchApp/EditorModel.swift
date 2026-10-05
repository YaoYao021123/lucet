import AppKit
import AVFoundation
import CoreImage
import MediaCore
import Observation
import Photos

enum CompareMode: String, Sendable {
    case off, original, split
}

struct Notice: Sendable {
    var title: String
    var message: String
}

/// Implemented by the image canvas; lets menus and keys drive zoom.
@MainActor
protocol CanvasController: AnyObject {
    var isZoomed: Bool { get }
    func zoomToFit()
    func zoomToActualPixels()
    func zoom(by factor: CGFloat)
}

/// One open document: its edits, preview, playback, undo history and autosave.
/// Views observe individual properties; avoid reading `edits` from a view body.
@MainActor
@Observable
final class EditorModel {
    // MARK: Document
    private(set) var url: URL?
    private(set) var mediaURL: URL?
    private(set) var metadata: MediaMetadata?
    private(set) var captureInfo: CaptureInfo?
    private(set) var isLoaded = false
    private(set) var isLoading = false
    private(set) var isLiveInput = false
    private(set) var sourceIsHDR = false
    private(set) var documentID = UUID()
    private(set) var draftStatus = ""
    var status = ""
    var isVideo: Bool { metadata?.kind == .video }
    var duration: Double { metadata?.durationSeconds ?? 0 }

    // MARK: Edits (each property observed on its own)
    var adjustments = BasicAdjustments() { didSet { if adjustments != oldValue { editsChanged() } } }
    var wheels = ColorWheels() { didSet { if wheels != oldValue { editsChanged() } } }
    var curves = ToneCurves() { didSet { if curves != oldValue { editsChanged() } } }
    var hsl = HSLAdjustments() { didSet { if hsl != oldValue { editsChanged() } } }
    var bypass: Set<GradeStage> = [] { didSet { if bypass != oldValue { editsChanged() } } }
    var geometry = GeometryAdjustments() { didSet { if geometry != oldValue { editsChanged() } } }
    var degrees = 0.0 { didSet { if degrees != oldValue { editsChanged() } } }
    private(set) var selectedLUT: CreativeLUT? { didSet { if selectedLUT?.id != oldValue?.id { editsChanged() } } }
    var strength = 1.0 { didSet { if strength != oldValue { editsChanged() } } }
    var hdrPreview = true { didSet { if hdrPreview != oldValue { editsChanged() } } }
    var hdrEffect = false { didSet { if hdrEffect != oldValue { editsChanged() } } }

    // MARK: Clip and sound
    private(set) var clipStart = 0.0
    private(set) var clipEnd = 0.0
    private(set) var cover = 0.0
    private(set) var playbackSpeed = 1.0
    var originalVolume: Float = 1 { didSet { if originalVolume != oldValue { editsChanged() } } }
    var musicURL: URL? { didSet { if musicURL != oldValue { editsChanged() } } }
    var musicVolume: Float = 0.5 { didSet { if musicVolume != oldValue { editsChanged() } } }

    // MARK: Viewing
    var compareMode = CompareMode.off { didSet { if compareMode != oldValue { compareChanged() } } }
    var splitPosition = 0.5
    var showClipping = false
    var showGrid = false
    var screenHeadroom: CGFloat = 1
    var zoomPercent: Int?
    private(set) var frame: GradeFrame?
    private(set) var scopes: ScopeData?
    private(set) var isLoadingFullResolution = false
    @ObservationIgnored weak var canvas: CanvasController?

    // MARK: Video playback
    private(set) var player: AVPlayer?
    private(set) var position = 0.0
    private(set) var playing = false
    private(set) var filmstrip: [CGImage] = []
    private(set) var filmstripLoading = false

    // MARK: Undo
    private(set) var canUndo = false
    private(set) var canRedo = false

    // MARK: Collaborators
    @ObservationIgnored var onNotice: ((Notice) -> Void)?
    @ObservationIgnored var onRecipeSaved: ((URL) -> Void)?
    @ObservationIgnored let drafts: DraftStore

    // MARK: Private state
    @ObservationIgnored private var suspended = 0
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var history: EditHistory<EditorSnapshot>?
    @ObservationIgnored private var sourceStamp: SourceStamp?
    @ObservationIgnored private var companionStamp: SourceStamp?
    @ObservationIgnored private var imageSession: ImageGradeSession?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var scopeTask: Task<Void, Never>?
    @ObservationIgnored private var scopesDirty = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var filmstripTask: Task<Void, Never>?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var analysisCache: StraighteningAssessment?
    @ObservationIgnored private var videoState: VideoPreviewState?
    @ObservationIgnored private var appliedKey: PreviewKey?
    @ObservationIgnored private var appliedSpeed = 1.0
    @ObservationIgnored private var appliedVolumes: (Float, Float) = (1, 0.5)
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var seekTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSeek: (value: Double, exact: Bool)?
    @ObservationIgnored private var seekGeneration = UUID()

    init(drafts: DraftStore) {
        self.drafts = drafts
    }

    // MARK: Derived values (model code only)

    var edits: MediaEdits {
        MediaEdits(degrees: degrees, lut: selectedLUT, strength: strength, hdrEffect: isVideo && hdrEffect,
                   adjustments: adjustments, geometry: geometry, wheels: wheels, curves: curves, hsl: hsl, bypass: bypass)
    }
    var clip: ClipSettings {
        ClipSettings(start: clipStart, end: clipEnd, cover: cover, originalVolume: originalVolume,
                     musicURL: musicURL, musicVolume: musicVolume, speed: playbackSpeed)
    }
    private var snapshot: EditorSnapshot { EditorSnapshot(edits: edits, clip: isVideo ? clip : nil, hdrPreview: hdrPreview) }

    var previewLabel: String {
        guard isLoaded else { return "" }
        if compareMode == .original { return "原片" }
        if isVideo, hdrEffect { return "HDR 效果 · HLG" }
        if !sourceIsHDR { return "SDR" }
        if isVideo { return previewNeedsSDR ? "SDR 预览" : "HDR 原片" }
        if edits.hasGrade { return "调色 · SDR" }
        return hdrPreview && screenHeadroom > 1 ? "HDR" : "HDR → SDR"
    }

    private struct PreviewKey: Equatable {
        let start: Double, end: Double, speed: Double
        let music: URL?
        let sdr: Bool
        let hdrEffect: Bool
    }
    /// SDR sources always get a filter composition, so the first edit and the
    /// before/after toggle never rebuild the player.
    private var previewNeedsSDR: Bool {
        if hdrEffect { return false }
        return !sourceIsHDR || !hdrPreview || edits.hasGrade || edits.hasGeometry
    }
    private var previewKey: PreviewKey {
        PreviewKey(start: clipStart, end: clipEnd, speed: playbackSpeed, music: musicURL,
                   sdr: previewNeedsSDR, hdrEffect: hdrEffect)
    }

    static func proxyDimension() -> Int {
        let longest = NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 2560
        return Int(min(3200, max(1600, longest * 0.85)))
    }

    // MARK: Opening

    func open(_ selected: URL) {
        if selected == url, isLoaded || isLoading { return }
        flushDraft()
        cancelWork()
        teardownPlayer()
        suspended += 1
        adjustments = .init(); wheels = .init(); curves = .init(); hsl = .init(); bypass = []
        geometry = .init(); degrees = 0; selectedLUT = nil; strength = 1; hdrEffect = false; hdrPreview = true
        clipStart = 0; clipEnd = 0; cover = 0; playbackSpeed = 1
        originalVolume = 1; musicURL = nil; musicVolume = 0.5
        suspended -= 1
        compareMode = .off
        url = selected; mediaURL = nil; metadata = nil; captureInfo = nil; frame = nil; scopes = nil
        isLoaded = false; isLoading = true; isLiveInput = false; sourceIsHDR = false
        filmstrip = []; position = 0; playing = false; zoomPercent = nil
        history = nil; updateUndoState()
        sourceStamp = nil; companionStamp = nil; analysisCache = nil
        status = "正在读取素材…"; draftStatus = ""
        documentID = UUID(); session = UUID()
        let token = session
        let proxy = Self.proxyDimension()
        let drafts = self.drafts
        loadTask = Task {
            do {
                let info = try await MediaInspector.inspect(selected)
                var input = selected
                var liveCover: Double?
                var notice: String?
                if info.kind == .image, let pair = try await LivePhotoPipeline.pairedMovie(for: selected) {
                    do {
                        _ = try await LivePhotoPipeline.load(imageURL: selected, videoURL: pair)
                        liveCover = try await LivePhotoPipeline.coverTime(in: pair)
                        input = pair
                    } catch { notice = "Live 配对未通过系统检查，已作为静态图片打开。" }
                }
                let movieInput = input
                let meta = input == selected ? info : try await MediaInspector.inspect(input)
                let loaded = await Task.detached(priority: .userInitiated) { () -> (EditRecipe?, CreativeLUT?, String?, CaptureInfo?) in
                    let capture = CaptureInfo.read(selected)
                    do {
                        guard let recipe = try drafts.load(selected) else { return (nil, nil, nil, capture) }
                        let lut = try recipe.lut.map { try drafts.loadLUT($0) }
                        return (recipe, lut, nil, capture)
                    } catch { return (nil, nil, error.localizedDescription, capture) }
                }.value
                let stamp = try SourceStamp(selected)
                let companion = movieInput == selected ? nil : try SourceStamp(movieInput)
                guard token == session, !Task.isCancelled else { return }

                mediaURL = input; metadata = meta; captureInfo = loaded.3
                isLiveInput = input != selected
                sourceStamp = stamp; companionStamp = companion
                suspended += 1
                if meta.kind == .video {
                    guard let seconds = meta.durationSeconds, seconds >= 0.1 else { throw VideoWorkError.invalidRange }
                    clipStart = 0; clipEnd = seconds
                    cover = min(max(0, liveCover ?? seconds / 2), max(0, seconds - 0.05))
                    sourceIsHDR = meta.transferFunction == AVVideoTransferFunction_ITU_R_2100_HLG
                        || meta.transferFunction == AVVideoTransferFunction_SMPTE_ST_2084_PQ
                }
                var restoreNotice: String?
                if let recipe = loaded.0 { restoreNotice = apply(recipe, lut: loaded.1) }
                suspended -= 1

                if meta.kind == .image {
                    let renderer = try await Task.detached(priority: .userInitiated) {
                        try ImageGradeSession(url: input, maximumDimension: proxy)
                    }.value
                    let first = try await renderer.frame(edits: edits)
                    guard token == session, !Task.isCancelled else { return }
                    imageSession = renderer
                    frame = first
                    sourceIsHDR = first.sourceHeadroom > 1
                } else {
                    try await buildPlayer(input, token: token)
                    guard token == session else { return }
                    if isLiveInput { seek(cover - clipStart) }
                    loadFilmstrip(input, duration: duration, token: token)
                }
                history = EditHistory(snapshot); updateUndoState()
                isLoaded = true; isLoading = false
                draftStatus = loaded.0 == nil ? "自动保存" : "已恢复上次的编辑"
                status = notice ?? restoreNotice ?? loaded.2.map { "旧配方未载入：\($0)" }
                    ?? (loaded.0 != nil ? "已恢复这份素材的编辑。" : isLiveInput ? "已识别 Live Photo，可从动态部分重新制作。" : "")
                markScopesDirty()
                schedulePreview()  // catch up with anything changed while loading
            } catch {
                guard token == session else { return }
                isLoading = false
                status = "打开失败"
                onNotice?(Notice(title: "无法打开 \(selected.lastPathComponent)", message: error.localizedDescription))
            }
        }
    }

    func close() {
        flushDraft()
        cancelWork()
        teardownPlayer()
        session = UUID()
        url = nil; mediaURL = nil; metadata = nil; frame = nil; scopes = nil; captureInfo = nil
        isLoaded = false; isLoading = false; status = ""; filmstrip = []
        history = nil; updateUndoState()
        imageSession = nil
    }

    /// Applies a stored recipe. Returns a notice when something could not be restored.
    @discardableResult
    private func apply(_ recipe: EditRecipe, lut: CreativeLUT?) -> String? {
        adjustments = recipe.adjustments; wheels = recipe.wheels; curves = recipe.curves; hsl = recipe.hsl
        bypass = recipe.bypass; geometry = recipe.geometry; degrees = recipe.degrees
        selectedLUT = lut; strength = recipe.strength; hdrEffect = recipe.hdrEffect; hdrPreview = recipe.hdrPreview
        guard isVideo, var range = recipe.clip else { return nil }
        guard (try? range.validate(duration: duration)) != nil else { return "保存的片段超出当前素材长度，已使用完整范围。" }
        var notice: String?
        if let music = range.musicURL, !FileManager.default.fileExists(atPath: music.path) {
            range.musicURL = nil
            notice = "背景音乐文件不在原位置，已恢复其他编辑。"
        }
        clipStart = range.start; clipEnd = range.end; cover = range.cover; playbackSpeed = range.speed
        originalVolume = range.originalVolume; musicURL = range.musicURL; musicVolume = range.musicVolume
        return notice
    }

    private func cancelWork() {
        loadTask?.cancel(); loadTask = nil
        previewTask?.cancel(); previewTask = nil
        scopeTask?.cancel(); scopeTask = nil; scopesDirty = false
        saveTask?.cancel(); saveTask = nil
        filmstripTask?.cancel(); filmstripTask = nil
        analysisTask?.cancel(); analysisTask = nil
        seekTask?.cancel(); seekTask = nil; pendingSeek = nil; seekGeneration = UUID()
        imageSession = nil
        isLoadingFullResolution = false
    }

    // MARK: Change tracking

    private func editsChanged() {
        guard suspended == 0 else { return }
        revision += 1
        guard isLoaded else { return }
        history?.record(snapshot); updateUndoState()
        scheduleDraft()
        schedulePreview()
    }

    private func updateUndoState() {
        let undo = history?.canUndo == true, redo = history?.canRedo == true
        if canUndo != undo { canUndo = undo }
        if canRedo != redo { canRedo = redo }
    }

    /// Groups a continuous drag into one undo step.
    func beginEditing(_ editing: Bool) {
        if editing { history?.beginGroup() } else { history?.endGroup(); updateUndoState(); flushDraft() }
    }

    func undo() {
        guard let value = history?.undo() else { return }
        restore(value); status = "已撤销"
    }

    func redo() {
        guard let value = history?.redo() else { return }
        restore(value); status = "已重做"
    }

    private func restore(_ value: EditorSnapshot) {
        suspended += 1
        let e = value.edits
        adjustments = e.adjustments; wheels = e.wheels; curves = e.curves; hsl = e.hsl; bypass = e.bypass
        geometry = e.geometry; degrees = e.degrees; selectedLUT = e.lut; strength = e.strength
        hdrEffect = e.hdrEffect; hdrPreview = value.hdrPreview
        if let clip = value.clip {
            clipStart = clip.start; clipEnd = clip.end; cover = clip.cover; playbackSpeed = clip.speed
            originalVolume = clip.originalVolume; musicURL = clip.musicURL; musicVolume = clip.musicVolume
            position = min(position, max(0, clip.sourceDuration - 0.05))
        }
        suspended -= 1
        revision += 1
        updateUndoState()
        scheduleDraft()
        schedulePreview()
    }

    /// Performs several changes as one undo step.
    func group(_ changes: () -> Void) {
        beginEditing(true)
        changes()
        beginEditing(false)
    }

    // MARK: Edit actions

    func setAdjustment(_ parameter: AdjustmentParameter, _ value: Double) { adjustments[parameter] = value }
    func setWheel(_ wheel: ColorWheels.Wheel, _ value: WheelValue) { wheels[wheel] = value }
    func setCurve(_ channel: ToneCurves.Channel, _ points: [CurvePoint]) { curves[channel] = points }
    func setHSL(_ band: HueBand, _ component: HSLAdjustments.Component, _ value: Double) { hsl[band, component] = value }

    func isStageOn(_ stage: GradeStage) -> Bool { !bypass.contains(stage) }
    func setStage(_ stage: GradeStage, on: Bool) {
        if on { bypass.remove(stage) } else { bypass.insert(stage) }
        status = on ? "\(stage.title) 已开启" : "\(stage.title) 已关闭（参数保留，可随时开启比较）"
    }

    func resetAll() {
        group {
            adjustments = .init(); wheels = .init(); curves = .init(); hsl = .init(); bypass = []
            geometry = .init(); degrees = 0; selectedLUT = nil; strength = 1; hdrEffect = false
        }
        compareMode = .off
        status = "已恢复原片画面，可撤销。"
    }

    func resetGroup(_ group: AdjustmentGroup) {
        self.group {
            var next = adjustments
            for p in AdjustmentParameter.allCases where p.group == group { next[p] = 0 }
            adjustments = next
        }
    }

    func resetStage(_ stage: GradeStage) {
        group {
            switch stage {
            case .basic:
                var next = adjustments
                for p in AdjustmentParameter.allCases where p.group != .detail { next[p] = 0 }
                adjustments = next
            case .wheels: wheels = .init()
            case .curves: curves = .init()
            case .hsl: hsl = .init()
            case .lut: selectedLUT = nil; strength = 1
            case .detail: resetGroup(.detail)
            }
        }
    }

    func selectLUT(_ lut: CreativeLUT?) {
        selectedLUT = lut
        status = lut.map { "LUT：\($0.name)" } ?? "已移除 LUT"
    }

    /// Applies a look (preset, pasted settings) as one undo step.
    func applyLook(_ recipe: EditRecipe, lut: CreativeLUT?, name: String) {
        group {
            adjustments = recipe.adjustments; wheels = recipe.wheels; curves = recipe.curves; hsl = recipe.hsl
            bypass = recipe.bypass
            if recipe.lut != nil || lut == nil { selectedLUT = lut; strength = recipe.strength }
        }
        status = "已应用 \(name)，可撤销。"
    }

    func rotate(clockwise: Bool) {
        geometry.quarterTurns = (geometry.quarterTurns + (clockwise ? 3 : 1)) % 4
    }

    func autoStraighten() {
        guard let input = mediaURL, !isVideo, isLoaded else { return }
        if let result = analysisCache { applyStraighten(result); return }
        let token = session
        status = "正在识别地平线…"
        analysisTask = Task {
            do {
                let result = try await ImageStraightener.analyze(input)
                guard token == session else { return }
                analysisCache = result
                applyStraighten(result)
            } catch {
                if token == session { status = "自动拉直失败：\(error.localizedDescription)" }
            }
        }
    }

    private func applyStraighten(_ result: StraighteningAssessment) {
        status = result.message
        if let plan = result.plan { group { degrees = plan.rotationDegrees } }
    }

    // MARK: Recipes and autosave

    func currentRecipe() throws -> EditRecipe {
        var recipe = EditRecipe()
        recipe.adjustments = adjustments; recipe.wheels = wheels; recipe.curves = curves; recipe.hsl = hsl
        recipe.bypass = bypass; recipe.geometry = geometry; recipe.degrees = degrees; recipe.strength = strength
        recipe.hdrEffect = hdrEffect; recipe.hdrPreview = hdrPreview; recipe.clip = isVideo ? clip : nil
        if let lut = selectedLUT { recipe.lut = try drafts.storeLUT(lut) }
        return recipe
    }

    /// Replaces the open document's edits with a stored recipe (snapshot, undo of a batch).
    func restoreRecipe(_ recipe: EditRecipe, lut: CreativeLUT?) {
        beginEditing(true)
        suspended += 1
        let notice = apply(recipe, lut: lut)
        suspended -= 1
        revision += 1
        history?.record(snapshot)
        beginEditing(false)
        schedulePreview()
        if let notice { status = notice }
    }

    private func scheduleDraft() {
        guard sourceStamp != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flushDraft()
        }
    }

    func flushDraft() {
        saveTask?.cancel(); saveTask = nil
        guard suspended == 0, isLoaded, let sourceStamp, let url else { return }
        do {
            try drafts.save(currentRecipe(), source: sourceStamp, companion: companionStamp)
            draftStatus = "已自动保存"
            onRecipeSaved?(url)
        } catch {
            draftStatus = "保存失败"
            onNotice?(Notice(title: "编辑未能保存", message: error.localizedDescription))
        }
    }

    func saveSnapshot(named name: String) {
        guard let sourceStamp, isLoaded else { return }
        do {
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try drafts.saveSnapshot(currentRecipe(), name: title.isEmpty ? Date().formatted(date: .abbreviated, time: .shortened) : title,
                                        source: sourceStamp, companion: companionStamp)
            status = "已保存版本快照。"
        } catch { onNotice?(Notice(title: "快照未保存", message: error.localizedDescription)) }
    }

    func snapshots() -> [SavedSnapshot] { url.map { drafts.snapshots(for: $0) } ?? [] }

    func restoreSnapshot(_ value: SavedSnapshot) {
        guard let url else { return }
        do {
            let recipe = try drafts.restoreSnapshot(value, for: url)
            let lut = try recipe.lut.map { try drafts.loadLUT($0) }
            restoreRecipe(recipe, lut: lut)
            status = "已恢复快照：\(value.name)，可撤销。"
        } catch { onNotice?(Notice(title: "无法恢复快照", message: error.localizedDescription)) }
    }

    // MARK: Preview

    private func schedulePreview() {
        guard isLoaded, previewTask == nil else { return }
        let token = session
        previewTask = Task {
            do {
                while token == session, !Task.isCancelled {
                    let version = revision
                    if let imageSession {
                        let next = try await imageSession.frame(edits: edits)
                        guard token == session, !Task.isCancelled else { return }
                        frame = next
                    } else if player != nil, let input = mediaURL {
                        if appliedKey == previewKey {
                            updateLiveVideoPreview()
                            try await Task.sleep(for: .milliseconds(16))
                        } else {
                            try await buildPlayer(input, token: token)
                        }
                    }
                    if version == revision { break }
                }
            } catch is CancellationError {
            } catch {
                if token == session { onNotice?(Notice(title: "预览失败", message: error.localizedDescription)) }
            }
            if token == session { previewTask = nil; markScopesDirty() }
        }
    }

    /// Updates the running composition's parameters without touching the decoder.
    private func updateLiveVideoPreview() {
        guard let player, let item = player.currentItem else { return }
        videoState?.update(edits)
        videoState?.showsOriginal = compareMode != .off
        if appliedVolumes != (originalVolume, musicVolume) {
            let inputs = item.audioMix?.inputParameters ?? []
            let mix = AVMutableAudioMix()
            mix.inputParameters = inputs.enumerated().map { index, input in
                let parameter = AVMutableAudioMixInputParameters()
                parameter.trackID = input.trackID
                let isMusic = musicURL != nil && index == inputs.count - 1
                parameter.setVolume(isMusic ? musicVolume : originalVolume, at: .zero)
                return parameter
            }
            item.audioMix = mix
            appliedVolumes = (originalVolume, musicVolume)
        }
        // Apple QA1966: a new composition instance redraws a paused frame.
        if !playing, let composition = item.videoComposition {
            item.videoComposition = composition.mutableCopy() as? AVVideoComposition
        }
    }

    private func buildPlayer(_ input: URL, token: UUID) async throws {
        let key = previewKey
        let range = clip
        let state = VideoPreviewState(edits: edits)
        state.showsOriginal = compareMode != .off
        let wasPlaying = playing
        let oldPosition = position
        let prepared = try await VideoPipeline.prepare(input, clip: range, edits: edits, sdr: key.sdr, preview: state)
        guard token == session, !Task.isCancelled else { return }
        let item = AVPlayerItem(asset: prepared.asset)
        item.videoComposition = prepared.videoComposition
        item.audioMix = prepared.audioMix
        item.audioTimePitchAlgorithm = .spectral
        appliedSpeed = range.speed
        appliedKey = key
        appliedVolumes = (range.originalVolume, range.musicVolume)
        videoState = state
        seekTask?.cancel(); seekTask = nil; pendingSeek = nil; seekGeneration = UUID()
        if let player {
            player.currentItem?.cancelPendingSeeks()
            player.replaceCurrentItem(with: item)
        } else {
            let player = AVPlayer(playerItem: item)
            self.player = player
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self, self.seekTask == nil else { return }
                    let next = max(0, time.seconds * self.appliedSpeed)
                    if abs(next - self.position) > 0.001 { self.position = next }
                    if self.player?.rate == 0, self.playing { self.playing = false; self.markScopesDirty() }
                }
            }
        }
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "视频预览失败。"
            Task { @MainActor [weak self] in self?.onNotice?(Notice(title: "视频预览失败", message: message)) }
        }
        let target = min(oldPosition / range.speed, max(0, prepared.duration - 0.05))
        await player?.seek(to: CMTime(seconds: target, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
        if wasPlaying { player?.play(); playing = true }
    }

    private func teardownPlayer() {
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil; statusObserver = nil
        player = nil; videoState = nil; appliedKey = nil
    }

    private func compareChanged() {
        if isVideo {
            videoState?.showsOriginal = compareMode != .off
            if !playing, let item = player?.currentItem, let composition = item.videoComposition {
                item.videoComposition = composition.mutableCopy() as? AVVideoComposition
            }
        }
        markScopesDirty()
    }

    func requestFullResolution() {
        guard let imageSession, !isLoadingFullResolution, frame?.fullImage == nil else { return }
        isLoadingFullResolution = true
        let token = session
        Task {
            do {
                try await imageSession.loadFullResolution()
                guard token == session else { return }
                isLoadingFullResolution = false
                revision += 1
                schedulePreview()
            } catch {
                if token == session { isLoadingFullResolution = false }
            }
        }
    }

    // MARK: Scopes (throttled, live while dragging)

    func markScopesDirty() {
        scopesDirty = true
        guard scopeTask == nil, isLoaded else { return }
        let token = session
        scopeTask = Task {
            while scopesDirty, token == session, !Task.isCancelled {
                scopesDirty = false
                try? await Task.sleep(for: .milliseconds(isVideo ? 200 : 60))
                guard token == session, !Task.isCancelled else { break }
                let data = await computeScopes()
                guard token == session, !Task.isCancelled else { break }
                if let data { scopes = data }
            }
            if token == session { scopeTask = nil }
        }
    }

    private func computeScopes() async -> ScopeData? {
        if let frame {
            let original = compareMode == .original
            let image = original ? frame.original : frame.image
            let headroom = original ? frame.sourceHeadroom : frame.headroom
            return await Task.detached(priority: .utility) { ScopeAnalyzer.analyze(image, headroom: headroom) }.value
        }
        guard let item = player?.currentItem, !playing else { return nil }
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.videoComposition = item.videoComposition
        generator.maximumSize = CGSize(width: 320, height: 320)
        generator.dynamicRangePolicy = .forceSDR
        generator.appliesPreferredTrackTransform = true
        guard let bitmap = try? await generator.image(at: CMTime(seconds: position / appliedSpeed, preferredTimescale: 60000)).image else { return nil }
        return await Task.detached(priority: .utility) { ScopeAnalyzer.analyze(CIImage(cgImage: bitmap)) }.value
    }

    // MARK: Filmstrip

    private func loadFilmstrip(_ input: URL, duration: Double, token: UUID, count: Int = 16) {
        filmstripLoading = true
        filmstripTask = Task {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: input))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 240, height: 140)
            generator.dynamicRangePolicy = .forceSDR
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
            let times = (0..<count).map { CMTime(seconds: max(0, duration - 0.05) * Double($0) / Double(count - 1), preferredTimescale: 600) }
            var images: [CGImage] = []
            // One batched request decodes sequentially and reuses the decoder.
            for await result in generator.images(for: times) {
                if Task.isCancelled { break }
                if let image = try? result.image { images.append(image) }
            }
            guard token == session, !Task.isCancelled else { return }
            filmstrip = images
            filmstripLoading = false
        }
    }

    // MARK: Playback and clip

    func togglePlayback() {
        guard let player else { return }
        if playing {
            player.pause(); playing = false; markScopesDirty()
        } else {
            if position >= clipEnd - clipStart - 0.05 { seek(0) }
            player.play(); playing = true
        }
    }

    func pause() {
        player?.pause()
        if playing { playing = false; markScopesDirty() }
    }

    func seek(_ value: Double) { scrubSeek(value, exact: true) }

    /// Coalesced seeking: one seek in flight, newest request wins.
    func scrubSeek(_ value: Double, exact: Bool = false) {
        player?.pause(); playing = false
        position = min(max(0, value), max(0, clipEnd - clipStart - 0.01))
        pendingSeek = (position, exact)
        guard seekTask == nil, let player else { return }
        let token = session, generation = seekGeneration
        seekTask = Task {
            while token == session, generation == seekGeneration, !Task.isCancelled, let request = pendingSeek {
                pendingSeek = nil
                let tolerance = request.exact ? CMTime.zero : CMTime(seconds: 1 / 30, preferredTimescale: 60000)
                await player.seek(to: CMTime(seconds: request.value / appliedSpeed, preferredTimescale: 60000),
                                  toleranceBefore: tolerance, toleranceAfter: tolerance)
            }
            if token == session, generation == seekGeneration { seekTask = nil; markScopesDirty() }
        }
    }

    func stepFrame(_ direction: Double) {
        let rate = Double(metadata?.nominalFrameRate ?? 30)
        seek(min(max(0, position + direction * playbackSpeed / max(1, rate)), max(0, clipEnd - clipStart - 0.01)))
    }

    private func clipChanged(_ change: () -> Void) {
        suspended += 1
        change()
        suspended -= 1
        editsChanged()
    }

    /// Commits trim handles once, after a drag ends; keeps the playhead's source time.
    func setRange(start: Double, end: Double) {
        guard duration >= 0.1 else { return }
        let absolute = clipStart + position
        pause()
        clipChanged {
            clipStart = min(max(0, start), duration - 0.1)
            clipEnd = min(duration, max(clipStart + 0.1, end))
            cover = min(max(cover, clipStart), clipEnd - 0.05)
            position = min(max(0, absolute - clipStart), clipEnd - clipStart - 0.05)
        }
    }

    func setInPoint() { setRange(start: clipStart + position, end: clipEnd) }
    func setOutPoint() { setRange(start: clipStart, end: clipStart + position) }

    func moveRange(by delta: Double) {
        let next = clip.shifted(by: delta, duration: duration)
        let relative = position
        pause()
        clipChanged {
            clipStart = next.start; clipEnd = next.end; cover = next.cover
            position = min(relative, max(0, next.sourceDuration - 0.05))
        }
    }

    func moveCover(to seconds: Double, exact: Bool = true) {
        let value = min(max(seconds, clipStart), clipEnd - 0.05)
        if exact { clipChanged { cover = value } } else { cover = value }
        scrubSeek(value - clipStart, exact: exact)
    }

    func setCoverAtPlayhead() {
        clipChanged { cover = min(clipEnd - 0.05, max(clipStart, clipStart + position)) }
        status = "封面设为 \(timeLabel(cover))"
    }

    func setSpeed(_ speed: Double) {
        let value = min(4, max(0.5, speed))
        guard value != playbackSpeed else { return }
        clipChanged { playbackSpeed = value }
    }

    func fitLiveSpeed() {
        setSpeed((clipEnd - clipStart) / 3)
        status = clip.outputDuration <= 3.001 ? "已压缩为 3 秒 Live，原片保留。" : "范围过长：4× 速度下仍超过 3 秒，请缩短选取范围。"
    }

    func selectLiveRange() {
        let center = min(duration - 0.05, max(0, clipStart + position))
        let length = 3 * playbackSpeed
        pause()
        clipChanged {
            clipStart = max(0, center - length / 2)
            clipEnd = min(duration, clipStart + length)
            clipStart = max(0, clipEnd - length)
            cover = min(max(center, clipStart), clipEnd - 0.05)
            position = cover - clipStart
        }
    }

    var liveIsValid: Bool { clip.outputDuration >= 0.5 && clip.outputDuration <= 3.001 }

    // MARK: Zoom

    func zoomToFit() { canvas?.zoomToFit() }
    func zoomToActualPixels() { canvas?.zoomToActualPixels() }
    func zoom(by factor: CGFloat) { canvas?.zoom(by: factor) }
    func toggleZoom() {
        guard let canvas else { return }
        if canvas.isZoomed { canvas.zoomToFit() } else { canvas.zoomToActualPixels() }
    }
}

func timeLabel(_ seconds: Double) -> String {
    let centiseconds = Int(max(0, seconds.isFinite ? seconds : 0) * 100)
    return String(format: "%02d:%02d.%02d", centiseconds / 6000, (centiseconds / 100) % 60, centiseconds % 100)
}
