import Foundation

public struct RecommendationRecord: Codable, Equatable, Sendable {
  public var time: Date
  public var mode: WritingSituation.Mode?
  public var message: String?
  public var recommendations: [String]
  public var outcome: Outcome
  public var selected: String?
  public var selectedIndex: Int?
  public var appName: String?
  public var appBundleIdentifier: String?
  /// The HUD text shown for a failed attempt.
  public var notice: String?
  /// The underlying error when it says more than `notice`.
  public var errorDetail: String?
  /// Accessibility signals used to place the caret, kept with the attempt that observed them.
  public var caret: CaretDebug?

  public enum Outcome: String, Codable, Equatable, Sendable {
    case selected
    case cancelled
    case failed
  }

  public init(
    time: Date = Date(),
    mode: WritingSituation.Mode? = nil,
    message: String? = nil,
    recommendations: [String],
    outcome: Outcome,
    selected: String? = nil,
    selectedIndex: Int? = nil,
    appName: String? = nil,
    appBundleIdentifier: String? = nil,
    notice: String? = nil,
    errorDetail: String? = nil,
    caret: CaretDebug? = nil
  ) {
    self.time = time
    self.mode = mode
    self.message = message
    self.recommendations = recommendations
    self.outcome = outcome
    self.selected = selected
    self.selectedIndex = selectedIndex
    self.appName = appName
    self.appBundleIdentifier = appBundleIdentifier
    self.notice = notice
    self.errorDetail = errorDetail
    self.caret = caret
  }
}

/// What Accessibility reported about the caret, and which of those signals the app trusted.
public struct CaretDebug: Codable, Equatable, Sendable {
  public var basis: Basis
  /// `AXSelectedTextRange` location. Often a column on the visible line, not an index into the field.
  public var reported: Int?
  public var reportedLength: Int?
  public var resolved: Int
  public var resolvedLength: Int
  /// Caret from the selected text marker, counted in the field's text-marker string.
  public var marker: Int?
  /// `AXValue` length when the text came from text markers. Chromium's value can disagree with its caret.
  public var valueLength: Int?
  public var visibleLocation: Int?
  public var visibleLength: Int?
  public var line: Int?
  public var hostHeight: Double?
  public var textLength: Int
  public var head: String
  public var around: String

  public enum Basis: String, Codable, Equatable, Sendable {
    case reported
    case marker
    case visibleLine
    case lineNumber
    case selection
    /// The caret lies past the text the app shares, as when Chromium cuts `AXValue` at 10,000 UTF-8 bytes.
    case truncated
    /// Text read around a caret that lies past `AXValue`, through `AXStringForRange`.
    case window
    /// A terminal's Neovim buffer and cursor, read over Neovim's RPC socket.
    case neovim
  }

  public init(
    basis: Basis,
    reported: Int? = nil,
    reportedLength: Int? = nil,
    resolved: Int,
    resolvedLength: Int,
    marker: Int? = nil,
    valueLength: Int? = nil,
    visibleLocation: Int? = nil,
    visibleLength: Int? = nil,
    line: Int? = nil,
    hostHeight: Double? = nil,
    textLength: Int,
    head: String,
    around: String
  ) {
    self.basis = basis
    self.reported = reported
    self.reportedLength = reportedLength
    self.resolved = resolved
    self.resolvedLength = resolvedLength
    self.marker = marker
    self.valueLength = valueLength
    self.visibleLocation = visibleLocation
    self.visibleLength = visibleLength
    self.line = line
    self.hostHeight = hostHeight
    self.textLength = textLength
    self.head = head
    self.around = around
  }
}

public enum RecommendationHistory {
  private static let queue = DispatchQueue(label: "com.minsikseo.emote.recommendation-history")

  public static func defaultFileURL() -> URL {
    let root =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      .appendingPathComponent("Library/Application Support", isDirectory: true)
    return root.appendingPathComponent("Emote/recommendation-history.jsonl")
  }

  public static func append(_ record: RecommendationRecord, to fileURL: URL) throws {
    try queue.sync {
      try write(record, to: fileURL)
    }
  }

  public static func load(from fileURL: URL) throws -> [RecommendationRecord] {
    let text = try String(contentsOf: fileURL, encoding: .utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var records: [RecommendationRecord] = []
    for line in text.split(whereSeparator: \.isNewline) {
      records.append(try decoder.decode(RecommendationRecord.self, from: Data(line.utf8)))
    }
    return records
  }

  private static func write(_ record: RecommendationRecord, to fileURL: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(record)
    data.append(0x0A)
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: fileURL.path) {
      let handle = try FileHandle(forWritingTo: fileURL)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
    } else {
      try data.write(to: fileURL, options: .atomic)
    }
  }
}
