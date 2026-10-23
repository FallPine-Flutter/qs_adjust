import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'qs_adjust_method_channel.dart';

abstract class QsAdjustPlatform extends PlatformInterface {
  /// Constructs a QsAdjustPlatform.
  QsAdjustPlatform() : super(token: _token);

  static final Object _token = Object();

  static QsAdjustPlatform _instance = MethodChannelQsAdjust();

  /// The default instance of [QsAdjustPlatform] to use.
  ///
  /// Defaults to [MethodChannelQsAdjust].
  static QsAdjustPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [QsAdjustPlatform] when
  /// they register themselves.
  static set instance(QsAdjustPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }
}
