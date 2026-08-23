import CryptoKit
import Foundation

enum WhisperModelStore {
  private static let modelName = "ggml-base.bin"
  private static let expectedSize: Int64 = 147_951_465
  private static let expectedSHA256 = "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
  private static let remoteURL = URL(
    string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
  )!

  static func baseModelURL(diagnostic: @escaping (String) -> Void) async throws -> URL {
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

    let modelURL = directory.appendingPathComponent(modelName)
    let markerURL = directory.appendingPathComponent("\(modelName).sha256")
    if try validateExistingModel(at: modelURL, markerURL: markerURL) {
      diagnostic("whisper_model_cache_hit:base")
      return modelURL
    }

    try? fileManager.removeItem(at: modelURL)
    try? fileManager.removeItem(at: markerURL)
    diagnostic("whisper_model_download_started:base:147951465")
    let temporaryURL = try await download(from: remoteURL)
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
    diagnostic("whisper_model_download_finished:base")
    return modelURL
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

  private static func download(from url: URL) async throws -> URL {
    if #available(iOS 15.0, *) {
      let (temporaryURL, response) = try await URLSession.shared.download(from: url)
      try validate(response: response)
      return temporaryURL
    }
    return try await withCheckedThrowingContinuation { continuation in
      let task = URLSession.shared.downloadTask(with: url) { temporaryURL, response, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        do {
          if let response {
            try validate(response: response)
          }
          guard let temporaryURL else {
            throw ModelError.missingDownload
          }
          let retainedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
          try FileManager.default.moveItem(at: temporaryURL, to: retainedURL)
          continuation.resume(returning: retainedURL)
        } catch {
          continuation.resume(throwing: error)
        }
      }
      task.resume()
    }
  }

  private static func validate(response: URLResponse) throws {
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
      throw ModelError.downloadFailed
    }
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
        return "Whisper base model download failed."
      case .missingDownload:
        return "Whisper base model download did not create a file."
      case .invalidSize(let expected, let actual):
        return "Whisper base model size is invalid (expected \(expected), received \(actual))."
      case .invalidChecksum:
        return "Whisper base model checksum verification failed."
      }
    }
  }
}
