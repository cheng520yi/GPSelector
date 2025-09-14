/// 批量请求优化器
/// 根据数据量和API类型智能调整分组大小和延时策略
class BatchOptimizer {
  /// 根据股票总数和API类型计算最优分组大小
  static int getOptimalBatchSize(int totalStocks, String apiType) {
    switch (apiType) {
      case 'daily':
        // 日线数据：相对简单，可以使用较大的分组
        if (totalStocks <= 50) return 25;
        if (totalStocks <= 100) return 20;
        if (totalStocks <= 300) return 15;
        if (totalStocks <= 500) return 12;
        return 10;
        
      case 'historical':
        // 历史数据：数据量大，使用较小的分组
        if (totalStocks <= 30) return 15;
        if (totalStocks <= 50) return 12;
        if (totalStocks <= 100) return 10;
        if (totalStocks <= 200) return 8;
        return 6;
        
      case 'market_value':
        // 市值数据：相对简单，可以使用较大的分组
        if (totalStocks <= 50) return 30;
        if (totalStocks <= 100) return 25;
        if (totalStocks <= 300) return 20;
        if (totalStocks <= 500) return 15;
        return 12;
        
      default:
        // 默认策略
        if (totalStocks <= 50) return 20;
        if (totalStocks <= 100) return 15;
        if (totalStocks <= 300) return 12;
        if (totalStocks <= 500) return 10;
        return 8;
    }
  }
  
  /// 根据分组大小计算最优延时
  static Duration getOptimalDelay(int batchSize) {
    if (batchSize >= 25) return const Duration(milliseconds: 150);  // 大分组，短延时
    if (batchSize >= 20) return const Duration(milliseconds: 200);  // 中大分组
    if (batchSize >= 15) return const Duration(milliseconds: 250);  // 中分组
    if (batchSize >= 10) return const Duration(milliseconds: 300);  // 小分组
    if (batchSize >= 8) return const Duration(milliseconds: 350);   // 更小分组
    return const Duration(milliseconds: 400);                       // 最小分组，最长延时
  }
  
  /// 计算总预估时间（用于进度显示）
  static Duration estimateTotalTime(int totalStocks, String apiType) {
    final batchSize = getOptimalBatchSize(totalStocks, apiType);
    final delay = getOptimalDelay(batchSize);
    final batchCount = (totalStocks / batchSize).ceil();
    
    // 预估：每批请求时间 + 延时时间
    final estimatedRequestTime = Duration(milliseconds: batchCount * 500); // 假设每批请求500ms
    final totalDelayTime = Duration(milliseconds: (batchCount - 1) * delay.inMilliseconds);
    
    return estimatedRequestTime + totalDelayTime;
  }
  
  /// 获取性能优化建议
  static Map<String, dynamic> getOptimizationInfo(int totalStocks, String apiType) {
    final batchSize = getOptimalBatchSize(totalStocks, apiType);
    final delay = getOptimalDelay(batchSize);
    final batchCount = (totalStocks / batchSize).ceil();
    final estimatedTime = estimateTotalTime(totalStocks, apiType);
    
    return {
      'batchSize': batchSize,
      'delay': delay.inMilliseconds,
      'batchCount': batchCount,
      'estimatedTime': estimatedTime.inSeconds,
      'optimization': _getOptimizationLevel(totalStocks, batchCount),
    };
  }
  
  /// 获取优化级别
  static String _getOptimizationLevel(int totalStocks, int batchCount) {
    if (totalStocks <= 50) return '高效';
    if (totalStocks <= 100) return '良好';
    if (totalStocks <= 300) return '一般';
    if (totalStocks <= 500) return '较慢';
    return '需要优化';
  }
}
