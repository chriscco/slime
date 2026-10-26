import AppKit
import Testing
@testable import slime

@Test @MainActor func fontPreferencesPersistAndRejectInvalidValues() throws {
  let suite = "slime.fonts.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  #expect(settings.fontFamily == .system)
  #expect(settings.searchFontSize == 15)
  #expect(settings.titleFontSize == 12)
  settings.fontFamily = .menlo
  settings.searchFontSize = 20
  settings.titleFontSize = 18
  let restored = Settings(defaults: defaults)
  #expect(restored.fontFamily == .menlo)
  #expect(restored.searchFontSize == 20)
  #expect(restored.titleFontSize == 18)
  #expect(restored.font(at: 20).familyName == "Menlo")
  defaults.set("missing-font", forKey: "panel.fontFamily")
  defaults.set(500, forKey: "panel.searchFontSize")
  defaults.set("bad", forKey: "panel.titleFontSize")
  #expect(restored.fontFamily == .system)
  #expect(restored.searchFontSize == 15)
  #expect(restored.titleFontSize == 12)
  settings.searchFontSize = .nan
  settings.titleFontSize = -1
  #expect(settings.searchFontSize == 15)
  #expect(settings.titleFontSize == 12)
  for family in Settings.FontFamily.allCases {
    settings.fontFamily = family
    #expect(settings.font(at: 16).pointSize == 16)
    if !family.isAvailable { #expect(settings.font(at: 16) == NSFont.systemFont(ofSize: 16)) }
  }
}

extension PanelAndThumbnailTests {
@Test @MainActor func panelFontsPreserveCompositionAndReachReusedCards() throws {
  let suite = "slime.panel-fonts.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  let controller = PanelController(settings: settings)
  defer { controller.dismiss() }
  let first = Window(pid: 1, windowID: 981, appName: "App", title: "工作 Safari 🐱", isMinimized: false)
  let second = Window(pid: 1, windowID: 982, appName: "App", title: "Beta", isMinimized: false)
  controller.setWindows([first, second])
  let state = State.lingering(query: "", selection: 0)
  controller.handle(state: state, effects: [.showPanel(.opt), .focusSearchField])
  let content = controller.panel.content
  let editor = content.searchEditor
  let card = try #require(content.gridView.card(for: first.windowID))
  controller.handle(state: state, effects: [.setQuery("Beta")])
  editor.setMarkedText("zhou", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
  let selection = editor.selectedRange()
  settings.fontFamily = .monaco
  settings.searchFontSize = 20
  settings.titleFontSize = 20
  controller.refreshAppearance()
  #expect(editor.font?.fontName == "Monaco")
  #expect(editor.font?.pointSize == 20)
  #expect(content.searchLabel.font == editor.font)
  #expect(editor.hasMarkedText())
  #expect(editor.string == "zhou")
  #expect(editor.selectedRange() == selection)
  #expect(controller.panel.firstResponder === editor)
  controller.handle(state: state, effects: [.setQuery("")])
  #expect(content.gridView.card(for: first.windowID) === card)
  let title = try #require(card.subviews.compactMap { $0 as? NSTextField }.first)
  #expect(title.font == settings.font(at: 20))
  controller.setWindows([first, second, Window(pid: 1, windowID: 983, appName: "App", title: "New", isMinimized: false)])
  let newCard = try #require(content.gridView.card(for: 983))
  #expect(newCard.subviews.compactMap { $0 as? NSTextField }.first?.font == settings.font(at: 20))
}

@Test @MainActor func allFontSizesFitSearchAndCardTitleGeometry() throws {
  let suite = "slime.font-layout.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let settings = Settings(defaults: defaults)
  let controller = PanelController(settings: settings)
  defer { controller.dismiss() }
  let window = Window(pid: 1, windowID: 984, appName: "App", title: "工作 Safari 🐱", isMinimized: false)
  controller.setWindows([window])
  controller.handle(state: .lingering(query: "", selection: 0), effects: [.showPanel(.opt)])
  let content = controller.panel.content
  let editor = content.searchEditor
  let manager = try #require(editor.layoutManager)
  let container = try #require(editor.textContainer)
  let card = try #require(content.gridView.card(for: window.windowID))
  let title = try #require(card.subviews.compactMap { $0 as? NSTextField }.first)
  for family in Settings.FontFamily.allCases where family.isAvailable {
    for size in Settings.fontSizes {
      settings.fontFamily = family
      settings.searchFontSize = size
      settings.titleFontSize = size
      editor.setCommittedText("Search")
      controller.refreshAppearance()
      content.layoutSubtreeIfNeeded()
      card.layoutSubtreeIfNeeded()
      #expect(editor.font == settings.font(at: size))
      for text in ["", "Search", "工作", "工作 Safari 🐱"] {
        editor.setCommittedText(text)
        editor.layoutSubtreeIfNeeded()
        manager.ensureLayout(for: container)
        let line = manager.numberOfGlyphs == 0 ? manager.extraLineFragmentRect
          : manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        if let latin = text.range(of: "Safari") {
          let offset = NSRange(latin, in: text).location
          let latinFont = editor.textStorage?.attribute(.font, at: offset, effectiveRange: nil) as? NSFont
          #expect(latinFont == settings.font(at: size))
        }
        #expect(line.height <= editor.bounds.height, "\(family) \(size): \(line)")
        #expect(abs(editor.textContainerOrigin.y + line.midY - editor.bounds.midY) <= 0.5, "\(family) \(size) \(text): line \(line), origin \(editor.textContainerOrigin), bounds \(editor.bounds)")
      }
      #expect(editor.enclosingScrollView!.frame.height <= content.searchBox.bounds.height)
      #expect(title.font == settings.font(at: size))
      #expect(title.frame.height >= title.intrinsicContentSize.height)
      #expect(card.preview.frame.maxY <= title.frame.minY)
      #expect(title.frame.maxY <= card.bounds.maxY - 10)
    }
  }
}
}

extension PanelAndThumbnailTests {
@Test @MainActor func nativeLatinAfterChineseKeepsTheChosenFont() throws {
  let panel = PanelWindow()
  panel.makeKeyAndOrderFront(nil)
  defer { panel.orderOut(nil) }
  panel.content.setSearchFocused(true)
  let editor = panel.content.searchEditor
  editor.searchFont = try #require(NSFont(name: "Menlo", size: 18))
  editor.insertText("工作", replacementRange: NSRange(location: NSNotFound, length: 0))
  editor.insertText(" Safari", replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(editor.string == "工作 Safari")
  #expect(editor.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont == editor.searchFont)
  editor.selectAll(nil)
  editor.setMarkedText("zhou", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
  editor.insertText("周报", replacementRange: NSRange(location: NSNotFound, length: 0))
  editor.insertText(" Safari", replacementRange: NSRange(location: NSNotFound, length: 0))
  #expect(editor.string == "周报 Safari")
  #expect(editor.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont == editor.searchFont)
}
}
