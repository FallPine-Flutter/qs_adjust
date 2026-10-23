import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:adjust_sdk/adjust.dart';
import 'package:adjust_sdk/adjust_attribution.dart';
import 'package:adjust_sdk/adjust_config.dart';
import 'package:qs_aes_encrypt/qs_aes_encrypt.dart';
import 'package:qs_asa_attribution_info/qs_asa_attribution_info.dart';
import 'package:qs_device_info/qs_device_info.dart';
import 'package:qs_log/qs_log.dart';
import 'package:qs_net_request/qs_net_request.dart';
import 'package:qs_storage_tool/qs_storage_tool.dart';

import 'qs_adjust_report_config.dart';
export 'qs_adjust_api_parameter_name_model.dart';
export 'qs_adjust_report_config.dart';

part 'qs_adjust_initialization_state.dart';

class QsAdjust {
  /// Custom Funcs
  /// 初始化并保存归因上报配置；重复调用不覆盖首次配置。
  /// skipAsaCheck 仅跳过 ASA 查询，仍优先检查上报成功标记。
  static void initialize({
    required String appToken,
    required QsAdjustReportConfig reportConfig,
    required bool skipAsaCheck,
  }) {
    if (_initializationState != _QsAdjustInitializationState.notStarted) return;
    _reportConfig = reportConfig;
    _skipAsaCheck = skipAsaCheck;
    _initializationState = _QsAdjustInitializationState.initializing;
    unawaited(_attemptInitialization(appToken: appToken));
  }

  static Future<void> _attemptInitialization({required String appToken}) async {
    try {
      if (await QsStorageTool.getBool(key: _attributionDataUploadedKey) ==
          true) {
        _uploaded = true;
        _skipInitialization();
        QsLog.info("Adjust归因已成功上报，跳过Adjust初始化");
        return;
      }
      if (!_skipAsaCheck) {
        final attribution = await QsAsaAttributionInfo.getAttributionInfo();
        final isAsaAttribution = attribution?['attribution'];
        if (isAsaAttribution is! bool) {
          _scheduleInitializationRetry(appToken: appToken);
          return;
        }
        if (isAsaAttribution) {
          _skipInitialization();
          QsLog.info("ASA归因为true，跳过Adjust初始化");
          return;
        }
      }
      QsLog.info(
        _skipAsaCheck ? "跳过ASA判断，开始初始化Adjust" : "ASA归因为false，开始初始化Adjust",
      );
      await _initializeAdjust(appToken: appToken);
    } catch (error) {
      QsLog.error("Adjust初始化准备失败: $error");
      _scheduleInitializationRetry(appToken: appToken);
    }
  }

  static void _skipInitialization() {
    _initializationState = _QsAdjustInitializationState.notRequired;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAction = null;
    _pendingReport = null;
    _pendingReportCompleter?.complete(false);
    _pendingReportCompleter = null;
    _failedCount = 0;
  }

  static void _scheduleInitializationRetry({required String appToken}) {
    _initializationFailedCount++;
    final delay = _retryDelay(failedCount: _initializationFailedCount);
    QsLog.info("ASA归因未明确或初始化准备失败，${delay.inSeconds}秒后重试");
    _initializationRetryTimer?.cancel();
    _initializationRetryTimer = Timer(delay, () {
      _initializationRetryTimer = null;
      unawaited(_attemptInitialization(appToken: appToken));
    });
  }

  static Future<void> _initializeAdjust({required String appToken}) async {
    AdjustConfig config = AdjustConfig(
      appToken,
      kReleaseMode ? AdjustEnvironment.production : AdjustEnvironment.sandbox,
    );
    var userId = await QsDeviceInfo.getUserId();
    // 日志
    config.logLevel = AdjustLogLevel.verbose;
    // 外部设备标识符
    config.externalDeviceId = userId;
    // 设置全局回传 external_device_id 后台固定参数名称
    Adjust.addGlobalCallbackParameter('external_device_id', userId);
    // 启用成本数据发送
    config.isCostDataInAttributionEnabled = true;
    // 启用后台记录
    config.isSendingInBackgroundEnabled = true;
    // 禁用 AdServices 处理（仅限 iOS）
    config.isAdServicesEnabled = false;
    // 自定义弹窗时机
    config.attConsentWaitingInterval = 30;
    // 归因数据变更回调
    config.attributionCallback = (AdjustAttribution attribution) {
      unawaited(
        reportAttributionInfo(attribution: attribution, forceReport: true),
      );
    };

    // 注意:设置完后再初始化SDK，否则有可能导致参数传递失败
    Adjust.initSdk(config);
    _initializationState = _QsAdjustInitializationState.initialized;
  }

  /// 上传归因数据；等待初始化或失败时返回 false，并在内存中安排补报。
  /// ASA 明确无需初始化时返回 false，不再补报。
  /// forceReport 忽略成功缓存；并发强制上报仅保留最新待执行归因。
  static Future<bool> reportAttributionInfo({
    AdjustAttribution? attribution,
    bool forceReport = false,
  }) async {
    final running = _activeReport;
    if (running != null) {
      if (!forceReport) return running;
      // 多个强制上报共用待执行结果，仅保留最新归因。
      _pendingReport = () =>
          reportAttributionInfo(attribution: attribution, forceReport: true);
      return (_pendingReportCompleter ??= Completer<bool>()).future;
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    _forceReport = forceReport;
    if (forceReport) _failedCount = 0;
    _retryAction = () => _prepareAndReport(attribution: attribution);
    return _startAttempt();
  }

  static Future<bool> _prepareAndReport({
    AdjustAttribution? attribution,
  }) async {
    final config = _reportConfig!;
    final apiParameterNameModel = config.apiParameterNameModel;
    final apiUrl = config.apiUrl;
    final aesSecretKey = config.aesSecretKey;
    final aesIv = config.aesIv;
    final aesSctToken = config.aesSctToken;
    final packageName = config.packageName;
    final iosAppId = config.iosAppId;
    late AdjustAttribution newAttribution;
    String? adjustId;
    late String userId;
    String? appVersion;
    try {
      newAttribution = attribution ?? await Adjust.getAttribution();
      adjustId = await Adjust.getAdid();
      userId = await QsDeviceInfo.getUserId();
      appVersion = await QsDeviceInfo.getAppVersion();
    } catch (error) {
      QsLog.error("获取Adjust归因上报数据失败: $error");
      return false;
    }

    var parameters = {
      apiParameterNameModel.iosAppId: iosAppId,
      apiParameterNameModel.packageName: packageName,
      apiParameterNameModel.userId: userId,
      apiParameterNameModel.adjustAdid: adjustId,
      apiParameterNameModel.trackerToken: newAttribution.trackerToken ?? "",
      apiParameterNameModel.trackerName: newAttribution.trackerName ?? "",
      apiParameterNameModel.network: newAttribution.network ?? "",
      apiParameterNameModel.campaign: newAttribution.campaign ?? "",
      apiParameterNameModel.campaignId: "",
      apiParameterNameModel.adgroup: newAttribution.adgroup ?? "",
      apiParameterNameModel.adgroupId: "",
      apiParameterNameModel.creative: newAttribution.creative ?? "",
      apiParameterNameModel.creativeId: "",
      apiParameterNameModel.clickLabel: newAttribution.clickLabel ?? "",
      apiParameterNameModel.costType: newAttribution.costType ?? "",
      apiParameterNameModel.costAmount:
          newAttribution.costAmount?.toDouble() ?? 0.0,
      apiParameterNameModel.costCurrency: newAttribution.costCurrency ?? "",
      apiParameterNameModel.platform: "ios",
      apiParameterNameModel.appVersion: appVersion,
      apiParameterNameModel.rawData: _getRawData(newAttribution.jsonResponse),
    };

    QsLog.debug("Adjust Attribution params--------$parameters");

    final content = _myJsonEncode(parameters);
    if (content.isEmpty) {
      _retryAction = null;
      return false;
    }
    // JSON 或 AES 失败属于本地不可恢复错误，不启动后台重试。
    String encryptedParams;
    try {
      encryptedParams = QsAesEncrypt.encrypt(
        secretKey: aesSecretKey,
        iv: aesIv,
        content: content,
      );
    } catch (error) {
      QsLog.error("加密失败: $error");
      _retryAction = null;
      return false;
    }
    if (encryptedParams.isEmpty) {
      QsLog.error("加密失败");
      _retryAction = null;
      return false;
    }
    // 获取并加密成功后，补报仅保留密文和请求信息。
    _retryAction = () => _postEncryptedAttributionInfo(
      apiUrl: apiUrl,
      encryptedParams: encryptedParams,
      aesSctToken: aesSctToken,
    );
    return _retryAction!();
  }

  static Future<bool> _postEncryptedAttributionInfo({
    required String apiUrl,
    required String encryptedParams,
    required String aesSctToken,
  }) async {
    try {
      final response = await QsNetRequest.getInstance().postJson(
        apiUrl,
        parameters: {"data": encryptedParams},
        headers: {"sct": aesSctToken},
        isShowLoading: false,
        onError: (error) {
          QsLog.error("上传Adjust归因数据失败: ${error.message}");
        },
      );
      if (response?["code"] != 0) {
        QsLog.error("上传Adjust归因数据失败: ${response?["message"] ?? response}");
        return false;
      }
      QsLog.info("上传Adjust归因数据成功");
      return true;
    } catch (error) {
      QsLog.error("上传Adjust归因数据异常: $error");
      return false;
    }
  }

  static Future<bool> _startAttempt() {
    // 先登记 Future，再执行异步逻辑，合并同一进程内的并发调用。
    final completer = Completer<bool>();
    _activeReport = completer.future;
    unawaited(_completeAttempt(completer: completer));
    return completer.future;
  }

  static Future<void> _completeAttempt({
    required Completer<bool> completer,
  }) async {
    var success = false;
    try {
      switch (_initializationState) {
        case _QsAdjustInitializationState.notStarted:
        case _QsAdjustInitializationState.initializing:
          QsLog.info("Adjust尚未初始化，等待补报");
          return;
        case _QsAdjustInitializationState.notRequired:
          _retryAction = null;
          return;
        case _QsAdjustInitializationState.initialized:
          break;
      }
      if (!_forceReport && !_uploaded) {
        _uploaded =
            await QsStorageTool.getBool(key: _attributionDataUploadedKey) ==
            true;
      }
      success = (!_forceReport && _uploaded) || await _retryAction!();
      if (success) {
        _uploaded = true;
        _retryAction = null;
        _pendingReport = null;
        _failedCount = 0;
        try {
          final saved = await QsStorageTool.setBool(
            key: _attributionDataUploadedKey,
            value: true,
          );
          if (!saved) QsLog.error("Adjust归因上报成功标记保存失败");
        } catch (error) {
          QsLog.error("Adjust归因上报成功标记保存异常: $error");
        }
      }
    } catch (error) {
      QsLog.error("Adjust归因上报异常: $error");
    } finally {
      _activeReport = null;
      final pending = _pendingReport;
      final pendingCompleter = _pendingReportCompleter;
      _pendingReport = null;
      _pendingReportCompleter = null;
      if (pending != null &&
          _initializationState != _QsAdjustInitializationState.notRequired) {
        // 当前任务已结束，新任务可安全接管补报状态。
        pendingCompleter!.complete(pending());
      } else if (!success && _retryAction != null) {
        _failedCount++;
        _retryTimer = Timer(_retryDelay(failedCount: _failedCount), () {
          _retryTimer = null;
          unawaited(_startAttempt());
        });
      }
      if (pending == null && pendingCompleter != null) {
        pendingCompleter.complete(false);
      }
      completer.complete(success);
    }
  }

  static Duration _retryDelay({required int failedCount}) {
    const seconds = [2, 5, 10, 20, 40, 60];
    return Duration(seconds: seconds[(failedCount - 1).clamp(0, 5)]);
  }

  static dynamic _getRawData(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(value);
    } catch (error) {
      QsLog.error("归因数据解析失败: $error");
      return null;
    }
  }

  /// 自定义 JSON 编码
  static String _myJsonEncode(Object? params) {
    try {
      return jsonEncode(params);
    } catch (e) {
      QsLog.error("jsonEncode error: $e");
      return "";
    }
  }

  /// Properties
  static bool _skipAsaCheck = false;
  static QsAdjustReportConfig? _reportConfig;
  static bool _forceReport = false;
  static Future<bool> Function()? _pendingReport;
  static Completer<bool>? _pendingReportCompleter;
  static _QsAdjustInitializationState _initializationState =
      _QsAdjustInitializationState.notStarted;
  static int _initializationFailedCount = 0;
  static Timer? _initializationRetryTimer;
  static const String _attributionDataUploadedKey =
      "qs_adjust_attribution_info_report_success";
  static bool _uploaded = false;
  static int _failedCount = 0;
  static Future<bool>? _activeReport;
  static Future<bool> Function()? _retryAction;
  static Timer? _retryTimer;
}
