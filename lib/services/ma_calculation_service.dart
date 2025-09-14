import '../models/kline_data.dart';
import 'dart:math' as math;

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
      print('⚠️ 数据不足，需要至少20个交易日，当前只有${klineDataList.length}个');
      return 0.0;
    }
    
    // 取最近20天的收盘价（数据已按时间排序，最后20个是最新的）
    final recent20Days = klineDataList.reversed.take(20).toList();
    final sum = recent20Days.fold(0.0, (sum, kline) => sum + kline.close);
    final ma20 = sum / 20;
    
    print('📊 20日均线计算详情:');
    print('   数据总数: ${klineDataList.length}个交易日');
    print('   计算范围: 最近20个交易日');
    print('   20日线值: ${ma20.toStringAsFixed(2)}');
    print('   前5个交易日收盘价:');
    for (int i = 0; i < math.min(5, recent20Days.length); i++) {
      print('     ${recent20Days[i].tradeDate}: ${recent20Days[i].close.toStringAsFixed(2)}');
    }
    
    return ma20;
  }

  // 计算价格距离均线的百分比
  static double calculateDistanceToMAInPoints(double currentPrice, double ma) {
    if (ma == 0) return 0.0;
    // 计算百分比距离：(当前价格 - 均线) / 均线 * 100
    return ((currentPrice - ma) / ma * 100).abs();
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
  ) {
    final distance5 = calculateDistanceToMAInPoints(currentPrice, ma5);
    final distance10 = calculateDistanceToMAInPoints(currentPrice, ma10);
    final distance20 = calculateDistanceToMAInPoints(currentPrice, ma20);

    // 检查是否在指定K线点数范围内
    return distance5 <= ma5Distance &&
           distance10 <= ma10Distance &&
           distance20 <= ma20Distance;
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
      print('   ⚠️ 数据不足: 总数据${klineDataList.length}天, 需要${consecutiveDays}天, 起始索引${startIndex}');
      return false;
    }
    
    print('   🔍 开始检查连续${consecutiveDays}天收盘价高于20日线条件...');
    print('   📊 数据范围: 从索引${startIndex - consecutiveDays + 1}到${startIndex}');
    
    // 检查连续N天，从startIndex开始往前检查
    for (int i = 0; i < consecutiveDays; i++) {
      final checkIndex = startIndex - i;
      if (checkIndex < 19) {
        print('   ❌ 数据不足: 检查索引${checkIndex} < 19，无法计算20日均线');
        return false; // 数据不足
      }
      
      // 计算该日期的20日均线
      final ma20 = calculateMA20ForDate(klineDataList, checkIndex);
      final closePrice = klineDataList[checkIndex].close;
      
      print('   📈 检查第${i + 1}个交易日 ${klineDataList[checkIndex].tradeDate}:');
      print('     收盘价=${closePrice.toStringAsFixed(2)}, 20日线=${ma20.toStringAsFixed(2)}');
      print('     计算范围: 索引${checkIndex - 19}到${checkIndex} (共20天)');
      
      if (closePrice <= ma20) {
        print('   ❌ 第${i + 1}个交易日收盘价${closePrice.toStringAsFixed(2)} <= 20日线${ma20.toStringAsFixed(2)}');
        return false;
      } else {
        print('   ✅ 第${i + 1}个交易日收盘价${closePrice.toStringAsFixed(2)} > 20日线${ma20.toStringAsFixed(2)}');
      }
    }
    
    print('   🎉 所有${consecutiveDays}天都满足条件！');
    return true;
  }
}
