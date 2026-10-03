import EmoteGemma
import Foundation

@MainActor
final class GemmaModelStore: ObservableObject {
  static let shared = GemmaModelStore()

  @Published private(set) var fraction: Double = 0
  @Published private(set) var isDownloading = false
  @Published private(set) var isReady = false
  @Published private(set) var failure: String?
  @Published var confirmDownload = false

  private var task: Task<Void, Never>?
  private var session: URLSession?
  private var delegate: DownloadDelegate?

  private init() {
    refresh()
  }

  func refresh() {
    isReady = GemmaModelFiles.modelDirectory() != nil
    if isReady {
      fraction = 1
      failure = nil
    }
  }

  func startDownload() {
    guard !isDownloading else { return }
    failure = nil
    isDownloading = true
    fraction = 0
    task = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.downloadAll()
        self.refresh()
        self.isDownloading = false
      } catch is CancellationError {
        self.isDownloading = false
      } catch {
        self.failure = error.localizedDescription
        self.isDownloading = false
        self.refresh()
      }
    }
  }

  private func downloadAll() async throws {
    let destination = GemmaModelFiles.directory
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let files = GemmaModelFiles.files
    let total = files.reduce(Int64(0)) { $0 + $1.bytes }
    var finished: Int64 = 0
    for file in files {
      let target = destination.appendingPathComponent(file.name)
      if GemmaModelFiles.fileSize(target) >= file.bytes {
        finished += file.bytes
        fraction = Double(finished) / Double(total)
        continue
      }
      try await download(file: file, to: target, finished: finished, total: total)
      finished += file.bytes
      fraction = Double(finished) / Double(total)
    }
  }

  private func download(
    file: GemmaModelFiles.File,
    to target: URL,
    finished: Int64,
    total: Int64
  ) async throws {
    let url = URL(
      string: "https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit/resolve/main/\(file.name)"
    )!
    let delegate = DownloadDelegate { written in
      let fraction = Double(finished + written) / Double(max(total, 1))
      let clamped = min(max(fraction, 0), 1)
      Task { @MainActor in
        GemmaModelStore.shared.fraction = clamped
      }
    }
    self.delegate = delegate
    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    self.session = session
    defer {
      session.finishTasksAndInvalidate()
      self.session = nil
      self.delegate = nil
    }
    let (temporary, response) = try await session.download(from: url)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      throw URLError(.badServerResponse)
    }
    if FileManager.default.fileExists(atPath: target.path) {
      try FileManager.default.removeItem(at: target)
    }
    try FileManager.default.moveItem(at: temporary, to: target)
  }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let onWrite: @Sendable (Int64) -> Void

  init(onWrite: @escaping @Sendable (Int64) -> Void) {
    self.onWrite = onWrite
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    onWrite(totalBytesWritten)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
}
