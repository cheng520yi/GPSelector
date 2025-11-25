import '../models/kline_data.dart';
import '../models/macd_data.dart';
import '../models/boll_data.dart';
import 'dart:math' as math;

/// 指标计算服务
/// 用于本地计算MACD和BOLL指标
class IndicatorCalculationService {
  /// 计算MACD指标
  /// 
  /// MACD计算公式：
  /// - EMA12 = 12日指数移动平均
  /// - EMA26 = 26日指数移动平均
  /// - DIF = EMA12 - EMA26
  /// - DEA = DIF的9日指数移动平均
  /// - MACD = (DIF - DEA) * 2
  /// 
  /// [klineDataList] K线数据列表（按时间正序排列）
  /// [tsCode] 股票代码
  /// 返回MACD数据列表
  static List<MacdData> calculateMACD(
    List<KlineData> klineDataList,
    String tsCode,
  ) {
    if (klineDataList.length < 26) {
      return [];
    }

    List<MacdData> macdDataList = [];

    // 计算EMA12和EMA26
    List<double> ema12List = _calculateEMA(klineDataList, 12);
    List<double> ema26List = _calculateEMA(klineDataList, 26);

    // 计算DIF = EMA12 - EMA26
    List<double> difList = [];
    for (int i = 0; i < klineDataList.length; i++) {
      if (i >= 25) { // 从第26个数据点开始有EMA26
        difList.add(ema12List[i] - ema26List[i]);
      } else {
        difList.add(0.0);
      }
    }

    // 计算DEA = DIF的9日指数移动平均
    List<double> deaList = _calculateEMAFromValues(difList, 9);

    // 计算MACD = (DIF - DEA) * 2
    for (int i = 0; i < klineDataList.length; i++) {
      if (i >= 33) { // 从第34个数据点开始有完整的MACD值（26+9-1=34）
        final dif = difList[i];
        final dea = deaList[i];
        final macd = (dif - dea) * 2;

        macdDataList.add(MacdData(
          tsCode: tsCode,
          tradeDate: klineDataList[i].tradeDate,
          dif: dif,
          dea: dea,
          macd: macd,
        ));
      }
    }

    return macdDataList;
  }

  /// 计算BOLL指标
  /// 
  /// BOLL计算公式：
  /// - 中轨(MID) = N日移动平均线（通常N=20）
  /// - 标准差 = N日收盘价的标准差
  /// - 上轨(UP) = 中轨 + K * 标准差（通常K=2）
  /// - 下轨(LOW) = 中轨 - K * 标准差
  /// 
  /// [klineDataList] K线数据列表（按时间正序排列）
  /// [tsCode] 股票代码
  /// [period] 周期，默认20
  /// [stdDev] 标准差倍数，默认2
  /// 返回BOLL数据列表
  static List<BollData> calculateBOLL(
    List<KlineData> klineDataList,
    String tsCode, {
    int period = 20,
    double stdDev = 2.0,
  }) {
    if (klineDataList.length < period) {
      return [];
    }

    List<BollData> bollDataList = [];

    for (int i = period - 1; i < klineDataList.length; i++) {
      // 获取最近period天的收盘价
      final prices = klineDataList
          .sublist(i - period + 1, i + 1)
          .map((e) => e.close)
          .toList();

      // 计算中轨（移动平均）
      final middle = prices.reduce((a, b) => a + b) / period;

      // 计算标准差
      final variance = prices
          .map((price) => math.pow(price - middle, 2))
          .reduce((a, b) => a + b) /
          period;
      final standardDeviation = math.sqrt(variance);

      // 计算上轨和下轨
      final upper = middle + stdDev * standardDeviation;
      final lower = middle - stdDev * standardDeviation;

      bollDataList.add(BollData(
        tsCode: tsCode,
        tradeDate: klineDataList[i].tradeDate,
        upper: upper,
        middle: middle,
        lower: lower,
      ));
    }

    return bollDataList;
  }

  /// 计算指数移动平均（EMA）
  /// 
  /// EMA计算公式：
  /// EMA(today) = (Price(today) * 2 / (N + 1)) + (EMA(yesterday) * (N - 1) / (N + 1))
  /// 
  /// [klineDataList] K线数据列表
  /// [period] 周期
  /// 返回EMA值列表
  static List<double> _calculateEMA(List<KlineData> klineDataList, int period) {
    List<double> emaList = [];
    double multiplier = 2.0 / (period + 1);

    for (int i = 0; i < klineDataList.length; i++) {
      if (i == 0) {
        // 第一个值使用收盘价
        emaList.add(klineDataList[i].close);
      } else {
        // EMA = (Price * multiplier) + (Previous EMA * (1 - multiplier))
        final ema = (klineDataList[i].close * multiplier) +
            (emaList[i - 1] * (1 - multiplier));
        emaList.add(ema);
      }
    }

    return emaList;
  }

  /// 从数值列表计算EMA
  /// 
  /// [values] 数值列表
  /// [period] 周期
  /// 返回EMA值列表
  static List<double> _calculateEMAFromValues(List<double> values, int period) {
    List<double> emaList = [];
    double multiplier = 2.0 / (period + 1);

    for (int i = 0; i < values.length; i++) {
      if (i == 0) {
        emaList.add(values[i]);
      } else {
        final ema = (values[i] * multiplier) + (emaList[i - 1] * (1 - multiplier));
        emaList.add(ema);
      }
    }

    return emaList;
  }
}

