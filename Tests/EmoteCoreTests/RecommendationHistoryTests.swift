import EmoteCore
import XCTest

final class RecommendationHistoryTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("emote-history-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDownWithError() throws {
    if let directory {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  func testSelectedAndCancelledRecordsRoundTripInOrder() throws {
    let file = directory.appendingPathComponent("recommendation-history.jsonl")
    let message = """
      <sentence>오늘 퇴근길에 갑자기 비가 쏟아져서 신발까지 다 젖었어.</sentence>
      <tone>neutral</tone>
      """
    let selected = RecommendationRecord(
      time: Date(timeIntervalSince1970: 1_700_000_000),
      mode: .sentence,
      message: message,
      recommendations: ["🌧️", "👟", "😅"],
      outcome: .selected,
      selected: "👟",
      selectedIndex: 1
    )
    let cancelled = RecommendationRecord(
      time: Date(timeIntervalSince1970: 1_700_000_060),
      mode: .heading,
      message: """
        <heading>이직 준비</heading>
        <next-sentence>다음 주 면접이 세 개다.</next-sentence>
        <tone>dry</tone>
        """,
      recommendations: ["💼", "📝"],
      outcome: .cancelled
    )

    try RecommendationHistory.append(selected, to: file)
    try RecommendationHistory.append(cancelled, to: file)
    let loaded = try RecommendationHistory.load(from: file)

    XCTAssertEqual(loaded, [selected, cancelled])
    XCTAssertEqual(loaded[0].message, message as String?)
    XCTAssertNil(loaded[0].appName)
    XCTAssertNil(loaded[1].selected)
    XCTAssertNil(loaded[1].selectedIndex)
    XCTAssertNil(loaded[1].notice)
  }

  func testFailedRecordKeepsAppAndErrorText() throws {
    let file = directory.appendingPathComponent("recommendation-history.jsonl")
    let failed = RecommendationRecord(
      time: Date(timeIntervalSince1970: 1_700_000_120),
      mode: .sentence,
      message: "<sentence>오늘 회의 망했다.</sentence>",
      recommendations: [],
      outcome: .failed,
      appName: "Slack",
      appBundleIdentifier: "com.tinyspeck.slackmacgap",
      notice: "The model took too long",
      errorDetail: "The request timed out."
    )

    try RecommendationHistory.append(failed, to: file)
    let loaded = try RecommendationHistory.load(from: file)

    XCTAssertEqual(loaded, [failed])
  }

  func testDecodesRecordsWrittenBeforeAppAndFailureFields() throws {
    let file = directory.appendingPathComponent("recommendation-history.jsonl")
    let line = """
      {"message":"<sentence>hi</sentence>","mode":"word","outcome":"selected","recommendations":["✨"],"selected":"✨","selectedIndex":0,"time":"2023-11-14T22:13:20Z"}
      """
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(line.utf8).write(to: file)

    let loaded = try RecommendationHistory.load(from: file)

    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(loaded[0].mode, .word)
    XCTAssertEqual(loaded[0].outcome, .selected)
    XCTAssertEqual(loaded[0].selected, "✨")
    XCTAssertNil(loaded[0].appName)
    XCTAssertNil(loaded[0].appBundleIdentifier)
    XCTAssertNil(loaded[0].notice)
    XCTAssertNil(loaded[0].errorDetail)
    XCTAssertNil(loaded[0].caret)
  }

  func testCaretDebugRoundTripsWithTheAttempt() throws {
    let file = directory.appendingPathComponent("recommendation-history.jsonl")
    let caret = CaretDebug(
      basis: .marker,
      reported: 4,
      reportedLength: 0,
      resolved: 86,
      resolvedLength: 0,
      marker: 86,
      visibleLocation: 70,
      visibleLength: 40,
      line: 2,
      hostHeight: 22,
      textLength: 400,
      head: "첫째 줄\\n둘째 줄",
      around: "보이는 줄에서|캐럿"
    )
    let record = RecommendationRecord(
      time: Date(timeIntervalSince1970: 1_700_000_180),
      mode: .sentence,
      message: "<sentence>보이는 줄에서</sentence>",
      recommendations: ["👀"],
      outcome: .cancelled,
      appName: "Code",
      appBundleIdentifier: "com.microsoft.VSCode",
      caret: caret
    )

    try RecommendationHistory.append(record, to: file)
    let loaded = try RecommendationHistory.load(from: file)

    XCTAssertEqual(loaded, [record])
    XCTAssertEqual(loaded[0].caret?.basis, .marker)
    XCTAssertEqual(loaded[0].caret?.resolved, 86)
  }

  func testDefaultFileLivesInApplicationSupport() {
    let url = RecommendationHistory.defaultFileURL()
    XCTAssertEqual(url.lastPathComponent, "recommendation-history.jsonl")
    XCTAssertTrue(url.path.contains("Application Support/Emote/"))
  }
}
