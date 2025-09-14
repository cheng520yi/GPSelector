import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../models/stock_ranking.dart';
import 'stock_api_service.dart';
import 'stock_pool_service.dart';

class StockFilterService {
  // 预定义的成交额筛选条件
  static const List<double> amountThresholds = [5.0, 10.0, 20.0, 50.0, 100.0];
  static const double defaultMinAmountThreshold = 5.0; // 默认最低成交额阈值（亿元）

  // 基于股票池筛选符合条件的股票（快速筛选）
  static Future<List<StockRanking>> filterStocksFromPool({
    double minAmountThreshold = defaultMinAmountThreshold,
  }) async {
    try {
      // 1. 获取股票池
      final List<StockInfo> stockPool = await StockPoolService.buildStockPool();
      if (stockPool.isEmpty) {
        return [];
      }

      // 2. 获取股票池的单日K线数据
      final List<String> tsCodes = stockPool.map((stock) => stock.tsCode).toList();
      final Map<String, KlineData> klineDataMap = 
          await StockPoolService.getBatchDailyKlineData(tsCodes: tsCodes);

      // 3. 筛选和排序
      List<StockRanking> rankings = [];
      
      for (StockInfo stock in stockPool) {
        final KlineData? klineData = klineDataMap[stock.tsCode];
        
        if (klineData != null && klineData.amountInYi >= minAmountThreshold) {
          rankings.add(StockRanking(
            stockInfo: stock,
            klineData: klineData,
            amountInYi: klineData.amountInYi,
            rank: 0, // 临时排名，稍后会重新排序
          ));
        }
      }

      // 4. 按成交额排序
      return StockRanking.sortByAmount(rankings);
      
    } catch (e) {
      print('从股票池筛选股票失败: $e');
      return [];
    }
  }

  // 基于股票池进行精细筛选（获取60日数据）
  static Future<List<StockRanking>> filterStocksDetailed({
    required List<StockInfo> stockPool,
    String kLineType = 'daily',
    int days = 60,
    double minAmountThreshold = defaultMinAmountThreshold,
  }) async {
    try {
      // 1. 提取股票代码
      final List<String> tsCodes = stockPool.map((stock) => stock.tsCode).toList();

      // 2. 批量获取60日K线数据
      final Map<String, List<KlineData>> klineDataMap = 
          await StockApiService.getBatchKlineData(
        tsCodes: tsCodes,
        kLineType: kLineType,
        days: days,
      );

      // 3. 筛选和排序
      List<StockRanking> rankings = [];
      
      for (StockInfo stock in stockPool) {
        final List<KlineData> klineDataList = klineDataMap[stock.tsCode] ?? [];
        
        if (klineDataList.isNotEmpty) {
          // 获取最新的K线数据（通常是第一条）
          final KlineData latestKline = klineDataList.first;
          
          // 检查成交额是否满足条件
          if (latestKline.amountInYi >= minAmountThreshold) {
            rankings.add(StockRanking(
              stockInfo: stock,
              klineData: latestKline,
              amountInYi: latestKline.amountInYi,
              rank: 0, // 临时排名，稍后会重新排序
            ));
          }
        }
      }

      // 4. 按成交额排序
      return StockRanking.sortByAmount(rankings);
      
    } catch (e) {
      print('精细筛选股票失败: $e');
      return [];
    }
  }

  // 兼容性方法：筛选符合条件的股票（使用原有逻辑）
  static Future<List<StockRanking>> filterStocks({
    String kLineType = 'daily',
    int days = 60,
    double minAmountThreshold = defaultMinAmountThreshold,
  }) async {
    // 默认使用快速筛选
    return filterStocksFromPool(minAmountThreshold: minAmountThreshold);
  }

  // 根据行业筛选股票
  static Future<List<StockRanking>> filterStocksByIndustry({
    required String industry,
    String kLineType = 'daily',
    int days = 60,
    double minAmountThreshold = defaultMinAmountThreshold,
  }) async {
    final List<StockRanking> allRankings = await filterStocks(
      kLineType: kLineType,
      days: days,
      minAmountThreshold: minAmountThreshold,
    );

    return allRankings
        .where((ranking) => ranking.stockInfo.industry == industry)
        .toList();
  }

  // 根据地区筛选股票
  static Future<List<StockRanking>> filterStocksByArea({
    required String area,
    String kLineType = 'daily',
    int days = 60,
    double minAmountThreshold = defaultMinAmountThreshold,
  }) async {
    final List<StockRanking> allRankings = await filterStocks(
      kLineType: kLineType,
      days: days,
      minAmountThreshold: minAmountThreshold,
    );

    return allRankings
        .where((ranking) => ranking.stockInfo.area == area)
        .toList();
  }

  // 获取所有行业列表
  static Future<List<String>> getAllIndustries() async {
    final List<StockInfo> stockList = await StockApiService.loadStockData();
    final Set<String> industries = stockList.map((stock) => stock.industry).toSet();
    return industries.toList()..sort();
  }

  // 获取所有地区列表
  static Future<List<String>> getAllAreas() async {
    final List<StockInfo> stockList = await StockApiService.loadStockData();
    final Set<String> areas = stockList.map((stock) => stock.area).toSet();
    return areas.toList()..sort();
  }
}
