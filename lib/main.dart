import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/log_service.dart';
import 'services/console_capture_service.dart';

void main() {
  // 添加一些测试日志
  final logService = LogService.instance;
  logService.info('APP', '应用程序启动');
  logService.info('APP', '开始初始化服务');
  
  // 启动控制台捕获服务
  ConsoleCaptureService.instance.startCapture();
  
  // 添加一些控制台输出测试
  print('🚀 应用程序启动中...');
  print('📱 正在初始化股票筛选器');
  print('✅ 初始化完成');
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '股票筛选器',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
