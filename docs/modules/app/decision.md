# App · 取舍记录

<!-- 新的在最上面。 -->

## 2026-10-11 · 用 Swift 6 语言模式（偏离 spec §13 的 Swift 5 锁）

- **背景**：本机只有 CommandLineTools，没有完整 Xcode —— XCTest 拿不到，测试就没法跑。Swift 6 工具链自带 swift-testing（`import Testing`），可以不装 Xcode 跑测试。这是项目所有者给出的指令（「swift 使用 swift 6，这样 testing 不依赖于 xctest，不需要下载 xcode」）。
- **选定**：`swift-tools-version:6.0`，全 target 默认 Swift 6 语言模式；测试用 swift-testing。本机补 Testing 搜索路径的 workaround 在 `scripts/test`（根因写在脚本注释里：manifest 里的 unsafe flags 会被 SwiftPM 转坏，见那个提交的说明）。
- **放弃了**：spec §13 / CLAUDE.md 原本的「Swift 5 锁」（Swift 6 的严格并发会让 AppKit 代码到处要标注解）；为了跑测试而装完整 Xcode（几 GB，且本机原本就用不上）。
- **代价**：AppKit 代码要按严格并发写（`@MainActor`、少量 `@unchecked Sendable` 边界，全部就地注释）；`@preconcurrency import` 一处（导入的 AX 常量键）。CI 的 `macos-latest` 用完整 Xcode 跑，同一份 manifest 两种环境都通 —— probe 逻辑在 `scripts/test`。
- **推翻条件**：除非某天发现 Swift 6 严格并发逼出 @unchecked 的雪崩（现在只有 EventTap 一处、有完整注释），或者测试环境换成完整 Xcode。

## 2026-10-11 · 权限引导：轮询等授权，然后提示用户重启（不自动重启）

- **背景**：辅助功能权限「授权后要重启 app 才生效」（spec §9 / CLAUDE.md 第五条）。用户在系统设置里勾选时，运行中的进程 `AXIsProcessTrusted()` 不会变。
- **选定**：启动时无权限 → 弹系统对话框 → 每秒轮询（最多 2 分钟）→ 授权成功弹「已授权，请重启 slime」后退出；超时弹「请去设置里勾上」后退出。手动验收的指令里包含 `killall slime`。
- **放弃了**：自动重启（`NSWorkspace.openApplication` 自替换）—— 多一层时序（旧进程退出与新进程启动的竞态、TCC 对 bundle 路径的识别），0.0.1 不值当；在运行中重试（授权不生效）。
- **代价**：用户要做「授权 → 重启」两步，且没有 Dock/菜单栏入口，重启靠命令行。
- **推翻条件**：把「重启 slime」变成用户别扭的操作时 —— 补一个菜单栏项（退出/重开入口）或自动重启。

## 2026-10-11 · 系统选型 Swift + AppKit（记录 spec §4 的取舍）

- **背景**：见 spec §4 的量化（一次 ⌘+Tab 的热点是跨进程 AX IPC 和 WindowServer，纯 CPU 部分 <0.1ms）。
- **选定**：Swift + AppKit；状态机/搜索纯 Swift；零第三方依赖。
- **放弃了**：Rust（语言省不下系统 API 的耗时，objc2 样板 2–3 倍）；Tauri / egui / winit（窗口做不成 nonactivating panel，而「切换器不能抢焦点」是硬约束）。
- **代价**：需接受 SwiftPM + CLT 工具链的工程限制（测试 workaround、手工组 .app）。
- **推翻条件**：spec §4 的论证被实测推翻时（比如纯 CPU 部分真的成了瓶颈 —— 现在不是）。
