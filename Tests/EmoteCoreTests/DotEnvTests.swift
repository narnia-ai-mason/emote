import EmoteCore
import XCTest

final class DotEnvTests: XCTestCase {
  func testParsesExportPrefixCommentsAndQuotes() {
    let values = DotEnv.parse(
      """
      # comment
      export OPENROUTER_API_KEY="sk-test"
      OPENROUTER_MODEL='google/gemma-4-31b-it:free'

      EMPTY=
      """
    )

    XCTAssertEqual(values["OPENROUTER_API_KEY"], "sk-test")
    XCTAssertEqual(values["OPENROUTER_MODEL"], "google/gemma-4-31b-it:free")
    XCTAssertEqual(values["EMPTY"], "")
  }

  func testProcessEnvironmentOverridesFileValues() {
    let values = DotEnv.load(
      process: ["OPENROUTER_API_KEY": "from-process"],
      workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
    )

    XCTAssertEqual(values["OPENROUTER_API_KEY"], "from-process")
  }
}
