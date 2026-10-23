import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qs_adjust/qs_adjust.dart';
import 'package:qs_aes_encrypt/qs_aes_encrypt.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  test('全部字段映射、密文补报和成功缓存', () async {
    // 仅对本测试启用本地 HTTP 服务，不改动生产网络层。
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final bodies = <Map<String, dynamic>>[];
    var sdkGets = 0;
    var stored = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async {
        if (call.method == 'getAll') return <String, Object>{};
        if (call.method == 'setBool') stored = true;
        return true;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.adjust.sdk/api'),
      (call) async {
        if (call.method == 'getAttribution') {
          sdkGets++;
          return <String, String>{
            'trackerToken': 'tracker',
            'network': 'network',
            'costAmount': '1.5',
            'jsonResponse': '{"hello":"world"}',
          };
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
    final heldRequest = Completer<void>();
    final releaseRequest = Completer<void>();
    server.listen((request) async {
      expect(request.headers.value('sct'), 'token');
      bodies.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      if (bodies.length == 3) {
        heldRequest.complete();
        await releaseRequest.future;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': bodies.length == 1 || bodies.length == 3 || bodies.length == 5
              ? 1
              : 0,
        }),
      );
      await request.response.close();
    });
    initializeAdjust(
      reportConfig: QsAdjustReportConfig(
        apiParameterNameModel: names,
        apiUrl: 'http://127.0.0.1:${server.port}/attribution',
        aesSecretKey: '0123456789abcdef',
        aesIv: '0123456789abcdef',
        aesSctToken: 'token',
        packageName: 'test.app',
        iosAppId: '123',
      ),
    );
    QsAdjust.initialize(
      skipAsaCheck: false,
      appToken: 'ignored-token',
      reportConfig: emptyReportConfig,
    );
    await Future<void>.delayed(Duration.zero);
    Future<bool> report() => QsAdjust.reportAttributionInfo();
    expect(await report(), false);
    final expected = <String, dynamic>{
      'custom_iosAppId': '123',
      'custom_packageName': 'test.app',
      'custom_userId': 'user-id',
      'custom_adjustAdid': 'adid',
      'custom_trackerToken': 'tracker',
      'custom_trackerName': '',
      'custom_network': 'network',
      'custom_campaign': '',
      'custom_campaignId': '',
      'custom_adgroup': '',
      'custom_adgroupId': '',
      'custom_creative': '',
      'custom_creativeId': '',
      'custom_clickLabel': '',
      'custom_costType': '',
      'custom_costAmount': 1.5,
      'custom_costCurrency': '',
      'custom_platform': 'ios',
      'custom_appVersion': '1.0',
      'custom_rawData': {'hello': 'world'},
    };
    expect(bodies.single, {
      'data': QsAesEncrypt.encrypt(
        secretKey: '0123456789abcdef',
        iv: '0123456789abcdef',
        content: jsonEncode(expected),
      ),
    });
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (!stored && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(stored, true);
    expect(bodies, hasLength(2));
    expect(bodies[1], bodies[0]);
    expect(sdkGets, 1);
    expect(await report(), true);
    expect(bodies, hasLength(2));

    Future<void> callback({required String network}) async {
      final done = Completer<void>();
      messenger.handlePlatformMessage(
        'com.adjust.sdk/api',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('adj-attribution-changed', {'network': network}),
        ),
        (_) => done.complete(),
      );
      await done.future;
    }

    await callback(network: 'first');
    await heldRequest.future.timeout(const Duration(seconds: 5));
    await callback(network: 'superseded');
    await callback(network: 'latest');
    releaseRequest.complete();
    Future<void> waitForBodies({required int count}) async {
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (bodies.length < count && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(bodies, hasLength(count));
      // 等待响应处理和成功标记保存完成。
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    await waitForBodies(count: 4);
    Map<String, dynamic> encryptedCallback({required String network}) => {
      'data': QsAesEncrypt.encrypt(
        secretKey: '0123456789abcdef',
        iv: '0123456789abcdef',
        content: jsonEncode({
          ...expected,
          'custom_trackerToken': '',
          'custom_network': network,
          'custom_costAmount': 0.0,
          'custom_rawData': null,
        }),
      ),
    };
    expect(bodies[2], encryptedCallback(network: 'first'));
    expect(bodies[3], encryptedCallback(network: 'latest'));
    expect(sdkGets, 1);
    expect(await report(), true);
    expect(bodies, hasLength(4));

    // 已存在成功缓存时，强制上报失败也必须继续补报。
    // 服务端让第五次请求失败、第六次成功。
    await callback(network: 'retry');
    await waitForBodies(count: 6);
    expect(bodies[4], encryptedCallback(network: 'retry'));
    expect(bodies[5], bodies[4]);
    expect(sdkGets, 1);
  });
}
