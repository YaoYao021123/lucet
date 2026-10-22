import MediaCore
import SwiftUI

/// Candidate cover frames for a Live Photo, the best one marked.
struct CoverPickerView: View {
    let editor: EditorModel
    @Binding var isPresented: Bool
    @UIState private var frames: [CoverCandidate] = []
    @UIState private var best = 0
    @UIState private var failed = false

    private let columns = Array(repeating: GridItem(.fixed(150), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("挑一张封面").font(.headline)
            Text("封面是照片库里看到的那一张。已经帮你找了最清晰的一帧；点哪一张就用哪一张。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(width: 470, alignment: .leading)
            if frames.isEmpty {
                HStack(spacing: 8) {
                    if failed { Text("没能读取这段视频的画面。").foregroundStyle(.secondary) }
                    else { ProgressView().controlSize(.small); Text("正在挑选…").foregroundStyle(.secondary) }
                }
                .frame(width: 470, height: 120)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(frames) { frame in tile(frame) }
                }
            }
        }
        .padding(16)
        .task { await load() }
    }

    private func tile(_ frame: CoverCandidate) -> some View {
        let current = abs(frame.time - editor.cover) < 0.12
        return Button {
            editor.setCover(at: frame.time)
            isPresented = false
        } label: {
            VStack(spacing: 3) {
                Image(decorative: frame.image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 150, height: 100).clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(current ? Color.white : .clear, lineWidth: 2))
                    .overlay(alignment: .topLeading) {
                        if frame.id == best {
                            Text("推荐").font(.caption2.weight(.semibold)).foregroundStyle(.black)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.white)).padding(5)
                        }
                    }
                HStack {
                    Text(timeLabel(frame.time)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    if frame.faceQuality != nil { Image(systemName: "face.smiling").font(.caption2).foregroundStyle(.secondary) }
                    if current { Text("当前").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(frame.faceQuality.map { String(format: L("清晰度 %.0f%% · 人像质量 %.0f%%"), frame.sharpness * 100, $0 * 100) }
              ?? String(format: L("清晰度 %.0f%%"), frame.sharpness * 100))
    }

    private func load() async {
        guard let url = editor.mediaURL else { failed = true; return }
        let range = editor.clipStart...max(editor.clipStart + 0.1, editor.clipEnd)
        do {
            let result = try await CoverPicker.candidates(in: url, range: range)
            frames = result.frames; best = result.best
        } catch is CancellationError {
        } catch { failed = true }
    }
}
