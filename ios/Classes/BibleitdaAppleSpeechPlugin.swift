import AVFoundation
import Flutter
import Speech
import UIKit

public final class BibleitdaAppleSpeechPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var activeSession: AnyObject?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BibleitdaAppleSpeechPlugin()
    let methodChannel = FlutterMethodChannel(
      name: "bibleitda_apple_speech/methods",
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: "bibleitda_apple_speech/events",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "availability":
      result([
        "supported": ProcessInfo.processInfo.isOperatingSystemAtLeast(
          OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ),
        "systemVersion": UIDevice.current.systemVersion,
        "minimumVersion": "26.0",
      ])
    case "start":
      guard #available(iOS 26.0, *) else {
        result("unsupported")
        return
      }
      let arguments = call.arguments as? [String: Any]
      let localeIdentifier = arguments?["localeIdentifier"] as? String ?? "ko_KR"
      let contextualPhrases = arguments?["contextualPhrases"] as? [String] ?? []
      Task { @MainActor [weak self] in
        guard let self else {
          result("listen_error")
          return
        }
        guard await Self.requestPermissions() else {
          result("permission_denied")
          return
        }
        if let current = self.activeSession as? AppleSpeechSession {
          await current.cancel()
        }
        let session = AppleSpeechSession { [weak self] event in
          self?.emit(event)
        }
        self.activeSession = session
        do {
          let engine = try await session.start(
            localeIdentifier: localeIdentifier,
            contextualPhrases: contextualPhrases
          )
          result("started:\(engine)")
        } catch AppleSpeechSession.SessionError.unsupportedLocale {
          self.activeSession = nil
          result("unsupported")
        } catch {
          self.activeSession = nil
          self.emit([
            "type": "error",
            "code": "listen_error",
            "message": error.localizedDescription,
          ])
          result("listen_error")
        }
      }
    case "stop":
      guard #available(iOS 26.0, *), let session = activeSession as? AppleSpeechSession else {
        result(nil)
        return
      }
      Task { @MainActor [weak self] in
        await session.stop()
        self?.activeSession = nil
        result(nil)
      }
    case "cancel":
      guard #available(iOS 26.0, *), let session = activeSession as? AppleSpeechSession else {
        result(nil)
        return
      }
      Task { @MainActor [weak self] in
        await session.cancel()
        self?.activeSession = nil
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }

  @MainActor
  private static func requestPermissions() async -> Bool {
    let speechAllowed: Bool
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      speechAllowed = true
    case .notDetermined:
      speechAllowed = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
          continuation.resume(returning: status == .authorized)
        }
      }
    default:
      speechAllowed = false
    }
    guard speechAllowed else { return false }

    let audioSession = AVAudioSession.sharedInstance()
    switch audioSession.recordPermission {
    case .granted:
      return true
    case .undetermined:
      return await withCheckedContinuation { continuation in
        audioSession.requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      }
    default:
      return false
    }
  }
}

@available(iOS 26.0, *)
@MainActor
private final class AppleSpeechSession {
  enum SessionError: Error {
    case unsupportedLocale
    case noAudioFormat
    case noAudioInput
    case converterUnavailable
  }

  private enum Engine {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)

    var name: String {
      switch self {
      case .speech:
        return "speech_transcriber"
      case .dictation:
        return "dictation_transcriber"
      }
    }

    var modules: [any SpeechModule] {
      switch self {
      case .speech(let transcriber):
        return [transcriber]
      case .dictation(let transcriber):
        return [transcriber]
      }
    }
  }

  private let emit: ([String: Any]) -> Void
  private var engine: Engine?
  private var analyzer: SpeechAnalyzer?
  private var audioEngine: AVAudioEngine?
  private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var resultTask: Task<Void, Never>?
  private var isActive = false
  private var rememberedCategory: AVAudioSession.Category?
  private var rememberedMode: AVAudioSession.Mode?
  private var rememberedOptions: AVAudioSession.CategoryOptions?

  init(emit: @escaping ([String: Any]) -> Void) {
    self.emit = emit
  }

  func start(localeIdentifier: String, contextualPhrases: [String]) async throws -> String {
    emit(["type": "status", "status": "preparing"])

    let requestedLocale = Locale(identifier: localeIdentifier)
    let selectedEngine: Engine
    // Prefer the same transcription family used by Apple's system dictation.
    // It is a better fit for users reading complete Bible sentences aloud.
    if let locale = await DictationTranscriber.supportedLocale(
      equivalentTo: requestedLocale
    ) {
      selectedEngine = .dictation(
        DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
      )
    } else if let locale = await SpeechTranscriber.supportedLocale(
      equivalentTo: requestedLocale
    ) {
      selectedEngine = .speech(
        SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
      )
    } else {
      throw SessionError.unsupportedLocale
    }
    engine = selectedEngine

    if let installation = try await AssetInventory.assetInstallationRequest(
      supporting: selectedEngine.modules
    ) {
      emit(["type": "status", "status": "preparing_model"])
      try await installation.downloadAndInstall()
    }

    let context = AnalysisContext()
    context.contextualStrings[.general] = Self.normalizedContext(contextualPhrases)
    let analyzerOptions = SpeechAnalyzer.Options(
      priority: .userInitiated,
      modelRetention: .processLifetime
    )
    let newAnalyzer = SpeechAnalyzer(
      modules: selectedEngine.modules,
      options: analyzerOptions
    )
    try await newAnalyzer.setContext(context)

    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
      compatibleWith: selectedEngine.modules
    ) else {
      throw SessionError.noAudioFormat
    }
    try await newAnalyzer.prepareToAnalyze(in: analyzerFormat)

    let inputPair = AsyncStream<AnalyzerInput>.makeStream(
      bufferingPolicy: .bufferingNewest(24)
    )
    inputContinuation = inputPair.continuation
    analyzer = newAnalyzer
    startResultTask(for: selectedEngine)
    try await newAnalyzer.start(inputSequence: inputPair.stream)
    try startAudioEngine(analyzerFormat: analyzerFormat, continuation: inputPair.continuation)

    isActive = true
    emit([
      "type": "status",
      "status": "listening",
      "engine": selectedEngine.name,
    ])
    return selectedEngine.name
  }

  func stop() async {
    guard isActive || analyzer != nil else { return }
    isActive = false
    stopAudioInput()
    inputContinuation?.finish()
    inputContinuation = nil
    do {
      try await analyzer?.finalizeAndFinishThroughEndOfInput()
      await resultTask?.value
    } catch {
      emit([
        "type": "error",
        "code": "finalize_error",
        "message": error.localizedDescription,
      ])
    }
    clearSession()
    emit(["type": "status", "status": "done"])
  }

  func cancel() async {
    isActive = false
    stopAudioInput()
    inputContinuation?.finish()
    inputContinuation = nil
    resultTask?.cancel()
    resultTask = nil
    await analyzer?.cancelAndFinishNow()
    clearSession()
    emit(["type": "status", "status": "done"])
  }

  private func startResultTask(for engine: Engine) {
    switch engine {
    case .speech(let transcriber):
      resultTask = Task { [weak self] in
        do {
          for try await result in transcriber.results {
            guard !Task.isCancelled else { return }
            self?.publish(
              text: result.text,
              alternatives: result.alternatives,
              isFinal: result.isFinal,
              engine: engine.name
            )
          }
        } catch is CancellationError {
          return
        } catch {
          self?.publishError(error)
        }
      }
    case .dictation(let transcriber):
      resultTask = Task { [weak self] in
        do {
          for try await result in transcriber.results {
            guard !Task.isCancelled else { return }
            self?.publish(
              text: result.text,
              alternatives: result.alternatives,
              isFinal: result.isFinal,
              engine: engine.name
            )
          }
        } catch is CancellationError {
          return
        } catch {
          self?.publishError(error)
        }
      }
    }
  }

  private func publish(
    text: AttributedString,
    alternatives: [AttributedString],
    isFinal: Bool,
    engine: String
  ) {
    let mainText = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !mainText.isEmpty else { return }
    emit([
      "type": "result",
      "text": mainText,
      "alternatives": alternatives.prefix(5).map { String($0.characters) },
      "isFinal": isFinal,
      "engine": engine,
    ])
  }

  private func publishError(_ error: Error) {
    emit([
      "type": "error",
      "code": "recognition_error",
      "message": error.localizedDescription,
    ])
  }

  private func startAudioEngine(
    analyzerFormat: AVAudioFormat,
    continuation: AsyncStream<AnalyzerInput>.Continuation
  ) throws {
    let session = AVAudioSession.sharedInstance()
    rememberedCategory = session.category
    rememberedMode = session.mode
    rememberedOptions = session.categoryOptions

    // Match Apple's speech-recognition capture recommendations. Measurement
    // mode avoids voice-processing effects that can distort quiet Korean
    // syllables, while omitting Bluetooth options keeps the built-in mic route.
    try session.setCategory(.record, mode: .measurement, options: [])
    if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
      try session.setPreferredInput(builtInMic)
    }
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let engine = AVAudioEngine()
    let inputNode = engine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    guard inputFormat.channelCount > 0 else {
      throw SessionError.noAudioInput
    }
    guard let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
      throw SessionError.converterUnavailable
    }

    inputNode.installTap(
      onBus: 0,
      bufferSize: 4096,
      format: inputFormat
    ) { buffer, _ in
      guard let converted = Self.convert(
        buffer: buffer,
        using: converter,
        outputFormat: analyzerFormat
      ) else {
        return
      }
      continuation.yield(AnalyzerInput(buffer: converted))
    }
    engine.prepare()
    try engine.start()
    audioEngine = engine

    let route = session.currentRoute.inputs.first
    emit([
      "type": "diagnostic",
      "input": route?.portType.rawValue ?? "none",
      "inputName": route?.portName ?? "none",
      "sampleRate": session.sampleRate,
      "channels": inputFormat.channelCount,
      "mode": session.mode.rawValue,
      "category": session.category.rawValue,
    ])
  }

  private func stopAudioInput() {
    if let engine = audioEngine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      audioEngine = nil
    }
    let session = AVAudioSession.sharedInstance()
    do {
      if let category = rememberedCategory,
         let mode = rememberedMode,
         let options = rememberedOptions {
        try session.setCategory(category, mode: mode, options: options)
      }
      try session.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      emit([
        "type": "diagnostic",
        "message": "audio_session_restore_failed: \(error.localizedDescription)",
      ])
    }
  }

  private func clearSession() {
    resultTask?.cancel()
    resultTask = nil
    analyzer = nil
    engine = nil
  }

  nonisolated private static func convert(
    buffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    outputFormat: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    if buffer.format == outputFormat {
      return buffer
    }
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

  nonisolated private static func normalizedContext(_ phrases: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for phrase in phrases {
      let value = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
      guard value.count >= 2, !seen.contains(value) else { continue }
      seen.insert(value)
      result.append(value)
      if result.count == 100 { break }
    }
    return result
  }
}
