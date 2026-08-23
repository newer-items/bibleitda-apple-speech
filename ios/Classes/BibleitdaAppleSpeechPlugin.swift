import AVFoundation
import Flutter
import UIKit

public final class BibleitdaAppleSpeechPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var activeSession: WhisperSpeechSession?
  private var whisperEngine: WhisperEngine?
  private var engineLoadTask: Task<WhisperEngine, Error>?

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
          OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        ),
        "systemVersion": UIDevice.current.systemVersion,
        "minimumVersion": "14.0",
      ])
    case "start":
      let arguments = call.arguments as? [String: Any]
      let localeIdentifier = arguments?["localeIdentifier"] as? String ?? "ko_KR"
      Task { @MainActor [weak self] in
        guard let self else {
          result("listen_error")
          return
        }
        guard await Self.requestMicrophonePermission() else {
          result("permission_denied")
          return
        }

        await self.activeSession?.cancel()
        self.activeSession = nil

        do {
          let engine = try await self.loadEngine()
          let session = WhisperSpeechSession(engine: engine) { [weak self] event in
            self?.emit(event)
          }
          self.activeSession = session
          try session.start(localeIdentifier: localeIdentifier)
          result("started:whisper_cpp_base")
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
      Task { @MainActor [weak self] in
        guard let self, let session = self.activeSession else {
          result(nil)
          return
        }
        await session.stop()
        self.activeSession = nil
        result(nil)
      }
    case "cancel":
      Task { @MainActor [weak self] in
        guard let self, let session = self.activeSession else {
          result(nil)
          return
        }
        await session.cancel()
        self.activeSession = nil
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

  private func loadEngine() async throws -> WhisperEngine {
    if let whisperEngine {
      return whisperEngine
    }
    if let engineLoadTask {
      return try await engineLoadTask.value
    }

    emit(["type": "status", "status": "preparing_model", "engine": "whisper_cpp_base"])
    let task = Task<WhisperEngine, Error> { [weak self] in
      let modelURL = try await WhisperModelStore.baseModelURL { message in
        self?.emit(["type": "diagnostic", "message": message])
      }
      return try await WhisperEngine.load(modelURL: modelURL)
    }
    engineLoadTask = task
    do {
      let engine = try await task.value
      whisperEngine = engine
      engineLoadTask = nil
      emit([
        "type": "diagnostic",
        "message": "whisper_model_ready:base:147951465",
      ])
      return engine
    } catch {
      engineLoadTask = nil
      throw error
    }
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }

  @MainActor
  private static func requestMicrophonePermission() async -> Bool {
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
