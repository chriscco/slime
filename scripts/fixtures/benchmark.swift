import AppKit
import Foundation
_ = NSApplication.shared
func milliseconds(_ duration: Duration) -> Double {
  let c = duration.components
  return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
}
for count in [10, 50, 100] {
  for grouped in [false, true] {
    let suite = "slime.benchmark.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = Settings(defaults: defaults)
    settings.groupByApp = grouped
    let controller = PanelController(settings: settings)
    controller.handle(state: .lingering(query: "", selection: 0), effects: [])
    controller.setWindows((0..<count).map { index in
      Window(pid: pid_t(990000 + index / 10), windowID: UInt32(index + 1), appName: "Bench app \(index / 10)",
        title: "Window \(index): pull requests, document, terminal and notes", isMinimized: false)
    })
    let view = controller.panel.content
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    var values: [Double] = []
    for sample in 0..<35 {
      let start = ContinuousClock.now
      controller.handle(state: .lingering(query: "w", selection: 0), effects: [.appendQuery("w")])
      view.layoutSubtreeIfNeeded()
      view.cacheDisplay(in: view.bounds, to: bitmap)
      let elapsed = milliseconds(start.duration(to: .now))
      if sample >= 5 { values.append(elapsed) }
      controller.handle(state: .lingering(query: "", selection: 0), effects: [.deleteQueryChar])
    }
    values.sort()
    print("windows=\(count) grouped=\(grouped) samples=\(values.count) p50_ms=\(values[14]) p95_ms=\(values[28])")
    controller.dismiss()
    defaults.removePersistentDomain(forName: suite)
  }
}
