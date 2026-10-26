import AppKit

/// AppKit owns marked text, selection, clipboard and the insertion-point geometry.
final class SearchEditor: NSTextView {
  var onQuery: ((String) -> Void)?
  var onCommand: ((Event) -> Void)?
  var onFocus: (() -> Void)?
  private let searchUndo = UndoManager()
  private var changingMarkedText = false
  private var committed = ""
  override var undoManager: UndoManager? { searchUndo }

  init() {
    let storage = NSTextStorage()
    let layout = NSLayoutManager()
    let container = NSTextContainer()
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    super.init(frame: .zero, textContainer: container)
    isRichText = false
    importsGraphics = false
    drawsBackground = false
    font = .systemFont(ofSize: 15)
    textColor = .labelColor
    insertionPointColor = .labelColor
    textContainerInset = .zero
    textContainer?.lineFragmentPadding = 0
    isHorizontallyResizable = true
    isVerticallyResizable = false
    textContainer?.widthTracksTextView = false
    textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 24)
    minSize = .zero
    maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 24)
    allowsUndo = true
    setAccessibilityLabel(localized("Search windows", "搜索窗口"))
  }
  required init?(coder: NSCoder) { fatalError("Use init()") }

  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    let caret = NSRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
    if flag {
      color.setFill()
      NSBezierPath(roundedRect: caret, xRadius: 1, yRadius: 1).fill()
    } else {
      setNeedsDisplay(caret)
    }
  }

  override func setNeedsDisplay(_ invalidRect: NSRect) {
    // AppKit invalidates a thin caret; also erase the extra width when it moves or blinks.
    super.setNeedsDisplay(NSRect(x: invalidRect.minX, y: invalidRect.minY,
      width: invalidRect.width + 2, height: invalidRect.height))
  }

  func reset() {
    onQuery = nil
    onCommand = nil
    inputContext?.discardMarkedText()
    super.unmarkText()
    string = ""
    committed = ""
    setSelectedRange(NSRange(location: 0, length: 0))
    searchUndo.removeAllActions()
  }

  func setCommittedText(_ text: String) {
    guard string != text else { return }
    string = text
    committed = text
    setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
  }

  override func mouseDown(with event: NSEvent) {
    onFocus?()
    super.mouseDown(with: event)
  }

  override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    changingMarkedText = true
    super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    changingMarkedText = false
    publishCommittedText()
  }

  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    let text = (insertString as? NSAttributedString)?.string ?? (insertString as? String ?? "")
    let singleLine = text.replacingOccurrences(of: "\r\n", with: " ")
      .components(separatedBy: .newlines).joined(separator: " ")
    super.insertText(singleLine, replacementRange: replacementRange)
    publishCommittedText()
  }

  override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
    guard let text = pboard.string(forType: .string) else { return false }
    insertText(text, replacementRange: selectedRange())
    return true
  }

  override func unmarkText() {
    super.unmarkText()
    publishCommittedText()
  }

  override func didChangeText() {
    super.didChangeText()
    publishCommittedText()
  }

  private func publishCommittedText() {
    guard !changingMarkedText, !hasMarkedText(), committed != string else { return }
    committed = string
    onQuery?(string)
  }

  override func keyDown(with event: NSEvent) {
    // Snapshot before interpretation: the same key that ends composition cannot act on the panel.
    if hasMarkedText() { super.keyDown(with: event); return }
    let flags = event.modifierFlags
    let command = flags.contains(.command)
    let option = flags.contains(.option)
    let plain = flags.intersection([.command, .option, .control, .shift]).isEmpty
    if event.keyCode == 2, command, event.isARepeat { return }
    let panelEvent: Event?
    switch event.keyCode {
    case 48 where !flags.contains(.control): panelEvent = .tab(shift: flags.contains(.shift))
    case 36, 76: panelEvent = .enter
    case 53: panelEvent = .escape
    case 126 where plain: panelEvent = .arrow(axis: .vertical, step: -1)
    case 125 where plain: panelEvent = .arrow(axis: .vertical, step: 1)
    case 2 where command: panelEvent = .closeWindow
    case 3 where command || option: panelEvent = .focusSearch
    case 43 where command || option: panelEvent = .openSettings
    default: panelEvent = nil
    }
    if let panelEvent { onCommand?(panelEvent); return }
    if command {
      switch event.charactersIgnoringModifiers?.lowercased() {
      case "a": selectAll(nil)
      case "c": copy(nil)
      case "x": cut(nil)
      case "v": pasteAsPlainText(nil)
      case "z":
        breakUndoCoalescing()
        if flags.contains(.shift) { searchUndo.redo() } else { searchUndo.undo() }
      default: interpretKeyEvents([event])
      }
    } else { super.keyDown(with: event) }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
    keyDown(with: event)
    return true
  }

  override func doCommand(by selector: Selector) {
    switch NSStringFromSelector(selector) {
    case "insertNewline:", "insertNewlineIgnoringFieldEditor:", "insertLineBreak:",
         "insertParagraphSeparator:", "insertTab:", "insertTabIgnoringFieldEditor:", "insertBacktab:": return
    default: break
    }
    // Unbound commands end here, never in the application's menu or a background responder.
    if responds(to: selector) { super.doCommand(by: selector) }
  }
}
