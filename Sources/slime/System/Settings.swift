import AppKit

/// 设置（spec §7 / §8）。放 System/ 不放 Core/ —— 读写全局可变状态是副作用，
/// 不是纯逻辑（CLAUDE.md 第六条）。
///
/// 注入 `UserDefaults` 是为了测试不污染真的 defaults，不是为了「将来换实现」。
struct Settings {
  enum GlassStyle: String, CaseIterable {
    case regular, clear

    var glassEffectStyle: NSGlassEffectView.Style {
      self == .regular ? .regular : .clear
    }
  }

  static let cornerRadiusRange: ClosedRange<Double> = 0...40
  static let defaultCornerRadius: Double = 12

  /// 玻璃浓度（spec §7）：0 = 完全看不到面板后面的内容，1 = 完全透明。
  /// 实数上它是遮罩层的 alpha 的补数（`alpha = 1 − strength`），面板自己换算。
  static let strengthRange: ClosedRange<Double> = 0...1
  /// 默认给偏透明的值，但留出可见余量：1.0 时滑块到底、没有任何变化可看。
  /// shortcut: 0.7 是提案值，对着真机看玻璃定 —— 人工验收清单里那一条。
  static let defaultGlassStrength: Double = 0.7

  /// 高亮线条的颜色（spec §8）。**固定默认值，不跟系统主题色** —— 绑系统意味着
  /// 系统主题一改 slime 就跟着变，那是需求方明确不要的耦合，还多一个「跟随系统」
  /// 勾选框。这个橙是实测过的（近黑面板底 + 2.5pt 线条下对比度够）。
  static let defaultHighlightColor = NSColor(
    srgbRed: 0.969, green: 0.510, blue: 0.106, alpha: 1)

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var glassStyle: GlassStyle {
    get {
      defaults.string(forKey: Key.glassStyle).flatMap(GlassStyle.init(rawValue:)) ?? .regular
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: Key.glassStyle) }
  }

  /// 读和写都钳位 —— 值可能是旧版本写的、或者被人手动改过。
  var glassStrength: Double {
    get {
      guard defaults.object(forKey: Key.glassStrength) != nil else {
        return Self.defaultGlassStrength
      }
      return Self.clampStrength(defaults.double(forKey: Key.glassStrength))
    }
    nonmutating set {
      defaults.set(Self.clampStrength(newValue), forKey: Key.glassStrength)
    }
  }

  var glassCornerRadius: Double {
    get {
      guard defaults.object(forKey: Key.glassCornerRadius) != nil else {
        return Self.defaultCornerRadius
      }
      return Self.clampCornerRadius(defaults.double(forKey: Key.glassCornerRadius))
    }
    nonmutating set {
      defaults.set(Self.clampCornerRadius(newValue), forKey: Key.glassCornerRadius)
    }
  }

  /// 高亮色不带「无颜色」这个状态（0.0.2 的 `glassTint` 是可选，所以要用
  /// 「取到白就算清除」这种别扭表达）—— 它永远有个值，取不到就用默认。
  var highlightColor: NSColor {
    get {
      guard
        let data = defaults.data(forKey: Key.highlightColor),
        let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
      else { return Self.defaultHighlightColor }
      return color
    }
    nonmutating set {
      guard
        let data = try? NSKeyedArchiver.archivedData(
          withRootObject: newValue, requiringSecureCoding: true)
      else { return }
      defaults.set(data, forKey: Key.highlightColor)
    }
  }

  static func clampStrength(_ value: Double) -> Double {
    clamp(value, to: strengthRange)
  }

  /// 两个钳位（浓度 / 圆角）是这一层仅有的纯逻辑，也是仅有的单测点。
  static func clampCornerRadius(_ value: Double) -> Double {
    clamp(value, to: cornerRadiusRange)
  }

  /// 两个设置项共用的钳位：非有限值按符号取上 / 下界（NaN 落到下界）。
  private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    guard value.isFinite else { return value > 0 ? range.upperBound : range.lowerBound }
    return min(max(value, range.lowerBound), range.upperBound)
  }

  private enum Key {
    static let glassStyle = "glass.style"
    static let glassStrength = "glass.strength"
    static let highlightColor = "highlight.color"
    static let glassCornerRadius = "glass.cornerRadius"
  }
}
