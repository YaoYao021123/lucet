# Lucet 光集 · 「边调边学」专章口播稿（中文 + English）

这是主视频（[script-long.md](script-long.md)）之外的**第二章**：只讲互动课。适合单独发 B 站 / 视频号 / YouTube，也可以拆成短视频；主视频里只留一小段预告，指向这里。

时长：中文约 6 分钟（按每秒 5 个字，含标点），英文约 7 分钟（每分钟约 140 词）。七个小节可以单独拿出来用，想短一些，保留第 1、2、7 节，或者每节发一条短视频。`【…】` 里是留给你自己的话（你自己学摄影时卡在哪里，最能让人觉得亲近）。

怎么用：

- **提词器**：`docs/marketing/xiaohongshu/teleprompter.html?v=learn-zh`（中文）或 `?v=learn-en`（英文）。改了这里，运行 `python3 scripts/sync-teleprompter.py` 同步。
- **白板**：这一章有 7 页手绘白板（`why` `read` `light` `color` `shoot` `video` `lessons`），剪辑时加 `--chapter learn`，见 [xiaohongshu/script.md](xiaohongshu/script.md) 第 1c 节。每页里放的是**应用自己渲染的课程截图**（3D 场景也在内）。
- **画面**：课程的动画要真的动起来才好看。用 macOS 自带录屏（⇧⌘5）录一课的 15–20 秒（打开一课 → 拖一拖 → 转一转 3D），比静态图有说服力得多。没有录屏时，每页用的截图也够用。全部 27 个步骤的截图可以用 `bash scripts/make-lesson-stills.sh <照片>` 重新生成（放在 `dist/lesson-stills/`）。
- 稿子里每节课的**问题和答案都来自课程本身**（`Sources/MediaCore/Lessons.swift`），没有加课程里没有的内容。别加没做的课：目前一共 13 课。
- 张小样那一段是诚实的致谢，灵感来源，不是合作；如果你不想提名字，换成「抖音上有摄影博主……」即可。别说价格、「免费」「收费」。

---

## 中文版

### 1. 为什么要教（约 32 秒）

一键滤镜，能让一张照片变好看。
可是下一次，你还是不知道，为什么。

抖音上有一位摄影博主，张小样，他用动画讲直方图、讲曲线、讲光圈，比任何说明书都清楚。
可惜，他只有几条视频，讲不完所有的基础。

所以，我们把这种讲法，放进了 App 里。
而且，用的是你自己的照片。

每一课只要几分钟：先看动画，再自己拖一拖，最后有一个小问题。

【这里说一句你自己：你学摄影的时候，卡在哪个词上？比如：「我第一次听说直方图，是在一个教程里，一句话就带过去了。」】

〔画面：「学习」面板（`website/assets/panel-learn.jpg`）；点开一课；动画、拖一拖、小问题各给 3 秒。〕

### 2. 看懂一张照片（约 49 秒）

先从一个问题开始：调色软件里，那座「小山」，到底是什么？

答案是，一张照片，碎成一个个小格子。
去掉颜色，只剩明暗；再把明暗变成高度，照片就成了一片立体的柱子，你可以用手拖着转。
然后把所有的格子，按亮度排好队，一样亮的，叠在同一列。叠出来的形状，就是直方图。

接着是：「提亮暗部」里的暗部，到底是哪一部分？
把亮度分成五段，从最暗部，到最亮部。点哪一段，照片上就只保留属于它的地方。

还有一课，专门讲：为什么有些天空，怎么调都是一片白。
因为纯白的地方，相机根本没有记录到那里的差别，后期是找不回来的。

〔画面：`lesson-pixels-histogram-3`（3D 柱子 + 五个亮度区）、`lesson-five-zones-0`、`lesson-clipping-0`。拖着转一转 3D。〕

### 3. 调整明暗（约 44 秒）

都是变亮，为什么有时候，天空先「爆」掉了？
因为曝光，像是多进了一倍的光：越亮的地方，增加得越多。而亮度，更像是整体往上挪一点。

高光、阴影、白色、黑色，有什么区别？
选一个滑块拖一拖：照片上亮起来的，就是它改变的地方；直方图上的阴影，就是它管的那一段亮度。

曲线，看起来很专业，其实只回答一个问题：原来多亮，现在多亮。
横着是原来，竖着是现在。往上拉，就是变亮；S 形，是暗的更暗，亮的更亮，对比就变强了。所以照片发灰的时候，最常用的就是 S 形。

〔画面：`lesson-exposure-brightness-0`、`lesson-tone-controls-0`、`lesson-curves-1`。〕

### 4. 颜色（约 47 秒）

为什么在室内拍的照片，总是发黄？
因为光本身，是有颜色的。烛光和灯泡偏橙，正午的阳光接近白，阴天和树荫偏蓝。

课里让你在照片上，点一个本来就该是白色或灰色的地方，光集就把它校正成中性灰，整张照片的偏色，也跟着消失了。
你还能看到，照片的像素，在一个 RGB 立方体里，是怎样偏离灰色的那根轴的。

再问一个：怎样只让天空更蓝，而草地不变？
答案是 HSL。任何一种颜色，都能用三个数找到：绕着圈的是色相，向外是饱和度，向上是明亮度。选中蓝色，只把蓝色的明亮度往下压，天空变深，草地不动。

〔画面：`lesson-white-balance-0`、`lesson-white-balance-1`、`lesson-hsl-1`。〕

### 5. 拍摄的原理（约 76 秒）

这些课，不只教你修，也教你拍。

为什么 ƒ/4，比 ƒ/2.8 的光圈小？
因为 ƒ 后面，是一个除数：开口的直径，等于焦距，除以 ƒ 值。ƒ 值越大，开口越小，进来的光越少。
想拍背景虚化的照片，就要开大光圈：这时候，空间里只有很薄的一层是清楚的，前面和后面的东西，就虚了。

同样亮的照片，为什么有的糊，有的满是噪点？
课里把时间想成纵深：快门开着的那段时间，是一块玻璃板，板越厚，进来的光越多，球在板里走过的路，也越长，这就是拖影。
ISO 呢，是把每一格收到的光，统统放大；可光是一颗一颗随机落下来的，放得越大，噪点就越明显。
光圈、快门、ISO，三个旋钮，同一个亮度，每一个都有它的代价：景深、拖影、噪点。

还有，同一个位置，为什么手机的「2 倍」「5 倍」，拍出来差这么多？
因为焦距越长，相机看到的是一个越窄的楔形，同一座山，占的画面比例就越大，背景显得又大又近。

〔画面：`lesson-aperture-1`（景深那块薄板）、`lesson-exposure-triangle-0`（快门的玻璃板）、`lesson-focal-length-0`（楔形视野）。都是 3D，拖着转。〕

### 6. 视频（约 39 秒）

拍视频的人，还有两课。

为什么视频的快门，不能像拍照那样越快越好？
因为每一帧，都要有一点拖影。常用的做法是：快门大约等于一除以两倍的帧率。用 25 帧拍，就是五十分之一秒。太快了，每一帧都清清楚楚，连起来反而一跳一跳。

还有，D-Log 拍出来，为什么灰蒙蒙的？
因为 Log，把更多的亮度，装进了同一个文件，代价就是又灰又淡。所以拿到素材，第一步，是先套用这台相机对应的转换 LUT，再去调。

〔画面：`lesson-frame-rate-1`、`lesson-log-lut-1`。如果你有 DJI 的 D-Log 素材，在这里放一段「灰」和「还原后」的对比。〕

### 7. 一共十三课（约 58 秒）

现在一共有十三课，从直方图、曝光、曲线，到白平衡、光圈、焦距，还有视频的帧率和 Log。
很多课里的画面，是 3D 的，可以用手拖着转。

你可以选初级、中级、高级，讲解的深浅，会跟着变。
学过什么，只记在你的 Mac 上。

它还会读你的这张照片，指出哪里亮过头了，哪里偏色，再给你一个，点一下就能试的调整。
而且，它从来不催你学。想知道一个滑块是做什么的，在它上面点右键，或者把鼠标放在区块的标题上，点那个小小的播放键，课就在眼前；学完，回到你的照片，刚才那几个滑块会轻轻亮一下。
不想学，它一句也不会打扰你，还能整个关掉。
文字和动画，都是我们自己写、自己画的，而且还在一课一课地往上加。

〔画面：「学习」面板里的 13 节课；悬停在滑块名字上，照片上亮出它管的那一段；在滑块上点右键看到「……是做什么的？」；区块标题旁的小播放键；最后回到一张调好的照片。〕

---

## English version

*Written for an English-speaking audience, not a line-by-line translation. Every lesson's question and answer comes from the lesson itself.*

### 1. Why teach (~40 s)

A one-tap filter can make a photo look better.
But next time, you still don't know why.

There's a photography creator on Douyin, Zhang Xiaoyang, who explains histograms, curves and aperture with animation, more clearly than any manual I've read.
But he's only made a handful of videos. They can't cover all the basics.

So we brought that way of teaching into the app.
And we do it with your own photo.

Each lesson takes a few minutes: watch the animation, drag something yourself, and answer one small question.

【One line of your own: where did you get stuck when you were learning photography? e.g. "The first time I heard the word histogram, it was one sentence in a tutorial, and then it moved on."】

[The Learn tab (`website/assets/en/panel-learn.jpg`); open a lesson; give the animation, the dragging and the question three seconds each.]

### 2. Reading a photo (~65 s)

Let's start with a question: in every editing app, what is that little mountain?

The answer starts with a photo, broken into small cells.
Take away the color and you're left with brightness. Turn the brightness into height, and the photo becomes a field of columns that you can drag to turn.
Then line all the cells up by brightness, with equally bright ones stacked in the same column. The shape that builds up is the histogram.

Next: when an editor says "lift the shadows", which part of the photo is that?
The lesson splits brightness into five zones, from the darkest to the brightest. Click one, and only the part of the photo that belongs to it stays.

And one lesson is about why some skies stay white however you edit them.
Because in a pure white area the camera never recorded any difference, and editing can't bring it back.

[Stills: `lesson-pixels-histogram-3` (3D columns and the five zones), `lesson-five-zones-0`, `lesson-clipping-0`. Drag the 3D scene around.]

### 3. Light and shadow (~55 s)

Both make a photo brighter, so why does the sky sometimes blow out first?
Because exposure is like letting in twice the light: the brighter the spot, the more it gains. Brightness is more like nudging everything up a little.

Highlights, shadows, whites, blacks: what's the difference?
Drag one slider and the photo lights up where that slider works; the shaded part of the histogram is the range of brightness it controls.

Curves look very professional, but they only answer one question: how bright was it, and how bright is it now?
Across is before, up is after. Pull up and it's brighter. An S-shape makes darks darker and lights lighter, so contrast goes up. That's why an S-curve is the usual fix for a gray, flat photo.

[Stills: `lesson-exposure-brightness-0`, `lesson-tone-controls-0`, `lesson-curves-1`.]

### 4. Color (~60 s)

Why do photos taken indoors always look yellow?
Because light itself has a color. Candles and bulbs lean orange, noon sun is close to white, overcast and shade lean blue.

In the lesson, you click a spot in the photo that should be white or gray, and Lucet corrects it to neutral gray, and the color cast across the whole photo goes with it.
You can also see the photo's pixels in an RGB cube, and how they drift away from the gray axis.

One more: how do you make only the sky bluer while the grass stays the same?
The answer is HSL. Any color can be found with three numbers: around the circle is hue, outward is saturation, upward is brightness. Pick blue, pull down only the blue's brightness, and the sky gets deeper while the grass doesn't move.

[Stills: `lesson-white-balance-0`, `lesson-white-balance-1`, `lesson-hsl-1`.]

### 5. How shooting works (~100 s)

These lessons don't only teach you to edit. They teach you to shoot.

Why is f/4 a smaller opening than f/2.8?
Because the number after the f is a divisor: the diameter of the opening equals the focal length divided by the f-number. The bigger the number, the smaller the opening and the less light gets in.
Want a blurry background? Open the aperture wide. Then only a very thin slice of space is sharp, and what's in front and behind it goes soft.

Two photos, equally bright. Why is one blurry and the other full of noise?
The lesson treats time as depth. The time the shutter is open is a slab of glass. The thicker the slab, the more light gets in, and the longer the path a moving ball travels inside it, and that's motion blur.
ISO multiplies whatever each cell collected. But light lands one particle at a time, at random, so the more you multiply, the more the noise shows.
Aperture, shutter and ISO are three knobs for the same brightness, and each has its price: depth of field, blur, noise.

And one more: from the same spot, why do a phone's "2×" and "5×" look so different?
Because the longer the focal length, the narrower the wedge the camera sees. The same mountain fills more of the frame, and the background looks bigger and closer.

[Stills: `lesson-aperture-1` (the thin slab of sharpness), `lesson-exposure-triangle-0` (the shutter's slab of glass), `lesson-focal-length-0` (the wedge of view). All 3D, drag to turn.]

### 6. Video (~50 s)

If you shoot video, there are two more lessons.

Why can't a video's shutter simply be as fast as possible, the way it is for photos?
Because every frame needs a little blur. The usual rule: shutter is about one over twice the frame rate. Shooting 25 frames a second, that's 1/50. Faster, and every frame is crisp, but played together it stutters.

And why does D-Log footage look so flat and gray?
Because Log packs more brightness into the same file, and the price is that it looks gray and washed out. So when you get the footage, the first step is to apply the conversion LUT for that camera, and only then start grading.

[Stills: `lesson-frame-rate-1`, `lesson-log-lut-1`. If you have your own D-Log footage, add a before/after of the gray and the converted version here.]

### 7. Thirteen lessons (~65 s)

There are thirteen lessons now: histograms, exposure, curves, white balance, aperture, focal length, and for video, frame rate and Log.
Many of them are in 3D, and you can drag to turn them.

You can choose Beginner, Intermediate or Advanced, and the explanations change depth.
What you've learned stays on your Mac.

It also reads your photo and points out where it's too bright and where there's a color cast, with an adjustment you can try in one click.
And it never nags. Want to know what a slider does? Right-click it, or hover over a section's title and click the small play button, and the lesson is right there. When it ends, you're back on your photo, and those sliders glow for a moment.
If you'd rather not learn, it stays quiet, and you can switch it all off.
Every word and every animation is our own, and we keep adding lessons one at a time.

[The 13 lessons in the Learn tab; hover over a slider's name and the photo lights up the part it controls; right-click a slider to see "What does … do?"; the small play button beside a section title; end on a finished photo.]
