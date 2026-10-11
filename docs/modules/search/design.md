# Search · 设计

## 职责

打字即时搜索的纯函数实现：过滤 + 排序。负责「给一批按 MRU 排好的窗口和一段 query，返回过滤后按匹配质量排好的窗口」。

**不负责**：取窗口数据（WindowEnumerator）、维护 MRU（WindowCache）、渲染和选中（PanelController）。这一层只有纯函数，没有任何系统调用 —— 它是本项目能单测的两块逻辑之一（spec §10）。

## 数据结构

- `Window`（`Core/Window.swift`）：不可变 struct，`pid` / `windowID: UInt32` / `appName` / `title` / `isMinimized`。`windowID` 用 `UInt32` 而不是 `CGWindowID`：那是 CoreGraphics 的类型，Core/ 不许碰。
- `Window.label` = `appName — title`（title 为空时只有 app 名）。列表显示和搜索匹配共用同一个串，所以搜 app 名和搜标题命中同一批结果（spec §7）。

## 流程

`Search.rank(windows, query)` 一次遍历：

1. 空 query：原样返回（输入即 MRU，不重排）。
2. 非空：对每个窗口的 `label` 做贪心子序列匹配（不区分大小写），命中者带得分。
3. 显式按 `(得分降序, 原下标升序)` 排序 —— 得分相同保持 MRU。

匹配得分（每个命中字符）：`+1` 基础，`+1` 与前一个命中字符相邻，`+1` 落在词首（开头，或前一字符是空格 / 连字符 / 下划线）。连续与词首权重相同。

## 接口

```swift
public static func rank(_ windows: [Window], query: String) -> [Window]
```

纯函数。契约：

- 输入 `windows` 必须已按 MRU 排好；
- 返回命中的窗口，得分降序、同分保持输入相对顺序；无命中返回空数组。

## 正确性假设

- **输入是 MRU 序**。打破时（调用方传任意序）：无 query 的结果顺序随即失去意义 —— 可观察症状是「刚用过的窗口没排在最前」。
- **贪心匹配不会漏命中**：每个 query 字符取最早可行位置是子序列可行性的最优策略，贪心只会让*得分*不是最优对齐（`a_b_ab` 这类多重合处），不影响命中与否。症状只会是「排名没达到理想」，不会是「窗口搜不到」。
- **`label` 是唯一的匹配目标**：调用方（枚举层）不在别处拼接 app 名和标题，否则会出现搜不到的窗口。

## 已知限制

- 得分不含位置惩罚、长度归一，未做 fzf 式最优对齐 —— 0.0.1 不需要，见 decision.md。
- 无拼音（spec §3 主动砍掉）。
- `lowercased()` 是 Unicode 感知的，非 ASCII 大写（如土耳其语 İ）行为以 Foundation 为准，未专门测。
