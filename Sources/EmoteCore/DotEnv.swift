import Foundation

public enum DotEnv {
  public static func load(
    process: [String: String] = ProcessInfo.processInfo.environment,
    workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    fileManager: FileManager = .default
  ) -> [String: String] {
    var merged = parse(contentsOfNearestFile(startingAt: workingDirectory, fileManager: fileManager))
    for (key, value) in process {
      merged[key] = value
    }
    return merged
  }

  public static func parse(_ contents: String?) -> [String: String] {
    guard let contents else {
      return [:]
    }

    var values: [String: String] = [:]
    for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
      var line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix("#") {
        continue
      }
      if line.hasPrefix("export ") {
        line = String(line.dropFirst("export ".count))
          .trimmingCharacters(in: .whitespaces)
      }
      guard let separator = line.firstIndex(of: "=") else {
        continue
      }

      let key = line[..<separator].trimmingCharacters(in: .whitespaces)
      guard !key.isEmpty else {
        continue
      }
      values[String(key)] = unquote(
        String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
      )
    }
    return values
  }

  private static func contentsOfNearestFile(
    startingAt directory: URL,
    fileManager: FileManager
  ) -> String? {
    var current = directory.standardizedFileURL
    while true {
      let candidate = current.appendingPathComponent(".env")
      if fileManager.isReadableFile(atPath: candidate.path),
        let contents = try? String(contentsOf: candidate, encoding: .utf8)
      {
        return contents
      }

      let parent = current.deletingLastPathComponent()
      if parent.path == current.path {
        return nil
      }
      current = parent
    }
  }

  private static func unquote(_ value: String) -> String {
    if value.count >= 2 {
      if value.hasPrefix("\"") && value.hasSuffix("\"") {
        return String(value.dropFirst().dropLast())
      }
      if value.hasPrefix("'") && value.hasSuffix("'") {
        return String(value.dropFirst().dropLast())
      }
    }
    return value
  }
}
