# System · 设计

## 职责

四个文件，把 spec §7 的数据流和 §8 的红线落到代码：

| 文件 | 管什么 |
|---|---|
| `WindowEnumerator.swift` | 有哪些窗口：`CGWindowList` 定集合，AX 取标题/最小化（`AXWindows` 是和激活层共用的 AX 读取/匹配） |
| `WindowCache.swift` | 快照 + 后台刷新 + app 级 MRU + 当前窗口排除 |
| `WindowActivator.swift` | 取消最小化 → `kAXRaiseAction` → unhide + activate |
| `EventTap.swift` | `CGEvent ↔ Event`、吞放、状态机宿主、被禁重开与兜底 |

**不负责**：渲染与选中（UI 层）、启动流程与权限（App 层）。

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
- `AXWindows.Entry`：一个 app 的某个 AX 窗口的元素 + frame + 标题 + 最小化。
- `WindowCache.snapshot`：MRU 序、滤掉 `frontWindowID`（当前窗口）的列表。

## 流程

**枚举**（后台）：`CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements])` → 过滤：

| 规则 | 为什么 |
|---|---|
| `layer == 0` | 红线 7；**不按尺寸**（台前调度里 CG 报的是条带小方框，按尺寸会把它们全丢掉） |
| `alpha > 0` | 不可见的辅助窗口 |
| 非本进程 | 面板自己的窗口 |
| app 是 `.regular` | 菜单栏 app / 系统服务的「窗口」不是切换目标 |
| **在屏上 或 有 AX 对应物** | 系统会给每个 app 生一批幽灵窗口（菜单栏条 1470×33/1920×30、缓存窗 500×500@(0,456)/1×1/64×64、helper 窗），它们既不在屏上、也不在 `kAXWindows` 里。不滤掉面板会被同一 app 的十几行空标题刷屏、没有窗口的 app 也会出现（issue #21，252 候选里滤到 6 个真窗口） |

然后按 pid 分组，一次建 AX app element → 读全部 AX 窗口（`kAXWindows` + `kAXMainWindow`）→ 按 frame（近似）匹配出标题/最小化 → 组装 `[Window]`（front-to-back 序）。

三个细节：

- **known 表（见过的窗口）**：通过过滤的窗口写进跨次持有的 known 表 —— `kAXWindows` 只暴露当前 Space 的窗口，所以一个 app 的其他窗口只要不在屏上就会消失（issue #23）。known 表记住「见过一次」的窗口（含最后的标题/最小化状态），用户访问过的 Space 里的窗口留档，之后离屏也仍在列表里。幽灵窗口永远进不了表（它们从不在屏上、从不在 AX 里）。表按「这一轮出现过的 id」重建 —— 窗口消失即自然修剪，防 id 复用误判（残留风险：id 被复用的一瞬可能误判一次，见 decision.md）。

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
- **从没访问过的其他 Space 窗口进不来**：`kAXWindows` 只暴露当前 Space；免空间过滤的公开 API 只有主窗口/焦点窗口；剩下的靠 known 表「访问过就记住」。应用刚启动（known 为空）时，隐藏 Space 里的窗口要等用户去过那个 Space 才进列表 —— alt-tab 为补上这块改用了私有 WindowServer API（spec §3 把那条路列为非目标，代价记在 decision.md）。
- 台前调度条带里的窗口如果 frame 对不上、标题也可能丢（只能显示 app 名）。
- Electron/Chromium 的**非主窗口**标题可能拿不到（`AXManualAccessibility` 在本机实测对 Chrome 返回 attribute unsupported、Electron 类 5 秒后仍 0 个窗口）；主窗口标题经 `kAXMainWindow` 正常。
- `WindowCache` 的观察者活到进程退出，没有 stop/清理路径（0.0.1 用不到）。
- 安全输入（密码框）开着时系统不给 tap 发事件，⌘+Tab 自动走原生行为（红线 9，预期行为不是 bug）。
