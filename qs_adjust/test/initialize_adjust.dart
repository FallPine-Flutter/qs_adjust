import 'package:qs_adjust/qs_adjust.dart';
import 'package:qs_asa_attribution_info/qs_asa_attribution_info_platform_interface.dart';

void initializeAdjust({required QsAdjustReportConfig reportConfig}) {
  QsAsaAttributionInfoPlatform.instance = _AsaPlatform();
  QsAdjust.initialize(
    skipAsaCheck: false,
    appToken: 'test-token',
    reportConfig: reportConfig,
  );
}

class _AsaPlatform extends QsAsaAttributionInfoPlatform {
  @override
  Future<Map<String, dynamic>?> getAttributionInfo() async => {
    'attribution': false,
  };
}

const initializationNames = QsAdjustApiParameterNameModel(
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

const emptyReportConfig = QsAdjustReportConfig(
  apiParameterNameModel: initializationNames,
  apiUrl: '',
  aesSecretKey: '',
  aesIv: '',
  aesSctToken: '',
  packageName: '',
  iosAppId: '',
);
