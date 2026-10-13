# Trigger · 设计

纯函数 `reduce(state, event) -> (state, [Effect])`，只依赖标准库。EventTap 翻译并独占状态；PanelController 执行 UI Effect，维护有边界的真实选择。

| 状态 | 转移 |
|---|---|
| idle | 修饰键按下 → armed；其余放行 |
| armed(m) | Tab → holding + showPanel；该修饰键松开 → idle；普通快捷键放行 |
| holding(cmd) | 松 Command → activate/hide；⌘F → lingering |
| holding(opt) | 松 Option → lingering |
| lingering | 修饰键上下保持 query/selection；Tab、方向、输入继续操作；Enter 激活，Esc 取消，⌘, 开设置 |
| closing | 修饰键上下保持会话，导航/输入/重复关闭吞掉；Esc 或设置仍可结束；closeFinished → lingering |

holding/lingering 的 ⌘D 都进入 closing 并发出 closeWindow。因此松 Command 不会意外激活邻居。关闭操作完成（包括失败、空列表）后由 UI 经 tap run loop 发 closeFinished；会话 revision 过滤过期完成。

`panelStep` 共用普通导航、搜索和结束操作。`selection` 是无界计数，实际窗口数量、分组、循环导航及身份跟随由 PanelController/GridLayout 处理。空列表 activate 由 UI 变为 no-op。

Effect 中有 swallow 才吞；会话外非 Tab 键必须放行。会话内无法翻译的 keyDown、关闭键 autorepeat 由 EventTap 兜底处理。Core 不引用 AppKit/CGEvent/AX，状态转移可直接单测。
