import Foundation

public enum GemmaModelFiles {
  public static let expectedWeightBytes: Int64 = 5_146_800_534

  public struct File: Sendable {
    public var name: String
    public var bytes: Int64
  }

  public static let files = [
    File(name: "config.json", bytes: 6_628),
    File(name: "generation_config.json", bytes: 208),
    File(name: "chat_template.jinja", bytes: 17_336),
    File(name: "tokenizer_config.json", bytes: 2_740),
    File(name: "processor_config.json", bytes: 1_316),
    File(name: "model.safetensors.index.json", bytes: 240_961),
    File(name: "tokenizer.json", bytes: 32_169_626),
    File(name: "model.safetensors", bytes: expectedWeightBytes),
  ]

  public static var directory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Emote/Models/gemma-4-e4b-it-4bit", isDirectory: true)
  }

  public static func modelDirectory() -> URL? {
    if isComplete(directory) { return directory }
    return cachedSnapshot()
  }

  public static func isComplete(_ directory: URL) -> Bool {
    fileSize(directory.appendingPathComponent("model.safetensors")) >= expectedWeightBytes
      && fileSize(directory.appendingPathComponent("config.json")) > 0
      && fileSize(directory.appendingPathComponent("tokenizer.json")) > 0
  }

  public static func fileSize(_ url: URL) -> Int64 {
    let path = url.resolvingSymlinksInPath().path
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
  }

  private static func cachedSnapshot() -> URL? {
    let root = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        ".cache/huggingface/hub/models--mlx-community--gemma-4-e4b-it-4bit/snapshots"
      )
    guard
      let folders = try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
      )
    else { return nil }
    return folders.first { isComplete($0) }
  }
}
