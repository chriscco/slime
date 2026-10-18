<p align="center">
  <img src="docs/assets/slime-banner.png" alt="Slime — logo and green slime mascot" width="100%">
</p>

<p align="center">
  <a href="README.md">English →</a>
</p>

macOS 窗口切换器。比系统自带的切换器多两样东西：**打字即时搜索**和**双触发手势**。

## 安装

### 下载 DMG

需要 **macOS 15 或更新版本**。macOS 15 为实验性支持，权限和窗口操作仍待桌面实测。本轮发行包面向 **Apple silicon（arm64）**；Intel 可从源码构建，但本轮不提供已验证的 Intel 安装包。

1. 从 [GitHub Releases](https://github.com/chriscco/slime/releases) 下载 DMG 和对应的 `.sha256` 文件。
2. 在下载目录运行 `shasum -a 256 -c slime-0.0.6-arm64.dmg.sha256` 校验文件。
3. 打开 DMG，将 slime 拖到 Applications，推出磁盘映像，再从应用程序打开 slime。

**0.0.6 使用本地自签证书，未经 Apple 公证。** 如果 macOS 因无法验证开发者而阻止打开，确认文件来自本仓库且校验通过后，在“系统设置 → 隐私与安全性”中对 slime 选择“仍要打开”，再确认系统提示。无需全局关闭 Gatekeeper。参见 [Apple 的首次打开说明](https://support.apple.com/en-ie/102445)。

下载 DMG 安装无需运行签名或构建脚本。

### 从源码构建

安装 Xcode Command Line Tools 后，在仓库目录运行；无需完整 Xcode：

```sh
scripts/setup-signing     # 首次构建前运行一次，保持重新构建后的权限身份
scripts/build-app         # 生成 build/slime.app
open build/slime.app
```

发布构建使用 `CONFIG=release scripts/build-app`。

### 首次运行

在“系统设置 → 隐私与安全性”中授予 slime **辅助功能**权限；如需窗口预览，同时授予**屏幕录制**权限，然后退出并重新打开 slime。

## 手势

| 按键 | 行为 |
|---|---|
| 按住 `⌘`，连按 `Tab` | 循环切换窗口。**松开 `⌘` 就切过去** —— 手感跟系统原生的切换器一致。 |
| 按住 `⌥`，连按 `Tab` | 同一个面板，但**松手后面板留住**。可以直接打字搜索，按回车才切。 |
| `⌘F` | 聚焦搜索框。两种模式下都可用。 |
| `Tab` / `⇧Tab` | 选中往前 / 往后移。高亮条在项之间平滑滑动。 |
| `↑` `↓` `←` `→` | 移动选中。 |
| 直接打字 | 实时模糊过滤；开始打字后，松开 `⌘` 也会保留面板。 |
| `Enter` | 切到选中项。**最小化的窗口也能切过去。** |
| `⌘D` | 关闭选中窗口并播放 CRT 预览动画，不退出应用。 |
| `⌘,` | 打开设置；松开 Option 后仍可使用。 |
| `Esc` | 关闭面板，且不改变当前窗口。 |

列表按应用级 MRU 排序，包含当前窗口并将其放在末尾；开启分组后每个应用独立分区。固定每行五张，少于五张时面板宽度不缩小。同行下划线平滑移动，跨行直接定位。

slime 没有 Dock 图标，也不会出现在系统原生的 `⌘+Tab` 列表里。你不叫它，它就不出现。

它按**窗口而非 app**显示条目，让你直接跳到目标。公开系统 API 无法可靠发现或操作所有离屏窗口，限制见下文。

## 设置

从菜单栏或面板内按 `⌘,` 打开。

- **通用**：启用 slime、按应用分组、登录时启动、English / 简体中文（默认英文）。关闭 slime 后恢复系统 `⌘Tab`。
- **外观**：黑色、白色、深蓝、石墨灰、深紫灰或跟随系统的背景主题；macOS 26+ 可选液态玻璃或纯色，可调整高亮色和圆角。玻璃选项仅在选择液态玻璃时显示。默认高亮色为史莱姆绿 `#96D76A`。
- **快捷键**：查看按键说明。
- **关于**：版本号和 GitHub 仓库链接。

## 性能

以下是跨次打开复用预览优化前的基线。测试环境：Apple M4 / 16 GiB、macOS 27、双屏，**台前调度已开启，左侧有收起的窗口**。两种模式使用同一组 11 个窗口，预热后各在 20 秒内完成 12 轮打开面板、搜索和关闭面板。

| 预览来源 | 平均 CPU | 峰值内存 | 有效预览 |
|---|---:|---:|---:|
| 缓存预览 | 9.9% | 29.0 MiB | 3 / 11 |
| 重新抓取（不使用磁盘缓存） | 10.1% | 34.6 MiB | 8 / 11 |

在**设置 → 外观 → 预览来源**切换。两种模式都会跨次打开复用预览，在后台更新变化的窗口。重新抓取可显示台前调度的倾斜窗口，图片不保存到磁盘。打字搜索不会重复截图。

数据来自运行真实面板代码的独立 release 测试进程；CPU 100% 表示占满一个核心，内存采用物理占用口径。这是包含不同状态窗口的短时测试，不含 WindowServer/GPU 开销，也不代表最坏情况上限。[测试方法与完整结果](docs/validation/2026-10-16-slime-0.0.8-performance.md#stage-manager-follow-up-for-the-readme)。

## 系统要求

- **macOS 15+**。液态玻璃需要 macOS 26+；macOS 15 使用纯色背景，目前为实验性支持。
- 从源码构建需要 **macOS 26+ SDK**（Xcode 26+ 或对应的命令行工具）。
- **屏幕录制权限**用于预览。没有有效预览或同窗口缓存时，显示带应用图标的通用小窗口占位。
- **需要辅助功能权限。** slime 通过辅助功能 API 读窗口列表，并且要拦截你按下的
  按键，所以必须由 macOS 授权。

## 打包发行版

```sh
scripts/package-dmg
```

脚本执行 release 构建，按实际架构命名 DMG，并只读挂载验证版本、签名、图标、二进制和 Applications 链接，最后生成 SHA-256 校验文件。产物位于 `build/`。本地自签名用于稳定开发权限，不等于 Developer ID 签名或 Apple 公证。

Tag 自动发布流程和英文 Release 模板见[发版指南](docs/releases/README.md)。

## 已知限制

公开 AX 信息可能只覆盖部分 Space；从未观察过的窗口可能暂缺，歧义目标会拒绝关闭。跨 Space 缓存预览可能过期；从应用自身关闭且系统保留表面的窗口可能延迟清理。安全输入开启时使用系统切换器。面板打开期间，未专门绑定的 Command 字母组合仍作为过滤输入。登录启动和权限行为需按本机系统提示确认。

## 目录结构

```text
slime/
├── Package.swift
├── Resources/
│   ├── slime.png
│   └── slime.icns
├── Sources/slime/
│   ├── App/
│   ├── Core/
│   ├── System/
│   └── UI/
├── Tests/slimeTests/
├── docs/
│   ├── specs/
│   ├── plans/
│   ├── modules/
│   ├── releases/
│   └── templates/
├── scripts/
│   ├── build-app
│   ├── package-dmg
│   ├── benchmark
│   ├── fixtures/
│   ├── test
│   ├── setup-signing
│   └── hooks/
└── .github/workflows/
    └── test.yml
```

## 参与开发

所有变更走 **issue → 分支 → PR → merge**。禁止直接提交到 `main`，
pre-commit 钩子会拦。

- 分支：`feat/` `fix/` `docs/` `chore/`
- 提交标题：`类型(范围): 做了什么`，例如
  `fix(panel): keep the selection when the list refreshes`
- PR 必须写清**为什么**，不只是改了什么，并且必须关联 issue。只有把 issue 的
  交付物**做完了**才写 `Closes #N`，只完成一部分写 `Refs #N` —— 用错 `Closes`
  会把没做完的 issue 关掉，比不关更糟。

完整的开发规范在 [`CLAUDE.md`](CLAUDE.md)（英文）。动 `EventTap` 或 `WindowEnumerator`
之前先读它 —— 里面写了这个领域的正确性红线，踩错不是「看起来不好」，是会把
用户的机器弄坏。

## 文档

| 路径 | 内容 |
|---|---|
| [`docs/specs/`](docs/specs/) | 每个版本要做什么 |
| [`docs/modules/`](docs/modules/) | 分模块的设计、取舍、交接 |

## 许可证

本项目采用 [MIT 许可证](LICENSE)。
