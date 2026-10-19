import 'package:flutter/services.dart';

class DlibService {
  static const MethodChannel _channel = MethodChannel('com.faskes.frista.frista_mobile/dlib');

  static bool _initialized = false;

  static Future<bool> init() async {
    if (_initialized) return true;
    try {
      final result = await _channel.invokeMethod<bool>('init');
      _initialized = result ?? false;
      return _initialized;
    } catch (e) {
      return false;
    }
  }

  static Future<List<double>?> computeDescriptor(
    Uint8List jpegBytes, {
    int left = 0,
    int top = 0,
    int right = 0,
    int bottom = 0,
  }) async {
    try {
      await init();
      final result = await _channel.invokeMethod<List<dynamic>>(
        'computeDescriptor',
        {
          'bytes': jpegBytes,
          'left': left,
          'top': top,
          'right': right,
          'bottom': bottom,
        },
      );
      if (result != null) {
        return result.map((e) => (e as num).toDouble()).toList();
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
