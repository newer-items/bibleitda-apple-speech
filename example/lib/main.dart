import 'package:flutter/material.dart';
import 'package:bibleitda_apple_speech/bibleitda_apple_speech.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = '확인 중';

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final availability = await BibleitdaAppleSpeech.instance.availability();
    if (!mounted) return;
    setState(() {
      _status = availability.supported
          ? 'iOS ${availability.systemVersion}: 사용 가능'
          : 'iOS ${availability.minimumVersion} 이상 필요';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Center(child: Text(_status)),
      ),
    );
  }
}
