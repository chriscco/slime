# Panel · 设计

## 职责

`UI/PanelWindow`（nonactivating 高层级面板 + 视图）+ `UI/PanelController`（搜索框文本、卡片网格、高亮、显示/隐藏、lingering 键盘）。

**不负责**：吞放事件（EventTap）、枚举与 MRU（WindowCache）、真正切窗口（WindowActivator）；这些通过 Effect 和回调交出去。

## 数据结构

- `PanelWindow: NSPanel`：`.nonactivatingPanel + .borderless`，覆写 `canBecomeKey`（无边框窗口默认拒绝 key 状态），`level = .floating`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`。
- `PanelContentView`：搜索框 + `NSScrollView` + 空态标签；手动 `layout()`，document view 的宽度经 `gridView.setContentWidth(scrollView.contentSize.width)` 传下去。
- `CardGridView`（document view）：手动排卡片；`HighlightView`（圆角、半透明强调色）是它 `positioned: .below` 的普通子视图，跟着滚动走；选中的动画由 `setSelection(_:animated:)` 用 `animator()` 驱动。
- `CardView`：单张卡片 —— app 图标在上（`AppIcons.icon(for:)`，`isFlipped`），窗口标题在下；标题为空时退回 app 名。
- `GridLayout`（`Core/`，纯数学）：列数（最多 5）、行数、可见排数（最多 3）、`origin(of:)`、`panelWidth` / `panelHeight`（面板尺寸）、`contentHeight`（document view 的完整高度，滚得到第 4 排以后）、`shouldAnimate(from:to:)`。
- `PanelController` 的展示层账本：`query`（与搜索框显示一致）、`selection`（循环取模、身份跟随）、`phase`（纯状态机镜像，用于喂 lingering 的 `reduce`）。

## 流程

**显示**（Effect `showPanel`）：清空 query/selection → 用当前快照 rank → 渲染 → 定位（鼠标所在屏幕的中间）→ `makeKeyAndOrderFront` → 通知 AppDelegate 后台重枚举。**第一帧就是完整网格**（spec §7 的缓存策略）。

**排版**：`reloadRows` 重建 `GridLayout`（列数/行数随结果）→ `CardGridView` 排卡片；`resizeAndPosition` 用 `gridLayout.panelWidth` / `panelHeight` 定窗口大小（空态宽度收下限，不窄于空态文字）。

**高亮**：`moveSelection(axis:step:)` —— ↑↓ 按排循环（首排 ↑ 绕到末排同一列，末排缺列时收到最后一个格子）、Tab / ←→ 循环取模恒为一格；跨行超过一排时直接跳（不斜穿面板，spec §10），否则 `HighlightView` 平滑滑动到目标卡。

**键入**：`appendQuery` / `deleteQueryChar` 更新 `query` 与搜索框文本 → 重新 rank → 选中归零（纯状态表语义）。

**刷新**（`setWindows`，面板还开着时）：重新 rank，选中按身份修回 —— 还在就跟随它的新位置；消失了回第 0 行；没有了就空态。

**lingering 键盘**：`PanelWindow.keyDown` 用 `KeyTable`（与 EventTap 共用）翻译成 `Event` → `reduce(phase, event)` → 执行 Effect；未翻译的键交给 `super`。

## 接口

- `PanelController.handle(state:effects:)`（EventTap 的主线程发布口）
- `PanelController.setWindows(_:)`（cache.onChange）
- `PanelController.onActivate: (Window) -> Void`、`onRefresh: () -> Void`
- `PanelWindow.onKey`、`onResignKey`

## 正确性假设

- **面板成为 key 而不激活 slime**（`.nonactivatingPanel` 的契约）。打破的症状：切换器一出现，前台 app 的菜单栏就易主、输入焦点被抢 —— 这是 spec §4 的硬约束，manual 验收里专门盯。
- **所有键盘事件都会到达 `PanelWindow.keyDown`**。0.0.1 的搜索框是只读的，没有 field editor 抢按键；`phase` 为 `.idle` 时 reduce 是恒等放行，最多无效不会坏。
- **document view 的宽度来自 scroll view**（`setContentWidth`，不为 0 时）—— 宽度为 0 时卡片 frame 宽度为负、什么都画不出来（0.0.1 的 issue #15，回归测试钉在 `PanelLayoutTests`）。
- **选中永远指向合法卡片或空态**：`moveSelection` 有 guard，`rerank` 把选中收进范围 —— 空态时 Enter/release 都不做事（spec §7）。
- **卡片的 identity 是 windowID**：刷新后跟随的是窗口不是位置。同名同位置的窗口极少，跟随窗口的行为比跟随位置正确。

## 已知限制

- 搜索框是**只读展示**，文本只经 Effect 更新 —— 输入法（IME）在 0.0.1 的面板里不可用。spec §3 的拼音搜索本来就是非目标；ASCII 打字不受影响。
- `focusSearchField` 在 0.0.1 是幂等的（键盘只有搜索框一个落点），实现成一次视觉脉冲给 ⌘F 一个可观察回执。点选卡片、多焦点不在本版范围。
- 面板不支持鼠标点选（spec §3 非目标）；resignKey（用户点了别的窗口）直接藏着走。
- 面板尺寸由 `GridLayout` 决定：一排最多 5 张、最多 3 排可见，其余滚动；不做自适应文案宽度。
