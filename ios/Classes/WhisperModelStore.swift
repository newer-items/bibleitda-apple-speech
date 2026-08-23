import CryptoKit
import Foundation

enum WhisperModelStore {
  private static let modelName = "ggml-tiny.bin"
  private static let expectedSize: Int64 = 77_691_713
  private static let expectedSHA256 = "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
  private static let remoteURL = URL(
    string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
  )!
  private static let legacyModelNames = ["ggml-base.bin"]

  static func removeLegacyModelsAtStartup() {
    let fileManager = FileManager.default
    guard let applicationSupport = try? fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ) else {
      return
    }
    let directory = applicationSupport
      .appendingPathComponent("BibleitdaSpeech", isDirectory: true)
      .appendingPathComponent("Models", isDirectory: true)
    removeLegacyModels(in: directory) { _ in }
  }

  static func lightModelURL(
    diagnostic: @escaping (String) -> Void,
    progress: @escaping (Int64, Int64) -> Void
  ) async throws -> URL {
    let fileManager = FileManager.default
    let applicationSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = applicationSupport
      .appendingPathComponent("BibleitdaSpeech", isDirectory: true)
      .appendingPathComponent("Models", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    var mutableDirectory = directory
    try? mutableDirectory.setResourceValues(resourceValues)

    removeLegacyModels(in: directory, diagnostic: diagnostic)

    let modelURL = directory.appendingPathComponent(modelName)
    let markerURL = directory.appendingPathComponent("\(modelName).sha256")
    if try validateExistingModel(at: modelURL, markerURL: markerURL) {
      diagnostic("whisper_model_cache_hit:tiny")
      return modelURL
    }

    try? fileManager.removeItem(at: modelURL)
    try? fileManager.removeItem(at: markerURL)
    diagnostic("whisper_model_download_started:tiny:\(expectedSize)")
    progress(0, expectedSize)
    let temporaryURL = try await ModelDownloader.download(
      from: remoteURL,
      progress: progress
    )
    defer { try? fileManager.removeItem(at: temporaryURL) }

    let attributes = try fileManager.attributesOfItem(atPath: temporaryURL.path)
    let downloadedSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    guard downloadedSize == expectedSize else {
      throw ModelError.invalidSize(expected: expectedSize, actual: downloadedSize)
    }

    let checksum = try sha256(of: temporaryURL)
    guard checksum == expectedSHA256 else {
      throw ModelError.invalidChecksum
    }

    try fileManager.moveItem(at: temporaryURL, to: modelURL)
    try expectedSHA256.write(to: markerURL, atomically: true, encoding: .utf8)
    progress(expectedSize, expectedSize)
    diagnostic("whisper_model_download_finished:tiny")
    return modelURL
  }

  private static func removeLegacyModels(
    in directory: URL,
    diagnostic: @escaping (String) -> Void
  ) {
    let fileManager = FileManager.default
    for legacyName in legacyModelNames {
      let modelURL = directory.appendingPathComponent(legacyName)
      let markerURL = directory.appendingPathComponent("\(legacyName).sha256")
      let existed = fileManager.fileExists(atPath: modelURL.path) ||
        fileManager.fileExists(atPath: markerURL.path)
      try? fileManager.removeItem(at: modelURL)
      try? fileManager.removeItem(at: markerURL)
      if existed {
        diagnostic("whisper_legacy_model_removed:base")
      }
    }
  }

  private static func validateExistingModel(at modelURL: URL, markerURL: URL) throws -> Bool {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: modelURL.path) else {
      return false
    }
    let attributes = try fileManager.attributesOfItem(atPath: modelURL.path)
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    guard size == expectedSize else {
      return false
    }
    if let marker = try? String(contentsOf: markerURL, encoding: .utf8),
       marker.trimmingCharacters(in: .whitespacesAndNewlines) == expectedSHA256 {
      return true
    }
    guard try sha256(of: modelURL) == expectedSHA256 else {
      return false
    }
    try expectedSHA256.write(to: markerURL, atomically: true, encoding: .utf8)
    return true
  }

  private static func sha256(of url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hasher = SHA256()
    while true {
      let data = try file.read(upToCount: 1_048_576) ?? Data()
      if data.isEmpty {
        break
      }
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  enum ModelError: LocalizedError {
    case downloadFailed
    case missingDownload
    case invalidSize(expected: Int64, actual: Int64)
    case invalidChecksum

    var errorDescription: String? {
      switch self {
      case .downloadFailed:
        return "Whisper light model download failed."
      case .missingDownload:
        return "Whisper light model download did not create a file."
      case .invalidSize(let expected, let actual):
        return "Whisper light model size is invalid (expected \(expected), received \(actual))."
      case .invalidChecksum:
        return "Whisper light model checksum verification failed."
      }
    }
  }
}

private final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
  private let progress: (Int64, Int64) -> Void
  private var lastReportedPercent = -1
  private var continuation: CheckedContinuation<URL, Error>?
  private var retainedURL: URL?
  private var responseError: Error?
  private var session: URLSession?

  private init(progress: @escaping (Int64, Int64) -> Void) {
    self.progress = progress
  }

  static func download(
    from url: URL,
    progress: @escaping (Int64, Int64) -> Void
  ) async throws -> URL {
    let downloader = ModelDownloader(progress: progress)
    return try await downloader.start(url: url)
  }

  private func start(url: URL) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let configuration = URLSessionConfiguration.default
      configuration.waitsForConnectivity = true
      configuration.timeoutIntervalForRequest = 60
      configuration.timeoutIntervalForResource = 600
      let session = URLSession(
        configuration: configuration,
        delegate: self,
        delegateQueue: nil
      )
      self.session = session
      session.downloadTask(with: url).resume()
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    let total = totalBytesExpectedToWrite > 0
      ? totalBytesExpectedToWrite
      : downloadTask.response?.expectedContentLength ?? 0
    let percent = total > 0
      ? Int((Double(totalBytesWritten) / Double(total) * 100).rounded(.down))
      : 0
    guard percent != lastReportedPercent else {
      return
    }
    lastReportedPercent = percent
    progress(totalBytesWritten, total)
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    do {
      guard let response = downloadTask.response as? HTTPURLResponse,
            (200...299).contains(response.statusCode) else {
        throw WhisperModelStore.ModelError.downloadFailed
      }
      let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      try FileManager.default.moveItem(at: location, to: destination)
      retainedURL = destination
    } catch {
      responseError = error
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    defer {
      continuation = nil
      self.session?.finishTasksAndInvalidate()
      self.session = nil
    }
    if let error {
      continuation?.resume(throwing: error)
    } else if let responseError {
      continuation?.resume(throwing: responseError)
    } else if let retainedURL {
      continuation?.resume(returning: retainedURL)
    } else {
      continuation?.resume(throwing: WhisperModelStore.ModelError.missingDownload)
    }
  }
}
