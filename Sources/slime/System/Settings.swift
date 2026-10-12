import AppKit

/// 设置（spec §8）。放 System/ 不放 Core/ —— 读写全局可变状态是副作用，
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

  var glassTint: NSColor? {
    get {
      guard let data = defaults.data(forKey: Key.glassTint) else { return nil }
      return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }
    nonmutating set {
      guard
        let newValue,
        let data = try? NSKeyedArchiver.archivedData(
          withRootObject: newValue, requiringSecureCoding: true)
      else {
        defaults.removeObject(forKey: Key.glassTint)
        return
      }
      defaults.set(data, forKey: Key.glassTint)
    }
  }

  /// 读和写都钳位 —— 值可能是旧版本写的、或者被人手动改过。
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

  /// 钳位是这一层唯一的纯逻辑，也是唯一的单测点。
  static func clampCornerRadius(_ value: Double) -> Double {
    guard value.isFinite else {
      return value > 0 ? cornerRadiusRange.upperBound : cornerRadiusRange.lowerBound
    }
    return min(max(value, cornerRadiusRange.lowerBound), cornerRadiusRange.upperBound)
  }

  private enum Key {
    static let glassStyle = "glass.style"
    static let glassTint = "glass.tint"
    static let glassCornerRadius = "glass.cornerRadius"
  }
}
