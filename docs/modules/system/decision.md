# System · 取舍记录

<!-- 新的在最上面。 -->

## 2026-10-12 · 幽灵窗口过滤：regular app + 在屏上/AX 对应，不按尺寸

- **背景**：用户实测面板里同一 app 刷出十几行空标题重复项、没有窗口的 app 也出现。诊断（在 slime 进程内取数）：本机 `layer == 0 && alpha > 0` 的候选有 **252 个**，绝大多数是系统给每个 app 生的幽灵窗口 —— 每个 app 每个显示器一个菜单栏条（1470×33 @(0,0)、1920×30 @(-582,-1080)）、跨 app 同位置同尺寸的缓存窗（500×500 @(0,456)、1×1、64×64）、以及各 app 的 helper 窗。
- **选定**：app 级只留 `activationPolicy == .regular`；窗口级只留「在屏上 **或** 在 `kAXWindows`/`kAXMainWindow` 里」；一个 AX 窗口只认领一个 CGWindow（在屏优先，防孪生幽灵重复行）。
- **放弃了**：按尺寸过滤（红线 7 禁止 —— 台前调度的小方框）；`kCGWindowName`（无录屏权限时整个键都不存在，实测）；manual accessibility（Chrome 实测 `AXManualAccessibility` 返回 attribute unsupported、Electron 类 5 秒后仍 0 个窗口 —— 不能作为准据）；私有 SkyLight/SLS（spec §3 非目标；alt-tab 的 windowserver/README.md 明确记录了它就是为了补「其他 Space 的窗口」才改用私有 API）。
- **代价**：**其他 Space 的窗口进不齐** —— 只有「在屏上」或「是该 app 的主窗口」时能进列表；手动验收里「Chrome 三个窗口都列出」要求那三个窗口至少在屏上（同一 Space / 双屏都在屏上）。少数同 frame 的真窗口会只留一个。
- **推翻条件**：真觉得「切不到别的 Space 的窗口」烦到不能忍时 —— 那时评估私有 API（等于推翻 spec §3 的非目标，spec §15 的 0.0.2 候选里没列，需要单独立项）。

## 2026-10-11 · 用公开的 frame/标题匹配 AX 窗口，不用私有 `_AXUIElementGetWindow`

- **背景**：激活一个 `Window` 需要它的 `AXUIElement`，但公开 API 里没有 windowID → AX element 的映射（CGWindowList 给 id，AX 只有 kAXWindowsAttribute 的元素数组）。
- **选定**：按 frame（±2pt）匹配，台前调度等对不上的场景退到标题匹配。匹配不中时激活降级为「只 activate app、不 raise」。
- **放弃了**：私有 `_AXUIElementGetWindow`（alt-tab 等工具在用，能精确拿 id）—— spec §3 把「私有 SkyLight」列为非目标，理由是随系统更新失效；同一类风险不在这里重开；标题匹配的错误代价只是标题/最小化状态，不是激活目标。
- **代价**：同名同位置窗口（同 app 两个「未命名」）可能匹配错元素；台前调度条带里的窗口拿不到标题。2pt 容差是拍的。
- **推翻条件**：真的出现「切错窗口」的用户反馈（不是切错 app）时，再评估私有 API 或别的锚。

## 2026-10-11 · 事件 tap 放 `kCGSessionEventTap`，`.headInsertEventTap` + `.defaultTap`

- **背景**：spec §12 把「session 层还是 HID 层」列为待验证项，两个都能吞事件。
- **选定**：先 `kCGSessionEventTap`（alt-tab 的常态位置）；吞放靠 Effect 里的 `swallow`，放行是默认。验证方式写在 design.md（真机按 ⌘Tab 看谁响应）。
- **放弃了**：一上来就 `kCGHIDEventTap` —— 更靠前意味着更早看到、也更可能被安全输入等机制挡住或被系统更新改行为；没有证据说 session 层不够。
- **代价**：如果 session 层拿不到 ⌘Tab（被系统先处理），需要手动验证后改一行。
- **推翻条件**：真机上 ⌘Tab 被系统抢走（面板不出现）时改 HID 层 —— spec §12 本来就要求写第一版时验证。

## 2026-10-11 · 缓存快照 + 按下时后台重枚举，而不是每次都枚举或 AXObserver 增量

- **背景**：AX 取标题是跨进程同步 IPC，一次 ⌘Tab 全量枚举会有 ~50ms 首次卡顿；AXObserver 增量缓存代码最多，通知会丢、时序难调。
- **选定**：启动枚举一次；按下时立刻用快照渲染，同时后台重新枚举、回来静默 diff 更新（generation 丢弃过期结果）。用①的代码量拿接近③的体感。
- **放弃了**：每次按下才枚举（第一下必卡）；AXObserver 增量缓存（0.0.2 再说，那时也更清楚通知在哪些场景会丢）。
- **代价**：面板刚出现的一瞬间列表可能不是最新的；「别的途径换前台 app」后的一帧里当前窗口可能没被排除，几十毫秒后静默修正。
- **推翻条件**：真的觉得列表更新不及时了。
