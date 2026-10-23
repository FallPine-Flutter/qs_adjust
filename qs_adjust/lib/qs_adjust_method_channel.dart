import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'qs_adjust_platform_interface.dart';

/// An implementation of [QsAdjustPlatform] that uses method channels.
class MethodChannelQsAdjust extends QsAdjustPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('qs_adjust');
}
