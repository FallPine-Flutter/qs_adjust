import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qs_adjust/qs_adjust.dart';
import 'package:qs_asa_attribution_info/qs_asa_attribution_info_platform_interface.dart';

import 'initialize_adjust.dart';

void main() {
  testWidgets('ASA空值退避重试后得到false，合并重复初始化', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var attempts = 0;
    final sdkCalls = <MethodCall>[];
    QsAsaAttributionInfoPlatform.instance = _AsaPlatform(
      read: () async {
        attempts++;
        switch (attempts) {
          case 1:
            return null;
          case 2:
            return <String, dynamic>{};
          case 3:
            return <String, dynamic>{'attribution': null};
          case 4:
            return <String, dynamic>{'attribution': 'false'};
          case 5:
            throw PlatformException(code: 'unavailable');
          case 6:
          case 7:
            return null;
          default:
            return <String, dynamic>{'attribution': false};
        }
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => 'user-id',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.adjust.sdk/api'),
      (call) async {
        sdkCalls.add(call);
        if (call.method == 'getAttribution') return <String, String>{};
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => call.method == 'getAll' ? <String, Object>{} : true,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => <String, String>{
        'appName': 'Test',
        'packageName': 'test.app',
        'version': '1.0',
        'buildNumber': '1',
      },
    );

    Future<bool> report() => QsAdjust.reportAttributionInfo();
    final pending = report();
    await tester.pump();
    expect(await pending, false);
    expect(attempts, 0);
    expect(sdkCalls, isEmpty);
    QsAdjust.initialize(
      skipAsaCheck: false,
      appToken: 'first-token',
      reportConfig: emptyReportConfig,
    );
    QsAdjust.initialize(
      skipAsaCheck: false,
      appToken: 'ignored-token',
      reportConfig: emptyReportConfig,
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(attempts, 1);
    for (final seconds in [2, 5, 10, 20, 40, 60, 60]) {
      expect(sdkCalls, isEmpty);
      QsAdjust.initialize(
        skipAsaCheck: false,
        appToken: 'ignored-token',
        reportConfig: emptyReportConfig,
      );
      final before = attempts;
      await tester.pump(Duration(seconds: seconds, milliseconds: -1));
      expect(attempts, before);
      await tester.pump(const Duration(milliseconds: 1));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(attempts, before + 1);
    }
    final config =
        sdkCalls.singleWhere((call) => call.method == 'initSdk').arguments
            as Map;
    expect(config['appToken'], 'first-token');
    expect(config['externalDeviceId'], 'user-id');
    QsAdjust.initialize(
      skipAsaCheck: false,
      appToken: 'later-token',
      reportConfig: emptyReportConfig,
    );
    await tester.pump(const Duration(minutes: 5));
    expect(attempts, 8);
    expect(
      sdkCalls.where((call) => call.method == 'getAttribution'),
      hasLength(1),
    );
    expect(sdkCalls.where((call) => call.method == 'initSdk').length, 1);
  });
}

class _AsaPlatform extends QsAsaAttributionInfoPlatform {
  _AsaPlatform({required this.read});

  @override
  Future<Map<String, dynamic>?> getAttributionInfo() => read();

  final Future<Map<String, dynamic>?> Function() read;
}
