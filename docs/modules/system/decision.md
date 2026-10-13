# System · 取舍记录

<!-- 新的在最上面。 -->

## 2026-10-12 · 缩略图抓取：SCK 公开 API，不用私有 SkyLight

- **背景**：spec §4 的 spike。私有 `CGSHWCaptureWindowList` 比 SCK 快 ~10ms，
  且能抓个别 SCK 失败的 Chrome 窗口（历史见过 -3811）。
- **选定**：`SCShareableContent` + `SCContentFilter(desktopIndependentWindow:)` +
  `SCScreenshotManager.captureImage`。**搁置窗口不实时抓** —— spike 实测三条路
  各有各的坏法（斜的透视条带 / 全白 / 不稳定），它们的卡片走「缓存上一张好图 →
  app 图标」的降级。用户看到的是它搁置**前**的全分辨率样子，比任何实时抓取都清楚。
- **放弃了**：私有 SkyLight（`dlopen` + 零文档 + 每次 macOS 升级赌一次，换 10ms
  和一类边缘窗口不值）；`SLSCaptureWindowsContentsToRectWithOptions`（符号存在但
  没有任何公开签名，参数猜错有把 WindowServer 搞崩的风险）。
- **代价**：多一项 TCC（屏幕录制）、多一个权限失败面；搁置窗口没有实时图。
- **推翻条件**：SCK 在真实使用里经常抓不到正常窗口（那时重估私有路径），
  或 Apple 给出抓「合成后但未变换」窗口的公开 API。

## 2026-10-12 · 缩略图判据：关掉 shadow framing + 四角采样内缩 2px

- **背景**：`looksLikeWindowRender` 的四角不透明判据第一版采最外圈 —— 真窗口的圆角
  本身就是透明的，**每一扇真窗口都被判否**（320pt 宽抓图，缩到 32×32 采样后 (0,0)
  的 alpha = 0）。另外 SCK 默认带 shadow framing，阴影把窗口从抓取边界内缩，
  抓出来的不是窗口本身。
- **选定**：抓取时 `config.ignoreShadowsSingleWindow = true`；四角采样**内缩 2px**
  （内缩后 (0,0) 实测 alpha = 255）。内缩不会放过斜条带 —— 它的四角在
  x ∈ [10, 22] 之外仍是空的，判据照旧拦得住。
- **代价**：内缩把「四角不透明」的有效范围收进 2px；「整扇窗只有一种颜色」的窗口
  仍会被第二种判据误杀 —— 退回 app 图标，不是白屏（shortcut: 注释）。
- **推翻条件**：内缩放过坏图的实测案例出现时（收窄内缩 / 改采样点）。

## 2026-10-12 · 过期缩略图用窗口身份判，不用 generation 计数

- **背景**：红线 5 要求「过期结果必须丢弃」。`WindowCache` 用的是 generation 计数。
- **选定**：`WindowThumbnails` 用 `live: Set<UInt32>`（当前快照的 windowID 集合），
  抓取结果回来时只收 `live` 里的。
- **为什么**：计数器只能说「这批可能过期了」，身份能说「这扇窗已经不在快照里了」。
  而且计数器在这里有个洞：批次 A 被批次 B 顶掉时，B 看到 A 的窗口还在 pending
  就跳过，A 回来又因 generation 不符而丢弃并清掉 pending —— 那几个窗口再没人抓。
- **代价**：windowID 被 WindowServer 复用时会认错（每一次快照边界都清理，
  所以复用得跨过边界才可能撞上）。
- **推翻条件**：出现「关掉的窗口的图被显示出来」的实测案例。

## 2026-10-12 · `WindowCache.sort` 从 private 放开到 internal 供测试直调

- **背景**：spec §10 的聚拢 bug 只有 4 行修法，但它是「冷启动后同一个 app 的窗口
  交错」这个现象的全部根因 —— 不留回归钉，下次动排序就会再犯。
- **选定**：`private nonisolated static func sort` → `nonisolated static func sort`，
  新增 `Tests/slimeTests/WindowCacheSortTests.swift` 用 `@testable import` 直接测。
- **放弃了**：搬进 `Core/`（纯逻辑进 Core 更合规矩，但那要新增文件，和 CLAUDE.md
  第六条「源文件保持精简 / 加文件之前先问能不能并进已有的那个」冲突，而它只有 4 行）。
- **代价**：**这是对「只有 Core 能单测」的一处有意偏离** —— `System/` 里出现了一个
  为测试而放开的可见性。它不 import 任何系统框架，是纯函数，所以偏离是安全的。
- **推翻条件**：`System/` 里为测试放开的成员多到第三处（那时该抽一个 `Core/` 模块）。

## 2026-10-12 · 助手条否决（AXUnknown + 空标题）与屏外丢弃 —— Chromium 的假窗口

- **背景**：用户实测 Chrome 只有 3 个窗口、面板显示 7 行。真机 dump（临时、未提交）：Chromium 经 AX 把**菜单栏 / 工具栏条**当窗口暴露 —— 两条 `subrole=AXUnknown`、`title=""`、`size=1920x41/47 @x=-1920`，且 `onscreen=1` 并 frame/title 匹配上 AX；现有「在屏上 / 有 AX 对应物 / known」三条判据全部拦不住，一进 known 表就长期驻留。对照：Chrome、ZCode、VS Code、企业微信、line puppy 的真窗口 subrole 全是 `AXStandardWindow`。现有证据链（真窗口 = 在屏上 / AX standard 匹配 / known）对这两条全部为真 —— 唯一为假的是「应用自己声明它是非标准窗口」。
- **选定**：(a) AX 匹配条目带 `subrole`；匹配到「`AXUnknown` 且无标题」→ 判为助手条，`select` 里**直接丢弃**（优先于 onscreen / matched / known），且**不进 known 表** —— 用户现有的 7 行会在下一次枚举自愈回 3 行。(b) 枚举阶段丢弃 frame 与所有显示器范围交集为空的窗口（显示器范围注入纯函数，可单测）—— 显示器范围外的窗口不可能是用户可见的窗口。
- **放弃了**：只靠现有三条正面证据（条全命中，拦不住）；把条留在 known 里靠后续过滤（known 是长期驻留地，必须在进表前否决）；按尺寸 / 位置启发式（红线 7 禁尺寸；「不在任何显示器内」比几何启发干净）；读不到 subrole 也谨慎否决（拿不准就不丢 —— 多一行的代价远小于误丢用户窗口）。
- **代价**：把真窗口报成 `AXUnknown` + 空标题的应用会被误丢（当前真机对照里没有）；多显示器热插拔瞬间 NSScreen 可能少一个屏，屏外的窗口会被丢弃一帧（下一轮枚举自愈）。「屏外」判定不涉及尺寸/位置启发 —— 台前调度条带（屏内小方框）、其他 Space（frame 在屏内）、全屏窗口都不会被误伤。
- **推翻条件**：再遇到应用把真窗口报成 `AXUnknown` + 空标题（用户反馈丢窗）时，改用别的信号（例如只否决「在屏外 **且** AXUnknown 且无标题」的组合，或评估私有 `_AXUIElementGetWindow` 语义）。

## 2026-10-12 · known 表：访问过一次的窗口，离屏后仍然留在列表里

- **背景**：幽灵过滤（上一条）之后的新 bug：一个 app 有多个窗口时面板只显示一个（用户实测 Warp、VS Code 各两个窗口）。根因：进列表需要「在屏上或 AX 里有对应物」的证据，而 `kAXWindows` 只暴露**当前 Space** 的窗口，免空间过滤的公开 API 只有 `kAXMainWindow`/`kAXFocusedWindow` —— 所以每个 app 只有主窗口进得来，第二个窗口只要不在屏上就消失。
- **选定**：枚举器带一张跨次持有的 known 表：窗口只要「在屏上 / AX 匹配上」过就记进去（含最后的标题/最小化），之后即使离屏也仍进列表；表按这一轮出现过的 id 重建（窗口消失即修剪）。
- **放弃了**：只按 in-screen/AX 过滤（用户可见的窗口会随机消失）；私有 SkyLight/AX（spec §3 非目标；同类工具为此改用私有 API，代价是随系统更新失效）；几何启发式（幽灵里有 500×500、1218×418 这种真窗口尺寸，分不开）。
- **代价**：应用刚启动时 known 为空 —— 隐藏 Space 里的非主窗口要等用户去过那个 Space 才进列表（之后持续记住）。窗口 id 被复用的一瞬可能把新窗口误判一次（等到下一轮 id 不在枚举里就修剪了）。标题在离屏期间可能过期（读不到新的）。
- **推翻条件**：still 觉得「切不到没去过的 Space」烦时 —— 评估私有 API（= 推翻 spec §3 的非目标，需要单独立项）。

## 2026-10-12 · 幽灵窗口过滤：regular app + 在屏上/AX 对应，不按尺寸

- **背景**：用户实测面板里同一 app 刷出十几行空标题重复项、没有窗口的 app 也出现。诊断（在 slime 进程内取数）：本机 `layer == 0 && alpha > 0` 的候选有 **252 个**，绝大多数是系统给每个 app 生的幽灵窗口 —— 每个 app 每个显示器一个菜单栏条（1470×33 @(0,0)、1920×30 @(-582,-1080)）、跨 app 同位置同尺寸的缓存窗（500×500 @(0,456)、1×1、64×64）、以及各 app 的 helper 窗。
- **选定**：app 级只留 `activationPolicy == .regular`；窗口级只留「在屏上 **或** 在 `kAXWindows`/`kAXMainWindow` 里」；一个 AX 窗口只认领一个 CGWindow（在屏优先，防孪生幽灵重复行）。
- **放弃了**：按尺寸过滤（红线 7 禁止 —— 台前调度的小方框）；`kCGWindowName`（无录屏权限时整个键都不存在，实测）；manual accessibility（Chrome 实测 `AXManualAccessibility` 返回 attribute unsupported、Electron 类 5 秒后仍 0 个窗口 —— 不能作为准据）；私有 SkyLight/SLS（spec §3 非目标；同类工具为补「其他 Space 的窗口」确实改用了私有 API）。
- **代价**：**其他 Space 的窗口进不齐** —— 只有「在屏上」或「是该 app 的主窗口」时能进列表；手动验收里「Chrome 三个窗口都列出」要求那三个窗口至少在屏上（同一 Space / 双屏都在屏上）。少数同 frame 的真窗口会只留一个。
- **推翻条件**：真觉得「切不到别的 Space 的窗口」烦到不能忍时 —— 那时评估私有 API（等于推翻 spec §3 的非目标，spec §15 的 0.0.2 候选里没列，需要单独立项）。

## 2026-10-11 · 用公开的 frame/标题匹配 AX 窗口，不用私有 `_AXUIElementGetWindow`

- **背景**：激活一个 `Window` 需要它的 `AXUIElement`，但公开 API 里没有 windowID → AX element 的映射（CGWindowList 给 id，AX 只有 kAXWindowsAttribute 的元素数组）。
- **选定**：按 frame（±2pt）匹配，台前调度等对不上的场景退到标题匹配。匹配不中时激活降级为「只 activate app、不 raise」。
- **放弃了**：私有 `_AXUIElementGetWindow`（同类工具在用，能精确拿 id）—— spec §3 把「私有 SkyLight」列为非目标，理由是随系统更新失效；同一类风险不在这里重开；标题匹配的错误代价只是标题/最小化状态，不是激活目标。
- **代价**：同名同位置窗口（同 app 两个「未命名」）可能匹配错元素；台前调度条带里的窗口拿不到标题。2pt 容差是拍的。
- **推翻条件**：真的出现「切错窗口」的用户反馈（不是切错 app）时，再评估私有 API 或别的锚。

## 2026-10-11 · 事件 tap 放 `kCGSessionEventTap`，`.headInsertEventTap` + `.defaultTap`

- **背景**：spec §12 把「session 层还是 HID 层」列为待验证项，两个都能吞事件。
- **选定**：先 `kCGSessionEventTap`（同类工具的常态位置）；吞放靠 Effect 里的 `swallow`，放行是默认。验证方式写在 design.md（真机按 ⌘Tab 看谁响应）。
- **放弃了**：一上来就 `kCGHIDEventTap` —— 更靠前意味着更早看到、也更可能被安全输入等机制挡住或被系统更新改行为；没有证据说 session 层不够。
- **代价**：如果 session 层拿不到 ⌘Tab（被系统先处理），需要手动验证后改一行。
- **推翻条件**：真机上 ⌘Tab 被系统抢走（面板不出现）时改 HID 层 —— spec §12 本来就要求写第一版时验证。

## 2026-10-11 · 缓存快照 + 按下时后台重枚举，而不是每次都枚举或 AXObserver 增量

- **背景**：AX 取标题是跨进程同步 IPC，一次 ⌘Tab 全量枚举会有 ~50ms 首次卡顿；AXObserver 增量缓存代码最多，通知会丢、时序难调。
- **选定**：启动枚举一次；按下时立刻用快照渲染，同时后台重新枚举、回来静默 diff 更新（generation 丢弃过期结果）。用①的代码量拿接近③的体感。
- **放弃了**：每次按下才枚举（第一下必卡）；AXObserver 增量缓存（0.0.2 再说，那时也更清楚通知在哪些场景会丢）。
- **代价**：面板刚出现的一瞬间列表可能不是最新的；「别的途径换前台 app」后的一帧里当前窗口可能没被排除，几十毫秒后静默修正。
- **推翻条件**：真的觉得列表更新不及时了。

## 2026-10-13 · known 表落 UserDefaults（跨 slime 重启），带 appName 防复用误判

- **背景**：用户实测「重启 slime 后永远只显示 zcode 一个窗口」。known 表在内存里，
  重启即空 —— 而 Electron 类 app 的 AX 不暴露窗口，它们的离屏窗口只能靠 known 表
  进来，所以重启后列表只剩「此刻在屏」的那几个。
- **选定**：known 表编码成 JSON 存进 `UserDefaults`（键 `cache.knownWindows`），
  加载即用。条目带 **appName**：windowID 只在一次开机内稳定，**重启机器**后可能
  被复用 —— 名字对不上的条目按不认识处理（纯函数测试 `knownEntryWithADifferentAppNameIsIgnored`）。
- **放弃了**：不持久化（用户的实测就是它的代价）；只存 windowID（跨开机复用误判的概率更高）。
- **代价**：第一次跑新版本时 known 表是空的，需要用户在各 Space 走一圈把窗口「看进」表里
  （之后跨重启保留）；重启机器后表里的旧 id 会自然修剪。
- **推翻条件**：出现「关掉的窗口的图/行又出现了」的实测案例。
