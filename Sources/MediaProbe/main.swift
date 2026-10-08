import AVFoundation
import Foundation
import MediaCore

@main
struct MediaProbe {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first,
              ((["inspect", "lut", "straighten", "details", "analyze", "auto"].contains(command) && arguments.count == 2)
                || (command == "auto" && arguments.count == 3)
                || (command == "live" && (3...4).contains(arguments.count))
                || (command == "details" && arguments.count == 3)
                || (command == "rotate" && arguments.count == 4)
                || (command == "straighten" && arguments.count == 3)) else {
            print("用法：media-probe inspect <素材> | live <≤3 秒的视频> <新文件夹> [封面秒数] | details <素材> [Live 动态 .mov] | lut <.cube> | straighten <图片> [新.png] | rotate <图片> <校正角度> <新.png>")
            exit(arguments.isEmpty ? 0 : 2)
        }
        do {
            let url = URL(fileURLWithPath: arguments[1]).standardizedFileURL
            if command == "live" {
                // Turns a short video into a Live Photo pair (cover JPEG + paired MOV) in a new folder; the system's
                // pairing check runs inside. The cover defaults to just before the end of the clip.
                let duration = try await AVURLAsset(url: url).load(.duration).seconds
                let cover = arguments.count == 4 ? (Double(arguments[3]) ?? duration - 0.2) : duration - 0.2
                let clip = ClipSettings(start: 0, end: min(duration, 3.0), cover: min(cover, min(duration, 3.0) - 0.05))
                let result = try await LivePhotoPipeline.export(url, to: URL(fileURLWithPath: arguments[2]).standardizedFileURL,
                                                                 clip: clip, edits: MediaEdits())
                print(result.imageURL.path); print(result.videoURL.path)
            } else if command == "auto" {
                // Developer check for 自动: the values, the statistics after, and an optional before|after JPEG.
                let session = try ImageGradeSession(url: url, maximumDimension: 1024)
                let plain = try await session.frame(edits: MediaEdits())
                guard let before = ScopeAnalyzer.analyze(plain.image, headroom: plain.headroom)?.analysis else { exit(4) }
                let auto = AutoEnhance.adjustments(for: before)
                let changed = AdjustmentParameter.allCases.filter { auto[$0] != 0 }.map { "\($0.title) \(auto[$0])" }
                print(changed.isEmpty ? "（无需调整）" : changed.joined(separator: "  "))
                let edited = try await session.frame(edits: MediaEdits(adjustments: auto))
                if let after = ScopeAnalyzer.analyze(edited.image, headroom: edited.headroom)?.analysis {
                    print(String(format: "p5 %.2f→%.2f  p50 %.2f→%.2f  p95 %.2f→%.2f  sat %.2f→%.2f  clipH %.3f→%.3f",
                                 before.p5, after.p5, before.p50, after.p50, before.p95, after.p95,
                                 before.meanSaturation, after.meanSaturation, before.clippedHighlights, after.clippedHighlights))
                }
                if arguments.count == 3 {
                    let left = ColorPipeline.toneMap(plain.image, sourceHeadroom: plain.headroom)
                    let right = edited.image.transformed(by: .init(translationX: left.extent.width + 8, y: 0))
                    let pair = right.composited(over: left)
                    try ColorPipeline.shared.writeJPEGRepresentation(of: pair, to: URL(fileURLWithPath: arguments[2]),
                        colorSpace: ColorPipeline.outputSpace, options: [:])
                }
            } else if command == "analyze" {
                // Developer check for the coach: statistics and tips for one photo, as the app computes them.
                let session = try ImageGradeSession(url: url, maximumDimension: 1024)
                let frame = try await session.frame(edits: MediaEdits())
                guard let a = ScopeAnalyzer.analyze(frame.image, headroom: frame.headroom)?.analysis else { exit(4) }
                print(String(format: "p1 %.2f p5 %.2f p50 %.2f p95 %.2f p99 %.2f mean %.2f clipH %.3f clipS %.3f sat %.2f bright %.2f dark %.2f neutral %.2f rgb %@",
                             a.p1, a.p5, a.p50, a.p95, a.p99, a.meanLuma, a.clippedHighlights, a.clippedShadows, a.meanSaturation,
                             a.brightFraction, a.darkFraction, a.neutralFraction, a.neutralRGB.map { String(format: "%.3f", $0) }.joined(separator: "/")))
                for insight in PhotoCoach.insights(for: a, edits: MediaEdits(), profile: LearnerProfile()) {
                    print("· \(insight.title)  \(insight.suggestion?.label ?? "")")
                }
            } else if command == "details" {
                let motion = arguments.count == 3 ? URL(fileURLWithPath: arguments[2]).standardizedFileURL : nil
                for file in [url] + (motion.map { [$0] } ?? []) where !FileManager.default.fileExists(atPath: file.path) {
                    print("找不到文件：\(file.path)")
                    exit(1)
                }
                print(await MediaDetails.read(url, motion: motion).text)
            } else if command == "inspect" {
                let metadata = try await MediaInspector.inspect(url)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                print(String(decoding: try encoder.encode(metadata), as: UTF8.self))
            } else if command == "lut" {
                let lut = try CubeLUT(text: String(contentsOf: url, encoding: .utf8))
                print("有效 3D LUT：\(lut.title ?? url.lastPathComponent)，\(lut.dimension) 阶，\(lut.rgb.count / 3) 条 RGB")
                print("输入域：\(lut.domainMin) → \(lut.domainMax)")
                print("这里只验证结构；尚未执行色彩转换或渲染。")
            } else if command == "straighten" {
                let assessment = try await ImageStraightener.analyze(url)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(assessment), as: UTF8.self))
                if arguments.count == 3 {
                    if let plan = assessment.plan {
                        _ = try ImageStraightener.exportPNG(url, to: URL(fileURLWithPath: arguments[2]), degrees: plan.rotationDegrees)
                        print("已导出 SDR PNG 副本；原片保留。")
                    } else {
                        print("未自动导出：\(assessment.message)")
                        exit(3)
                    }
                }
            } else {
                guard let degrees = Double(arguments[2]), degrees.isFinite else { throw StraighteningError.invalidGeometry }
                let plan = try ImageStraightener.exportPNG(url, to: URL(fileURLWithPath: arguments[3]), degrees: degrees)
                print("已导出 SDR PNG 副本：\(plan.outputWidth) × \(plan.outputHeight)；原片保留。")
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
