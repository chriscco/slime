# slime

macOS 窗口切换器，思路参考 [alt-tab-macos](https://github.com/lwouis/alt-tab-macos)，
但多了两样它没有的东西：**打字即时搜索**和**双触发手势**。

**[English →](README.md)**

> **当前版本：0.0.1。** 主链路已经能天天用。0.0.2（卡片网格、液态玻璃面板、
> 设置页）正在 [PR #29](https://github.com/chriscco/slime/pull/29) 上做。

## 手势

| 按键 | 行为 |
|---|---|
| 按住 `⌘`，连按 `Tab` | 循环切换窗口。**松开 `⌘` 就切过去** —— 手感跟系统原生的切换器一致。 |
| 按住 `⌥`，连按 `Tab` | 同一个面板，但**松手后面板留住**。可以直接打字搜索，按回车才切。 |
| `⌘F` | 聚焦搜索框。两种模式下都可用。 |
| `Tab` / `⇧Tab` | 选中往前 / 往后移。 |
| `↑` `↓` `←` `→` | 移动选中。 |
| 直接打字 | 实时模糊过滤 —— `ghb` 能命中 `Chrome — GitHub`。 |
| `Enter` | 切到选中项。**最小化的窗口也能切过去。** |
| `Esc` | 关闭面板，且不改变当前窗口。 |

列表按 MRU 排序，最近用过的窗口排在最前。

slime 没有 Dock 图标，也不会出现在系统原生的 `⌘+Tab` 列表里。你不叫它，它就不出现。

## 系统要求

- **0.0.1 需要 macOS 14+。** 0.0.2 会抬到 **macOS 26** —— 它用
  `NSGlassEffectView` 渲染面板，更早的系统没有这个类。
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

如果 slime 装不上事件监听，它会报错并退出，而不是静默地留在后台。如果运行中
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
  Core/     纯逻辑 —— Window, Search, Trigger。只依赖 Foundation，不 import AppKit。
  System/   EventTap, WindowEnumerator, WindowCache, WindowActivator
  UI/       PanelWindow, PanelController
Tests/slimeTests/     swift-testing
docs/       specs / plans / modules / templates
scripts/    build-app, test, setup-signing, hooks
```

`Core/` 刻意不能 import AppKit、CoreGraphics、ApplicationServices。
它是这个项目里唯一能被单测的层；一旦系统 API 进得去，这个项目就变成
「只能靠手点来验证」—— 那等于放弃测试。

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
