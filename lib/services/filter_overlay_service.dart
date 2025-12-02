import 'package:flutter/material.dart';
import '../models/stock_ranking.dart';
import '../services/condition_combination_service.dart';
import '../screens/stock_selector_screen.dart';
import 'stock_selector_singleton.dart';

/// 筛选浮窗服务
/// 管理全局筛选进度浮窗
class FilterOverlayService {
  static final FilterOverlayService _instance = FilterOverlayService._internal();
  factory FilterOverlayService() => _instance;
  FilterOverlayService._internal();

  OverlayEntry? _overlayEntry;
  BuildContext? _context;
  bool _isShowing = false;
  
  // 浮窗位置
  Offset _position = const Offset(300, 600);
  
  // 导航回调
  VoidCallback? _onNavigateCallback;

  // 筛选进度回调
  Function(int current, int total)? _onProgress;
  Function(List<StockRanking>)? _onComplete;
  Function(String)? _onError;
  
  // 筛选状态
  String _progressText = '开始筛选...';
  int _currentIndex = 0;
  int _totalStocks = 0;
  ConditionCombination? _currentCombination;
  bool _isFiltering = false; // 是否正在筛选

  /// 显示筛选浮窗
  void showOverlay(
    BuildContext context, {
    required ConditionCombination combination,
    Function(int current, int total)? onProgress,
    Function(List<StockRanking>)? onComplete,
    Function(String)? onError,
  }) {
    if (_isShowing) {
      return;
    }

    _context = context;
    _currentCombination = combination;
    _onProgress = onProgress;
    _onComplete = onComplete;
    _onError = onError;
    _progressText = '开始筛选...';
    _currentIndex = 0;
    _totalStocks = 0;
    _isFiltering = true;
    
    // 初始化位置（屏幕右下角）
    final screenSize = MediaQuery.of(context).size;
    _position = Offset(screenSize.width - 60, screenSize.height - 140);

    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    _isShowing = true;
  }

  /// 更新筛选进度
  void updateProgress(String text, int current, int total) {
    _progressText = text;
    _currentIndex = current;
    _totalStocks = total;
    
    // 通知外部进度回调
    _onProgress?.call(current, total);
    
    // 同步更新筛选页面状态（如果存在）- 无论浮窗是否显示都要更新
    final screenState = StockSelectorSingleton.screenKey.currentState;
    if (screenState != null) {
      try {
        (screenState as dynamic).updateFilterProgress(text, current, total);
      } catch (e) {
        // 忽略错误
        print('更新筛选进度失败: $e');
      }
    }

    // 更新浮窗（如果显示）
    if (_isShowing && _overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }


  /// 筛选出错
  void error(String errorMessage) {
    _isFiltering = false;
    
    // 更新筛选页面状态（如果存在）
    final screenState = StockSelectorSingleton.screenKey.currentState;
    if (screenState != null) {
      try {
        (screenState as dynamic).restoreFilterError(errorMessage);
      } catch (e) {
        print('恢复筛选错误状态失败: $e');
      }
    }
    
    if (!_isShowing) return;

    _progressText = '筛选失败: $errorMessage';
    
    // 通知外部错误回调
    _onError?.call(errorMessage);
  }

  /// 隐藏浮窗
  void hideOverlay() {
    if (!_isShowing || _overlayEntry == null) return;
    
    // 如果正在筛选，不要隐藏浮窗
    if (_isFiltering) {
      print('⚠️ 正在筛选中，不隐藏浮窗');
      return;
    }

    _overlayEntry!.remove();
    _overlayEntry = null;
    _isShowing = false;
    _context = null;
    _onProgress = null;
    _onComplete = null;
    _onError = null;
    _currentCombination = null;
    _onNavigateCallback = null;
  }
  
  /// 是否正在筛选
  bool get isFiltering => _isFiltering;

  /// 是否正在显示
  bool get isShowing => _isShowing;

  /// 获取当前上下文（用于导航）
  BuildContext? get context => _context;
  
  /// 获取当前进度文本
  String get progressText => _progressText;
  
  /// 获取当前索引
  int get currentIndex => _currentIndex;
  
  /// 获取总股票数
  int get totalStocks => _totalStocks;
  
  /// 获取当前筛选条件组合（供外部访问）
  ConditionCombination? get currentCombination => _currentCombination;

  /// 创建浮窗Entry（圆形可拖动）
  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) {
        final screenSize = MediaQuery.of(context).size;
        // 限制位置在屏幕范围内
        final clampedX = _position.dx.clamp(40.0, screenSize.width - 40.0);
        final clampedY = _position.dy.clamp(100.0, screenSize.height - 100.0);
        final position = Offset(clampedX, clampedY);
        
        return Positioned(
          left: position.dx - 40,
          top: position.dy - 40,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {
                // 点击浮窗返回筛选页面
                _navigateToFilterScreen(context);
              },
              onPanUpdate: (details) {
                // 拖动浮窗
                final newX = _position.dx + details.delta.dx;
                final newY = _position.dy + details.delta.dy;
                _position = Offset(
                  newX.clamp(40.0, screenSize.width - 40.0),
                  newY.clamp(100.0, screenSize.height - 100.0),
                );
                _overlayEntry?.markNeedsBuild();
              },
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.blue[600],
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.filter_list,
                      color: Colors.white,
                      size: 28,
                    ),
                    if (_totalStocks > 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          value: _currentIndex / _totalStocks,
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          backgroundColor: Colors.white.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  

  /// 筛选结果存储
  List<StockRanking>? _lastFilterResult;

  /// 设置导航回调
  void setNavigateCallback(VoidCallback callback) {
    _onNavigateCallback = callback;
  }
  
  /// 获取筛选结果
  List<StockRanking>? getLastFilterResult() {
    return _lastFilterResult;
  }

  /// 导航到筛选页面
  void _navigateToFilterScreen([BuildContext? context]) {
    // 优先使用传入的context，如果没有则使用保存的context
    BuildContext? ctx = context ?? _context;
    
    // 如果context无效，尝试从Navigator获取
    if (ctx == null || !ctx.mounted) {
      // 尝试从全局获取context
      final navigatorKey = StockSelectorSingleton().navigatorKey;
      if (navigatorKey.currentContext != null) {
        ctx = navigatorKey.currentContext;
      }
    }
    
    // 如果还是无效，尝试从浮窗的context获取
    if ((ctx == null || !ctx.mounted) && _context != null) {
      try {
        // 尝试从浮窗的Overlay context获取Navigator
        final overlayContext = _context;
        if (overlayContext != null && overlayContext.mounted) {
          ctx = overlayContext;
        }
      } catch (e) {
        print('获取context失败: $e');
      }
    }
    
    if (ctx == null || !ctx.mounted) {
      print('⚠️ 无法获取有效的context进行导航');
      return;
    }
    
    // 不要隐藏浮窗，保持显示
    // hideOverlay();
    
    // 使用单例导航到筛选页面（确保使用正确的context）
    Future.microtask(() {
      if (ctx != null && ctx.mounted) {
        StockSelectorSingleton.navigateToFilterScreen(ctx).then((_) {
          // 导航完成后，延迟恢复筛选页面状态（确保页面已经构建完成）
          Future.delayed(const Duration(milliseconds: 500), () {
            _restoreFilterScreenState();
          });
        });
      }
    });
  }
  
  /// 恢复筛选页面状态
  void _restoreFilterScreenState() {
    final screenState = StockSelectorSingleton.screenKey.currentState;
    if (screenState != null && _isFiltering) {
      try {
        // 恢复筛选状态
        (screenState as dynamic).restoreFilteringState(
          progressText: _progressText,
          currentIndex: _currentIndex,
          totalStocks: _totalStocks,
          combination: _currentCombination,
        );
      } catch (e) {
        print('恢复筛选页面状态失败: $e');
      }
    }
  }
  
  /// 完成筛选时保存结果
  void complete(List<StockRanking> rankings) {
    _lastFilterResult = rankings;
    _isFiltering = false;
    
    _progressText = '筛选完成！共找到 ${rankings.length} 只符合条件的股票';
    _currentIndex = _totalStocks;
    
    // 更新筛选页面状态（如果存在）
    final screenState = StockSelectorSingleton.screenKey.currentState;
    if (screenState != null) {
      // 通过动态调用恢复结果（避免循环依赖）
      try {
        // 使用反射或直接调用方法
        // 由于State类是私有的，我们通过接口来调用
        (screenState as dynamic).restoreFilterResult(rankings);
      } catch (e) {
        // 如果调用失败，忽略（页面可能已销毁）
        print('恢复筛选结果失败: $e');
      }
    }
    
    // 通知外部完成回调
    _onComplete?.call(rankings);
    
    if (!_isShowing) return;

    // 更新浮窗显示
    _overlayEntry?.markNeedsBuild();

    // 延迟关闭浮窗（如果用户没有点击进入筛选页面）
    // 注意：筛选完成后，_isFiltering已经是false，所以可以隐藏
    Future.delayed(const Duration(seconds: 3), () {
      // 只有在浮窗仍然显示且筛选已完成时才关闭
      if (_isShowing && !_isFiltering) {
        hideOverlay();
      }
    });
  }
}

