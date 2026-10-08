import Foundation

struct WhisperTranscription: Sendable {
  let text: String
  let processingMilliseconds: Int
}

@_silgen_name("wf_context_create")
private func wf_context_create(
  _ modelPath: UnsafePointer<CChar>?,
  _ useGPU: Int32,
  _ flashAttention: Int32,
  _ useDTW: Int32,
  _ dtwModel: Int32
) -> UnsafeMutableRawPointer?

@_silgen_name("wf_context_free")
private func wf_context_free(_ context: UnsafeMutableRawPointer?)

@_silgen_name("wf_job_create")
private func wf_job_create(_ strategy: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("wf_job_free")
private func wf_job_free(_ job: UnsafeMutableRawPointer?)

@_silgen_name("wf_job_set_int")
private func wf_job_set_int(
  _ job: UnsafeMutableRawPointer?,
  _ key: UnsafePointer<CChar>?,
  _ value: Int64
)

@_silgen_name("wf_job_set_double")
private func wf_job_set_double(
  _ job: UnsafeMutableRawPointer?,
  _ key: UnsafePointer<CChar>?,
  _ value: Double
)

@_silgen_name("wf_job_set_string")
private func wf_job_set_string(
  _ job: UnsafeMutableRawPointer?,
  _ key: UnsafePointer<CChar>?,
  _ value: UnsafePointer<CChar>?
)

@_silgen_name("wf_run")
private func wf_run(
  _ context: UnsafeMutableRawPointer?,
  _ job: UnsafeMutableRawPointer?,
  _ samples: UnsafePointer<Float>?,
  _ sampleCount: Int32
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("wf_string_free")
private func wf_string_free(_ value: UnsafeMutablePointer<CChar>?)

@_silgen_name("wf_last_error")
private func wf_last_error() -> UnsafePointer<CChar>?

final class WhisperEngine: @unchecked Sendable {
  private let context: UnsafeMutableRawPointer
  private let queue = DispatchQueue(label: "kr.co.newer.bibleitda.whisper", qos: .userInitiated)

  private init(context: UnsafeMutableRawPointer) {
    self.context = context
  }

  deinit {
    wf_context_free(context)
  }

  static func load(modelURL: URL) async throws -> WhisperEngine {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let context = modelURL.path.withCString {
          wf_context_create($0, 1, 1, 0, 0)
        }
        guard let context else {
          let message = wf_last_error().map(String.init(cString:))
            ?? "Unable to load the Whisper tiny model."
          continuation.resume(throwing: EngineError.inference(message))
          return
        }
        continuation.resume(returning: WhisperEngine(context: context))
      }
    }
  }

  func transcribe(samples: [Float], language: String, prompt: String = "") async throws -> WhisperTranscription {
    guard !samples.isEmpty else {
      return WhisperTranscription(text: "", processingMilliseconds: 0)
    }
    return try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        guard let job = wf_job_create(0) else {
          continuation.resume(throwing: EngineError.inference("Unable to create Whisper job."))
          return
        }
        defer { wf_job_free(job) }

        Self.set(job, int: "threads", value: 4)
        Self.set(job, int: "translate", value: 0)
        Self.set(job, int: "detect_language", value: 0)
        Self.set(job, int: "max_tokens", value: 128)
        Self.set(job, int: "single_segment", value: 1)
        Self.set(job, int: "no_context", value: 1)
        Self.set(job, int: "no_timestamps", value: 1)
        Self.set(job, int: "suppress_blank", value: 1)
        Self.set(job, int: "suppress_nst", value: 1)
        Self.set(job, int: "greedy_best_of", value: 1)
        Self.set(job, double: "temperature", value: 0)
        Self.set(job, double: "temperature_inc", value: 0)
        Self.set(job, double: "no_speech_thold", value: 0.30)
        Self.set(job, string: "language", value: language)
        if !prompt.isEmpty {
          Self.set(job, string: "initial_prompt", value: prompt)
        }

        let jsonPointer = samples.withUnsafeBufferPointer { buffer in
          wf_run(self.context, job, buffer.baseAddress, Int32(buffer.count))
        }
        guard let jsonPointer else {
          let message = wf_last_error().map(String.init(cString:))
            ?? "Whisper transcription failed."
          continuation.resume(throwing: EngineError.inference(message))
          return
        }
        defer { wf_string_free(jsonPointer) }

        do {
          let data = Data(String(cString: jsonPointer).utf8)
          let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
          let text = (value?["text"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
          let processingMicroseconds = value?["processing_us"] as? Int ?? 0
          continuation.resume(
            returning: WhisperTranscription(
              text: text,
              processingMilliseconds: processingMicroseconds / 1_000
            )
          )
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func set(_ job: UnsafeMutableRawPointer, int key: String, value: Int64) {
    key.withCString { wf_job_set_int(job, $0, value) }
  }

  private static func set(_ job: UnsafeMutableRawPointer, double key: String, value: Double) {
    key.withCString { wf_job_set_double(job, $0, value) }
  }

  private static func set(_ job: UnsafeMutableRawPointer, string key: String, value: String) {
    key.withCString { keyPointer in
      value.withCString { valuePointer in
        wf_job_set_string(job, keyPointer, valuePointer)
      }
    }
  }

  enum EngineError: LocalizedError {
    case inference(String)

    var errorDescription: String? {
      switch self {
      case .inference(let message):
        return message
      }
    }
  }
}
