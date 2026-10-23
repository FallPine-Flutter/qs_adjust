/// Adjust 归因上报加密内容中的接口字段名，全部由调用方提供。
class QsAdjustApiParameterNameModel {
  const QsAdjustApiParameterNameModel({
    required this.iosAppId,
    required this.packageName,
    required this.userId,
    required this.adjustAdid,
    required this.trackerToken,
    required this.trackerName,
    required this.network,
    required this.campaign,
    required this.campaignId,
    required this.adgroup,
    required this.adgroupId,
    required this.creative,
    required this.creativeId,
    required this.clickLabel,
    required this.costType,
    required this.costAmount,
    required this.costCurrency,
    required this.platform,
    required this.appVersion,
    required this.rawData,
  });

  /// Properties
  final String iosAppId;
  final String packageName;
  final String userId;
  final String adjustAdid;
  final String trackerToken;
  final String trackerName;
  final String network;
  final String campaign;
  final String campaignId;
  final String adgroup;
  final String adgroupId;
  final String creative;
  final String creativeId;
  final String clickLabel;
  final String costType;
  final String costAmount;
  final String costCurrency;
  final String platform;
  final String appVersion;
  final String rawData;
}
