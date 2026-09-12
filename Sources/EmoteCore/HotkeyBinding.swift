import Carbon.HIToolbox
import Foundation

public struct HotkeyBinding: Codable, Equatable, Sendable {
  public var keyCode: UInt16
  public var modifiers: Modifiers

  public struct Modifiers: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)
  }

  public static let `default` = HotkeyBinding(
    keyCode: UInt16(kVK_ANSI_E),
    modifiers: [.control, .command]
  )

  public init(keyCode: UInt16, modifiers: Modifiers) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  public var hasRequiredModifiers: Bool {
    modifiers.contains(.control)
      || modifiers.contains(.option)
      || modifiers.contains(.command)
      || modifiers.contains(.function)
  }

  public var usesEventTap: Bool {
    modifiers.contains(.function) || Int(keyCode) == kVK_Function
  }

  public var isFunctionKeyOnly: Bool {
    Int(keyCode) == kVK_Function && modifiers == [.function]
  }

  public var carbonModifiers: UInt32 {
    var value: UInt32 = 0
    if modifiers.contains(.control) { value |= UInt32(controlKey) }
    if modifiers.contains(.option) { value |= UInt32(optionKey) }
    if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
    if modifiers.contains(.command) { value |= UInt32(cmdKey) }
    return value
  }

  public var displayName: String {
    var parts: [String] = []
    if modifiers.contains(.function) { parts.append("fn") }
    if modifiers.contains(.control) { parts.append("⌃") }
    if modifiers.contains(.option) { parts.append("⌥") }
    if modifiers.contains(.shift) { parts.append("⇧") }
    if modifiers.contains(.command) { parts.append("⌘") }
    if Int(keyCode) != kVK_Function {
      parts.append(keyName)
    } else if parts.isEmpty {
      parts.append("fn")
    }
    return parts.joined()
  }

  public var layoutCharacter: String? {
    Self.glyph(for: keyCode)
  }

  public var keyName: String {
    switch Int(keyCode) {
    case kVK_Space: return "Space"
    case kVK_Return, kVK_ANSI_KeypadEnter: return "Return"
    case kVK_Tab: return "Tab"
    case kVK_Escape: return "Esc"
    case kVK_Delete: return "Delete"
    case kVK_ForwardDelete: return "Fwd Delete"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    default:
      return Self.glyph(for: keyCode) ?? "Key \(keyCode)"
    }
  }

  private static func glyph(for keyCode: UInt16) -> String? {
    let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
      return nil
    }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    return data.withUnsafeBytes { pointer -> String? in
      guard let layout = pointer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
        return nil
      }
      var deadKeyState: UInt32 = 0
      var chars: [UniChar] = Array(repeating: 0, count: 4)
      var length = 0
      let status = UCKeyTranslate(
        layout,
        keyCode,
        UInt16(kUCKeyActionDisplay),
        0,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        chars.count,
        &length,
        &chars
      )
      guard status == noErr, length > 0 else {
        return nil
      }
      return String(utf16CodeUnits: chars, count: length).uppercased()
    }
  }
}
