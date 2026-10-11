import AppKit

// slime 0.0.1 —— 入口（spec §7）。
//
// .accessory：无 Dock 图标、不出现在系统的 ⌘+Tab 列表里（spec §2 第 1 条）。
// delegate 是强引用：NSApplication.delegate 是 weak，顶层 let 活到进程退出。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
