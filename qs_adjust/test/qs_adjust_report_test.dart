import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qs_adjust/qs_adjust.dart';

import 'initialize_adjust.dart';

const names = QsAdjustApiParameterNameModel(
  iosAppId: 'custom_iosAppId',
  packageName: 'custom_packageName',
  userId: 'custom_userId',
  adjustAdid: 'custom_adjustAdid',
  trackerToken: 'custom_trackerToken',
  trackerName: 'custom_trackerName',
  network: 'custom_network',
  campaign: 'custom_campaign',
  campaignId: 'custom_campaignId',
  adgroup: 'custom_adgroup',
  adgroupId: 'custom_adgroupId',
  creative: 'custom_creative',
  creativeId: 'custom_creativeId',
  clickLabel: 'custom_clickLabel',
  costType: 'custom_costType',
  costAmount: 'custom_costAmount',
  costCurrency: 'custom_costCurrency',
  platform: 'custom_platform',
  appVersion: 'custom_appVersion',
  rawData: 'custom_rawData',
);

void main() {
  testWidgets('获取异常退避重试、并发合并、AES失败停止补报', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var gets = 0;
    var recover = false;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async {
        if (call.method == 'getAll') {
          return <String, Object>{};
        }
        return true;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.adjust.sdk/api'),
      (call) async {
        if (call.method == 'getAttribution') {
          gets++;
          if (!recover) throw PlatformException(code: 'not_ready');
          return <String, String>{};
        }
        return 'adid';
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => 'user-id',
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
    initializeAdjust(
      reportConfig: QsAdjustReportConfig(
        apiParameterNameModel: names,
        apiUrl: 'https://example.invalid',
        aesSecretKey: 'invalid',
        aesIv: 'invalid',
        aesSctToken: 'token',
        packageName: 'test.app',
        iosAppId: '123',
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    Future<bool> report() => QsAdjust.reportAttributionInfo();
    final first = report();
    final concurrent = report();
    await tester.pump();
    expect(await first, false);
    expect(await concurrent, false);
    expect(gets, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(gets, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(gets, 2);
    await tester.pump(const Duration(seconds: 4));
    expect(gets, 2);
    recover = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(gets, 3);
    await tester.pump(const Duration(minutes: 2));
    expect(gets, 3); // AES失败后不再重试。
  });
}
