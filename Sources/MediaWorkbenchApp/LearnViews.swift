import MediaCore
import SwiftUI

/// Coach output for the open photo, computed from the latest scope analysis.
@MainActor
struct CoachState {
    let insights: [CoachInsight]
    let resolved: [CoachInsight]

    init(app: AppModel) {
        let editor = app.editor
        guard let analysis = editor.scopes?.analysis else { insights = []; resolved = []; return }
        let current = PhotoCoach.insights(for: analysis, original: editor.originalAnalysis, faces: editor.faceAnalysis,
                                          edits: editor.edits, profile: app.learner, tilt: editor.horizonTilt,
                                          isVideo: editor.isVideo)
        insights = current
        // Issues present in the untouched photo that the edits have fixed.
        if let original = editor.originalAnalysis, editor.edits.hasGrade || editor.edits.hasGeometry {
            let before = PhotoCoach.insights(for: original, original: original, edits: MediaEdits(), profile: app.learner,
                                             tilt: editor.horizonTilt, isVideo: editor.isVideo)
            let now = Set(current.map(\.id))
            resolved = before.filter { !now.contains($0.id) && $0.id != "skin-ok" && $0.suggestion != nil }
        } else {
            resolved = []
        }
    }
}

/// The most relevant tip, one line, at the top of the color tab.
struct InsightStrip: View {
    let app: AppModel
    var editor: EditorModel { app.editor }

    var body: some View {
        let state = CoachState(app: app)
        Group {
            if let top = state.insights.first, top.severity >= 0.3 {
                HStack(spacing: 6) {
                    Image(systemName: top.symbol).foregroundStyle(WorkbenchTheme.accent).frame(width: 16)
                    Button { app.inspectorTab = .learn } label: {
                        Text(top.title).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help(top.observation + "\n点按查看讲解")
                    Spacer(minLength: 4)
                    if top.influence != nil || top.showsClipping {
                        Button("显示") { showArea(top) }.buttonStyle(.borderless).font(.caption)
                    }
                    if let suggestion = top.suggestion {
                        Button("修复") { app.trySuggestion(suggestion, concept: top.concept) }
                            .buttonStyle(.borderless).font(.caption.weight(.semibold))
                            .help("试一试：\(suggestion.label)（可撤销）")
                    }
                }
                .padding(.horizontal, 8).frame(height: 24)
                .background(WorkbenchTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 2)
            }
        }
        .task(id: editor.documentID) { editor.requestHorizon() }
    }

    private func showArea(_ insight: CoachInsight) {
        if insight.showsClipping { editor.showClipping.toggle() }
        else { editor.pinnedInfluence = editor.pinnedInfluence == insight.influence ? nil : insight.influence }
    }
}

struct LearnPanel: View {
    let app: AppModel
    var editor: EditorModel { app.editor }
    @UIState private var showAll = false
    @UIState private var expanded: Concept?

    var body: some View {
        let state = CoachState(app: app)
        let profile = app.learner
        VStack(alignment: .leading, spacing: 0) {
            InspectorSection("这张照片", help: "根据这张照片当前的样子给出建议；修改后会实时更新。") {
                VStack(alignment: .leading, spacing: 6) {
                    if editor.scopes == nil {
                        Text("正在分析画面…").font(.caption).foregroundStyle(.secondary)
                    } else if state.insights.isEmpty {
                        Label("没有发现明显的问题。可以从下面的学习路径挑一个技巧，在这张照片上试试。", systemImage: "checkmark.seal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(showAll ? state.insights : Array(state.insights.prefix(3))) { insight in
                        InsightCard(app: app, insight: insight)
                    }
                    if state.insights.count > 3 {
                        Button(showAll ? "收起" : "还有 \(state.insights.count - 3) 条") { showAll.toggle() }
                            .buttonStyle(.borderless).font(.caption)
                    }
                    if !state.resolved.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(state.resolved) { item in
                                Label("已改善：" + item.title, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(WorkbenchTheme.pick)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            InspectorSection("我的学习", help: "选择水平和感兴趣的方向，讲解和推荐会随之调整。") {
                VStack(alignment: .leading, spacing: 6) {
                    if !profile.onboarded {
                        Text("告诉我你的水平和想学什么，讲解会更适合你。").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("水平", selection: Binding(get: { profile.level }, set: { app.learner.level = $0; app.learner.onboarded = true })) {
                        ForEach(LearningLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                    FlowLayout(spacing: 4) {
                        ForEach(LearningTopic.allCases, id: \.self) { topic in
                            let on = profile.topics.contains(topic)
                            Button {
                                if on { app.learner.topics.remove(topic) } else { app.learner.topics.insert(topic) }
                                app.learner.onboarded = true
                            } label: {
                                Text(topic.title).font(.caption)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .foregroundStyle(on ? Color.black.opacity(0.85) : .primary)
                                    .background(Capsule().fill(on ? WorkbenchTheme.accent : WorkbenchTheme.well))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    Toggle("悬停参数名时，在画面上显示影响范围", isOn: Binding(get: { profile.hoverHints }, set: { app.learner.hoverHints = $0 }))
                        .toggleStyle(.checkbox).font(.caption)
                }
            }
            InspectorSection("学习路径", help: "按你选的方向排列；在照片上演示过或常用的技巧会打勾。") {
                VStack(alignment: .leading, spacing: 2) {
                    let path = profile.path
                    ProgressView(value: Double(profile.learnedInPath), total: Double(max(1, path.count)))
                        .controlSize(.small)
                    Text("已掌握 \(profile.learnedInPath) / \(path.count)").font(.caption2).foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                    ForEach(path, id: \.self) { concept in
                        ConceptRow(app: app, concept: concept, expanded: expanded == concept) {
                            expanded = expanded == concept ? nil : concept
                        }
                    }
                }
            }
            let muted = Concept.allCases.filter { profile.state($0).muted }
            if !muted.isEmpty {
                Button("恢复已关闭的提示（\(muted.count)）", action: app.unmuteAll)
                    .buttonStyle(.borderless).font(.caption).padding(.top, 8)
            }
        }
        .task(id: editor.documentID) {
            editor.requestHorizon()
            try? await Task.sleep(for: .seconds(1.5))
            app.markShown(Array(CoachState(app: app).insights.prefix(3)))
        }
    }
}

struct InsightCard: View {
    let app: AppModel
    let insight: CoachInsight
    @UIState private var showWhy = false
    var editor: EditorModel { app.editor }

    var body: some View {
        let learned = app.learner.isLearned(insight.concept)
        let areaOn = insight.showsClipping ? editor.showClipping : editor.pinnedInfluence == insight.influence && insight.influence != nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: insight.symbol).foregroundStyle(WorkbenchTheme.accent).frame(width: 16)
                Text(insight.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Menu {
                    Button("👍 有帮助") { app.feedback(.helpful, on: insight.concept) }
                    Button("我已经了解「\(insight.concept.title)」") { app.feedback(.known, on: insight.concept) }
                    Button("不再提示这类内容") { app.feedback(.mute, on: insight.concept) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("告诉我这条提示是否有用，之后的推荐会随之调整")
            }
            Text(insight.observation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !learned || showWhy {
                Text(insight.why).font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            if let suggestion = insight.suggestion {
                Label(suggestion.label, systemImage: "wand.and.stars").font(.caption).foregroundStyle(WorkbenchTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                if insight.influence != nil || insight.showsClipping {
                    Button(areaOn ? "隐藏区域" : "显示区域") {
                        if insight.showsClipping { editor.showClipping.toggle() }
                        else { editor.pinnedInfluence = areaOn ? nil : insight.influence }
                    }
                }
                if let suggestion = insight.suggestion {
                    Button(suggestion.changesEdits ? "试一试" : "打开") { app.trySuggestion(suggestion, concept: insight.concept) }
                        .help("作为一步应用，左右对比查看效果；⌘Z 撤销")
                }
                if learned, !showWhy {
                    Button("为什么？") { showWhy = true }.buttonStyle(.borderless)
                }
            }
            .glassButton().controlSize(.mini).font(.caption)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(WorkbenchTheme.well))
    }
}

struct ConceptRow: View {
    let app: AppModel
    let concept: Concept
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        let learned = app.learner.isLearned(concept)
        VStack(alignment: .leading, spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: learned ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(learned ? WorkbenchTheme.pick : .secondary).font(.caption)
                    Text(concept.title).font(.caption)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 20)
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(concept.explanation(for: app.learner.level))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let demo = concept.demo {
                        Label("演示：" + demo.label, systemImage: "wand.and.stars").font(.caption).foregroundStyle(WorkbenchTheme.accent)
                    }
                    HStack(spacing: 6) {
                        if let demo = concept.demo {
                            Button("演示") { app.trySuggestion(demo, concept: concept) }
                                .disabled(!app.editor.isLoaded)
                                .help("在这张照片上演示：\(demo.label)（可撤销）")
                        }
                        if let influence = concept.influence, !app.editor.isVideo {
                            let on = app.editor.pinnedInfluence == influence
                            Button(on ? "隐藏区域" : "看它影响哪里") { app.editor.pinnedInfluence = on ? nil : influence }
                        }
                        if !learned { Button("已了解") { app.feedback(.known, on: concept) }.buttonStyle(.borderless) }
                    }
                    .glassButton().controlSize(.mini).font(.caption)
                }
                .padding(.leading, 20).padding(.bottom, 4)
            }
        }
    }
}
