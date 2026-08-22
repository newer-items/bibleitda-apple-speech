import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'bibleitda_apple_speech.dart';
import 'bibleitda_apple_speech_method_channel.dart';

abstract class BibleitdaAppleSpeechPlatform extends PlatformInterface {
  BibleitdaAppleSpeechPlatform() : super(token: _token);

  static final Object _token = Object();
  static BibleitdaAppleSpeechPlatform _instance =
      MethodChannelBibleitdaAppleSpeech();

  static BibleitdaAppleSpeechPlatform get instance => _instance;

  static set instance(BibleitdaAppleSpeechPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<AppleSpeechEvent> get events =>
      throw UnimplementedError('events has not been implemented.');

  Future<AppleSpeechAvailability> availability() =>
      throw UnimplementedError('availability has not been implemented.');

  Future<String> start({
    required String localeIdentifier,
    required List<String> contextualPhrases,
  }) => throw UnimplementedError('start has not been implemented.');

  Future<void> stop() =>
      throw UnimplementedError('stop has not been implemented.');

  Future<void> cancel() =>
      throw UnimplementedError('cancel has not been implemented.');
}
