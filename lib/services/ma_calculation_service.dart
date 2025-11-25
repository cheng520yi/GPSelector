import '../models/kline_data.dart';

class MaCalculationService {
  // 计算5日均线
  static double calculateMA5(List<KlineData> klineDataList) {
    if (klineDataList.length < 5) {
      return 0.0;
    }
    
    // 取最近5天的收盘价（数据已按时间排序，最后5个是最新的）
    final recent5Days = klineDataList.reversed.take(5).toList();
    final sum = recent5Days.fold(0.0, (sum, kline) => sum + kline.close);
    return sum / 5;
  }

  // 计算10日均线
  static double calculateMA10(List<KlineData> klineDataList) {
    if (klineDataList.length < 10) {
      return 0.0;
    }
    
    // 取最近10天的收盘价（数据已按时间排序，最后10个是最新的）
    final recent10Days = klineDataList.reversed.take(10).toList();
    final sum = recent10Days.fold(0.0, (sum, kline) => sum + kline.close);
    return sum / 10;
  }

  // 计算20日均线
  static double calculateMA20(List<KlineData> klineDataList) {
    if (klineDataList.length < 20) {
      return 0.0;
    }
    
    // 取最近20天的收盘价（数据已按时间排序，最后20个是最新的）
    final recent20Days = klineDataList.reversed.take(20).toList();
    final sum = recent20Days.fold(0.0, (sum, kline) => sum + kline.close);
    return sum / 20;
  }

  // 计算价格距离均线的百分比（已废弃，使用calculateMaDistance）
  static double calculateDistanceToMAInPoints(double currentPrice, double ma) {
    return calculateMaDistance(currentPrice, ma);
  }

  /// 计算均线偏离百分比
  /// 以均线为基准，计算当前价格与均线的偏离的绝对值
  /// 
  /// 公式：偏离百分比 = |(当前价格 - 均线) / 均线| * 100
  /// 
  /// 示例：
  /// - 当前价格 = 10元，均线 = 8元，偏离 = |(10-8)/8| * 100 = 25%
  /// - 当前价格 = 8元，均线 = 10元，偏离 = |(8-10)/10| * 100 = 20%
  /// 
  /// [currentPrice] 当前价格
  /// [ma] 均线值（作为基准）
  /// 返回偏离百分比（绝对值，单位：%）
  static double calculateMaDistance(double currentPrice, double ma) {
    // 如果均线为0，无法计算偏离，返回0
    if (ma == 0 || ma.isNaN || ma.isInfinite) {
      return 0.0;
    }
    
    // 如果当前价格为0或无效值，返回0
    if (currentPrice == 0 || currentPrice.isNaN || currentPrice.isInfinite) {
      return 0.0;
    }
    
    // 以均线为基准，计算偏离百分比：|(当前价格 - 均线) / 均线| * 100
    final deviation = (currentPrice - ma) / ma;
    final deviationPercent = deviation.abs() * 100;
    
    return deviationPercent;
  }

  // 检查是否满足均线距离条件（百分比）
  static bool checkMaDistanceCondition(
    double currentPrice,
    double ma5,
    double ma10,
    double ma20,
    double ma5Distance,
    double ma10Distance,
    double ma20Distance,
    String stockName, // 添加股票名称参数用于日志输出
  ) {
    final distance5 = calculateDistanceToMAInPoints(currentPrice, ma5);
    final distance10 = calculateDistanceToMAInPoints(currentPrice, ma10);
    final distance20 = calculateDistanceToMAInPoints(currentPrice, ma20);

    // 检查是否在指定K线点数范围内
    final meetsCondition = distance5 <= ma5Distance &&
           distance10 <= ma10Distance &&
           distance20 <= ma20Distance;
    
    // 无论是否满足条件，都显示每个均线的偏离百分数
    if (meetsCondition) {
      print('✅ ${stockName}满足均线距离条件 (价格: ${currentPrice.toStringAsFixed(2)}, MA5偏离: ${distance5.toStringAsFixed(2)}%, MA10偏离: ${distance10.toStringAsFixed(2)}%, MA20偏离: ${distance20.toStringAsFixed(2)}%)');
    } else {
      print('❌ ${stockName}不满足均线距离条件 (价格: ${currentPrice.toStringAsFixed(2)}, MA5偏离: ${distance5.toStringAsFixed(2)}%, MA10偏离: ${distance10.toStringAsFixed(2)}%, MA20偏离: ${distance20.toStringAsFixed(2)}%)');
    }

    return meetsCondition;
  }

  // 基于特定日期计算20日均线（用于历史数据检查）
  static double calculateMA20ForDate(List<KlineData> klineDataList, int targetIndex) {
    if (klineDataList.length < 20 || targetIndex < 19) {
      return 0.0;
    }
    
    // 取目标日期之前20个交易日的收盘价
    // klineDataList是按时间正序排列的，所以targetIndex是目标日期
    // 我们需要取[targetIndex-19]到[targetIndex]这20天的数据
    final startIndex = targetIndex - 19;
    final endIndex = targetIndex;
    
    double sum = 0.0;
    for (int i = startIndex; i <= endIndex; i++) {
      sum += klineDataList[i].close;
    }
    
    return sum / 20;
  }

  // 检查连续N天收盘价高于20日线
  static bool checkConsecutiveDaysAboveMA20(
    List<KlineData> klineDataList,
    int consecutiveDays,
    int startIndex, // 开始检查的日期索引
  ) {
    if (klineDataList.length < 20 || startIndex < consecutiveDays) {
      print('   ⚠️ 数据不足: 总数据${klineDataList.length}天, 需要${consecutiveDays}天');
      return false;
    }
    
    // 检查连续N天，从startIndex开始往前检查
    for (int i = 0; i < consecutiveDays; i++) {
      final checkIndex = startIndex - i;
      if (checkIndex < 19) {
        print('   ❌ 数据不足: 无法计算20日均线');
        return false; // 数据不足
      }
      
      // 计算该日期的20日均线
      final ma20 = calculateMA20ForDate(klineDataList, checkIndex);
      final closePrice = klineDataList[checkIndex].close;
      
      if (closePrice <= ma20) {
        print('   ❌ 第${i + 1}天收盘价${closePrice.toStringAsFixed(2)} <= 20日线${ma20.toStringAsFixed(2)}');
        return false;
      }
    }
    
    print('   ✅ 连续${consecutiveDays}天收盘价高于20日线');
    return true;
  }
}
