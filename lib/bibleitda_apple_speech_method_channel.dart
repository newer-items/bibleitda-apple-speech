import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bibleitda_apple_speech.dart';
import 'bibleitda_apple_speech_platform_interface.dart';

class MethodChannelBibleitdaAppleSpeech extends BibleitdaAppleSpeechPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('bibleitda_apple_speech/methods');

  @visibleForTesting
  final eventChannel = const EventChannel('bibleitda_apple_speech/events');

  Stream<AppleSpeechEvent>? _events;

  @override
  Stream<AppleSpeechEvent> get events => _events ??= eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map(
        (event) =>
            AppleSpeechEvent.fromMap(Map<Object?, Object?>.from(event as Map)),
      )
      .asBroadcastStream();

  @override
  Future<AppleSpeechAvailability> availability() async {
    final value =
        await methodChannel.invokeMapMethod<Object?, Object?>('availability') ??
        const <Object?, Object?>{};
    return AppleSpeechAvailability.fromMap(value);
  }

  @override
  Future<String> start({
    required String localeIdentifier,
    required List<String> contextualPhrases,
  }) async {
    return await methodChannel.invokeMethod<String>('start', {
          'localeIdentifier': localeIdentifier,
          'contextualPhrases': contextualPhrases,
        }) ??
        'listen_error';
  }

  @override
  Future<void> stop() => methodChannel.invokeMethod<void>('stop');

  @override
  Future<void> cancel() => methodChannel.invokeMethod<void>('cancel');
}
