# slime

macOS 窗口切换器。比系统自带的切换器多两样东西：**打字即时搜索**和**双触发手势**。

**[English →](README.md)**

> **当前版本：0.0.5。** 固定五列、圆角预览、可选应用分组、重新设计的设置页，以及 `⌘D` 关闭窗口。

## 手势

| 按键 | 行为 |
|---|---|
| 按住 `⌘`，连按 `Tab` | 循环切换窗口。**松开 `⌘` 就切过去** —— 手感跟系统原生的切换器一致。 |
| 按住 `⌥`，连按 `Tab` | 同一个面板，但**松手后面板留住**。可以直接打字搜索，按回车才切。 |
| `⌘F` | 聚焦搜索框。两种模式下都可用。 |
| `Tab` / `⇧Tab` | 选中往前 / 往后移。高亮条在项之间平滑滑动。 |
| `↑` `↓` `←` `→` | 移动选中。 |
| 直接打字 | 实时模糊过滤 —— `ghb` 能命中 `Chrome — GitHub`。 |
| `Enter` | 切到选中项。**最小化的窗口也能切过去。** |
| `⌘D` | 关闭选中窗口并播放 CRT 预览动画，不退出应用。 |
| `⌘,` | 打开设置；松开 Option 后仍可使用。 |
| `Esc` | 关闭面板，且不改变当前窗口。 |

列表按应用级 MRU 排序；开启分组后每个应用独立分区。

slime 没有 Dock 图标，也不会出现在系统原生的 `⌘+Tab` 列表里。你不叫它，它就不出现。

它列的是**每个 app 的每一个窗口**，而不是一个 app 一条 —— 所以你能直接跳到想要
的那个窗口，不用先切到 app 再在它的窗口之间循环。

## 设置

从菜单栏或面板内 `⌘,` 打开。通用包含总开关、应用分组、登录启动和 English / 简体中文；
默认英文（包括升级用户），保留已有外观偏好。外观页保留玻璃样式、强度、颜色和面板圆角；
快捷键页展示固定绑定；关于页显示实际版本及仓库链接。

关闭总开关立即恢复系统 `⌘Tab`，菜单栏入口保留。登录启动读取 macOS 实际状态，可能需要在系统设置批准。

`⌘D` 仅请求关闭选中窗口；匹配不唯一时拒绝操作。保存确认或失败时恢复预览并说明原因，
不会退出应用，也不会代替用户回应保存对话框。系统开启“减少动态效果”时使用淡出替代 CRT 收缩闪烁。

## 系统要求

- **macOS 26+**，面板使用 `NSGlassEffectView`。
- **屏幕录制权限**用于预览。没有有效预览或同窗口缓存时，显示带应用图标的通用小窗口占位。
- **需要辅助功能权限。** slime 通过辅助功能 API 读窗口列表，并且要拦截你按下的
  按键，所以必须由 macOS 授权。
- **零第三方依赖。**

## 构建与运行

不需要 Xcode，命令行工具够了。

```sh
scripts/setup-signing     # 只跑一次；让辅助功能权限扛得住 rebuild
scripts/build-app         # 生成 build/slime.app
open build/slime.app
```

`scripts/build-app` 是手工拼 `.app` bundle 的（`swift build` + 生成 `Info.plist`），
不走 Xcode 工程。要 release 构建就 `CONFIG=release scripts/build-app`。

### `setup-signing` 为什么不是可选项

只跑一次，但这十分钟值得花。

macOS 把辅助功能授权绑定在 app 的**代码签名身份**上。ad-hoc 签名（`codesign -s -`）
的 designated requirement 只有一个 cdhash，于是**每次重新编译哈希都变，你必须手工
重新去系统设置里勾一遍权限**。换成自签证书，DR 锚定的是证书身份，证书不变 DR 就不变，
rebuild 不会掉权限。跳过这一步，你一天要勾几十次那个复选框。

## 首次运行

1. slime 会申请辅助功能权限，弹出系统对话框。
2. 在**系统设置 → 隐私与安全性 → 辅助功能**里把 slime 打开。
3. **退出 slime 再重新打开。** 权限只对新启动的进程生效 —— 每个人都会在这里
   踩一次坑。

如果 slime 装不上事件监听，它会报错并关闭接管，菜单栏设置仍可使用。授权后重启并在设置中重新启用。如果运行中
macOS 把 tap 禁掉了，slime 会停止拦截、退回系统原生 `⌘+Tab` —— **宁可切换器
失效，也不能让用户的键盘坏掉。**

## 测试

```sh
scripts/test
```

用 [swift-testing](https://github.com/swiftlang/swift-testing)（`import Testing`，
不是 XCTest）。测试集中在 `Sources/slime/Core/` 的纯逻辑上 —— 尤其是触发状态机：
状态机写错、吞掉了不该吞的按键，会让**整个系统的键盘**失效，而这个风险必须能在
单测里穷举，不能靠真人按键去试。

## 目录结构

```
Sources/slime/
  App/      main.swift, AppDelegate.swift, Permission.swift
  Core/     纯逻辑 —— Window, Search, Trigger, GridLayout。只依赖 Foundation，不 import AppKit。
  System/   EventTap, WindowEnumerator, WindowCache, WindowActivator
  UI/       面板、卡片、预览、设置
Tests/slimeTests/     swift-testing
docs/       specs / plans / modules / templates
scripts/    build-app, test, setup-signing, hooks
```

`Core/` 刻意不能 import AppKit、CoreGraphics、ApplicationServices。
纯状态/布局测试不依赖系统权限；另有 AppKit 控件及异步生命周期测试。真实 AX、登录项和动画观感仍需原生验收。

## 参与开发

所有变更走 **issue → 分支 → PR → merge**。禁止直接提交到 `main`，
pre-commit 钩子会拦。

- 分支：`feat/` `fix/` `docs/` `chore/`
- 提交标题：`类型(范围): 做了什么`，例如
  `fix(panel): keep the selection when the list refreshes`
- PR 必须写清**为什么**，不只是改了什么，并且必须关联 issue。只有把 issue 的
  交付物**做完了**才写 `Closes #N`，只完成一部分写 `Refs #N` —— 用错 `Closes`
  会把没做完的 issue 关掉，比不关更糟。

完整的开发规范在 [`CLAUDE.md`](CLAUDE.md)。动 `EventTap` 或 `WindowEnumerator`
之前先读它 —— 里面写了这个领域的正确性红线，踩错不是「看起来不好」，是会把
用户的机器弄坏。

## 文档

| 路径 | 内容 |
|---|---|
| [`docs/specs/`](docs/specs/) | 每个版本要做什么 |
| [`docs/modules/`](docs/modules/) | 分模块的设计、取舍、交接 |

## 许可证

尚未选定。
