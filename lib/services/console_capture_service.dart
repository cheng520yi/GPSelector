import 'dart:developer' as developer;
import 'log_service.dart';

/// 控制台输出捕获服务
class ConsoleCaptureService {
  static final ConsoleCaptureService _instance = ConsoleCaptureService._internal();
  factory ConsoleCaptureService() => _instance;
  ConsoleCaptureService._internal();

  static ConsoleCaptureService get instance => _instance;
  
  final LogService _logService = LogService.instance;
  bool _isCapturing = false;

  /// 开始捕获控制台输出
  void startCapture() {
    if (_isCapturing) return;
    
    _isCapturing = true;
    developer.log('开始捕获控制台输出', name: 'ConsoleCapture');
    
    // 由于无法重写全局print函数，我们提供一个替代方案
    // 在需要记录控制台输出的地方调用capturePrint方法
  }

  /// 停止捕获控制台输出
  void stopCapture() {
    if (!_isCapturing) return;
    
    _isCapturing = false;
    developer.log('停止捕获控制台输出', name: 'ConsoleCapture');
  }

  /// 手动捕获print输出
  void capturePrint(String message) {
    if (!_isCapturing) return;
    
    // 记录到日志服务
    _logService.addConsoleOutput(message);
  }

  /// 是否正在捕获
  bool get isCapturing => _isCapturing;
}
