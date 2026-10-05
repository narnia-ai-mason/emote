import ApplicationServices
import AppKit
import EmoteCore
import Foundation

@MainActor
enum FrontmostEditor {
  struct Snapshot: @unchecked Sendable {
    var element: AXUIElement
    /// The text and where its offsets fall in the element's `AXSelectedTextRange` space.
    var projection: ProjectedText
    var selectedUTF16: Range<Int>
    var caretScreenRect: CGRect?
    /// The next editable block's first line, when the field is a single block such as a Notion paragraph.
    var following: String?
    var application: NSRunningApplication?
    var caret: CaretDebug

    /// The caret is past the text the app shares, so `text` says nothing about the caret.
    var caretIsOutsideText: Bool { caret.basis == .truncated }
    var text: String { projection.text }
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

  /// The app a recommendation would act on, even when its text cannot be read.
  static func currentExternalApp() -> NSRunningApplication? {
    rememberExternalApp()
    if let app = NSWorkspace.shared.frontmostApplication,
      app.bundleIdentifier != Bundle.main.bundleIdentifier
    {
      return app
    }
    return lastExternalApp
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
    bounds(snapshot.element, utf16: snapshot.projection.source(focus.anchorUTF16))
      ?? snapshot.caretScreenRect
  }

  static func apply(emoji: String, to snapshot: Snapshot, focus: TextFocus) {
    if case .replace(let utf16) = focus.insertion, utf16 != snapshot.selectedUTF16 {
      _ = setSelectedRange(snapshot.element, snapshot.projection.source(utf16))
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
  guard let focused = copyElement(appElement, kAXFocusedUIElementAttribute) else {
    return nil
  }
  return snapshot(of: focused, application: app)
}

private struct TextSource {
  var element: AXUIElement
  var text: String
  /// False when `text` is only the selected string, so the element's range is not an index into it.
  var rangeIsInText: Bool
}

/// The field's text and selection read through text markers. Both come from the same walk of the
/// field's content, so the caret always indexes this text, whatever `AXValue` holds.
private struct MarkerDocument {
  var element: AXUIElement
  var text: String
  var selection: Range<Int>
  var selected: AXTextMarkerRange
  var start: AXTextMarker
  var end: AXTextMarker
}

private func snapshot(
  of focused: AXUIElement,
  application: NSRunningApplication?
) -> FrontmostEditor.Snapshot? {
  let source = textSource(from: focused)
  var hosts = [focused]
  if let source, !CFEqual(source.element, focused) {
    hosts.append(source.element)
  }
  for host in hosts {
    if let document = markerDocument(host),
      !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return markerSnapshot(document, application: application)
    }
  }

  guard let source else {
    return nil
  }
  let reported = selectedUTF16Range(source.element)
  let length = source.text.utf16.count
  if source.rangeIsInText, let reported, reported.upperBound > length, length > 0 {
    return beyondValueSnapshot(source, reported: reported, application: application)
  }

  let observation = observeCaret(
    element: source.element,
    text: source.text,
    reported: reported,
    rangeIsInText: source.rangeIsInText
  )
  let projection = ProjectedText(text: source.text).removingInvisibles()
  return FrontmostEditor.Snapshot(
    element: source.element,
    projection: projection,
    selectedUTF16: projection.local(observation.range),
    caretScreenRect: caretRect(source.element, utf16: observation.range, selected: nil),
    following: nil,
    application: application,
    caret: observation.debug
  )
}

private func markerSnapshot(
  _ document: MarkerDocument,
  application: NSRunningApplication?
) -> FrontmostEditor.Snapshot {
  let element = document.element
  let value = copyString(element, kAXValueAttribute)
  let projection = (value.flatMap { ProjectedText.aligning(document.text, onto: $0) }
    ?? ProjectedText(text: document.text)).removingInvisibles()
  var selection = projection.local(document.selection)
  if document.selection.isEmpty {
    let afterBreak = projection.local(document.selection, afterBreak: true)
    if afterBreak != selection, caretStartsItsBlock(document) {
      selection = afterBreak
    }
  }
  let debug = caretDebug(
    basis: .marker,
    element: element,
    text: projection.text,
    reported: selectedUTF16Range(element),
    resolved: selection,
    marker: document.selection.lowerBound,
    valueLength: value?.utf16.count
  )
  writeCaretDebug(debug)
  return FrontmostEditor.Snapshot(
    element: element,
    projection: projection,
    selectedUTF16: selection,
    caretScreenRect: caretRect(element, utf16: document.selection, selected: document.selected),
    following: projection.text.contains("\n") ? nil : followingBlock(after: document.end, in: element),
    application: application,
    caret: debug
  )
}

/// Chromium cuts `AXValue` at 10,000 UTF-8 bytes while the caret keeps counting the whole field.
/// Read the text around the caret directly. When the app won't give it, say the caret is out of reach.
private func beyondValueSnapshot(
  _ source: TextSource,
  reported: Range<Int>,
  application: NSRunningApplication?
) -> FrontmostEditor.Snapshot {
  let element = source.element
  if let window = textWindow(element, around: reported) {
    let debug = caretDebug(
      basis: .window,
      element: element,
      text: window.text,
      reported: reported,
      resolved: window.selection,
      valueLength: source.text.utf16.count
    )
    writeCaretDebug(debug)
    return FrontmostEditor.Snapshot(
      element: element,
      projection: ProjectedText(text: window.text, origin: window.origin),
      selectedUTF16: window.selection,
      caretScreenRect: caretRect(element, utf16: reported, selected: nil),
      following: nil,
      application: application,
      caret: debug
    )
  }

  let end = source.text.utf16.count
  let debug = caretDebug(
    basis: .truncated,
    element: element,
    text: source.text,
    reported: reported,
    resolved: end..<end
  )
  writeCaretDebug(debug)
  return FrontmostEditor.Snapshot(
    element: element,
    projection: ProjectedText(text: source.text),
    selectedUTF16: end..<end,
    caretScreenRect: caretRect(element, utf16: reported, selected: nil),
    following: nil,
    application: application,
    caret: debug
  )
}

private func textWindow(
  _ element: AXUIElement,
  around reported: Range<Int>
) -> (text: String, selection: Range<Int>, origin: Int)? {
  let start = max(0, reported.lowerBound - 2000)
  guard let before = stringForRange(element, start..<reported.lowerBound),
    before.utf16.count == reported.lowerBound - start,
    let inside = stringForRange(element, reported),
    inside.utf16.count == reported.count
  else { return nil }
  let after = [1000, 200, 20].lazy
    .compactMap { stringForRange(element, reported.upperBound..<(reported.upperBound + $0)) }
    .first ?? ""
  let lower = before.utf16.count
  return (before + inside + after, lower..<(lower + inside.utf16.count), start)
}

private func stringForRange(_ element: AXUIElement, _ range: Range<Int>) -> String? {
  guard range.lowerBound >= 0 else { return nil }
  if range.isEmpty { return "" }
  var cfRange = CFRange(location: range.lowerBound, length: range.count)
  guard let value = AXValueCreate(.cfRange, &cfRange) else { return nil }
  return copyParameterized(element, kAXStringForRangeParameterizedAttribute, value) as? String
}

private func textSource(from element: AXUIElement) -> TextSource? {
  var current: AXUIElement? = element
  for _ in 0..<6 {
    guard let node = current else {
      break
    }
    if let value = copyString(node, kAXValueAttribute),
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return TextSource(element: node, text: value, rangeIsInText: true)
    }
    if let selected = copyString(node, kAXSelectedTextAttribute),
      !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return TextSource(element: node, text: selected, rangeIsInText: false)
    }
    current = copyElement(node, kAXParentAttribute)
  }
  return nil
}

/// `AXStartTextMarker` is the start of the whole web page in Chromium, so the field's own marker range
/// bounds the text. The selection must split that text exactly, or it lies outside the field.
private func markerDocument(_ element: AXUIElement) -> MarkerDocument? {
  guard
    let whole = textMarkerRange(
      copyParameterized(element, kAXTextMarkerRangeForUIElementParameterizedAttribute, element)
    ),
    let selected = textMarkerRange(copyAttribute(element, kAXSelectedTextMarkerRangeAttribute))
  else { return nil }
  let start = AXTextMarkerRangeCopyStartMarker(whole)
  let end = AXTextMarkerRangeCopyEndMarker(whole)
  let caret = AXTextMarkerRangeCopyStartMarker(selected)
  let selectionEnd = AXTextMarkerRangeCopyEndMarker(selected)
  guard let text = markerString(element, from: start, to: end),
    let before = markerString(element, from: start, to: caret),
    let inside = markerString(element, from: caret, to: selectionEnd),
    let after = markerString(element, from: selectionEnd, to: end),
    before + inside + after == text
  else { return nil }
  let lower = before.utf16.count
  return MarkerDocument(
    element: element,
    text: text,
    selection: lower..<(lower + inside.utf16.count),
    selected: selected,
    start: start,
    end: end
  )
}

/// Where marker text has no break between two paragraphs, the end of one and the start of the next
/// share an offset. The caret's marker still belongs to one paragraph's own text element.
private func caretStartsItsBlock(_ document: MarkerDocument) -> Bool {
  let element = document.element
  let caret = AXTextMarkerRangeCopyStartMarker(document.selected)
  guard
    let leaf = copyParameterized(element, kAXUIElementForTextMarkerParameterizedAttribute, caret),
    CFGetTypeID(leaf) == AXUIElementGetTypeID(),
    let block = textMarkerRange(
      copyParameterized(element, kAXTextMarkerRangeForUIElementParameterizedAttribute, leaf)
    ),
    let before = markerString(element, from: document.start, to: AXTextMarkerRangeCopyStartMarker(block))
  else { return false }
  return before.utf16.count == document.selection.lowerBound
}

/// Block editors like Notion make each paragraph its own field. The next block is still reachable by
/// walking markers past this field's end, as long as it is editable text and not page chrome.
private func followingBlock(after end: AXTextMarker, in element: AXUIElement) -> String? {
  var marker = end
  for _ in 0..<4 {
    guard
      let next = textMarker(
        copyParameterized(element, kAXNextParagraphEndTextMarkerForTextMarkerParameterizedAttribute, marker)
      ),
      let leaf = copyParameterized(element, kAXUIElementForTextMarkerParameterizedAttribute, next),
      CFGetTypeID(leaf) == AXUIElementGetTypeID(),
      copyAttribute(leaf as! AXUIElement, "AXEditableAncestor") != nil,
      let text = markerString(element, from: end, to: next)
    else { return nil }
    let line = ProjectedText(text: text).removingInvisibles().text
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "•◦▪‣").union(.whitespaces)) }
      .first { $0.contains { $0.isLetter || $0.isNumber } }
    if let line {
      return line
    }
    marker = next
  }
  return nil
}

private func markerString(_ element: AXUIElement, from start: AXTextMarker, to end: AXTextMarker) -> String? {
  let range = AXTextMarkerRangeCreate(kCFAllocatorDefault, start, end)
  if let string = copyParameterized(element, kAXStringForTextMarkerRangeParameterizedAttribute, range)
    as? String
  {
    return string
  }
  return attributedString(range, element: element)
}

/// A one-line editor host publishes a page of text, while the reported caret is the column on the
/// visible line. Put that column on the visible line instead of using it as an index into the page.
private func observeCaret(
  element: AXUIElement,
  text: String,
  reported: Range<Int>?,
  rangeIsInText: Bool
) -> (range: Range<Int>, debug: CaretDebug) {
  let length = text.utf16.count
  let host = elementFrame(element)
  let visible = visibleCharacterRange(element)
  let lineNumber = insertionPointLineNumber(element)
  let fallback = clampedCaret(reported, length: length)
  let basis: CaretDebug.Basis
  let resolved: Range<Int>
  if !rangeIsInText {
    basis = .selection
    resolved = 0..<length
  } else if length == 0 || !fallback.isEmpty {
    basis = .reported
    resolved = fallback
  } else if let host,
    host.height > 0,
    host.height <= CaretReconciler.maxHostHeight,
    let visible,
    let offset = caretOnVisibleLine(
      column: fallback.lowerBound,
      visible: visible,
      text: text,
      length: length
    )
  {
    basis = .visibleLine
    resolved = offset..<offset
  } else if let host,
    host.height > 0,
    host.height <= CaretReconciler.maxHostHeight,
    let lineNumber,
    let line = CaretReconciler.lineRanges(in: text).indices.contains(lineNumber)
      ? CaretReconciler.lineRanges(in: text)[lineNumber]
      : nil,
    let offset = CaretReconciler.caretOffset(column: fallback.lowerBound, on: line, textLength: length)
  {
    basis = .lineNumber
    resolved = offset..<offset
  } else {
    basis = .reported
    resolved = fallback
  }
  let debug = caretDebug(
    basis: basis,
    element: element,
    text: text,
    reported: reported,
    resolved: resolved
  )
  writeCaretDebug(debug)
  return (resolved, debug)
}

private func caretDebug(
  basis: CaretDebug.Basis,
  element: AXUIElement,
  text: String,
  reported: Range<Int>?,
  resolved: Range<Int>,
  marker: Int? = nil,
  valueLength: Int? = nil
) -> CaretDebug {
  let visible = visibleCharacterRange(element)
  return CaretDebug(
    basis: basis,
    reported: reported?.lowerBound,
    reportedLength: reported.map(\.count),
    resolved: resolved.lowerBound,
    resolvedLength: resolved.count,
    marker: marker,
    valueLength: valueLength,
    visibleLocation: visible?.location,
    visibleLength: visible.map { max($0.length, 0) },
    line: insertionPointLineNumber(element),
    hostHeight: elementFrame(element).map { (Double($0.height) * 10).rounded() / 10 },
    textLength: text.utf16.count,
    head: String(text.prefix(120)).replacingOccurrences(of: "\n", with: "\\n"),
    around: snippet(text, around: resolved.lowerBound)
  )
}

private func writeCaretDebug(_ debug: CaretDebug) {
  let visible: String
  if let location = debug.visibleLocation, let length = debug.visibleLength {
    visible = "\(location)+\(length)"
  } else {
    visible = "nil"
  }
  let body = """
  basis=\(debug.basis.rawValue)
  reported=\(debug.reported.map(String.init) ?? "nil")
  reportedLength=\(debug.reportedLength.map(String.init) ?? "nil")
  resolved=\(debug.resolved)
  resolvedLength=\(debug.resolvedLength)
  marker=\(debug.marker.map(String.init) ?? "nil")
  valueLength=\(debug.valueLength.map(String.init) ?? "nil")
  visible=\(visible)
  line=\(debug.line.map(String.init) ?? "nil")
  hostHeight=\(debug.hostHeight.map { String(format: "%.1f", $0) } ?? "nil")
  textLength=\(debug.textLength)
  head=\(debug.head)
  around=\(debug.around)
  """
  let url = RecommendationHistory.defaultFileURL()
    .deletingLastPathComponent()
    .appendingPathComponent("caret-debug.txt")
  try? FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try? body.write(to: url, atomically: true, encoding: .utf8)
}

private func snippet(_ text: String, around offset: Int) -> String {
  let length = text.utf16.count
  let start = max(0, offset - 24)
  let end = min(length, offset + 24)
  return substring(text, start..<end).replacingOccurrences(of: "\n", with: "\\n")
}

private func caretOnVisibleLine(column: Int, visible: CFRange, text: String, length: Int) -> Int? {
  let lower = visible.location
  let upper = visible.location + max(visible.length, 0)
  guard lower >= 0, upper <= length, lower < upper else { return nil }
  guard !substring(text, lower..<upper).contains("\n") else { return nil }
  return CaretReconciler.caretOffset(column: column, on: lower..<upper, textLength: length)
}

private func clampedCaret(_ reported: Range<Int>?, length: Int) -> Range<Int> {
  guard let reported else { return length..<length }
  let lower = min(max(reported.lowerBound, 0), length)
  let upper = min(max(reported.upperBound, lower), length)
  return lower..<upper
}

private func attributedString(_ range: AXTextMarkerRange, element: AXUIElement) -> String? {
  let result = copyParameterized(
    element,
    kAXAttributedStringForTextMarkerRangeParameterizedAttribute,
    range
  )
  if let attributed = result as? NSAttributedString {
    return attributed.string
  }
  return result as? String
}

private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard result == .success else { return nil }
  return value
}

private func copyParameterized(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CFTypeRef? {
  var value: CFTypeRef?
  let result = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
  guard result == .success else { return nil }
  return value
}

private func textMarker(_ value: CFTypeRef?) -> AXTextMarker? {
  guard let value, CFGetTypeID(value) == AXTextMarkerGetTypeID() else { return nil }
  return (value as! AXTextMarker)
}

private func textMarkerRange(_ value: CFTypeRef?) -> AXTextMarkerRange? {
  guard let value, CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else { return nil }
  return (value as! AXTextMarkerRange)
}

private func visibleCharacterRange(_ element: AXUIElement) -> CFRange? {
  cfRangeAttribute(element, kAXVisibleCharacterRangeAttribute)
}

private func insertionPointLineNumber(_ element: AXUIElement) -> Int? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(
    element,
    kAXInsertionPointLineNumberAttribute as CFString,
    &value
  )
  guard result == .success, let number = value as? NSNumber else { return nil }
  let line = number.intValue
  return line >= 0 ? line : nil
}

private func cfRangeAttribute(_ element: AXUIElement, _ attribute: String) -> CFRange? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
  guard result == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
    return nil
  }
  var range = CFRange()
  guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0 else {
    return nil
  }
  return range
}

private func substring(_ text: String, _ range: Range<Int>) -> String {
  let view = text.utf16
  guard
    let start = view.index(view.startIndex, offsetBy: range.lowerBound, limitedBy: view.endIndex),
    let end = view.index(view.startIndex, offsetBy: range.upperBound, limitedBy: view.endIndex),
    let string = String(view[start..<end])
  else { return "" }
  return string
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

/// The caret on screen, from the most precise signal the app answers with a believable rectangle:
/// the character range, the text markers, the paragraph holding the caret, then the field itself.
private func caretRect(_ element: AXUIElement, utf16 range: Range<Int>, selected: AXTextMarkerRange?) -> CGRect? {
  if let rect = bounds(element, utf16: range) {
    return rect
  }
  let field = axFrame(element)
  if let selected {
    if let rect = markerCaretRect(element, selected: selected, field: field) {
      return cocoaRect(fromAX: rect)
    }
    if let rect = caretBlockRect(element, selected: selected, field: field) {
      return cocoaRect(fromAX: rect)
    }
  }
  return fieldCaret(element)
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

  let field = axFrame(element)
  for attempt in attempts {
    if let rect = axBounds(element, attempt), CaretReconciler.isPlausibleCaret(rect, in: field) {
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
  return axRect(copyParameterized(element, kAXBoundsForRangeParameterizedAttribute, rangeValue))
}

private func markerCaretRect(_ element: AXUIElement, selected: AXTextMarkerRange, field: CGRect?) -> CGRect? {
  let caret = AXTextMarkerRangeCopyStartMarker(selected)
  var ranges = [selected]
  if let next = textMarker(copyParameterized(element, kAXNextTextMarkerForTextMarkerParameterizedAttribute, caret)) {
    ranges.append(AXTextMarkerRangeCreate(kCFAllocatorDefault, caret, next))
  }
  if let previous = textMarker(
    copyParameterized(element, kAXPreviousTextMarkerForTextMarkerParameterizedAttribute, caret)
  ) {
    ranges.append(AXTextMarkerRangeCreate(kCFAllocatorDefault, previous, caret))
  }
  for range in ranges {
    if let rect = axRect(copyParameterized(element, kAXBoundsForTextMarkerRangeParameterizedAttribute, range)),
      CaretReconciler.isPlausibleCaret(rect, in: field)
    {
      return rect
    }
  }
  return nil
}

/// Chrome often answers every text-bounds query with an empty rectangle, but the paragraph element
/// holding the caret still has a real frame inside the field.
private func caretBlockRect(_ element: AXUIElement, selected: AXTextMarkerRange, field: CGRect?) -> CGRect? {
  let caret = AXTextMarkerRangeCopyStartMarker(selected)
  guard let leaf = copyParameterized(element, kAXUIElementForTextMarkerParameterizedAttribute, caret),
    CFGetTypeID(leaf) == AXUIElementGetTypeID(),
    let rect = axFrame(leaf as! AXUIElement),
    rect.height > 0,
    rect.height < (field?.height ?? .infinity),
    CaretReconciler.isPlausibleCaret(rect, in: field, maxHeight: .infinity)
  else { return nil }
  return rect
}

private func axRect(_ value: CFTypeRef?) -> CGRect? {
  guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
    return nil
  }
  var rect = CGRect.zero
  guard AXValueGetValue(value as! AXValue, .cgRect, &rect), !rect.isNull else {
    return nil
  }
  return rect
}

/// Without any caret rectangle, stay on the field: a compact field gets its left edge, a tall one
/// its first visible line, rather than the middle of the screen.
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
  guard let frame = elementFrame(element) else { return nil }
  let onScreen = NSScreen.screens.map(\.frame).first { $0.intersects(frame) }.map { frame.intersection($0) } ?? frame
  return CGRect(x: onScreen.minX + 8, y: onScreen.maxY - 18, width: 2, height: 18)
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
  axFrame(element).map(cocoaRect(fromAX:))
}

/// The element's frame in Accessibility's top-left-origin coordinates.
private func axFrame(_ element: AXUIElement) -> CGRect? {
  guard let origin = axPoint(element, kAXPositionAttribute),
    let size = axSize(element, kAXSizeAttribute),
    size.width > 0,
    size.height > 0
  else {
    return nil
  }
  return CGRect(origin: origin, size: size)
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
