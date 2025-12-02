import 'package:flutter/material.dart';
import '../screens/stock_selector_screen.dart';

/// 筛选页面单例管理器
/// 使用GlobalKey保持筛选页面状态，实现单例效果
class StockSelectorSingleton {
  static final StockSelectorSingleton _instance = StockSelectorSingleton._internal();
  factory StockSelectorSingleton() => _instance;
  StockSelectorSingleton._internal();

  // 使用GlobalKey保持筛选页面状态
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  static final GlobalKey<State<StockSelectorScreen>> _screenKey = GlobalKey<State<StockSelectorScreen>>();

  /// 获取Navigator Key
  GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;
  
  /// 获取Screen Key
  static GlobalKey<State<StockSelectorScreen>> get screenKey => _screenKey;

  /// 创建或获取筛选页面实例
  static Widget getFilterScreen() {
    return StockSelectorScreen(key: _screenKey);
  }
  
  /// 导航到筛选页面（单例）
  static Future<dynamic> navigateToFilterScreen(BuildContext context) {
    // 使用单例导航，保持筛选页面状态
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => getFilterScreen(),
        settings: const RouteSettings(name: '/stock_selector'),
      ),
    );
  }
}

