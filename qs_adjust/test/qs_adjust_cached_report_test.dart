import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qs_adjust/qs_adjust.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('成功标记存在时跳过初始化并取消待补报', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => call.method == 'getAll'
          ? <String, Object>{
              'flutter.qs_adjust_attribution_info_report_success': true,
            }
          : true,
    );
    final sdkCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.adjust.sdk/api'),
      (call) async {
        sdkCalls.add(call);
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => 'user-id',
    );
    final pending = QsAdjust.reportAttributionInfo();
    await tester.pump();
    expect(await pending, false);
    QsAdjust.initialize(
      appToken: 'test-token',
      skipAsaCheck: true,
      reportConfig: QsAdjustReportConfig(
        apiParameterNameModel: names,
        apiUrl: '',
        aesSecretKey: '',
        aesIv: '',
        aesSctToken: '',
        packageName: '',
        iosAppId: '',
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(sdkCalls, isEmpty);
    expect(await QsAdjust.reportAttributionInfo(), false);
    expect(await QsAdjust.reportAttributionInfo(forceReport: true), false);
    await tester.pump(const Duration(minutes: 5));
    expect(sdkCalls, isEmpty);
  });
}
