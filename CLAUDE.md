# CLAUDE.md — slime 开发规范

## 这个项目是什么

macOS 窗口切换器。两个核心特性：**打字即时搜索**和**双触发手势**
（⌘+Tab 松手切换 / ⌥+Tab 松手留住）。

**目标是快速迭代出一条能天天用的主链路**，不是做产品、不是做完整。
0.0.1 的边界见 `docs/specs/2026-10-11-slime-0.0.1-spec.md`。

---

## 第一条：KISS / YAGNI

写代码前先爬这个梯子，**停在第一个能用的台阶**：

1. 这东西需要存在吗？—— 投机性需求直接跳过，并在回复里说一句
2. 仓库里已经有了吗？—— 先找，再写。重复实现几文件外已有的东西是最常见的垃圾
3. 标准库 / 语言内建能做吗？
4. **平台原生能力覆盖了吗？** —— AppKit 和系统 API 能干的，不要自己造
5. 已装的依赖能解决吗？—— **本项目零第三方依赖**，加依赖要单独说明理由
6. 能一行写完吗？
7. 以上都不行，才写最小可用实现

**具体禁令**

- 不为一个实现写接口，不为一个产品写工厂，不为永不变化的值写配置
- 不留「以后要用」的脚手架 —— 以后可以自己搭
- 优先删代码而不是加代码；无聊胜过聪明，聪明是留给凌晨三点的人解码的
- **TDD**：代码行为变更先写一个通过公开接口观察行为的失败测试，再写最小实现使其通过；
  一次只做一个 red → green 纵向切片
- 测试放在 `Tests/slimeTests/`，用 **swift-testing**（`import Testing`，不是 XCTest）；
  本地提交前运行 `scripts/test`（本机补 Testing 路径的 workaround 在脚本里）
- 故意砍掉的角标 `shortcut:` 注释，写明上限和升级路径

**这个项目里 KISS 有牙齿的地方**：`Core/` 的那几个纯逻辑文件（`Window`、`Search`、
`Trigger`、`GridLayout`）是唯一能单测的东西。任何把系统 API 拉进 `Core/` 的改动，
都会让这个项目变成「只能靠手点来验证」—— 那等于放弃测试。

---

## 第二条：开发流程 —— 禁止直接改 main

所有变更走 **issue → 分支 → PR → merge 合入**：

```sh
gh issue create --title "..." --body "..."       # 1. 需求落到 issue
git switch -c feat/<短描述>                       # 2. 从最新 main 开分支
git commit -m "..."                              # 3. 小步提交
git push -u origin feat/<短描述>                  # 4. 推分支
gh pr create --fill --body "Closes #<issue>"     # 5. 开 PR 并关联 issue
gh pr merge --merge --delete-branch \
  -t "Merge pull request #<N> from chriscco/<branch>" \
  -b "<PR 标题>"                                   # 6. 合入并删分支
```

**合入用 merge commit，不用 squash。** 分支上的每个小步都是一次可回溯的改动
（为什么这么改、踩了什么），压成一条就全扔了 —— 而「这行为什么长这样」正是
issue/PR 流程要留住的东西。历史里 PR 的统一形状是：

```
Merge pull request #N from chriscco/<branch>
                                        ← 空行
<PR 标题>
```

gh 不传 `-t` 时默认给的是 PR 标题，对不上，所以要用 `-t` 指定 subject、
`-b` 补上 PR 标题那一行。

PR 开完之后**必须自己跑一遍 `.agents/skills/pr-review/SKILL.md` 的审查**，
把结论贴成 PR comment，修到 Ready 再合 —— 贴完 review 就可以直接合入，不用等人工。

本地 `pre-commit` 钩子会**拒绝在 main 上提交**。克隆后启用一次：

```sh
git config core.hooksPath scripts/hooks
```

**例外**：仓库初始化期间的提交直接在 main 上做 —— 首个 spec 提交，以及规范、
模板、钩子、构建脚本的落地。**初始化以 `.github/workflows/test.yml` 在 main 上
首次通过为界**，过了这条线不再有例外。

分支命名：`feat/` `fix/` `docs/` `chore/`

PR 必须写清**为什么**这么改，不只是改了什么。
行为变更必须同时提交测试；纯文档或只改静态配置时可以不新增测试，但仍要跑完整测试命令。

### 提交信息格式

**非 merge commit 的一行标题必须写成 `类型(范围): 做了什么`。** 例如：

```
feat(trigger): add the pure state machine
fix(panel): keep the selection when the list refreshes
docs(norms): record the commit-message format
chore(scripts): probe the toolchain in scripts/test
```

- 类型就是分支前缀那一组：`feat` / `fix` / `docs` / `chore`，与 `feat/` `fix/` … 分支对应
- 范围 = 改动的模块（`trigger` `search` `window` `system` `panel` `app` `scripts` `norms` …），不是文件路径
- 冒号后一个空格，接小写祈使句，说清「做了什么」；**为什么**和细节放正文
- merge commit 不适用 —— GitHub 生成的 `Merge pull request #N from chriscco/<branch>` 保持原样

### 提交署名

**作者必须是 `chriscco <2444628489c@gmail.com>`。** 已经在本地 git 配置里设好
（`--local`，不影响其他仓库）。不要从环境里继承别的身份。

### Issue 与 PR review

- 新 issue 默认用英文模板 `.github/ISSUE_TEMPLATE/issue.md`，中文版用
  `.github/ISSUE_TEMPLATE/issue-zh.md`：写清目标、原因、范围与可证伪的验收标准。
- 审查 PR 或发布 review comment 时，读取并遵循 `.agents/skills/pr-review/SKILL.md`。

### PR 必须关联 issue —— 但两类关联别用错

| 写法 | 何时用 | 合入效果 |
|---|---|---|
| `Closes #N` | 该 PR 把 issue 的交付物**做完了** | 自动关闭 issue |
| `Refs #N` | 只完成一部分（例如只产出 spec，还没实现） | 只建立链接，**不关闭** |

**每个合并的 PR 都必须关闭它关联的 issue（`Closes #N`）；`Refs #N` 的 PR 不合并。**

**用错 `Closes` 会把没做完的 issue 关掉。** issue 关了但活没干，比不关更糟 ——
它会从待办列表里消失，然后被忘掉。

**不允许无关联 issue 的 PR。** 没有 issue 就先建一个 —— 建 issue 的成本远低于
事后追查「这行为什么长这样」的成本。

---

## 第三条：什么时候写哪份文档

**不要每个小改动都写文档。** 文档本身也要过 KISS/YAGNI。触发阈值：

| 文档 | 何时必须写 | 位置 |
|---|---|---|
| spec | **较大需求**：跨多个模块 / 跨多次会话 / 含重要取舍 —— 三条任一成立 | `docs/specs/YYYY-MM-DD-<kebab-描述>-spec.md` |
| plan | spec 要拆成**有先后依赖的任务**、一次会话做不完时（plan 描述「怎么做」，spec 描述「做什么」） | `docs/plans/YYYY-MM-DD-<kebab-描述>.md` |
| design | 模块代码 > 150 行 **或** 含正确性假设 | `docs/modules/<模块>/design.md` |
| decision | **每做一个值得回溯的取舍就追加一条**，只追加不改写历史 | `docs/modules/<模块>/decision.md` |
| handoff | 会话结束 / 交接时更新：现状、下一步、坑 | `docs/modules/<模块>/handoff.md` |

小改动不写 spec，直接开 PR。模板在 `docs/templates/`。

**这个项目已经做出的、值得进 `decision.md` 的取舍**（写对应模块时补上）：
选 Swift 而非 Rust；触发状态机做成纯函数；0.0.1 不做缩略图；用缓存快照而非
AXObserver 增量更新。理由见 spec §4 / §6 / §7。

---

## 第四条：这个领域的正确性红线

窗口切换器踩错这些**不是风格问题**，是会把用户的机器弄坏：

1. **事件 tap 回调里绝对不许阻塞。** 不能有 AX 调用、不能读磁盘、不能等锁 ——
   只有状态机和吞事件。

2. **必须处理 `kCGEventTapDisabledByTimeout`。** 回调超时，macOS 会直接禁掉我们的 tap，
   **那一刻 ⌘+Tab 在全系统范围内失效，直到用户重启 slime**。收到必须立刻
   `CGEventTapEnable(tap, true)`。

3. **必须有兜底。** tap 被系统连续禁掉几次，就停止吞事件、退回系统原生 ⌘+Tab 并提示用户。
   **宁可功能失效，不能让用户没法切 app。**

4. **枚举必须在后台线程。** AX 是跨进程同步 IPC，跑主线程 = 按下快捷键就转圈。

5. **过期结果必须丢弃。** 用主线程上的 generation 计数，后台结果回来时对不上就扔。

6. **每个 AX element 要设 `AXUIElementSetMessagingTimeout`（~1 秒）。**
   一个无响应的 app 会让 `AXUIElementCopyAttributeValue` 一直挂着 ——
   **没有这一条，一个卡死的 Electron 应用就能让整个切换器瘫掉。**

7. **窗口过滤按 `kCGWindowLayer == 0`，不按窗口尺寸。** 台前调度搁置的窗口，
   `kCGWindowBounds` 报的是左侧条带里那个又小又斜的方框，按尺寸过滤会把它们全丢掉，
   而用户完全不知道为什么。

8. **`Window` 是不可变 struct，快照是不可变数组。** 主线程读旧快照、后台造新快照、
   发布时整体替换 —— **天然无锁**。不要引入共享可变状态。

9. **允许出现的降级要写清**：安全输入（密码框）开着时系统不给 tap 发事件，
   ⌘+Tab 自动走原生行为 —— 这是**预期行为**，不是 bug。

---

## 第五条：本机环境坑

- **只有 CommandLineTools，没有完整 Xcode。** 所以没有 Instruments、没有视图调试器。
  构建走 `swift build` + 手工组 `.app` bundle（`scripts/build-app`），不走 Xcode 工程。
- **辅助功能权限认的是代码签名。** 用 ad-hoc 签名（`codesign -s -`）的话，
  每次重新编译哈希都变 → **每次 rebuild 都要重新去系统设置勾一遍权限**。
  用自签证书签，让 designated requirement 稳定下来。**这不是可选项** ——
  它直接决定迭代速度。
- **授权后要重启 app 才生效。** 改了权限行为没变，先想到这条，别去查代码。
- 本机开了代理（Clash Verge），代理地址 `http://127.0.0.1:7897`。终端里
  `git push` / `gh` / `curl` 连不上 GitHub 时，**先 export 再试**：

  ```sh
  export http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897
  ```

  **别把它当成"网络坏了"** —— 提示是超时，根因是没有代理。
- **Swift 6 语言模式**（tools 6.0 默认）。这是对 spec §13「Swift 5 锁」的有意偏离：
  本机拿不到 XCTest，而 swift-testing 只随 Swift 6 工具链来 —— 用 Swift 6，
  测试就不依赖完整 Xcode。代价是 AppKit 代码要按严格并发写（`@MainActor`、
  少量有注释的 `@unchecked Sendable`）。理由和推翻条件在
  `docs/modules/app/decision.md`。
- 生成物（`.build/`、`build/`）不入库。

---

## 第六条：代码分层

```
Sources/slime/
  App/        main.swift, AppDelegate.swift, Permission.swift
  Core/       Window.swift, Search.swift, Trigger.swift, GridLayout.swift
  System/     EventTap.swift, WindowEnumerator.swift, WindowCache.swift, WindowActivator.swift,
              AppIcons.swift, Settings.swift
  UI/         PanelWindow.swift, PanelController.swift, CardGridView.swift, SettingsWindow.swift
Tests/slimeTests/
docs/         specs / modules / templates
scripts/      build-app, test, hooks/
```

### 谁能 import 谁

```
App/      →  UI, System, Core
UI/       →  System, Core
System/   →  Core, AppKit, CoreGraphics, ApplicationServices
Core/     →  Foundation, 标准库
             ✗ 禁止 AppKit、CoreGraphics、ApplicationServices
```

**纯逻辑层 = `Core/`。** 它是这个项目里唯一能被单测的部分，禁令不是洁癖：
`Trigger` 的状态机一旦能 import AppKit，就会有人顺手在里面摸一下 `NSEvent`，
然后「吞掉不该吞的按键导致全系统键盘挂掉」这个风险就再也没法在测试里穷举了。

`Trigger` 和 `Search` 的公开接口必须是纯函数：

```swift
func reduce(_ state: State, _ event: Event) -> (State, [Effect])
```

**翻译 CGEvent / NSEvent 的活在 `System/` 和 `UI/`，不在 `Core/`。**

### 目录按触发条件建，不提前堆空壳

| 目录 | 什么时候往里放东西 |
|---|---|
| `docs/modules/<模块>/` | 该模块代码超过 150 行，或有正确性假设时 |
| `Sources/slime/System/` 下新增文件 | 真的出现了新的系统边界时 |
| 分层守卫测试 | `Core/` 到第 4 个文件时补 —— **已补**：`Tests/slimeTests/LayeringTests.swift` 拦 Core/ 里 import AppKit / CoreGraphics / ApplicationServices |

**源文件保持精简（0.0.2 时 17 个）。** 加文件之前先问：能不能并进已有的那个？
