# System · 设计

## 职责

五个文件，把 spec §7 的数据流和 §8 的红线落到代码：

| 文件 | 管什么 |
|---|---|
| `WindowEnumerator.swift` | 有哪些窗口：`CGWindowList` 定集合，AX 取标题/最小化（`AXWindows` 是和激活层共用的 AX 读取/匹配） |
| `WindowCache.swift` | 快照 + 后台刷新 + app 级 MRU + 当前窗口排除 |
| `WindowActivator.swift` | 取消最小化 → `kAXRaiseAction` → unhide + activate |
| `WindowThumbnails.swift` | 窗口缩略图：按 `windowID` 缓存 / 后台抓取 / 快照边界清理（见下节） |
| `EventTap.swift` | `CGEvent ↔ Event`、吞放、状态机宿主、被禁重开与兜底 |

**不负责**：渲染与选中（UI 层）、启动流程与权限（App 层）。

## 缩略图（`WindowThumbnails`，2026-10-12 新增）

**职责**：按 `windowID` 缓存 `CGImage`（**内存 + 落盘**）、后台抓取、按快照边界清理。
**不碰 AppKit 视图**。

**接口**：`warm(_ windows: [Window])`（对齐一份快照：丢不在里面的、从盘上补进已有的、
补抓还没有的，挂 `WindowCache.onChange`）、`image(for:) -> CGImage?`（转成 `NSImage`
在 UI 边界 —— `CardView` 做，这一层不 import AppKit）、`onChange: (() -> Void)?`、
`looksLikeWindowRender(_:) -> Bool`、`capturePlan(windows:cached:busy:unrenderable:)`
（纯函数，单测直接钉）。

**线程**：缓存 / `pending` / `refreshing` / `live` / `unrenderable` / `onChange` 全在
主线程；抓取走 `Task.detached`（不是 `Task {}` —— 后者从 MainActor 上下文继承隔离，
等于把 IPC 放回主线程，红线 4）；结果经 `MainActor.run` 回主线程发布。抓取**串行**
（一扇窗一个流、16–25ms/个），**落盘也在后台**。

**抓取计划**（用户实测「大部分卡片只有 app 图标」之后的修法）：离屏窗口在合成层
没有被渲染，SCK 抓它们要么报 `-3811`、要么给坏图 —— 这跟节流 / 并发无关（串行抓、
隔 6 秒重试，失败的还是同一批）。所以：

- **没图的**（`needed`）：必抓，面板首帧要等它（`hasPendingWork` / `whenSettled`）；
  **但负缓存里的离屏窗口不再重试**（`unrenderable`）—— 它们注定失败，重试只会白烧
  IPC 并把首帧拖满 `warmUpDeadline`。回到屏上就再给一次机会（那时它真能抓）。
- **有图、在屏上的**（`refresh`）：刷新 —— 可见窗口的内容会变，图得跟得上。
  **不阻塞首帧**（`onChange` 就地换卡片）。

**降级链**：实时抓的图 → 落盘的「见它的最近一次」→ app 图标。抓不到的窗口
（其他 Space / 最小化 / 台前调度搁置）停在第二 / 第三级 —— 那张图是它在屏时的
最近一次，也是平台自己的行为（系统给最小化窗口显示的就是它上一次的样子）。

**落盘**（`Application Support/slime/thumbs/<windowID>.png`）：**必须跨重启存活** ——
离屏窗口整个会话都抓不到，不存的话重启后它们全是图标。清理的边界是「窗口关没关」，
**不是面板的显示列表** —— `warm` 收的是 `WindowCache.allWindows`（含当前窗口）：
用户所在的这扇窗不显示，但它切走之后就是列表里第一张卡，而那时它多半已经离屏、
抓不到了。关掉的窗口不在这份列表里（known 表在枚举里自然修剪），它的图会被删。

**判据**（`looksLikeWindowRender`，spec §16 选的方案 (a)）：缩到 32×32 采样，
四角必须不透明、至少两种量化颜色。对着实测到的两种坏法：斜的透视条带（四角空）、
全白（一种颜色）。两个实现细节都来自实测：

- 抓取时 `config.ignoreShadowsSingleWindow = true` —— 默认的 shadow framing 会把
  阴影一起抓进来（窗口从抓取边界内缩），关掉抓出来的才是窗口本身。实测（320pt 宽
  抓图）：不开时四角 alpha = 0（圆角外是空的）。
- 四角采样**内缩 2px** —— 真窗口的圆角本身就是透明的，采最外圈会把**每一扇真窗口
  都判否**。实测（320pt 宽抓图，32×32 采样）：(0,0) 的 alpha = 0，内缩 2px 后
  = 255（不透明）。内缩不会放过斜条带 —— 它的四角在 x ∈ [10, 22] 之外仍是空的。

## 线程模型

这是本模块最容易出问题的地方，先把线程边界写死：

```
主线程                      tap 线程                       后台队列
────────────────────────────────────────────────────────────────
WindowCache（@MainActor）   EventTap.state（独占）          枚举（WindowEnumerator）
PanelController             CGEventTap 回调                 激活的 AX 段
    ▲                            │
    └──── DispatchQueue.main ◄────┘  （Effect 与 State 单向发布）
```

- **EventTap 的状态只在 tap 线程访问**，没有共享、没有锁。主线程只在 `start()` 里经 semaphore 读一次启动结果（这就是 `@unchecked Sendable` 的边界）。
- 主线程 ← tap 的通信只有单向发布：`DispatchQueue.main`（严格 FIFO，保证打字顺序）。反过来不通信 —— panel 不需要让 tap 知道任何事，**lingering 下 tap 不参与键盘**。
- 枚举与激活的 AX 段在后台/全局队列；快照整体替换发布回主线程。

## 数据结构

- `Window`（Core）：不可变值类型；快照是不可变数组，发布时整体替换 —— 天然无锁（红线 8）。
- `AXWindows.Entry`：一个 app 的某个 AX 窗口的元素 + frame + 标题 + 子类型（`subrole`，真窗口是 `AXStandardWindow`）+ 最小化。
- `WindowCache.snapshot`：MRU 序、滤掉 `frontWindowID`（当前窗口）的列表。

## 流程

**枚举**（后台）：`CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements])` → 过滤：

| 规则 | 为什么 |
|---|---|
| `layer == 0` | 红线 7；**不按尺寸**（台前调度里 CG 报的是条带小方框，按尺寸会把它们全丢掉） |
| `alpha > 0` | 不可见的辅助窗口 |
| 非本进程 | 面板自己的窗口 |
| app 是 `.regular` | 菜单栏 app / 系统服务的「窗口」不是切换目标 |
| **frame 与任一显示器范围相交** | 显示器范围外的窗口不可能是用户可见的窗口 —— Chromium 经 AX 的助手条报 @x=-1920；台前调度条带 / 其他 Space 的窗口 frame 都在屏内，不会误伤（红线 7 禁的是按尺寸，这不是尺寸） |
| **在屏上 或 有 AX 对应物** | 系统会给每个 app 生一批幽灵窗口（菜单栏条 1470×33/1920×30、缓存窗 500×500@(0,456)/1×1/64×64、helper 窗），它们既不在屏上、也不在 `kAXWindows` 里。不滤掉面板会被同一 app 的十几行空标题刷屏、没有窗口的 app 也会出现（issue #21，252 候选里滤到 6 个真窗口） |
| **不是助手条**（AX 匹配到 `AXUnknown` 且无标题 → 否决） | Chromium 把菜单栏 / 工具栏条经 AX 报成窗口：`subrole=AXUnknown`、无标题，但 onscreen / matched / known 三条正面证据全命中，只有应用自己声明的「非标准 + 无标题」能拦 —— 用户窗口不可能是这样（用户实测 Chrome 3 窗口显示 7 行） |

然后按 pid 分组，一次建 AX app element → 读全部 AX 窗口（`kAXWindows` + `kAXMainWindow`）→ 按 frame（近似）匹配出标题/最小化 → 组装 `[Window]`（front-to-back 序）。

三个细节：

- **known 表（见过的窗口）**：通过过滤的窗口写进跨次持有的 known 表 —— `kAXWindows` 只暴露当前 Space 的窗口，所以一个 app 的其他窗口只要不在屏上就会消失（issue #23）。known 表记住「见过一次」的窗口（含最后的标题/最小化状态），用户访问过的 Space 里的窗口留档，之后离屏也仍在列表里。幽灵窗口永远进不了表（它们从不在屏上、从不在 AX 里）；助手条也进不了（在已知证据之前就被否决）—— 用户现有的多余行会在下一次枚举自愈回真实窗口数。表按「这一轮出现过的 id」重建 —— 窗口消失即自然修剪，防 id 复用误判（残留风险：id 被复用的一瞬可能误判一次，见 decision.md）。

- **一个 AX 窗口只认领一个 CGWindow**（在屏优先）：系统会给真窗口生一份同 frame 的**孪生幽灵**，不加这一步会多出整行重复。认错孪生无损 —— 激活是按 frame 重新匹配 AX 的（见下）。
- **`kAXMainWindow` 不受 Space 过滤**（`kAXWindows` 只给当前 Space）：其他 Space 上每个 app 的前台窗口靠它进列表，标题也靠它。

**刷新**：`refresh()` 在后台枚举 + 按 MRU 排序，回主线程对 generation 后整体替换；对不上丢弃（红线 5）。

**激活**：后台查该 windowID 的当前 frame → 匹配 AX element → 取消最小化 + raise → 主线程 unhide + activate。匹配不中（台前调度等）时的降级是「只 activate app、不 raise」——不精确但不会切错。

**事件**（tap 线程，回调里只有状态机和吞放）：

1. `tapDisabledByTimeout` / `ByUserInput` → 立刻重开（红线 2）；连续到阈值进入兜底（红线 3）。
2. `flagsChanged` → 修饰键按下/松开；`keyDown` → keycode 翻译成 `Event`。
3. 非 lingering：`reduce` → 发布到主线程；吞放按「Effect 里有 `swallow` 才吞」。
4. lingering：无脑放行，只盯 `modifierDown` —— 收到就回 `armed` 重新接管。

## 接口

- `WindowEnumerator.enumerate() -> [Window]`（需在后台线程调）
- `WindowCache`（`@MainActor`）：`start()` / `refresh()` / `noteActivated(_:)` / `snapshot` / `onChange`
- `WindowActivator.activate(_:)`（异步，不阻塞调用方）
- `WindowThumbnails.warm(_:)` / `image(for:) -> CGImage?` / `onChange`（见「缩略图」一节）
- `EventTap.init(onEffects:onDegraded:)` / `start() throws`

## 正确性假设

- **调用方在后台线程调 `enumerate()`**（红线 4）。打破的症状：按下快捷键转圈。
- **`layer == 0` 与台前调度**（红线 7）：搁在左侧条带的窗口 CG 报的是条带方框，所以**不按尺寸过滤**；副作用是它们出现在列表里是正确行为，激活能把它们拉上台。打破的症状：窗口从列表里静默消失。
- **每个 AX element 都设了 ~1s 超时**（红线 6）。打破的症状：一个无响应的 app 让整个切换器瘫掉 —— 没有这一条，这是必然事件。
- **generation 覆盖所有让在途结果过期的变化**。打破的症状：过期列表覆盖新状态（用户 Esc 关掉又重开，看到旧列表）。
- **tap 的状态机宿主只被 tap 线程碰**。任何在主线程同步读 `state` 的改动都会引入竞争。
- **`kCGSessionEventTap` + `.defaultTap` 能先于系统 ⌘Tab 拿到事件**（spec §12 的待验证项之一）。验证方法：真机按 ⌘Tab 看面板是否出现而不是系统切换器；不行就换 `kCGHIDEventTap`（见 decision.md）。

## 已知限制

- **holding 期间未翻译成 Event 的按键一律吞**（功能键、第三方 keyUp）。会话里键盘归我们；会话外（idle/armed）全部放行（红线 3）。副作用：⌘Tab 会话里 F5 之类不会透给应用。
- AX 匹配是同帧/标题启发式，不是精确的窗口身份（公开 API 没有 window id → AX element 的映射）。同名同位置的窗口可能张冠李戴 —— 代价是标题/最小化状态，不是激活目标。
- **从没访问过的其他 Space 窗口进不来**：`kAXWindows` 只暴露当前 Space；免空间过滤的公开 API 只有主窗口/焦点窗口；剩下的靠 known 表「访问过就记住」。应用刚启动（known 为空）时，隐藏 Space 里的窗口要等用户去过那个 Space 才进列表 —— 同类工具为补上这块改用了私有 WindowServer API（spec §3 把那条路列为非目标，代价记在 decision.md）。
- 台前调度条带里的窗口如果 frame 对不上、标题也可能丢（只能显示 app 名）。
- **助手条判定的前提**：真窗口的 subrole 是 `AXStandardWindow`（真机对照过 Chrome / ZCode / VS Code / 企业微信 / line puppy）。应用若把自己的真窗口报成 `AXUnknown` + 空标题会被误丢 —— 目前没有实例；读不到 subrole 时不否决（拿不准就不丢），见 decision.md。
- Electron/Chromium 的**非主窗口**标题可能拿不到（`AXManualAccessibility` 在本机实测对 Chrome 返回 attribute unsupported、Electron 类 5 秒后仍 0 个窗口）；主窗口标题经 `kAXMainWindow` 正常。
- `WindowCache` 的观察者活到进程退出，没有 stop/清理路径（0.0.1 用不到）。
- 安全输入（密码框）开着时系统不给 tap 发事件，⌘+Tab 自动走原生行为（红线 9，预期行为不是 bug）。
