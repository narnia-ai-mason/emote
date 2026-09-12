import Foundation

enum ResourceFile {
  static func url(name: String, extension fileExtension: String) -> URL? {
    let fileName = "\(name).\(fileExtension)"
    let candidates = [
      Bundle.main.resourceURL?
        .appendingPathComponent("Emote_EmoteCore.bundle")
        .appendingPathComponent(fileName),
      Bundle.main.bundleURL
        .appendingPathComponent("Emote_EmoteCore.bundle")
        .appendingPathComponent(fileName),
      Bundle.main.url(forResource: name, withExtension: fileExtension),
      Bundle.module.url(forResource: name, withExtension: fileExtension),
    ]
    return candidates.compactMap { $0 }.first {
      FileManager.default.isReadableFile(atPath: $0.path)
    }
  }
}
