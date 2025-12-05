import 'package:intl/intl.dart';
import '../models/stock_ranking.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../models/boll_data.dart';
import '../models/macd_data.dart';
import '../services/stock_api_service.dart';
import '../services/ranking_config_service.dart';
import '../services/stock_pool_service.dart';
import 'dart:math' as math;

/// 股票排名服务
class StockRankingService {
  /// 计算股票排名
  /// [rankings] 筛选后的股票列表
  /// [selectedDate] 筛选日期
  /// [useRealtimeInterface] 是否使用实时接口
  /// 返回带评分的排名列表
  static Future<List<RankedStock>> calculateRankings(
    List<StockRanking> rankings,
    DateTime selectedDate, {
    bool useRealtimeInterface = false,
  }) async {
    // 加载评分配置
    final config = await RankingConfigService.getConfig();
    
    // 获取所有股票的市值数据
    final tsCodes = rankings.map((r) => r.stockInfo.tsCode).toList();
    final marketValueMap = await StockPoolService.getBatchMarketValueData(
      tsCodes: tsCodes,
      targetDate: selectedDate,
    );
    
    // 计算每个股票的评分
    List<RankedStock> rankedStocks = [];
    
    for (final ranking in rankings) {
      final tsCode = ranking.stockInfo.tsCode;
      final marketValue = marketValueMap[tsCode] ?? 0.0;
      
      // 计算市值评分
      final marketValueScore = _calculateMarketValueScore(marketValue, config);
      
      // 计算BOLL偏离评分
        final bollResult = await _calculateBollDeviationScore(
          ranking,
          selectedDate,
          useRealtimeInterface,
          config,
        );
        final bollDeviationScore = bollResult['score'] as int;
        final bollDeviation = bollResult['deviation'] as double?;
        
        // 计算MACD评分
        final macdScore = await _calculateMacdScore(
          ranking,
          selectedDate,
          useRealtimeInterface,
          config,
        );
        
        final totalScore = marketValueScore + bollDeviationScore + macdScore;
        
        rankedStocks.add(RankedStock(
          stockRanking: ranking,
          marketValue: marketValue,
          marketValueScore: marketValueScore,
          bollDeviation: bollDeviation,
          bollDeviationScore: bollDeviationScore,
          macdScore: macdScore,
          totalScore: totalScore,
          rank: 0, // 临时值，排序后会重新分配
        ));
    }
    
    // 按总分排序
    rankedStocks.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    
    // 重新分配排名
    for (int i = 0; i < rankedStocks.length; i++) {
      rankedStocks[i] = rankedStocks[i].copyWith(rank: i + 1);
    }
    
    return rankedStocks;
  }
  
  /// 计算市值评分
  static int _calculateMarketValueScore(double marketValue, RankingConfig config) {
    for (final range in config.marketValueRanges) {
      if (marketValue >= range.min && (range.max == double.infinity || marketValue < range.max)) {
        return range.score;
      }
    }
    return 0;
  }
  
  /// 计算BOLL偏离评分
  /// 返回Map包含score和deviation
  static Future<Map<String, dynamic>> _calculateBollDeviationScore(
    StockRanking ranking,
    DateTime selectedDate,
    bool useRealtimeInterface,
    RankingConfig config,
  ) async {
    try {
      final tsCode = ranking.stockInfo.tsCode;
      final selectedDateStr = DateFormat('yyyyMMdd').format(selectedDate);
      
      double? currentPrice;
      double? bollMiddle;
      
      if (useRealtimeInterface) {
        // 实时接口：使用实时价格与前一个交易日的BOLL中轨比较
        // 获取实时价格
        final realtimeDataMap = await StockApiService.getIFinDRealTimeData(
          tsCodes: [tsCode],
        );
        if (realtimeDataMap.containsKey(tsCode)) {
          currentPrice = realtimeDataMap[tsCode]!.close;
        }
        
        // 获取前一个交易日的BOLL数据
        final prevTradingDate = _getPreviousTradingDay(selectedDate);
        final prevTradingDateStr = DateFormat('yyyyMMdd').format(prevTradingDate);
        
        // 获取BOLL数据
        final factorData = await StockApiService.getFactorProData(
          tsCode: tsCode,
          startDate: prevTradingDateStr,
          endDate: prevTradingDateStr,
        );
        
        final bollList = factorData['boll'] as List? ?? [];
        if (bollList.isNotEmpty) {
          final bollData = bollList.first;
          if (bollData is BollData) {
            bollMiddle = bollData.middle;
          }
        }
      } else {
        // 非实时接口：使用当天价格与当天BOLL中轨比较
        currentPrice = ranking.klineData.close;
        
        // 获取当天的BOLL数据
        final factorData = await StockApiService.getFactorProData(
          tsCode: tsCode,
          startDate: selectedDateStr,
          endDate: selectedDateStr,
        );
        
        final bollList = factorData['boll'] as List? ?? [];
        if (bollList.isNotEmpty) {
          final bollData = bollList.first;
          if (bollData is BollData) {
            bollMiddle = bollData.middle;
          }
        }
      }
      
      // 计算偏离值
      if (currentPrice != null && bollMiddle != null && bollMiddle > 0) {
        final deviation = ((currentPrice - bollMiddle) / bollMiddle * 100).abs();
        
        // 根据偏离值计算评分
        for (final range in config.bollDeviationRanges) {
          if (deviation >= range.min && (range.max == double.infinity || deviation < range.max)) {
            return {
              'score': range.score,
              'deviation': deviation,
            };
          }
        }
        
        // 如果没有匹配的范围，返回0分但保留偏离值
        return {
          'score': 0,
          'deviation': deviation,
        };
      }
    } catch (e) {
      print('计算BOLL偏离评分失败: ${ranking.stockInfo.name} - $e');
    }
    
    return {
      'score': 0,
      'deviation': null,
    };
  }
  
  /// 计算MACD评分
  /// 规则：
  /// 1. m值为正（macd > 0）
  /// 2. m值后一天比前一天高（需要获取前一个交易日的数据）
  /// 3. DIF大于M值（dif > macd）
  /// 3项全部满足：5分，满足2项：3分，满足1项：1分，一项不满足：0分
  static Future<int> _calculateMacdScore(
    StockRanking ranking,
    DateTime selectedDate,
    bool useRealtimeInterface,
    RankingConfig config,
  ) async {
    try {
      final tsCode = ranking.stockInfo.tsCode;
      final selectedDateStr = DateFormat('yyyyMMdd').format(selectedDate);
      
      MacdData? currentMacd;
      MacdData? prevMacd;
      
      if (useRealtimeInterface) {
        // 实时接口：使用前一个交易日的数据进行比较
        final prevTradingDate = _getPreviousTradingDay(selectedDate);
        final prevTradingDateStr = DateFormat('yyyyMMdd').format(prevTradingDate);
        
        // 获取前一个交易日和再前一个交易日的MACD数据
        final prevPrevTradingDate = _getPreviousTradingDay(prevTradingDate);
        final prevPrevTradingDateStr = DateFormat('yyyyMMdd').format(prevPrevTradingDate);
        
        // 获取MACD数据（获取两个交易日的数据）
        final startDate = prevPrevTradingDateStr;
        final endDate = prevTradingDateStr;
        
        final factorData = await StockApiService.getFactorProData(
          tsCode: tsCode,
          startDate: startDate,
          endDate: endDate,
        );
        
        final macdList = factorData['macd'] as List? ?? [];
        if (macdList.length >= 2) {
          // 按日期排序，确保顺序正确
          macdList.sort((a, b) {
            if (a is MacdData && b is MacdData) {
              return a.tradeDate.compareTo(b.tradeDate);
            }
            return 0;
          });
          
          // 再前一个交易日（前一天，较旧的）
          prevMacd = macdList[macdList.length - 2] as MacdData?;
          // 前一个交易日（当前比较的日期，较新的）
          currentMacd = macdList[macdList.length - 1] as MacdData?;
        } else if (macdList.length == 1) {
          // 只有一个交易日的数据，只能判断部分条件
          currentMacd = macdList[0] as MacdData?;
        }
      } else {
        // 非实时接口：使用当天和前一个交易日的数据
        final prevTradingDate = _getPreviousTradingDay(selectedDate);
        final prevTradingDateStr = DateFormat('yyyyMMdd').format(prevTradingDate);
        
        // 获取当天的MACD数据
        final currentFactorData = await StockApiService.getFactorProData(
          tsCode: tsCode,
          startDate: selectedDateStr,
          endDate: selectedDateStr,
        );
        
        final currentMacdList = currentFactorData['macd'] as List? ?? [];
        if (currentMacdList.isNotEmpty) {
          currentMacd = currentMacdList[0] as MacdData?;
        }
        
        // 获取前一个交易日的MACD数据
        final prevFactorData = await StockApiService.getFactorProData(
          tsCode: tsCode,
          startDate: prevTradingDateStr,
          endDate: prevTradingDateStr,
        );
        
        final prevMacdList = prevFactorData['macd'] as List? ?? [];
        if (prevMacdList.isNotEmpty) {
          prevMacd = prevMacdList[0] as MacdData?;
        }
      }
      
      // 如果没有当前MACD数据，返回0分
      if (currentMacd == null) {
        return config.macdScoreConfig.noneSatisfied;
      }
      
      // 检查三个条件
      int satisfiedCount = 0;
      
      // 条件1：m值为正（macd > 0）
      if (currentMacd.macd > 0) {
        satisfiedCount++;
      }
      
      // 条件2：m值后一天比前一天高（需要前一个交易日的数据）
      if (prevMacd != null && currentMacd.macd > prevMacd.macd) {
        satisfiedCount++;
      }
      
      // 条件3：DIF大于M值（dif > macd）
      if (currentMacd.dif > currentMacd.macd) {
        satisfiedCount++;
      }
      
      // 根据满足的条件数量返回对应分数
      switch (satisfiedCount) {
        case 3:
          return config.macdScoreConfig.allThreeSatisfied;
        case 2:
          return config.macdScoreConfig.twoSatisfied;
        case 1:
          return config.macdScoreConfig.oneSatisfied;
        default:
          return config.macdScoreConfig.noneSatisfied;
      }
    } catch (e) {
      print('计算MACD评分失败: ${ranking.stockInfo.name} - $e');
      return 0;
    }
  }
  
  /// 获取前一个交易日
  static DateTime _getPreviousTradingDay(DateTime date) {
    DateTime prevDate = date;
    do {
      prevDate = prevDate.subtract(const Duration(days: 1));
    } while (prevDate.weekday == 6 || prevDate.weekday == 7);
    return prevDate;
  }
}

/// 带评分的股票排名
class RankedStock {
  final StockRanking stockRanking;
  final double marketValue; // 市值（亿元）
  final int marketValueScore; // 市值评分
  final double? bollDeviation; // BOLL偏离值（百分比）
  final int bollDeviationScore; // BOLL偏离评分
  final int macdScore; // MACD评分
  final int totalScore; // 总分
  final int rank; // 排名
  
  RankedStock({
    required this.stockRanking,
    required this.marketValue,
    required this.marketValueScore,
    this.bollDeviation,
    required this.bollDeviationScore,
    required this.macdScore,
    required this.totalScore,
    required this.rank,
  });
  
  RankedStock copyWith({
    StockRanking? stockRanking,
    double? marketValue,
    int? marketValueScore,
    double? bollDeviation,
    int? bollDeviationScore,
    int? macdScore,
    int? totalScore,
    int? rank,
  }) {
    return RankedStock(
      stockRanking: stockRanking ?? this.stockRanking,
      marketValue: marketValue ?? this.marketValue,
      marketValueScore: marketValueScore ?? this.marketValueScore,
      bollDeviation: bollDeviation ?? this.bollDeviation,
      bollDeviationScore: bollDeviationScore ?? this.bollDeviationScore,
      macdScore: macdScore ?? this.macdScore,
      totalScore: totalScore ?? this.totalScore,
      rank: rank ?? this.rank,
    );
  }
}

