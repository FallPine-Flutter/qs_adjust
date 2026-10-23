import 'qs_adjust_api_parameter_name_model.dart';

/// 归因上报配置，初始化后在当前进程内复用。
class QsAdjustReportConfig {
  const QsAdjustReportConfig({
    required this.apiParameterNameModel,
    required this.apiUrl,
    required this.aesSecretKey,
    required this.aesIv,
    required this.aesSctToken,
    required this.packageName,
    required this.iosAppId,
  });

  /// Properties
  final QsAdjustApiParameterNameModel apiParameterNameModel;
  final String apiUrl;
  final String aesSecretKey;
  final String aesIv;
  final String aesSctToken;
  final String packageName;
  final String iosAppId;
}
