# Lucet 光集发布包

怎么让该知道光集的人知道它。里面的帖子草稿都是用「我」的口吻写的，发之前请改成你自己的话；方括号 `[…]` 是需要你补的链接或信息。

> 最近一次整理：2026-10-20，对照 README、网站（中 / 英）和 `git log`。功能、局限和发布状态以那一天的项目为准；之后又改了东西，请先看 README 的「Features」和「Current limitations」。
>
> 小红书的视频、图文 / 实况图、口播稿和发布文案在 [xiaohongshu/script.md](xiaohongshu/script.md)。
> **「和 AI 一起做出来」的故事**（真实节点、数字、三篇帖子草稿）在 [story.md](story.md)。
> 长版口播稿（中文约 6.5 分钟，English 约 8 分钟）在 [script-long.md](script-long.md)。

## 0. 名字和链接怎么写

- 品牌全称：**Lucet 光集**（英文在前，中间一个空格）。标题、首次出现、图片和视频封面都用全称。
- 正文里第二次以后可以只写「光集」；英文环境写 **Lucet**。
- 口号：**让每一个瞬间，自有光彩。**（英文：Let your moments shine.）
- 名字的来历，一句话版：Lucet 是拉丁语「它在发光」，光集是把光收集起来。
- 「Lucet」怎么读需要你定一个：英文习惯读「卢-塞特」（/ˈluː.sɛt/），古典拉丁语读「卢-凯特」（/ˈluː.kɛt/）。定下来后，视频和口播里统一用一种。
- 链接：
  - 网站（中文）https://yaoyao021123.github.io/lucet/　（English）https://yaoyao021123.github.io/lucet/en/
  - 代码：https://github.com/YaoYao021123/lucet （2026-10-17 从 `pic_review_edit` 改名，旧地址会自动跳转，但新帖子请只用新地址）

## 1. 先把一句话说清楚

**定位**：给 DJI 和 iPhone 拍摄者的 Mac 照片和视频调色工具，简单得像手机 App，需要时有完整的专业工具，边调边学；界面有中文和 English。

**起因（真实、可信的那一句）**：DJI Mimo 只有手机版（iOS / Android），想在 Mac 上调色没有顺手的选择；Lightroom 和 Photoshop 又太复杂。

一句话备选：

- 在 Mac 上把照片调好看，不用先学摄影。（网站主标题）
- DJI Mimo 只有手机版？Lucet 把调色搬到 Mac 上。
- 一键自动，六个滑块，调完存进「照片」。
- 一组照片，一个调色。
- 比 Lightroom 简单，比手机 App 大。
- English: Photo and video color for the Mac, no photography class required.

三种长度的介绍：

- **15 字**：Mac 上最简单的照片视频调色。
- **50 字**：Lucet 光集是一款 Mac 调色工具：一键自动、六个滑块、预设一眼挑，DJI 和 iPhone 拍的照片、视频、Live Photo 都能调，调完直接存进「照片」，不用先学摄影。
- **150 字**：我用 DJI 拍素材，想调颜色，才发现 DJI Mimo 只有手机版；Lightroom、Photoshop 又什么都有，却让没有基础的人无从下手。所以做了 Lucet 光集：默认只有「自动」和六个滑块，预设直接用你的照片预览，裁剪直接在画面上拖；只想改一部分，就拉一道渐变、涂一笔去掉路牌；同一次旅行的照片放进一个「项目」，共用一套颜色；想学，它会指着你这张照片讲道理，互动课里不少画面还是能拖着转的 3D。原片从不被修改，不上传照片，所有计算都在你的 Mac 上。

## 1b. 现在能讲的卖点（按先后顺序挑）

先讲最简单的那几条，再按对象挑后面的。每一条都有真实输出的图或 GIF，不用另做。

| 对谁讲 | 卖点 | 一句话 | 图 / 素材 |
|---|---|---|---|
| 所有人（先讲） | 一键「自动」 | 先读这张照片再调；白底、雪景不压灰，夜景还是夜景，日落保留暖色；不满意 ⌘Z | `website/assets/compare-auto.gif`、`before.jpg` / `after.jpg` |
| 所有人 | 六个滑块 + 能看见的预设 | 每个滑块一句人话；预设直接用你的照片预览 | `panel-presets.jpg` |
| 所有人 | 调完存进「照片」 | iCloud 照片开着，iPhone 上就能看到；Live Photo 也能编辑，导出还是 Live Photo | `sheet-export.jpg` |
| 想学的人 | 边调边学 | 13 节互动课，用你自己的照片；不少课是能拖着转的 3D；「五个亮度区」让你看见每个滑块改了哪一段 | `panel-learn.jpg` |
| 想改一部分的人 | 局部调整 + 去除 | 渐变压暗天空、椭圆提亮主体、画笔涂；自动找到主体；一笔去掉电线、路人 | `compare-sky.gif`、`compare-remove.gif`、`shot-local.jpg` |
| 想统一颜色的人 | 匹配色调 + 导出 LUT + 项目 | 借另一张照片的颜色；导出 `.cube` 给达芬奇 / Final Cut；一个项目里改一张、整组跟着变 | `compare-match.gif`、`shot-project.jpg` |
| 拍得多的人 | 筛片 | 重复文件、相似连拍分组，并排对比，选一张留下；按内容搜「天空」「狗」；从「照片」里挑着导入 | `shot-similar.jpg`、`sheet-compare.jpg` |
| DJI 用户 | DJI 素材 | 10-bit HEVC、DJI 官方 `.cube` LUT（Pocket 3 测试过）、视频裁剪变速、做成 Live Photo | `panel-info.jpg` |
| 对 AI 好奇的人 | AI 调色 / AI HDR | 小型神经网络为这张照片生成调色；让普通照片在 HDR 屏幕上有真正的高光；模型随 App 安装，在本机运行，不上传 | 网站「AI 调色」「AI HDR 光感」 |

AI 相关的说法要准：**AI 调色**用的是 Image-Adaptive-3DLUT（Apache-2.0），**AI HDR**用的是 GMNet（MIT），都在本机用 Swift 跑，致谢写在 README 和 `assets/models/NOTICE.md`。Live Photo 动态部分的 AI HDR 标明是「实验」功能，别说成成熟功能。

## 2. 谁会在意，去哪找

| 人群 | 他们的痛点 | 去哪里 |
|---|---|---|
| DJI 无人机 / Pocket / Action 用户 | 素材在手机 Mimo 里调，想在 Mac 上调 | 小红书、B 站（DJI 话题）、DJI 论坛和贴吧、各类无人机群；英文：r/dji、DJI 相关论坛 |
| iPhone / Live Photo 爱好者 | 想把视频做成 Live Photo，想统一调色 | 小红书、即刻、少数派；英文：r/iphonephotography 等 |
| 摄影入门者 | 想学调色，被 Lightroom 吓到 | 小红书、知乎、B 站入门教程评论区 |
| Mac 小工具爱好者 | 找轻量、原生的工具 | 少数派、V2EX（分享创造）、即刻；英文：r/macapps、Product Hunt |
| 用 AI 做东西的人（story 的读者） | 想看一个真实的、从原型到成品的例子，想找人交流 | 即刻、V2EX、少数派；英文：Hacker News（Show HN）、X / Bluesky、Claude Code 相关社区 |

先从最贴近的两类开始：**DJI 用户** 和 **摄影入门者**。起因就是为他们做的，也最容易讲清楚。「用 AI 做东西」的故事是第二波，适合在已经有人能下载、能试用之后再讲。

> 每个社区对自我推广的规则不同（有的要求先参与、有的限制链接、有的有专门的分享版块），**发之前读一遍规则**，规则会变，以发布当时为准。英文社区写英文帖，不要直接贴机翻。

## 3. 帖子草稿

### 小红书（短，图为主）

> **标题**：DJI 拍完想在 Mac 上调色？做了个最简单的
>
> 用 DJI 拍了素材，想调颜色，发现 Mimo 只有手机版，Lightroom 又太复杂。
> 所以做了「Lucet 光集」：
> ✅ 一键自动，调好大概的样子
> ✅ 只有 6 个滑块：亮度、对比度、亮部、暗部、冷暖、鲜艳度
> ✅ 预设直接用你的照片预览
> ✅ 只想改天空？拉一道渐变就行；一笔还能去掉路牌
> ✅ 调完直接存进「照片」，iPhone 上就能看到；Live Photo 也能编辑
> ✅ 一次旅行的照片放进一个「项目」，一套颜色
> 原片不会被改，也不上传任何东西。
> 目前是早期版本，Apple 芯片 Mac、macOS 15+，界面有中文也有 English。[链接]
>
> **配图顺序**：自动前后对比 → 预设缩略图 → 局部调整（压暗天空）→ 去除 → 项目 → 导出到「照片」（图文卡片的前 10 张已经按这个顺序做好，见 xiaohongshu/script.md 第 6 节）

### 即刻 / 微博（一段话）

> 做了个 Mac 上的调色工具「Lucet 光集」。起因：DJI Mimo 只有手机版，想在 Mac 上调色只剩 Lightroom/PS，对没基础的人太重了。光集默认只有「自动」+ 六个滑块，预设用你的照片预览，调完存进「照片」。想改一部分有渐变、画笔和去除；一组照片可以放进「项目」共用一套颜色；想深入再展开示波器、色轮、曲线，它还会指着这张照片告诉你哪里有问题。最早的原型是 ChatGPT 写的，后来全程和 Claude Code 一起改。早期版本，欢迎试用和吐槽 [链接]

### 少数派 / V2EX / 知乎（长，讲过程）

大纲：
1. **起因**：DJI Mimo 只有手机版，想在 Mac 上调色。
2. **目标用户**：不懂摄影的人。所以默认只给最少的东西。
3. **三个设计决定**：
   - 「自动」要克制：白底、雪景不压灰，夜景保持暗，日落保留暖色。（可放前后对比图）
   - 预设用你自己的照片预览，而不是文字名字。
   - 教学跟着这一张照片走，而不是固定教程。
4. **后来长出来的**：局部调整、去除、匹配色调、项目、筛片、AI 调色和 AI HDR；每一项都是「一句人话 → 一版改动」的结果（见 story.md 第 3 节）。
5. **做的过程**（可选，很多人爱看）：用 AI 协作完成；一路发现的问题，比如白底照片被当成「过曝」、Live Photo 导出后只剩视频，都改掉了（见 story.md 第 4 节）。
6. **现在的局限**（诚实写，会增加信任）：仅 Apple 芯片、macOS 15+；还没有苹果公证，首次打开要手动放行；RAW 只当普通图片打开，不做 RAW 冲洗；编辑 HDR 照片时按标准亮度预览（导出保留 HDR）；D-Log 需要手动导入转换 LUT；渐变、椭圆、画笔也能用在视频和 Live Photo 上，「主体」和「去除」暂时只用于照片。
7. **下一步**：想听你们要什么。附 [链接]。

### English（GitHub、Product Hunt、Reddit、X / Bluesky）

**一句话（GitHub About / 个人简介）**

> Lucet 光集: photo and video color for the Mac, no photography class required. One-click Auto, six plain sliders, presets you can see, save straight to Photos.

**Product Hunt**

- Tagline（≤ 60 字符）：`Photo and video color for Mac, no course required`
- Description（≤ 260 字符）：
  > Lucet is a color tool for Mac, built for people who shoot with DJI or iPhone and find Lightroom intimidating. One-click Auto, six sliders, presets previewed on your own photo, local adjustments, Live Photo editing, and lessons that use your photo. Originals are never changed; nothing is uploaded.

**Show HN（草稿，发之前按版块规则再改）**

> **Title**: Show HN: Lucet – a Mac color app for beginners, built with Claude Code
>
> I shoot with DJI gear and found DJI Mimo only exists on phones; Lightroom and Photoshop are too much for someone with no photography background. So I built a Mac app that starts with one-click Auto and six sliders, with the full tools tucked away.
>
> The first prototype was written by ChatGPT (the repo's first commit says so). I took it to Claude Code, and the first job was finding problems, each measured on a real Mac: adding a folder of 2,000 files went from 6.9 s (UI frozen) to under 0.01 s. After that almost every change started as one plain sentence from me ("this blue is too bright", "too many boxes"), and I looked at the result and said the next thing. The AI also got things wrong, and I've written down some of those.
>
> It's an early version: Apple silicon, macOS 15+, not notarized yet, interface in English and Chinese. Photos stay on your Mac; the two small neural models (AI Look, AI HDR) ship inside the app. Source and notes: https://github.com/YaoYao021123/lucet · [website]
>
> Happy to hear what's confusing, and how you work with AI tools if you build things with them.

**Reddit（r/macapps 之类，按版规调整）**

> **[Showcase] I made a Mac color tool for people who find Lightroom intimidating**
> DJI Mimo is phone-only, so grading drone footage on a Mac meant going back to the phone. Lucet: Auto + six sliders by default, presets previewed on your own photo, gradient / brush / remove for just part of a picture, projects that share one look across a set, Live Photo editing, and lessons that use your own photo. Originals are never modified, no account, nothing uploaded. Early version: Apple silicon, macOS 15+, not notarized yet (first launch needs "Open Anyway"). Feedback welcome: [link]

**X / Bluesky（4 条）**

1. DJI Mimo only exists on phones. Lightroom is a wall of sliders. So I built a Mac color app that starts with one button: Auto. [GIF: compare-auto.gif]
2. It holds back on purpose: white backdrops stay bright, night stays night, sunsets stay warm. Don't like it? ⌘Z.
3. Only the sky needs fixing? Drag a gradient. Wire in the way? Paint over it. [GIF: compare-sky.gif / compare-remove.gif]
4. The first prototype was ChatGPT's; the rest is me saying one plain sentence at a time to Claude Code. Early version, Apple silicon. [link]

> 英文帖里别写「free」「paid」「price」（项目没有定价，见下面第 7 节）；也别说「AI-powered」当卖点，说清楚具体做了什么。

## 4. 演示视频（45–60 秒，最值钱的素材）

没有任何一段文字比得上一段屏幕录制。建议用 macOS 自带的录屏（⇧⌘5），在真实的光集窗口里录（这样能看到真实的液态玻璃效果）：

1. 0–3 秒：拖进一个 DJI 素材文件夹。
2. 3–10 秒：点开一张偏灰的照片，按 `A`，再按 `\` 来回对比前后。
3. 10–16 秒：点几个预设，看缩略图和画面的对应。
4. 16–22 秒：切到「构图」，在画面上拖裁剪框，裁成方图。
5. 22–30 秒：「局部调整」里拉一道渐变压暗天空；再用「去除」涂掉一个路牌。
6. 30–36 秒：把几张照片放进一个「项目」，改其中一张的颜色，整组跟着变。
7. 36–46 秒：打开一段视频，裁成 3 秒，点「制作 Live」；或打开一张 Live Photo，调色后导出。
8. 46–56 秒：导出，选「保存到 照片」，切到「照片」App 里看到结果。

字幕只写一句：**Mac 上最简单的调色。**

已经做好的版本：竖屏动画视频（`xiaohongshu/video.html`，约 64 秒，没有声音，可以叠你自己的口播）、真人出镜 + 手绘白板的剪辑工具（`xiaohongshu/script.md` 第 1c 节）、12 张图文 / 实况卡片。

## 5. 发布前清单

状态是 2026-10-20 核对的，打勾的是我查过的，没打勾的需要你来做。

**已经完成**

- [x] 网站已上线：中文 https://yaoyao021123.github.io/lucet/ 、英文 …/en/，都能打开；最近一次发布工作流成功（2026-10-18，之前有几次失败后又重跑成功）。
- [x] README、网站、仓库地址、Pages 都已经跟着改名到 `lucet`。
- [x] 界面有中文和 English；README 和网站也有两种语言。
- [x] 第三方模型的许可证和致谢已随 App 附带（`assets/models/NOTICE.md`，Image-Adaptive-3DLUT 的 Apache-2.0 全文）。

**必须先做**（不做就别发）：

- [ ] **GitHub 上还没有任何 Release**（检查时数量是 0）。网站和 README 的「Download」都指向 Releases，现在点过去是空的。先做：`bash scripts/package-release.sh`，会在 `dist/` 里生成 `Lucet-<版本>-arm64.zip`（版本号在 `scripts/run-workbench.sh` 的 `CFBundleShortVersionString`，现在是 0.3.0），再在 GitHub 新建 Release 上传它。`dist/` 里那个叫 `Guangji-0.3.0-arm64.zip` 的是改名前的旧包，不要用。
- [ ] 找一台**没装过开发工具的 Mac**（或新建一个用户账户），按网站上的步骤从下载到打开走一遍，确认「仍要打开」的流程没有写错。
- [ ] 在你自己的 Mac 上**实际测一遍存到「照片」**：导出一张照片、一段视频、一个 Live Photo（包括编辑后的 iPhone Live Photo），确认出现在「照片」里、日期是拍摄日期，iPhone 上也能同步。这是主推功能，我只在代码和系统的检查里验证过，没有在你的「照片」资料库里实测。
- [ ] 给仓库选一个许可证（现在仍然没有 `LICENSE`，法律上默认别人不能使用或修改；邀请别人一起做之前请先选）。
- [ ] 把 `improve-workbench` 合并进 `main`（PR：https://github.com/YaoYao021123/lucet/pull/1 ；目前网站是从 `improve-workbench` 发布的，合并前请确认发布分支设置）。

**强烈建议**：

- [ ] **合作伙伴的署名措辞**：README 目前写的是「一位合作伙伴做了网页版（开源，Apache-2.0）」，没有点名也没有链接。对外讲之前请先和对方确认怎么写，再决定要不要点名、放链接。
- [ ] 确认网站和截图里的示例照片、视频你都有权公开（网站用的是风景和航拍，没有人像）。
- [ ] 找 3–5 个**真正没用过的人**试用，看他们第一次打开卡在哪里（见下）；最好有一位英文用户。
- [ ] 开 Issues，写一个简短的反馈模板（系统版本、素材来源、截图）。
- [ ] 想要更真实的首屏，用真实屏幕录制替换网站首屏图（现在的截图是用应用自己的渲染生成的，内容真实，但不是系统录屏）。

## 6. 找人试用时，问这些

不要问「好用吗」，要看他们做，并问：

1. 第一次打开，你觉得这是做什么的？（看首屏是否说清楚）
2. 请你把这张照片调好看。（别提示；看他们先点哪里，有没有找到「自动」）
3. 你觉得「亮部」「暗部」是什么意思？（测文案）
4. 这张照片只有天空太亮，你会怎么办？（看有没有找到「局部调整」）
5. 调完你会怎么把它放进手机？（看有没有找到「保存到 照片」）
6. 这三张照片是同一次旅行拍的，你想让它们颜色一致，会怎么做？（看有没有发现「项目」）
7. 哪一刻你想关掉它？
8. 你愿意把它推荐给谁？为什么？

记录他们**没问出口的卡顿**，比他们说的更有用。英文用户另外看：界面里有没有还是中文的地方、有没有读不懂的翻译。

## 7. 说话要注意

- **别说「DJI 在 Mac 上没有软件」**。DJI Studio 有 Mac 版（用于 360° 素材）；准确的说法是 **DJI Mimo 只有手机版（iOS / Android）**。
- 不要暗示和 DJI、Apple、Adobe、Anthropic、OpenAI 有合作或认可；网站页脚和 README 已经有声明。
- 不要拿 Lightroom、Photoshop 来贬低；说「对没有基础的人太重」就够了。
- **不要写没做到的**：D-Log 自动识别、Intel Mac、Windows、RAW 冲洗、苹果公证、多轨视频剪辑，目前都没有。（英文界面、HDR 照片导出保留 HDR、局部调整、Live Photo 编辑、项目，已经有了，可以讲。）
- 说 AI 要具体：「一个小型神经网络，在你的 Mac 上为这张照片生成调色」，不要说「AI 魔法」。AI 调色和 AI HDR 的模型来自别人的开源研究，致谢要在；它们不是我们训练的。
- 价格：目前没有定价，网站和 README 都不提价格。对外也不要主动承诺「免费」或「收费」；以后如果有变化，先改网站和 README，再对外说。唯一要说明的费用：可选的「问问这张照片」需要你自己的 Anthropic API 密钥，默认关闭。
- 合作伙伴：只用 README 里的措辞，不点名、不用任何人称代词猜测对方的性别。
- 讲「和 AI 一起做」时，分工要准确：原型是 ChatGPT 写的；之后的改造、网站、视频是在 Claude Code 里完成的；方向、品味和拍板是你。别说「AI 全自动做完」，也别说「我一个人写的」。
