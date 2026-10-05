import Foundation

/// Text Emote reads, paired with where each of its offsets falls in the app's own offset space,
/// the space `AXSelectedTextRange` and `AXBoundsForRange` speak.
public struct ProjectedText: Equatable, Sendable {
  public private(set) var text: String
  /// The app offset of each UTF-16 offset in `text`, including the end, so one longer than the text.
  public private(set) var sourceOffsets: [Int]

  public init(text: String, origin: Int = 0) {
    self.text = text
    self.sourceOffsets = Array(origin...(origin + text.utf16.count))
  }

  private init(units: [UInt16], sourceOffsets: [Int]) {
    self.text = String(decoding: units, as: UTF16.self)
    self.sourceOffsets = sourceOffsets
  }

  /// `layout` is the same content as `source` but with the line breaks the app draws.
  /// Chromium's text markers drop the break between paragraphs while `AXValue` keeps it,
  /// and the caret counts in marker space. Nil when the two differ in more than layout,
  /// as when `layout` is cut short.
  public static func aligning(_ source: String, onto layout: String) -> ProjectedText? {
    let marker = Array(source.utf16)
    let value = Array(layout.utf16)
    var offsets: [Int] = []
    offsets.reserveCapacity(value.count + 1)
    var i = 0
    var j = 0
    func layoutRun(_ units: [UInt16], from start: Int) -> Int {
      units[start...].prefix(while: isLayout).count
    }
    while i < marker.count || j < value.count {
      let extraBreak = j < value.count && isLayout(value[j])
        && (i >= marker.count || layoutRun(value, from: j) > layoutRun(marker, from: i))
      if !extraBreak, i < marker.count, j < value.count, marker[i] == value[j] {
        offsets.append(i)
        i += 1
        j += 1
      } else if j < value.count, isLayout(value[j]) {
        offsets.append(i)
        j += 1
      } else if i < marker.count, isLayout(marker[i]) || isInvisible(marker[i]) {
        i += 1
      } else {
        return nil
      }
    }
    offsets.append(marker.count)
    return ProjectedText(units: value, sourceOffsets: offsets)
  }

  /// Object replacement characters and zero-width spaces stand in for widgets and hidden markup.
  /// They read as part of a word or line, so they are dropped.
  public func removingInvisibles() -> ProjectedText {
    let units = Array(text.utf16)
    guard units.contains(where: Self.isInvisible) else { return self }
    var kept: [UInt16] = []
    var offsets: [Int] = []
    for (index, unit) in units.enumerated() where !Self.isInvisible(unit) {
      kept.append(unit)
      offsets.append(sourceOffsets[index])
    }
    offsets.append(sourceOffsets[units.count])
    return ProjectedText(units: kept, sourceOffsets: offsets)
  }

  /// An app range in `text` offsets. Several offsets can share one app offset where the app has
  /// no line break; an empty caret takes the first unless `afterBreak`, a selection hugs its content.
  public func local(_ range: Range<Int>, afterBreak: Bool = false) -> Range<Int> {
    if range.isEmpty {
      let caret = afterBreak ? last(atOrBefore: range.lowerBound) : first(atOrAfter: range.lowerBound)
      return caret..<caret
    }
    let lower = last(atOrBefore: range.lowerBound)
    let upper = max(lower, first(atOrAfter: range.upperBound))
    return lower..<upper
  }

  /// A range in `text` as the app counts it.
  public func source(_ range: Range<Int>) -> Range<Int> {
    let end = sourceOffsets.count - 1
    let lower = sourceOffsets[min(max(range.lowerBound, 0), end)]
    let upper = sourceOffsets[min(max(range.upperBound, 0), end)]
    return lower..<max(lower, upper)
  }

  private func first(atOrAfter offset: Int) -> Int {
    sourceOffsets.firstIndex { $0 >= offset } ?? sourceOffsets.count - 1
  }

  private func last(atOrBefore offset: Int) -> Int {
    sourceOffsets.lastIndex { $0 <= offset } ?? 0
  }

  private static func isLayout(_ unit: UInt16) -> Bool {
    switch unit {
    case 0x0A, 0x0D, 0x20, 0x09, 0xA0, 0x2028, 0x2029: return true
    default: return false
    }
  }

  private static func isInvisible(_ unit: UInt16) -> Bool {
    switch unit {
    case 0xFFFC, 0x200B, 0xFEFF, 0x2060: return true
    default: return false
    }
  }
}
