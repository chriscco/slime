# Trigger · 设计

## 职责

两个手势（⌘+Tab 松手切换 / ⌥+Tab 松手留住）的**纯函数**状态机：`reduce(state, event) -> (state, [Effect])`。

**不负责**：把 CGEvent / NSEvent 翻译成 `Event`（在 `System/EventTap` 和 `UI/PanelController`）；执行 Effect（吞事件、移动高亮、切窗口）；列表和选中的真实边界（PanelController）。这一层没有任何副作用、不 import AppKit —— 它是可以把「吞错键」穷举进单测的地方（spec §10）。

## 数据结构

- `Modifier`：`.cmd` / `.opt`。
- `State`：`idle` / `armed(m)` / `holding(m, query, selection)` / `lingering(query, selection)`。
  - `selection` 是**无界计数**：纯状态机不知道列表长度，`sel+1` 不做钳位。真正的显示选中由 PanelController 维护（循环取模、刷新后钳位、选中项消失回 0）。
- `Event`：修饰键上下、`tab(shift:)`、`char` / `backspace` / `arrow(±1)` / `focusSearch` / `enter` / `escape`。
- `Effect`：`passThrough` / `swallow`（事件级）+ `showPanel` / `hidePanel` / `moveSelection` / `appendQuery` / `deleteQueryChar` / `focusSearchField` / `activate` / `cancel`（UI 级）。

## 流程

`reduce` 按 `State` 分四支：

- `idle`：只认 `modifierDown` → `armed`；其余全部 `passThrough`（不装手势时键盘完全是应用的）。
- `armed(m)`：`tab` → `holding(m, "", 0)` + `showPanel`（⇧Tab 等价）；`modifierUp(m)` → `idle`；**其余（含 ⌘C 这类按键、另一个修饰键）全放行**。
- `holding(m)`：`modifierUp(m)` 是会话出口 —— `.cmd` 松手 → `activate + hidePanel`；`.opt` 松手 → `lingering` + `focusSearchField`。`:cmd` 模式下 ⌘F 也转 `lingering`（「我要慢慢找」；见 decision.md）。其余键盘事件走共用的 `panelStep`。
- `lingering`：`modifierDown` → 关面板并回 `armed`（开始新手势）；键盘事件与 `holding` 走同一个 `panelStep`（spec §6 的「同上转移」）。

`panelStep` 是 holding / lingering 共用的转移（tab/char/backspace/arrow/focusSearch/enter/escape），两处实现不分别写，免得漂移。

**放行是默认的**：一个转移的 Effect 里没有 `swallow` 就默认放行。只有明确要吞的事件才吞（红线 3）。

## 接口

```swift
public func reduce(_ state: State, _ event: Event) -> (State, [Effect])
```

纯函数、无副作用。两个事件源（EventTap 与 PanelController）翻译成同一个 `Event` 调它。

## 正确性假设

- **状态机是唯一决定吞/放的地方**：翻译层（CGEvent → Event）不做吞放判断。打破时：按键被吞错/漏吞，症状是全系统或某 app 的键盘行为异常 —— 这是本项目最严重的故障类别（红线 3）。
- **`armed` / `idle` 下不吞任何非 Tab 键**：⌘C、⌘V 等必须原样到应用。被打破的症状：普通快捷键失效。
- **`panelStep` 对空 query 的 backspace 是安全的**（`dropLast()` 空串不崩、返回空）。
- **`selection` 无界不会越界崩溃**：它只是 Int 计数，钳位是展示层的事。症状只会是「高亮位置不对」，不会是崩溃。

## 已知限制

- `holding` 期间**未列入状态表的按键**（功能键等）的吞放由 EventTap 的兜底策略决定（见 System 模块文档），纯状态机管不到。
- 状态表的「列表为空时回车/松手不做事」由执行端把 `activate` 变成 no-op 实现 —— `reduce` 永远发 `activate`，不感知列表。
- `selection` 在 `lingering` 会带着纯计数的值（可能与展示层的取模值不同），展示层以自己维护的值为准。
