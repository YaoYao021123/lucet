import Foundation
import MediaCore

@main
struct MediaProbe {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first,
              ((["inspect", "lut", "straighten"].contains(command) && arguments.count == 2)
                || (command == "rotate" && arguments.count == 4)
                || (command == "straighten" && arguments.count == 3)) else {
            print("用法：media-probe inspect <素材> | lut <.cube> | straighten <图片> [新.png] | rotate <图片> <校正角度> <新.png>")
            exit(arguments.isEmpty ? 0 : 2)
        }
        do {
            let url = URL(fileURLWithPath: arguments[1]).standardizedFileURL
            if command == "inspect" {
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
