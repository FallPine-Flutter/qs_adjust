import 'package:flutter_test/flutter_test.dart';
import 'package:qs_adjust/qs_adjust_platform_interface.dart';
import 'package:qs_adjust/qs_adjust_method_channel.dart';

void main() {
  final QsAdjustPlatform initialPlatform = QsAdjustPlatform.instance;

  test('$MethodChannelQsAdjust is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelQsAdjust>());
  });
}
