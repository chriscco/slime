import Testing

@testable import slime

// ←(123) / →(124) 曾经掉进 KeyTable 的 default 分支。方向键的
// charactersIgnoringModifiers 是私用区的 U+F702 / U+F703，既不是控制字符
// （isControlLike 判的是 < 0x20 || == 0x7F）也不为 nil，于是被翻译成
// .char("\u{F702}") —— 面板里按左右键会往搜索框塞不可见字符、列表清空。
// 这两个测试就是那条 bug 的回归。

@Test func leftAndRightArrowsAreNotCharacters() throws {
  let left = try #require(
    KeyTable.event(keyCode: 123, shift: false, commandOrOption: true, character: "\u{F702}"))
  #expect(left == .arrow(axis: .horizontal, step: -1))

  let right = try #require(
    KeyTable.event(keyCode: 124, shift: false, commandOrOption: true, character: "\u{F703}"))
  #expect(right == .arrow(axis: .horizontal, step: 1))
}

@Test func upAndDownArrowsAreVertical() throws {
  let up = try #require(
    KeyTable.event(keyCode: 126, shift: false, commandOrOption: true, character: "\u{F700}"))
  #expect(up == .arrow(axis: .vertical, step: -1))

  let down = try #require(
    KeyTable.event(keyCode: 125, shift: false, commandOrOption: true, character: "\u{F701}"))
  #expect(down == .arrow(axis: .vertical, step: 1))
}

// spec §9：`,` 是 keyCode 43。不加这条分支它就掉进 default → `.char(",")`，
// 把逗号塞进搜索框。裸 `,` 必须仍然是字符 —— 搜索窗口标题时打逗号是正常的。
@Test func commandCommaOpensSettingsInsteadOfTypingAComma() throws {
  let command = try #require(
    KeyTable.event(keyCode: 43, shift: false, commandOrOption: true, character: ","))
  #expect(command == .openSettings)
}

@Test func bareCommaStillTypesAComma() throws {
  // ⌘, 是开设置；**裸 , 必须还是往搜索框打逗号** —— 这条和上一条配对，
  // 防止未来把 43 无脑映射成 .openSettings（spec §11）。
  let comma = try #require(
    KeyTable.event(keyCode: 43, shift: false, commandOrOption: false, character: ","))
  #expect(comma == .char(","))
}

@Test func bareCommaIsStillTypedIntoTheQuery() throws {
  let bare = try #require(
    KeyTable.event(keyCode: 43, shift: false, commandOrOption: false, character: ","))
  #expect(bare == .char(","))
}
