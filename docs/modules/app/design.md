# App · 设计

## 职责

启动与组装（spec §7）：权限检查与引导 → 事件 tap → 缓存 → 面板，以及两个来源的 Effect 接成一条链路。`main.swift` 起 `NSApplication`，`.accessory` 策略（无 Dock 图标、不进系统 ⌘+Tab 列表）。

**不负责**：各层内部行为（见各模块文档）；没有登录自启、没有打包分发、没有菜单栏入口（spec §3 非目标）。

## 数据结构

- `AppDelegate`（`@MainActor`）：持有 `WindowCache`（weak 关系不成立 —— 强引用）、`PanelController`、`EventTap`，用闭包把三者接起来。

## 流程

**启动**

1. 无辅助功能权限 → `Permission.promptAccessibility()` 弹系统对话框 → 轮询等授权（≤2 分钟）→ 弹提示（「已授权，请重启 slime」/「没等到」）→ 退出。
2. 有权限 → 建缓存、面板、事件 tap；tap 装不上就弹窗报错退出（spec §9）。
3. 接线路：tap 的 Effect → `panel.handle`；`panel.onActivate` → `WindowActivator.activate` + `cache.noteActivated`；`panel.onRefresh` → `cache.refresh`；`cache.onChange` → `panel.setWindows`。
4. `cache.start()`：首次枚举 + 订阅 `didActivateApplicationNotification`（MRU）。

**tap 连续被禁**（红线 3 的兜底在 EventTap 里）→ `onDegraded` 弹窗；顺手重查权限（spec §9 的「权限中途被撤销」多半就是这个信号），没权限就再引导一次。

## 接口

- `main.swift`：顶层代码起 app（`.accessory`）。
- `AppDelegate.applicationDidFinishLaunching(_:)`。
- `Permission`：`isAccessibilityTrusted` / `promptAccessibility()` / `waitUntilTrusted(timeout:completion:)`。

## 正确性假设

- **授权只对新进程生效**（CLAUDE.md 第五条）：所以流程是「引导 → 提示重启」，不是原地重试。打破的症状：用户授权后功能还是不动，以为 app 坏了。
- **`.accessory` 策略在 `app.run()` 之前设置**：晚设会在 Dock 里闪现图标/进 ⌘Tab 列表。症状：spec §2 第 1 条失败。
- **弹窗前 `NSApp.activate()`**：accessory app 不激活的话弹窗在别的 app 后面，用户看不到。症状：启动/兜底提示「没出现」。
- **三个回调都只在主线程被触发**（EventTap 经 `DispatchQueue.main` 发布；cache 是 `@MainActor`）。打破的症状：UI 从别的线程更新，间歇性崩。

## 已知限制

- 没有退出入口（无 Dock 图标、无菜单栏项）—— 退出用 `killall slime`。手动验收需要重启时记着这条。
- 权限撤销的检测是兜底式的（tap 被禁 → 重查），不是实时的。
- 首次枚举的失败（无窗口 / AX 全超时）不报错，只是空列表 —— 面板显示「没有其他窗口」。
