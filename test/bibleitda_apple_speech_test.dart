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
        minimumVersion: '14.0',
      );

  @override
  Future<String> start({
    required String localeIdentifier,
    required List<String> contextualPhrases,
  }) async =>
      'started:whisper_cpp_base';

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
    expect(availability.minimumVersion, '14.0');
  });

  test('iOS uses whisper.cpp base with stable model verification', () {
    final plugin = File(
      'ios/Classes/BibleitdaAppleSpeechPlugin.swift',
    ).readAsStringSync();
    final session = File(
      'ios/Classes/WhisperSpeechSession.swift',
    ).readAsStringSync();
    final modelStore = File(
      'ios/Classes/WhisperModelStore.swift',
    ).readAsStringSync();

    expect(plugin, contains('started:whisper_cpp_base'));
    expect(plugin, isNot(contains('SFSpeechRecognizer')));
    expect(session, contains('sampleRate = 16_000.0'));
    expect(session, contains('bufferSize: 2_048'));
    expect(session, contains('isFinal": true'));
    expect(modelStore, contains('ggml-base.bin'));
    expect(modelStore, contains('147_951_465'));
    expect(
      modelStore,
      contains(
        '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
      ),
    );
  });
}
