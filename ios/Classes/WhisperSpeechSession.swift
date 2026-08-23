@preconcurrency import AVFoundation
import Foundation

final class WhisperSpeechSession: @unchecked Sendable {
  enum SessionError: LocalizedError {
    case noAudioInput
    case converterUnavailable

    var errorDescription: String? {
      switch self {
      case .noAudioInput:
        return "The iPhone microphone did not provide an audio channel."
      case .converterUnavailable:
        return "The iPhone microphone audio converter is unavailable."
      }
    }
  }

  private static let sampleRate = 16_000.0
  private static let minimumInferenceSamples = 16_000
  private static let maximumInferenceSamples = 480_000
  private static let inferenceInterval: TimeInterval = 0.9
  private static let minimumRMS: Float = 0.0015

  private let engine: WhisperEngine
  private let emit: ([String: Any]) -> Void
  private let stateQueue = DispatchQueue(
    label: "kr.co.newer.bibleitda.whisper.audio",
    qos: .userInitiated
  )

  private var audioEngine: AVAudioEngine?
  private var rememberedCategory: AVAudioSession.Category?
  private var rememberedMode: AVAudioSession.Mode?
  private var rememberedOptions: AVAudioSession.CategoryOptions?
  private var language = "ko"
  private var generation = 0
  private var active = false
  private var samples: [Float] = []
  private var inferenceInFlight = false
  private var inferencePending = false
  private var lastInferenceAt = Date.distantPast
  private var lastTranscript = ""

  init(engine: WhisperEngine, emit: @escaping ([String: Any]) -> Void) {
    self.engine = engine
    self.emit = emit
  }

  func start(localeIdentifier: String) throws {
    emit(["type": "status", "status": "preparing", "engine": "whisper_cpp_base"])
    stateQueue.sync {
      language = Self.whisperLanguage(from: localeIdentifier)
      generation += 1
      active = true
      samples.removeAll(keepingCapacity: true)
      inferenceInFlight = false
      inferencePending = false
      lastInferenceAt = .distantPast
      lastTranscript = ""
    }
    try startAudioEngine()
    emit([
      "type": "status",
      "status": "listening",
      "engine": "whisper_cpp_base",
    ])
  }

  func stop() async {
    let shouldStop = stateQueue.sync { active }
    guard shouldStop || audioEngine != nil else { return }
    stopAudioInput()
    let finalState = stateQueue.sync { () -> (Int, [Float], String) in
      active = false
      return (generation, samples, language)
    }
    let finalGeneration = finalState.0
    let finalSamples = finalState.1
    if Self.hasSpeech(finalSamples) {
      do {
        let text = try await engine.transcribe(
          samples: Array(finalSamples.suffix(Self.maximumInferenceSamples)),
          language: finalState.2
        )
        guard finalGeneration == stateQueue.sync(execute: { generation }) else { return }
        let cleaned = Self.clean(text)
        if !cleaned.isEmpty {
          stateQueue.sync { lastTranscript = cleaned }
          emit([
            "type": "result",
            "text": cleaned,
            "alternatives": [],
            "isFinal": true,
            "engine": "whisper_cpp_base",
          ])
        }
      } catch {
        emit([
          "type": "error",
          "code": "finalize_error",
          "message": error.localizedDescription,
        ])
      }
    }
    emit(["type": "status", "status": "done", "engine": "whisper_cpp_base"])
  }

  func cancel() async {
    stopAudioInput()
    stateQueue.sync {
      active = false
      generation += 1
      samples.removeAll(keepingCapacity: false)
      inferencePending = false
    }
    emit(["type": "status", "status": "done", "engine": "whisper_cpp_base"])
  }

  private func startAudioEngine() throws {
    let session = AVAudioSession.sharedInstance()
    rememberedCategory = session.category
    rememberedMode = session.mode
    rememberedOptions = session.categoryOptions

    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
    try session.setPreferredSampleRate(Self.sampleRate)
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let audioEngine = AVAudioEngine()
    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    guard inputFormat.channelCount > 0 else {
      throw SessionError.noAudioInput
    }
    guard let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: Self.sampleRate,
      channels: 1,
      interleaved: false
    ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw SessionError.converterUnavailable
    }

    inputNode.installTap(
      onBus: 0,
      bufferSize: 2_048,
      format: inputFormat
    ) { [weak self] buffer, _ in
      guard let converted = Self.convert(
        buffer: buffer,
        using: converter,
        outputFormat: outputFormat
      ), let channel = converted.floatChannelData?[0], converted.frameLength > 0 else {
        return
      }
      let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
      self?.accept(chunk)
    }
    audioEngine.prepare()
    try audioEngine.start()
    self.audioEngine = audioEngine

    let route = session.currentRoute.inputs.first
    emit([
      "type": "diagnostic",
      "message": "whisper_audio_engine:\(route?.portType.rawValue ?? "none"):\(route?.portName ?? "none"):\(session.sampleRate):16000",
    ])
  }

  private nonisolated func accept(_ chunk: [Float]) {
    stateQueue.async { [weak self] in
      guard let self, self.active else { return }
      self.samples.append(contentsOf: chunk)
      guard self.samples.count >= Self.minimumInferenceSamples else { return }
      let now = Date()
      guard now.timeIntervalSince(self.lastInferenceAt) >= Self.inferenceInterval else {
        return
      }
      if self.inferenceInFlight {
        self.inferencePending = true
        return
      }
      self.startInferenceLocked()
    }
  }

  private nonisolated func startInferenceLocked() {
    guard active, !inferenceInFlight else { return }
    let snapshot = Array(samples.suffix(Self.maximumInferenceSamples))
    guard Self.hasSpeech(snapshot) else { return }
    let inferenceGeneration = generation
    let inferenceLanguage = language
    inferenceInFlight = true
    inferencePending = false
    lastInferenceAt = Date()

    Task { [weak self] in
      guard let self else { return }
      do {
        let text = try await self.engine.transcribe(
          samples: snapshot,
          language: inferenceLanguage
        )
        self.finishInference(text: text, generation: inferenceGeneration, error: nil)
      } catch {
        self.finishInference(text: "", generation: inferenceGeneration, error: error)
      }
    }
  }

  private nonisolated func finishInference(text: String, generation: Int, error: Error?) {
    stateQueue.async { [weak self] in
      guard let self else { return }
      self.inferenceInFlight = false
      guard generation == self.generation else { return }

      if let error {
        self.emit([
          "type": "error",
          "code": "recognition_error",
          "message": error.localizedDescription,
        ])
      } else {
        let cleaned = Self.clean(text)
        if !cleaned.isEmpty, cleaned != self.lastTranscript {
          self.lastTranscript = cleaned
          self.emit([
            "type": "result",
            "text": cleaned,
            "alternatives": [],
            "isFinal": false,
            "engine": "whisper_cpp_base",
          ])
        }
      }

      if self.active, self.inferencePending {
        self.startInferenceLocked()
      }
    }
  }

  private func stopAudioInput() {
    if let audioEngine {
      audioEngine.inputNode.removeTap(onBus: 0)
      audioEngine.stop()
      self.audioEngine = nil
    }
    let session = AVAudioSession.sharedInstance()
    do {
      if let rememberedCategory, let rememberedMode, let rememberedOptions {
        try session.setCategory(
          rememberedCategory,
          mode: rememberedMode,
          options: rememberedOptions
        )
      }
      try session.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      emit([
        "type": "diagnostic",
        "message": "whisper_audio_session_restore_failed:\(error.localizedDescription)",
      ])
    }
  }

  private nonisolated static func hasSpeech(_ samples: [Float]) -> Bool {
    guard !samples.isEmpty else { return false }
    let recent = samples.suffix(min(samples.count, 32_000))
    let energy = recent.reduce(Float.zero) { $0 + ($1 * $1) }
    return sqrt(energy / Float(recent.count)) >= minimumRMS
  }

  private nonisolated static func clean(_ text: String) -> String {
    text
      .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
      .replacingOccurrences(of: "[MUSIC]", with: "")
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private nonisolated static func whisperLanguage(from localeIdentifier: String) -> String {
    let normalized = localeIdentifier.replacingOccurrences(of: "-", with: "_")
    return normalized.split(separator: "_").first.map(String.init)?.lowercased() ?? "ko"
  }

  private nonisolated static func convert(
    buffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    outputFormat: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let ratio = outputFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
    guard let output = AVAudioPCMBuffer(
      pcmFormat: outputFormat,
      frameCapacity: capacity
    ) else {
      return nil
    }

    var suppliedInput = false
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
      if suppliedInput {
        inputStatus.pointee = .noDataNow
        return nil
      }
      suppliedInput = true
      inputStatus.pointee = .haveData
      return buffer
    }
    guard conversionError == nil,
          status == .haveData || status == .inputRanDry else {
      return nil
    }
    return output.frameLength > 0 ? output : nil
  }
}
