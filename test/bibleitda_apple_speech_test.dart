import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bibleitda_apple_speech/bibleitda_apple_speech.dart';
import 'package:bibleitda_apple_speech/bibleitda_apple_speech_platform_interface.dart';
import 'package:bibleitda_apple_speech/bibleitda_apple_speech_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBibleitdaAppleSpeechPlatform
    with MockPlatformInterfaceMixin
    implements BibleitdaAppleSpeechPlatform {
  @override
  Stream<AppleSpeechEvent> get events => const Stream.empty();

  @override
  Future<AppleSpeechAvailability> availability() async =>
      const AppleSpeechAvailability(
        supported: true,
        systemVersion: '26.0',
        minimumVersion: '26.0',
      );

  @override
  Future<String> start({
    required String localeIdentifier,
    required List<String> contextualPhrases,
  }) async =>
      'started:speech_transcriber';

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

void main() {
  final BibleitdaAppleSpeechPlatform initialPlatform =
      BibleitdaAppleSpeechPlatform.instance;

  test('$MethodChannelBibleitdaAppleSpeech is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBibleitdaAppleSpeech>());
  });

  test('availability', () async {
    final fakePlatform = MockBibleitdaAppleSpeechPlatform();
    BibleitdaAppleSpeechPlatform.instance = fakePlatform;

    final availability = await BibleitdaAppleSpeech.instance.availability();
    expect(availability.supported, isTrue);
    expect(availability.minimumVersion, '26.0');
  });

  test('iOS uses responsive verse dictation with cumulative range updates', () {
    final swift = File(
      'ios/Classes/BibleitdaAppleSpeechPlugin.swift',
    ).readAsStringSync();

    expect(swift, contains('.progressiveShortDictation'));
    expect(swift, isNot(contains('.progressiveLongDictation')));
    expect(swift, contains('bufferSize: 2048'));
    expect(swift,
        contains('resultsFinalizationTime: result.resultsFinalizationTime'));
    expect(swift, contains('replaceTranscriptSegment('));
    expect(swift, contains('.map(\\.text)'));
  });
}
