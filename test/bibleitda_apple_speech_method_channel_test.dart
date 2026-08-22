import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bibleitda_apple_speech/bibleitda_apple_speech_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelBibleitdaAppleSpeech platform =
      MethodChannelBibleitdaAppleSpeech();
  const MethodChannel channel = MethodChannel('bibleitda_apple_speech/methods');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return <String, Object>{
            'supported': true,
            'systemVersion': '26.0',
            'minimumVersion': '26.0',
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('availability', () async {
    final availability = await platform.availability();
    expect(availability.supported, isTrue);
    expect(availability.systemVersion, '26.0');
  });
}
