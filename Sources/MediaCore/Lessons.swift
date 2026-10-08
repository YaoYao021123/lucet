import Foundation

/// Interactive lessons: short sequences of animated, hands-on scenes that run on the user's own
/// photo. Content is data here (testable); the app draws each `LessonScene`.
///
/// Teaching pattern for every lesson: a question worth answering → a picture of the mechanism →
/// try it yourself on your photo → check what you saw.
public struct Lesson: Identifiable, Sendable {
    public let id: String
    public let unit: LessonUnit
    public let title: String
    /// The question the lesson answers, in the learner's words.
    public let hook: String
    public let concept: Concept?
    public let steps: [LessonStep]
    public var minutes: Int { max(1, (steps.count + 1) / 2) }
}

public enum LessonUnit: String, CaseIterable, Sendable {
    case reading, tone, camera
    public var title: String {
        switch self {
        case .reading: "看懂一张照片"
        case .tone: "调整明暗"
        case .camera: "拍摄的原理"
        }
    }
}

public struct LessonStep: Sendable {
    public let scene: LessonScene
    public let title: String
    public let text: String
    public var question: LessonQuestion?
    public init(_ scene: LessonScene, _ title: String, _ text: String, question: LessonQuestion? = nil) {
        self.scene = scene; self.title = title; self.text = text; self.question = question
    }
}

/// Each scene is an interactive animation the app implements.
public enum LessonScene: String, Sendable, CaseIterable {
    // Reading a photo
    case pixelGrid, brightnessOnly, histogramBuild, histogramRead
    case zoneExplorer, keyStyles
    case clippingDemo
    // Tone
    case exposureVsBrightness, toneControl, curveAxes, curveShapes
    // Camera
    case apertureOpening, depthOfField, shutterMotion, isoNoise, exposureTriangle
}

public struct LessonQuestion: Sendable {
    public enum Answer: Sendable, Equatable {
        case option(Int)
        /// The tone zone holding most of the open photo; options are the zone titles.
        case mainZone
    }
    public let prompt: String
    public let options: [String]
    public let answer: Answer
    /// Shown after answering, right or wrong.
    public let explanation: String

    public func correctIndex(zoneShares: [ToneZone: Double]) -> Int? {
        switch answer {
        case .option(let index): return index
        case .mainZone:
            guard let main = zoneShares.max(by: { $0.value < $1.value })?.key else { return nil }
            return options.firstIndex(of: main.title)
        }
    }
}

extension Lesson {
    public static let catalog: [Lesson] = [
        Lesson(id: "pixels-histogram", unit: .reading, title: "直方图从哪里来",
               hook: "调色软件里那座「小山」到底是什么？", concept: .histogram, steps: [
            LessonStep(.pixelGrid, "照片由小格子组成",
                       "放大到足够大，任何照片都是一格一格的像素。每一格只有一种颜色。"),
            LessonStep(.brightnessOnly, "先只看明暗",
                       "把颜色去掉，每一格只剩下一个亮度：0 是纯黑，100 是纯白。"),
            LessonStep(.histogramBuild, "按亮度排队",
                       "把所有格子按亮度从左到右排好，一样亮的叠在同一列。叠出来的形状，就是直方图。"),
            LessonStep(.histogramRead, "读一读你的照片",
                       "山峰在哪里，照片的大部分就在哪里。左边高说明暗的多，右边高说明亮的多。",
                       question: LessonQuestion(prompt: "这张照片的大部分在哪个区域？",
                                                options: ToneZone.allCases.map(\.title), answer: .mainZone,
                                                explanation: "看直方图最高、最宽的那一段落在哪个区域。")),
        ]),
        Lesson(id: "five-zones", unit: .reading, title: "五个亮度区",
               hook: "「提亮暗部」里的暗部，到底是哪一部分？", concept: .histogram, steps: [
            LessonStep(.zoneExplorer, "把亮度分成五段",
                       "从左到右：最暗部、暗部、中间调、亮部、最亮部。点一个区域，照片上只保留属于它的地方。"),
            LessonStep(.keyStyles, "亮和暗都可以是对的",
                       "白墙、雪景常常大部分在亮部，夜景大部分在暗部。直方图偏向一边不等于拍错了，要看你想要的感觉。",
                       question: LessonQuestion(prompt: "一张雪景的直方图大部分在右边，说明什么？",
                                                options: ["一定过曝了", "画面以亮的东西为主，可能正好合适", "相机坏了"],
                                                answer: .option(1),
                                                explanation: "直方图只说明亮度怎么分布。只有贴着最右边、出现纯白时，才是真的丢了细节。")),
        ]),
        Lesson(id: "clipping", unit: .reading, title: "纯白和死黑",
               hook: "为什么有些天空怎么调都是一片白？", concept: .clipping, steps: [
            LessonStep(.clippingDemo, "亮到头，就没有细节了",
                       "拖动曝光。太亮的地方会变成纯白（标红），太暗的地方变成纯黑（标蓝）。直方图会在边上堆成一堵墙。",
                       question: LessonQuestion(prompt: "拍摄时天空已经是纯白，后期把高光往下拉会怎样？",
                                                options: ["能找回云的细节", "只会变成一片灰，细节找不回来", "会变成蓝色"],
                                                answer: .option(1),
                                                explanation: "纯白意味着相机没有记录到那里的差别。拍的时候就要留住：降低一点曝光，或者打开 HDR。")),
        ]),
        Lesson(id: "exposure-brightness", unit: .tone, title: "曝光和亮度不一样",
               hook: "都是变亮，为什么有时候天空先「爆」掉？", concept: .exposure, steps: [
            LessonStep(.exposureVsBrightness, "一个乘，一个加",
                       "曝光像多进一倍的光：越亮的地方增加得越多。亮度更像整体往上挪一点。拖两个滑块，看右边的线怎么变。",
                       question: LessonQuestion(prompt: "照片的天空已经很亮、地面偏暗，想提亮地面，先用哪个？",
                                                options: ["曝光", "亮度或阴影"], answer: .option(1),
                                                explanation: "曝光会让本来就亮的天空先溢出；亮度和阴影对亮部影响更小。")),
        ]),
        Lesson(id: "tone-controls", unit: .tone, title: "四个滑块各管一段",
               hook: "高光、阴影、白色、黑色有什么区别？", concept: .highlights, steps: [
            LessonStep(.toneControl, "每个滑块只动自己的那段",
                       "选一个滑块拖动。照片上亮起来的是它改变的地方，直方图上阴影部分是它作用的亮度范围。",
                       question: LessonQuestion(prompt: "逆光人像，脸太暗但背景的天空正好，应该动哪个？",
                                                options: ["高光", "阴影", "白色"], answer: .option(1),
                                                explanation: "脸在暗部，阴影只提亮暗部，天空几乎不受影响。")),
        ]),
        Lesson(id: "curves", unit: .tone, title: "曲线：把旧亮度换成新亮度",
               hook: "曲线看起来很专业，其实只回答一个问题。", concept: .curves, steps: [
            LessonStep(.curveAxes, "横轴是原来，竖轴是现在",
                       "斜线上的每一点都在说：原来这么亮，现在还是这么亮。拖动中间的点，看哪段亮度变了。"),
            LessonStep(.curveShapes, "三种常见形状",
                       "整体往上 = 变亮；往下 = 变暗；S 形 = 暗的更暗、亮的更亮，对比更强。点按钮切换，看照片和直方图。",
                       question: LessonQuestion(prompt: "照片发灰、没有层次，最常用哪种曲线？",
                                                options: ["整体往上", "S 形", "整体往下"], answer: .option(1),
                                                explanation: "S 形把直方图向两边拉开，画面就不再发灰。")),
        ]),
        Lesson(id: "aperture", unit: .camera, title: "光圈：数字越大，开口越小",
               hook: "为什么 ƒ/4 比 ƒ/2.8 的光圈小？", concept: nil, steps: [
            LessonStep(.apertureOpening, "ƒ 后面是一个除数",
                       "光圈开口的直径 = 焦距 ÷ ƒ 值。所以 ƒ 值越大，开口越小，进来的光越少。ƒ 值每乘以 1.4，进光量减半。"),
            LessonStep(.depthOfField, "开口还决定背景有多虚",
                       "开口大（ƒ 值小），只有很薄的一层是清楚的，背景就虚；开口小，前后都清楚。拖动看看。",
                       question: LessonQuestion(prompt: "想拍背景虚化的人像，应该怎么选？",
                                                options: ["ƒ/1.8", "ƒ/11"], answer: .option(0),
                                                explanation: "ƒ 值小 = 开口大 = 清楚的范围薄，背景更虚。")),
        ]),
        Lesson(id: "exposure-triangle", unit: .camera, title: "快门、ISO 和曝光三角",
               hook: "同样亮的照片，为什么有的糊、有的满是噪点？", concept: .noise, steps: [
            LessonStep(.shutterMotion, "快门：开多久",
                       "快门开得越久，进来的光越多，但移动的东西会拖出影子。手持拍摄，快门最好快于 1/焦距 秒。"),
            LessonStep(.isoNoise, "ISO：把信号放大",
                       "光不够时，ISO 把传感器的信号放大，照片变亮，但噪点也一起被放大。"),
            LessonStep(.exposureTriangle, "三个旋钮，同一个亮度",
                       "光圈、快门、ISO 都能改变亮度，但各有代价：景深、拖影、噪点。调到指针居中，再看看画面的变化。",
                       question: LessonQuestion(prompt: "夜里拍街景，照片太暗又不想糊，先试哪个？",
                                                options: ["把快门调慢很多", "开大光圈，再适当提高 ISO", "把 ISO 调到最低"],
                                                answer: .option(1),
                                                explanation: "先用光圈多进光；还不够再提 ISO。快门太慢，手一抖就糊了。")),
        ]),
    ]

    public static func lesson(_ id: String) -> Lesson? { catalog.first { $0.id == id } }
}
