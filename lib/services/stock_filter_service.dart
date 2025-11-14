import 'package:intl/intl.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../models/stock_ranking.dart';
import 'stock_api_service.dart';
import 'stock_pool_service.dart';
import 'condition_combination_service.dart';
import 'ma_calculation_service.dart';
import 'stock_pool_config_service.dart';
import 'blacklist_service.dart';
import 'log_service.dart';
import 'console_capture_service.dart';

class StockFilterService {
  // 预定义的成交额筛选条件
  static const List<double> amountThresholds = [5.0, 10.0, 20.0, 50.0, 100.0];
  static const double defaultMinAmountThreshold = 5.0; // 默认最低成交额阈值（亿元）

  // 基于条件组合筛选股票
  static Future<List<StockRanking>> filterStocksWithCombination({
    required ConditionCombination combination,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      final logService = LogService.instance;
      
      logService.info('FILTER', '开始使用条件组合筛选股票', data: {
        'combinationName': combination.name,
        'combinationId': combination.id,
        'shortDescription': combination.shortDescription,
      });
      
      print('🎯 开始使用条件组合筛选股票: ${combination.name}');
      print('📋 筛选条件: ${combination.shortDescription}');
      
      // 捕获控制台输出
      ConsoleCaptureService.instance.capturePrint('🎯 开始使用条件组合筛选股票: ${combination.name}');
      ConsoleCaptureService.instance.capturePrint('📋 筛选条件: ${combination.shortDescription}');
      
      // 1. 获取本地股票池
      print('📊 获取本地股票池...');
      ConsoleCaptureService.instance.capturePrint('📊 获取本地股票池...');
      final localData = await StockPoolService.loadStockPoolFromLocal();
      final List<StockInfo> stockPool = localData['stockPool'] as List<StockInfo>;
      if (stockPool.isEmpty) {
        print('❌ 本地股票池为空，请先配置股票池');
        ConsoleCaptureService.instance.capturePrint('❌ 本地股票池为空，请先配置股票池');
        return [];
      }
      print('✅ 从本地获取到 ${stockPool.length} 只股票');
      ConsoleCaptureService.instance.capturePrint('✅ 从本地获取到 ${stockPool.length} 只股票');

      // 额外处理：当筛选日期为当天时的接口判断逻辑
      final config = await StockPoolConfigService.getConfig();
      final DateTime currentDateTime = DateTime.now();
      final DateTime today = DateTime(currentDateTime.year, currentDateTime.month, currentDateTime.day);
      final DateTime selectedDay = DateTime(
        combination.selectedDate.year,
        combination.selectedDate.month,
        combination.selectedDate.day,
      );

      bool useIFinDRealTime = false;
      bool allowHistoryFetch = true;
      if (selectedDay == today) {
        final String dateStr = DateFormat('yyyy-MM-dd').format(selectedDay);

        if (!StockApiService.isTradingDay(combination.selectedDate)) {
          final message = '当前日期 $dateStr 为非交易日，暂无数据，请选择历史交易日。';
          print('⚠️ $message');
          ConsoleCaptureService.instance.capturePrint('⚠️ $message');
          throw Exception('当前日期无数据：非交易日');
        }

        if (config.enableRealtimeInterface) {
          if (!StockApiService.isAfterTradingStart(referenceTime: currentDateTime)) {
            final message = '当前时间未到 09:30，iFinD 暂无 $dateStr 的数据。';
            print('⚠️ $message');
            ConsoleCaptureService.instance.capturePrint('⚠️ $message');
            throw Exception('当前日期无数据：未到交易时间');
          }

          if (!StockApiService.isWithinRealTimeWindow(referenceTime: currentDateTime)) {
            final message = '当前时间不在交易时段，iFinD 暂无 $dateStr 的数据。';
            print('⚠️ $message');
            ConsoleCaptureService.instance.capturePrint('⚠️ $message');
            throw Exception('当前日期无数据：非交易时段');
          }

          useIFinDRealTime = true;
          allowHistoryFetch = false;
        } else {
          useIFinDRealTime = false;
          allowHistoryFetch = StockApiService.isAfterHistoryAvailability(referenceTime: currentDateTime);
          if (!allowHistoryFetch) {
            final message = '未开启实时接口，且当前时间未到 16:30，TuShare 暂无 $dateStr 的历史数据。';
            print('⚠️ $message');
            ConsoleCaptureService.instance.capturePrint('⚠️ $message');
            throw Exception('当前日期无数据：历史数据未更新');
          }
        }
      } else {
        useIFinDRealTime = StockApiService.shouldUseRealTimeData(combination.selectedDate);
        allowHistoryFetch = true;
      }

      // 2. 黑名单过滤（第一轮筛选）
      print('🔍 黑名单过滤: 移除黑名单中的股票');
      ConsoleCaptureService.instance.capturePrint('🔍 黑名单过滤: 移除黑名单中的股票');
      final blacklist = await BlacklistService.getBlacklist();
      print('📋 当前黑名单包含 ${blacklist.length} 只股票');
      ConsoleCaptureService.instance.capturePrint('📋 当前黑名单包含 ${blacklist.length} 只股票');
      
      final filteredStockPool = stockPool.where((stock) => !blacklist.contains(stock.tsCode)).toList();
      print('✅ 黑名单过滤完成: ${filteredStockPool.length}只股票通过黑名单筛选 (移除了${stockPool.length - filteredStockPool.length}只黑名单股票)');
      ConsoleCaptureService.instance.capturePrint('✅ 黑名单过滤完成: ${filteredStockPool.length}只股票通过黑名单筛选 (移除了${stockPool.length - filteredStockPool.length}只黑名单股票)');
      
      if (filteredStockPool.isEmpty) {
        print('❌ 所有股票都在黑名单中，无法进行筛选');
        ConsoleCaptureService.instance.capturePrint('❌ 所有股票都在黑名单中，无法进行筛选');
        return [];
      }

      // 3. 判断是否使用iFinD实时K线数据
      final bool isTradingTime = StockApiService.isTradingTime();
      final DateTime now = currentDateTime;
      
      print('🕐 当前时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}');
      ConsoleCaptureService.instance.capturePrint('🕐 当前时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}');
      print('🕐 当前是否为交易时间: $isTradingTime');
      ConsoleCaptureService.instance.capturePrint('🕐 当前是否为交易时间: $isTradingTime');
      print('🕐 选择日期: ${DateFormat('yyyy-MM-dd').format(combination.selectedDate)}');
      ConsoleCaptureService.instance.capturePrint('🕐 选择日期: ${DateFormat('yyyy-MM-dd').format(combination.selectedDate)}');
      print('🕐 是否使用iFinD实时数据: $useIFinDRealTime');
      ConsoleCaptureService.instance.capturePrint('🕐 是否使用iFinD实时数据: $useIFinDRealTime');
      
      if (useIFinDRealTime) {
        print('🕐 当前时间在9:30-16:30范围内，使用iFinD实时K线数据进行筛选');
        ConsoleCaptureService.instance.capturePrint('🕐 当前时间在9:30-16:30范围内，使用iFinD实时K线数据进行筛选');
      } else {
        print('🕐 超出iFinD使用时间范围，使用TuShare历史K线数据进行筛选');
        ConsoleCaptureService.instance.capturePrint('🕐 超出iFinD使用时间范围，使用TuShare历史K线数据进行筛选');
      }

      // 4. 获取K线数据（实时或历史）
      Map<String, KlineData> klineDataMap = {};
      final List<String> tsCodes = filteredStockPool.map((stock) => stock.tsCode).toList();
      
      if (useIFinDRealTime) {
        print('📡 获取K线数据（根据时间和日期选择实时或历史接口）...');
        ConsoleCaptureService.instance.capturePrint('📡 获取K线数据（根据时间和日期选择实时或历史接口）...');
        klineDataMap = await StockApiService.getBatchRealTimeKlineData(
          tsCodes: tsCodes,
          selectedDate: combination.selectedDate,
        );
        print('✅ 获取到 ${klineDataMap.length} 只股票的K线数据');
        ConsoleCaptureService.instance.capturePrint('✅ 获取到 ${klineDataMap.length} 只股票的K线数据');
      } else {
        print('📡 获取${combination.selectedDate}的TuShare历史K线数据...');
        ConsoleCaptureService.instance.capturePrint('📡 获取${combination.selectedDate}的TuShare历史K线数据...');
        if (!allowHistoryFetch) {
          print('⚠️ 当前配置不允许获取历史数据');
          ConsoleCaptureService.instance.capturePrint('⚠️ 当前配置不允许获取历史数据');
          throw Exception('当前日期无数据：历史数据不可用');
        }
        klineDataMap = await StockPoolService.getBatchDailyKlineData(
          tsCodes: tsCodes,
          targetDate: combination.selectedDate,
          onProgress: onProgress,
        );
        print('✅ 获取到 ${klineDataMap.length} 只股票的历史K线数据');
        ConsoleCaptureService.instance.capturePrint('✅ 获取到 ${klineDataMap.length} 只股票的历史K线数据');
      }

      // 5. 第一轮筛选：成交额（必填条件）
      String amountFilterDesc;
      if (combination.amountRangeConfig.enabled) {
        if (combination.amountRangeConfig.maxAmount >= 1000) {
          amountFilterDesc = '成交额≥${combination.amountRangeConfig.minAmount.toStringAsFixed(0)}亿元';
        } else {
          amountFilterDesc = '成交额${combination.amountRangeConfig.minAmount.toStringAsFixed(0)}~${combination.amountRangeConfig.maxAmount.toStringAsFixed(0)}亿元';
        }
      } else {
        amountFilterDesc = '成交额≥${combination.amountThreshold}亿元';
      }
      print('🔍 条件1: 成交额筛选 ($amountFilterDesc)');
      ConsoleCaptureService.instance.capturePrint('🔍 条件1: 成交额筛选 ($amountFilterDesc)');
      
      List<StockRanking> candidates = [];
      for (StockInfo stock in filteredStockPool) {
        final KlineData? klineData = klineDataMap[stock.tsCode];
        if (klineData != null) {
          bool passesAmountFilter;
          
          if (combination.amountRangeConfig.enabled) {
            // 使用成交额范围筛选
            final amount = klineData.amountInYi;
            if (combination.amountRangeConfig.maxAmount >= 1000) {
              // 无上限，只检查最小值
              passesAmountFilter = amount >= combination.amountRangeConfig.minAmount;
            } else {
              // 有上限，检查范围
              passesAmountFilter = amount >= combination.amountRangeConfig.minAmount && 
                                   amount <= combination.amountRangeConfig.maxAmount;
            }
          } else {
            // 使用传统的阈值筛选
            passesAmountFilter = klineData.amountInYi >= combination.amountThreshold;
          }
          
          if (passesAmountFilter) {
            candidates.add(StockRanking(
              stockInfo: stock,
              klineData: klineData,
              amountInYi: klineData.amountInYi,
              rank: 0,
            ));
          }
        }
      }
      print('✅ 条件1完成: ${candidates.length}只股票通过成交额筛选');
      ConsoleCaptureService.instance.capturePrint('✅ 条件1完成: ${candidates.length}只股票通过成交额筛选');
      _printStockPool(candidates, '条件1-成交额筛选');

      // 6. 第二轮筛选：涨跌幅（可选条件）
      if (combination.enablePctChg) {
        print('🔍 条件2: 涨跌幅筛选 (${combination.pctChgMin}%~${combination.pctChgMax}%)');
        ConsoleCaptureService.instance.capturePrint('🔍 条件2: 涨跌幅筛选 (${combination.pctChgMin}%~${combination.pctChgMax}%)');
        List<StockRanking> filteredCandidates = [];
        int processed = 0;
        
        for (StockRanking ranking in candidates) {
          processed++;
          if (processed <= 5) {
            // 使用实时数据时，使用计算出的涨跌幅
            final pctChg = useIFinDRealTime ? ranking.klineData.calculatedPctChg : ranking.klineData.pctChg;
            print('  📊 ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 涨跌幅${pctChg.toStringAsFixed(2)}% (限制: ${combination.pctChgMin}%~${combination.pctChgMax}%)');
            ConsoleCaptureService.instance.capturePrint('  📊 ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 涨跌幅${pctChg.toStringAsFixed(2)}% (限制: ${combination.pctChgMin}%~${combination.pctChgMax}%)');
            if (pctChg >= combination.pctChgMin && pctChg <= combination.pctChgMax) {
              print('    ✅ 通过涨跌幅筛选');
              ConsoleCaptureService.instance.capturePrint('    ✅ 通过涨跌幅筛选');
              filteredCandidates.add(ranking);
            } else {
              print('    ❌ 未通过涨跌幅筛选');
              ConsoleCaptureService.instance.capturePrint('    ❌ 未通过涨跌幅筛选');
            }
          } else {
            // 对于第6个及以后的股票，只进行筛选不打印详情
            final pctChg = useIFinDRealTime ? ranking.klineData.calculatedPctChg : ranking.klineData.pctChg;
            if (pctChg >= combination.pctChgMin && pctChg <= combination.pctChgMax) {
              filteredCandidates.add(ranking);
            }
          }
        }
        
        candidates = filteredCandidates;
        print('✅ 条件2完成: ${candidates.length}只股票通过涨跌幅筛选');
        ConsoleCaptureService.instance.capturePrint('✅ 条件2完成: ${candidates.length}只股票通过涨跌幅筛选');
        _printStockPool(candidates, '条件2-涨跌幅筛选');
      }

      // 7. 获取历史K线数据用于均线计算（仅当需要均线筛选时）
      Map<String, List<KlineData>> historicalKlineDataMap = {};
      if (combination.enableMaDistance || combination.enableConsecutiveDays) {
        print('📡 获取历史K线数据用于均线计算...');
        ConsoleCaptureService.instance.capturePrint('📡 获取历史K线数据用于均线计算...');
        final List<String> candidateTsCodes = candidates.map((ranking) => ranking.stockInfo.tsCode).toList();
        
        try {
          // 使用Tushare接口获取历史K线数据（需要60天数据来计算MA20）
          historicalKlineDataMap = await StockApiService.getBatchKlineData(
            tsCodes: candidateTsCodes,
            kLineType: 'daily', // 日K线
            days: 60, // 获取60天数据
          );
          print('✅ 获取到 ${historicalKlineDataMap.length} 只股票的历史K线数据');
        } catch (e) {
          print('❌ 获取历史K线数据失败: $e');
          ConsoleCaptureService.instance.capturePrint('❌ 获取历史K线数据失败: $e');
          // 如果获取历史数据失败，清空历史数据映射，后续筛选会跳过
          historicalKlineDataMap.clear();
        }
      }

      // 8. 第三轮筛选：均线偏离（可选条件）
      if (combination.enableMaDistance && historicalKlineDataMap.isNotEmpty) {
        print('🔍 条件3: 均线偏离筛选');
        ConsoleCaptureService.instance.capturePrint('🔍 条件3: 均线偏离筛选');
        candidates = await _filterByMaDistance(candidates, combination, useIFinDRealTime, historicalKlineDataMap);
        print('✅ 条件3完成: ${candidates.length}只股票通过均线偏离筛选');
        ConsoleCaptureService.instance.capturePrint('✅ 条件3完成: ${candidates.length}只股票通过均线偏离筛选');
        _printStockPool(candidates, '条件3-均线偏离筛选');
      } else if (combination.enableMaDistance && historicalKlineDataMap.isEmpty) {
        print('⚠️ 跳过均线偏离筛选 - 历史数据获取失败');
        ConsoleCaptureService.instance.capturePrint('⚠️ 跳过均线偏离筛选 - 历史数据获取失败');
      }

      // 9. 第四轮筛选：连续天数（可选条件）
      if (combination.enableConsecutiveDays && historicalKlineDataMap.isNotEmpty) {
        print('🔍 条件4: 连续天数筛选');
        ConsoleCaptureService.instance.capturePrint('🔍 条件4: 连续天数筛选');
        candidates = await _filterByConsecutiveDays(candidates, combination, useIFinDRealTime, historicalKlineDataMap);
        print('✅ 条件4完成: ${candidates.length}只股票通过连续天数筛选');
        ConsoleCaptureService.instance.capturePrint('✅ 条件4完成: ${candidates.length}只股票通过连续天数筛选');
        _printStockPool(candidates, '条件4-连续天数筛选');
      } else if (combination.enableConsecutiveDays && historicalKlineDataMap.isEmpty) {
        print('⚠️ 跳过连续天数筛选 - 历史数据获取失败');
        ConsoleCaptureService.instance.capturePrint('⚠️ 跳过连续天数筛选 - 历史数据获取失败');
      }

      // 10. 按成交额排序
      print('🔄 按成交额排序...');
      ConsoleCaptureService.instance.capturePrint('🔄 按成交额排序...');
      final sortedCandidates = StockRanking.sortByAmount(candidates);
      print('✅ 排序完成，最终结果: ${sortedCandidates.length}只股票');
      ConsoleCaptureService.instance.capturePrint('✅ 排序完成，最终结果: ${sortedCandidates.length}只股票');
      _printStockPool(sortedCandidates, '最终结果');

      return sortedCandidates;
      
    } catch (e) {
      print('❌ 条件组合筛选失败: $e');
      ConsoleCaptureService.instance.capturePrint('❌ 条件组合筛选失败: $e');
      return [];
    }
  }

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

  // 打印股票池信息
  static void _printStockPool(List<StockRanking> candidates, String stage) {
    if (candidates.isEmpty) {
      print('📋 $stage: 无符合条件的股票');
      ConsoleCaptureService.instance.capturePrint('📋 $stage: 无符合条件的股票');
      return;
    }
    
    print('📋 $stage: 共${candidates.length}只股票');
    ConsoleCaptureService.instance.capturePrint('📋 $stage: 共${candidates.length}只股票');
    // 只打印前5只股票
    final printCount = candidates.length > 5 ? 5 : candidates.length;
    for (int i = 0; i < printCount; i++) {
      final ranking = candidates[i];
      // 判断是否为实时数据，使用相应的涨跌幅
      final pctChg = ranking.klineData.calculatedPctChg != 0.0 ? ranking.klineData.calculatedPctChg : ranking.klineData.pctChg;
      print('  ${i + 1}. ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}) - 当前价: ${ranking.klineData.close.toStringAsFixed(2)}元, 成交额: ${ranking.amountInYi.toStringAsFixed(2)}亿元, 涨跌幅: ${pctChg.toStringAsFixed(2)}%');
      ConsoleCaptureService.instance.capturePrint('  ${i + 1}. ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}) - 当前价: ${ranking.klineData.close.toStringAsFixed(2)}元, 成交额: ${ranking.amountInYi.toStringAsFixed(2)}亿元, 涨跌幅: ${pctChg.toStringAsFixed(2)}%');
    }
    if (candidates.length > 5) {
      print('  ... 还有${candidates.length - 5}只股票');
      ConsoleCaptureService.instance.capturePrint('  ... 还有${candidates.length - 5}只股票');
    }
  }

  // 均线偏离筛选
  static Future<List<StockRanking>> _filterByMaDistance(
    List<StockRanking> candidates,
    ConditionCombination combination,
    bool useIFinDRealTime,
    Map<String, List<KlineData>> historicalKlineDataMap,
  ) async {
    List<StockRanking> filteredCandidates = [];
    int processed = 0;
    
    for (StockRanking ranking in candidates) {
      processed++;
      // 只打印前5个股票的详细过程
      bool shouldPrintDetails = processed <= 5;
      
      try {
        if (processed % 10 == 0) {
          print('  📊 均线偏离筛选进度: $processed/${candidates.length}');
          ConsoleCaptureService.instance.capturePrint('  📊 均线偏离筛选进度: $processed/${candidates.length}');
        }
        
        // 从已获取的历史数据中获取该股票的数据
        final List<KlineData>? historicalData = historicalKlineDataMap[ranking.stockInfo.tsCode];
        
        if (historicalData == null || historicalData.length < 20) {
          if (shouldPrintDetails) {
            print('  ❌ ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 历史数据不足，跳过');
            ConsoleCaptureService.instance.capturePrint('  ❌ ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 历史数据不足，跳过');
          }
          continue; // 数据不足，跳过
        }
        
        bool passesMaDistance = true;
        List<String> failedConditions = [];
        
        // 检查MA5偏离
        if (combination.ma5Config.enabled) {
          final ma5 = MaCalculationService.calculateMA5(historicalData);
          // 使用实时数据时，使用实时价格；否则使用历史价格
          final currentPrice = useIFinDRealTime ? ranking.klineData.close : ranking.klineData.close;
          final ma5Distance = MaCalculationService.calculateMaDistance(
            currentPrice,
            ma5,
          );
          if (shouldPrintDetails) {
            print('  📊 ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 当前价${currentPrice.toStringAsFixed(2)}元, MA5=${ma5.toStringAsFixed(2)}元, MA5偏离 ${ma5Distance.toStringAsFixed(2)}% (限制: ≤${combination.ma5Config.distance}%)');
          }
          if (ma5Distance > combination.ma5Config.distance) {
            passesMaDistance = false;
            failedConditions.add('MA5偏离${ma5Distance.toStringAsFixed(2)}% > ${combination.ma5Config.distance}%');
          }
        }
        
        // 检查MA10偏离
        if (combination.ma10Config.enabled && passesMaDistance) {
          final ma10 = MaCalculationService.calculateMA10(historicalData);
          // 使用实时数据时，使用实时价格；否则使用历史价格
          final currentPrice = useIFinDRealTime ? ranking.klineData.close : ranking.klineData.close;
          final ma10Distance = MaCalculationService.calculateMaDistance(
            currentPrice,
            ma10,
          );
          if (shouldPrintDetails) {
            print('  📊 ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 当前价${currentPrice.toStringAsFixed(2)}元, MA10=${ma10.toStringAsFixed(2)}元, MA10偏离 ${ma10Distance.toStringAsFixed(2)}% (限制: ≤${combination.ma10Config.distance}%)');
          }
          if (ma10Distance > combination.ma10Config.distance) {
            passesMaDistance = false;
            failedConditions.add('MA10偏离${ma10Distance.toStringAsFixed(2)}% > ${combination.ma10Config.distance}%');
          }
        }
        
        // 检查MA20偏离
        if (combination.ma20Config.enabled && passesMaDistance) {
          final ma20 = MaCalculationService.calculateMA20(historicalData);
          // 使用实时数据时，使用实时价格；否则使用历史价格
          final currentPrice = useIFinDRealTime ? ranking.klineData.close : ranking.klineData.close;
          final ma20Distance = MaCalculationService.calculateMaDistance(
            currentPrice,
            ma20,
          );
          if (shouldPrintDetails) {
            print('  📊 ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 当前价${currentPrice.toStringAsFixed(2)}元, MA20=${ma20.toStringAsFixed(2)}元, MA20偏离 ${ma20Distance.toStringAsFixed(2)}% (限制: ≤${combination.ma20Config.distance}%)');
          }
          if (ma20Distance > combination.ma20Config.distance) {
            passesMaDistance = false;
            failedConditions.add('MA20偏离${ma20Distance.toStringAsFixed(2)}% > ${combination.ma20Config.distance}%');
          }
        }
        
        if (passesMaDistance) {
          if (shouldPrintDetails) {
            print('  ✅ ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 通过均线偏离筛选');
          }
          filteredCandidates.add(ranking);
        } else {
          if (shouldPrintDetails) {
            print('  ❌ ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 未通过均线偏离筛选 - ${failedConditions.join(', ')}');
          }
        }
      } catch (e) {
        if (shouldPrintDetails) {
          print('  ❌ ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 获取历史数据失败');
        }
        continue;
      }
    }
    
    return filteredCandidates;
  }

  // 连续天数筛选
  static Future<List<StockRanking>> _filterByConsecutiveDays(
    List<StockRanking> candidates,
    ConditionCombination combination,
    bool useIFinDRealTime,
    Map<String, List<KlineData>> historicalKlineDataMap,
  ) async {
    List<StockRanking> filteredCandidates = [];
    int processed = 0;
    
    for (StockRanking ranking in candidates) {
      processed++;
      // 只打印前5个股票的详细过程
      bool shouldPrintDetails = processed <= 5;
      
      try {
        if (processed % 10 == 0) {
          print('  📊 连续天数筛选进度: $processed/${candidates.length}');
        }
        
        // 从已获取的历史数据中获取该股票的数据
        final List<KlineData>? historicalData = historicalKlineDataMap[ranking.stockInfo.tsCode];
        
        // 检查数据是否足够
        int requiredDataLength = combination.consecutiveDaysConfig.days;
        if (combination.consecutiveDaysConfig.maType == 'ma5') {
          requiredDataLength = combination.consecutiveDaysConfig.days + 4; // 需要额外4天计算MA5
        } else if (combination.consecutiveDaysConfig.maType == 'ma10') {
          requiredDataLength = combination.consecutiveDaysConfig.days + 9; // 需要额外9天计算MA10
        } else if (combination.consecutiveDaysConfig.maType == 'ma20') {
          requiredDataLength = combination.consecutiveDaysConfig.days + 19; // 需要额外19天计算MA20
        }
        
        if (historicalData == null || historicalData.length < requiredDataLength) {
          if (shouldPrintDetails) {
            print('  ❌ ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 历史数据不足，需要${requiredDataLength}天，实际${historicalData?.length ?? 0}天，跳过');
          }
          continue; // 数据不足，跳过
        }
        
        // 检查连续天数条件
        bool passesConsecutiveDays = true;
        final requiredDays = combination.consecutiveDaysConfig.days;
        final maTypeName = combination.consecutiveDaysConfig.maType == 'ma5' ? 'MA5' : 
                          combination.consecutiveDaysConfig.maType == 'ma10' ? 'MA10' : 'MA20';
        
        if (shouldPrintDetails) {
          print('  📊 ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 检查连续${requiredDays}天收盘价高于${maTypeName}');
        }
        
        // 从最新日期开始往前检查连续天数
        // historicalData[0] 是最早的数据，historicalData[historicalData.length-1] 是最新的数据
        // 所以我们需要从数组末尾开始往前遍历
        for (int i = 0; i < requiredDays; i++) {
          final dataIndex = historicalData.length - 1 - i; // 从最新数据开始往前
          final klineData = historicalData[dataIndex]; // 第i天的数据（从最新日期开始往前）
          double maValue;
          
          // 如果是使用实时数据且检查的是最新一天，使用实时价格
          double currentPrice;
          if (useIFinDRealTime && i == 0) {
            currentPrice = ranking.klineData.close; // 使用实时价格
          } else {
            currentPrice = klineData.close; // 使用历史价格
          }
          
          // 计算对应均线值 - 使用从第dataIndex天开始的数据
          switch (combination.consecutiveDaysConfig.maType) {
            case 'ma5':
              if (dataIndex + 1 >= 5) {
                maValue = MaCalculationService.calculateMA5(historicalData.sublist(dataIndex - 4, dataIndex + 1));
              } else {
                maValue = 0.0;
              }
              break;
            case 'ma10':
              if (dataIndex + 1 >= 10) {
                maValue = MaCalculationService.calculateMA10(historicalData.sublist(dataIndex - 9, dataIndex + 1));
              } else {
                maValue = 0.0;
              }
              break;
            case 'ma20':
              if (dataIndex + 1 >= 20) {
                maValue = MaCalculationService.calculateMA20(historicalData.sublist(dataIndex - 19, dataIndex + 1));
              } else {
                maValue = 0.0;
              }
              break;
            default:
              if (dataIndex + 1 >= 20) {
                maValue = MaCalculationService.calculateMA20(historicalData.sublist(dataIndex - 19, dataIndex + 1));
              } else {
                maValue = 0.0;
              }
          }
          
          final dayIndex = i + 1;
          final dateStr = useIFinDRealTime && i == 0 ? '实时' : klineData.tradeDate; // 显示实际日期或实时
          if (shouldPrintDetails) {
            print('    第${dayIndex}天(${dateStr}): 收盘价${currentPrice.toStringAsFixed(2)} vs ${maTypeName} ${maValue.toStringAsFixed(2)}');
          }
          
          if (currentPrice <= maValue) {
            passesConsecutiveDays = false;
            if (shouldPrintDetails) {
              print('    ❌ 第${dayIndex}天(${dateStr})收盘价${currentPrice.toStringAsFixed(2)} ≤ ${maTypeName} ${maValue.toStringAsFixed(2)}，不满足条件');
            }
            break;
          }
        }
        
        if (passesConsecutiveDays) {
          if (shouldPrintDetails) {
            print('  ✅ ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 通过连续天数筛选');
          }
          filteredCandidates.add(ranking);
        } else {
          if (shouldPrintDetails) {
            print('  ❌ ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 未通过连续天数筛选');
          }
        }
      } catch (e) {
        if (shouldPrintDetails) {
          print('  ❌ ${ranking.stockInfo.name} (${ranking.stockInfo.tsCode}): 获取历史数据失败');
        }
        continue;
      }
    }
    
    return filteredCandidates;
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
