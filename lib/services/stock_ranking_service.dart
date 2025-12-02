import 'package:intl/intl.dart';
import '../models/stock_ranking.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../models/boll_data.dart';
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
        
        final totalScore = marketValueScore + bollDeviationScore;
        
        rankedStocks.add(RankedStock(
          stockRanking: ranking,
          marketValue: marketValue,
          marketValueScore: marketValueScore,
          bollDeviation: bollDeviation,
          bollDeviationScore: bollDeviationScore,
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
  final int totalScore; // 总分
  final int rank; // 排名
  
  RankedStock({
    required this.stockRanking,
    required this.marketValue,
    required this.marketValueScore,
    this.bollDeviation,
    required this.bollDeviationScore,
    required this.totalScore,
    required this.rank,
  });
  
  RankedStock copyWith({
    StockRanking? stockRanking,
    double? marketValue,
    int? marketValueScore,
    double? bollDeviation,
    int? bollDeviationScore,
    int? totalScore,
    int? rank,
  }) {
    return RankedStock(
      stockRanking: stockRanking ?? this.stockRanking,
      marketValue: marketValue ?? this.marketValue,
      marketValueScore: marketValueScore ?? this.marketValueScore,
      bollDeviation: bollDeviation ?? this.bollDeviation,
      bollDeviationScore: bollDeviationScore ?? this.bollDeviationScore,
      totalScore: totalScore ?? this.totalScore,
      rank: rank ?? this.rank,
    );
  }
}

