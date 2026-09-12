import ApplicationServices
import AppKit
import EmoteCore
import Foundation

@MainActor
enum FrontmostEditor {
  struct Snapshot: @unchecked Sendable {
    var element: AXUIElement
    var text: String
    var selectedUTF16: Range<Int>
    var caretScreenRect: CGRect?
    var application: NSRunningApplication?
  }

  private static var lastExternalApp: NSRunningApplication?
  private static var memoryTimer: Timer?

  static func startRemembering() {
    guard memoryTimer == nil else {
      return
    }
    rememberExternalApp()
    memoryTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
      Task { @MainActor in
        rememberExternalApp()
      }
    }
  }

  static func rememberExternalApp() {
    guard let app = NSWorkspace.shared.frontmostApplication,
      app.bundleIdentifier != Bundle.main.bundleIdentifier
    else {
      return
    }
    lastExternalApp = app
  }

  static func read() -> Snapshot? {
    rememberExternalApp()
    var seen = Set<pid_t>()
    let apps = [NSWorkspace.shared.frontmostApplication, lastExternalApp]
      .compactMap { $0 }
      .filter { app in
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else {
          return false
        }
        return seen.insert(app.processIdentifier).inserted
      }

    for app in apps {
      if let snapshot = readSnapshot(from: app) {
        return snapshot
      }
    }
    return nil
  }

  static func anchorRect(in snapshot: Snapshot, focus: TextFocus) -> CGRect? {
    bounds(snapshot.element, utf16: focus.anchorUTF16)
      ?? snapshot.caretScreenRect
      ?? fieldCaret(snapshot.element)
  }

  static func apply(emoji: String, to snapshot: Snapshot, focus: TextFocus) {
    if case .replace(let utf16) = focus.insertion {
      _ = setSelectedRange(snapshot.element, utf16)
    }
    type(emoji)
  }

  static func ensureTrusted() -> Bool {
    AXIsProcessTrustedWithOptions(
      ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    )
  }
}

private func readSnapshot(from app: NSRunningApplication) -> FrontmostEditor.Snapshot? {
  let appElement = AXUIElementCreateApplication(app.processIdentifier)
  guard let element = copyElement(appElement, kAXFocusedUIElementAttribute) else {
    return nil
  }
  return snapshot(of: element, application: app)
}

private func snapshot(
  of element: AXUIElement,
  application: NSRunningApplication?
) -> FrontmostEditor.Snapshot? {
  var text = readText(from: element)
  var selected = selectedUTF16Range(element)

  if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
    let selectedText = copyString(element, kAXSelectedTextAttribute),
    !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  {
    text = selectedText
    selected = 0..<selectedText.utf16.count
  }

  guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    return nil
  }

  let selectedUTF16 = selected ?? utf16Cursor(in: text)
  return FrontmostEditor.Snapshot(
    element: element,
    text: text,
    selectedUTF16: selectedUTF16,
    caretScreenRect: bounds(element, utf16: selectedUTF16) ?? fieldCaret(element),
    application: application
  )
}

private func readText(from element: AXUIElement) -> String {
  var current: AXUIElement? = element
  for _ in 0..<6 {
    guard let node = current else {
      break
    }
    if let value = copyString(node, kAXValueAttribute),
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return value
    }
    if let selected = copyString(node, kAXSelectedTextAttribute),
      !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return selected
    }
    current = copyElement(node, kAXParentAttribute)
  }
  return ""
}

private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard result == .success else {
    return nil
  }
  return (value as! AXUIElement)
}

private func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard result == .success else {
    return nil
  }
  return value as? String
}

private func selectedUTF16Range(_ element: AXUIElement) -> Range<Int>? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(
    element,
    kAXSelectedTextRangeAttribute as CFString,
    &value
  )
  guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
    return nil
  }
  var range = CFRange()
  guard AXValueGetValue(axValue as! AXValue, .cfRange, &range), range.location >= 0 else {
    return nil
  }
  let location = range.location
  let length = max(range.length, 0)
  return location..<(location + length)
}

private func utf16Cursor(in text: String) -> Range<Int> {
  let end = text.utf16.count
  return end..<end
}

private func bounds(_ element: AXUIElement, utf16 range: Range<Int>) -> CGRect? {
  var attempts: [CFRange] = []
  if range.count > 0 {
    attempts.append(CFRange(location: range.lowerBound, length: range.count))
  }
  attempts.append(CFRange(location: range.lowerBound, length: 1))
  if range.lowerBound > 0 {
    attempts.append(CFRange(location: range.lowerBound - 1, length: 1))
  }

  for attempt in attempts {
    if let rect = axBounds(element, attempt) {
      return cocoaRect(fromAX: rect)
    }
  }
  return nil
}

private func axBounds(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
  var cfRange = range
  guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
    return nil
  }
  var value: CFTypeRef?
  let result = AXUIElementCopyParameterizedAttributeValue(
    element,
    kAXBoundsForRangeParameterizedAttribute as CFString,
    rangeValue,
    &value
  )
  guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
    return nil
  }
  var rect = CGRect.zero
  guard AXValueGetValue(axValue as! AXValue, .cgRect, &rect), !rect.isNull, rect.height > 0 else {
    return nil
  }
  return rect
}

private func fieldCaret(_ element: AXUIElement) -> CGRect? {
  if let frame = compactFrame(element) {
    return caretInField(frame)
  }
  var current: AXUIElement? = element
  for _ in 0..<5 {
    guard let node = current else {
      break
    }
    if let child = focusedChild(node), let frame = compactFrame(child) {
      return caretInField(frame)
    }
    current = copyElement(node, kAXParentAttribute)
  }
  return nil
}

private func focusedChild(_ element: AXUIElement) -> AXUIElement? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(
    element,
    kAXFocusedUIElementAttribute as CFString,
    &value
  )
  guard result == .success else {
    return nil
  }
  return value.map { $0 as! AXUIElement }
}

private func compactFrame(_ element: AXUIElement) -> CGRect? {
  guard let frame = elementFrame(element), frame.height > 0, frame.height <= 180 else {
    return nil
  }
  return frame
}

private func caretInField(_ frame: CGRect) -> CGRect {
  CGRect(
    x: frame.minX + 8,
    y: frame.minY,
    width: 2,
    height: min(18, max(frame.height, 12))
  )
}

private func elementFrame(_ element: AXUIElement) -> CGRect? {
  guard let origin = axPoint(element, kAXPositionAttribute),
    let size = axSize(element, kAXSizeAttribute),
    size.width > 0,
    size.height > 0
  else {
    return nil
  }
  return cocoaRect(fromAX: CGRect(origin: origin, size: size))
}

private func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
    return nil
  }
  var point = CGPoint.zero
  guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else {
    return nil
  }
  return point
}

private func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
    return nil
  }
  var size = CGSize.zero
  guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else {
    return nil
  }
  return size
}

private func cocoaRect(fromAX rect: CGRect) -> CGRect {
  let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
  let primaryMaxY = primary?.frame.maxY ?? 0
  return HUDPlacement.cocoaRect(fromAX: rect, primaryMaxY: primaryMaxY)
}

private func setSelectedRange(_ element: AXUIElement, _ range: Range<Int>) -> Bool {
  var cfRange = CFRange(location: range.lowerBound, length: range.count)
  guard let value = AXValueCreate(.cfRange, &cfRange) else {
    return false
  }
  return AXUIElementSetAttributeValue(
    element,
    kAXSelectedTextRangeAttribute as CFString,
    value
  ) == .success
}

private func type(_ text: String) {
  let units = Array(text.utf16)
  guard !units.isEmpty else {
    return
  }
  let source = CGEventSource(stateID: .hidSystemState)
  units.withUnsafeBufferPointer { buffer in
    guard let base = buffer.baseAddress else {
      return
    }
    let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
    up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
  }
}
