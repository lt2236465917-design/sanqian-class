import 'dart:async';
import 'package:mobile_scanner/src/enums/camera_facing.dart';
import 'package:mobile_scanner/src/enums/detection_speed.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/src/method_channel/mobile_scanner_method_channel.dart';
import 'package:mobile_scanner/src/mobile_scanner_exception.dart';
import 'package:mobile_scanner/src/objects/start_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('leaving while permission is pending never starts the camera', () async {
    final permission = Completer<int>();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'state') return permission.future;
          return null;
        });
    final scanner = MethodChannelMobileScanner();
    final pending = scanner.start(
      const StartOptions(
        cameraDirection: CameraFacing.back,
        cameraResolution: null,
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 250,
        formats: [],
        returnImage: false,
        torchEnabled: false,
        invertImage: false,
        autoZoom: false,
        initialZoom: null,
      ),
    );
    final rejected = expectLater(
      pending,
      throwsA(isA<MobileScannerException>()),
    );
    await Future<void>.delayed(Duration.zero);
    await scanner.dispose();
    permission.complete(1);
    await rejected;
    expect(calls.where((c) => c.method == 'start'), isEmpty);
    expect(calls.where((c) => c.method == 'stop').single.arguments, {
      'force': true,
    });
  });
  test('leaving during native startup discards its late texture', () async {
    final native = Completer<Map<String, Object?>>();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'state') return 1;
          if (call.method == 'start') return native.future;
          return null;
        });
    final scanner = MethodChannelMobileScanner();
    final pending = scanner.start(
      const StartOptions(
        cameraDirection: CameraFacing.back,
        cameraResolution: null,
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 250,
        formats: [],
        returnImage: false,
        torchEnabled: false,
        invertImage: false,
        autoZoom: false,
        initialZoom: null,
      ),
    );
    final rejected = expectLater(
      pending,
      throwsA(isA<MobileScannerException>()),
    );
    await Future<void>.delayed(Duration.zero);
    await scanner.dispose();
    native.complete({'textureId': 9});
    await rejected;
    expect(calls.where((c) => c.method == 'stop').single.arguments, {
      'force': true,
    });
  });
}
