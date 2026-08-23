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
      'started:whisper_cpp_tiny';

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

  test('iOS uses whisper.cpp tiny with progress and stable verification', () {
    final plugin = File(
      'ios/Classes/BibleitdaAppleSpeechPlugin.swift',
    ).readAsStringSync();
    final session = File(
      'ios/Classes/WhisperSpeechSession.swift',
    ).readAsStringSync();
    final modelStore = File(
      'ios/Classes/WhisperModelStore.swift',
    ).readAsStringSync();
    final podspec = File(
      'ios/bibleitda_apple_speech.podspec',
    ).readAsStringSync();
    final metalDevice = File(
      'ios/Vendor/WhisperCppCore/ggml/src/ggml-metal/ggml-metal-device.m',
    ).readAsStringSync();
    final metalShader = File(
      'ios/Vendor/WhisperCppCore/ggml/Resources/ggml-metal.txt',
    );

    expect(plugin, contains('started:whisper_cpp_tiny'));
    expect(plugin, contains('"type": "download"'));
    expect(plugin, contains('removeLegacyModelsAtStartup()'));
    expect(plugin, isNot(contains('SFSpeechRecognizer')));
    expect(session, contains('sampleRate = 16_000.0'));
    expect(session, contains('bufferSize: 2_048'));
    expect(session, contains('isFinal": true'));
    expect(session, contains('containsSpeech(finalSamples)'));
    expect(session, contains('whisper_inference:'));
    expect(podspec, contains('ggml/Resources/ggml-metal.txt'));
    expect(
        metalDevice, contains('pathForResource:@"ggml-metal" ofType:@"txt"'));
    expect(metalShader.lengthSync(), greaterThan(400000));
    expect(modelStore, contains('ggml-tiny.bin'));
    expect(modelStore, contains('77_691_713'));
    expect(modelStore, contains('legacyModelNames = ["ggml-base.bin"]'));
    expect(modelStore, contains('URLSessionDownloadDelegate'));
    expect(modelStore, contains('lastReportedPercent'));
    expect(
      modelStore,
      contains(
        'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
      ),
    );
  });

  test('download events expose progress and byte counts', () {
    final event = AppleSpeechEvent.fromMap({
      'type': 'download',
      'model': 'tiny',
      'progress': 0.42,
      'receivedBytes': 42,
      'totalBytes': 100,
    });

    expect(event.type, 'download');
    expect(event.model, 'tiny');
    expect(event.progress, 0.42);
    expect(event.receivedBytes, 42);
    expect(event.totalBytes, 100);
  });
}
