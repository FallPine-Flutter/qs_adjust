import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qs_adjust/qs_adjust.dart';
import 'package:qs_asa_attribution_info/qs_asa_attribution_info_platform_interface.dart';

import 'initialize_adjust.dart';

void main() {
  testWidgets('跳过ASA，准备失败重试沿用首次开关和配置', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final asa = _AsaPlatform();
    QsAsaAttributionInfoPlatform.instance = asa;
    var storageReads = 0;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async {
        if (call.method == 'getAll') {
          storageReads++;
          if (storageReads == 1) throw PlatformException(code: 'unavailable');
          return <String, Object>{};
        }
        return true;
      },
    );
    var reads = 0;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        reads++;
        return 'user-id';
      },
    );
    final sdkCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.adjust.sdk/api'),
      (call) async {
        sdkCalls.add(call);
        return null;
      },
    );
    QsAdjust.initialize(
      appToken: 'first-token',
      reportConfig: emptyReportConfig,
      skipAsaCheck: true,
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(reads, 0);
    expect(storageReads, 1);
    expect(sdkCalls, isEmpty);
    QsAdjust.initialize(
      skipAsaCheck: false,
      appToken: 'ignored-token',
      reportConfig: emptyReportConfig,
    );
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(reads, 1);
    expect(asa.calls, 0);
    final init = sdkCalls.singleWhere((call) => call.method == 'initSdk');
    expect((init.arguments as Map)['appToken'], 'first-token');
    await tester.pump(const Duration(minutes: 2));
    expect(reads, 1);
  });
}

class _AsaPlatform extends QsAsaAttributionInfoPlatform {
  @override
  Future<Map<String, dynamic>?> getAttributionInfo() async {
    calls++;
    return {'attribution': true};
  }

  int calls = 0;
}
