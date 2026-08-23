import 'bibleitda_apple_speech_platform_interface.dart';

/// Result or lifecycle notification from Bibleitda's iOS speech engine.
class AppleSpeechEvent {
  const AppleSpeechEvent({
    required this.type,
    this.text = '',
    this.isFinal = false,
    this.alternatives = const <String>[],
    this.confidence,
    this.status = '',
    this.code = '',
    this.message = '',
    this.engine = '',
    this.model = '',
    this.progress,
    this.receivedBytes = 0,
    this.totalBytes = 0,
  });

  factory AppleSpeechEvent.fromMap(Map<Object?, Object?> value) {
    return AppleSpeechEvent(
      type: value['type'] as String? ?? '',
      text: value['text'] as String? ?? '',
      isFinal: value['isFinal'] as bool? ?? false,
      alternatives: (value['alternatives'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      confidence: (value['confidence'] as num?)?.toDouble(),
      status: value['status'] as String? ?? '',
      code: value['code'] as String? ?? '',
      message: value['message'] as String? ?? '',
      engine: value['engine'] as String? ?? '',
      model: value['model'] as String? ?? '',
      progress: (value['progress'] as num?)?.toDouble(),
      receivedBytes: (value['receivedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (value['totalBytes'] as num?)?.toInt() ?? 0,
    );
  }

  final String type;
  final String text;
  final bool isFinal;
  final List<String> alternatives;
  final double? confidence;
  final String status;
  final String code;
  final String message;
  final String engine;
  final String model;
  final double? progress;
  final int receivedBytes;
  final int totalBytes;
}

class AppleSpeechAvailability {
  const AppleSpeechAvailability({
    required this.supported,
    required this.systemVersion,
    required this.minimumVersion,
  });

  factory AppleSpeechAvailability.fromMap(Map<Object?, Object?> value) {
    return AppleSpeechAvailability(
      supported: value['supported'] as bool? ?? false,
      systemVersion: value['systemVersion'] as String? ?? '',
      minimumVersion: value['minimumVersion'] as String? ?? '14.0',
    );
  }

  final bool supported;
  final String systemVersion;
  final String minimumVersion;
}

class BibleitdaAppleSpeech {
  BibleitdaAppleSpeech._();

  static final BibleitdaAppleSpeech instance = BibleitdaAppleSpeech._();

  Stream<AppleSpeechEvent> get events =>
      BibleitdaAppleSpeechPlatform.instance.events;

  Future<AppleSpeechAvailability> availability() =>
      BibleitdaAppleSpeechPlatform.instance.availability();

  Future<String> start({
    required String localeIdentifier,
    List<String> contextualPhrases = const <String>[],
  }) {
    return BibleitdaAppleSpeechPlatform.instance.start(
      localeIdentifier: localeIdentifier,
      contextualPhrases: contextualPhrases,
    );
  }

  Future<void> stop() => BibleitdaAppleSpeechPlatform.instance.stop();

  Future<void> cancel() => BibleitdaAppleSpeechPlatform.instance.cancel();
}
