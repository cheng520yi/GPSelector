import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../models/macd_data.dart';
import '../services/stock_api_service.dart';
import '../widgets/kline_chart_widget.dart';

class StockDetailScreen extends StatefulWidget {
  final StockInfo stockInfo;
  final KlineData? currentKlineData;

  const StockDetailScreen({
    super.key,
    required this.stockInfo,
    this.currentKlineData,
  });

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  List<KlineData> _klineDataList = [];
  List<MacdData> _macdDataList = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _selectedDays = 60; // 默认显示60天
  int _subChartCount = 1; // 默认显示1个副图
  String _selectedChartType = 'daily'; // 默认选择日K，可选：daily(日K), weekly(周K), monthly(月K)

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  // 初始化数据：先加载设置，再加载K线数据
  Future<void> _initializeData() async {
    await _loadSettings();
    _loadKlineData();
  }

  // 加载保存的设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDays = prefs.getInt('kline_display_days');
      final savedSubChartCount = prefs.getInt('kline_sub_chart_count');
      
      if (savedDays != null) {
        setState(() {
          _selectedDays = savedDays;
        });
      }
      
      if (savedSubChartCount != null) {
        setState(() {
          _subChartCount = savedSubChartCount;
        });
      }
    } catch (e) {
      // 如果加载失败，使用默认值
      print('加载设置失败: $e');
    }
  }

  // 保存设置
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('kline_display_days', _selectedDays);
      await prefs.setInt('kline_sub_chart_count', _subChartCount);
    } catch (e) {
      print('保存设置失败: $e');
    }
  }

  Future<void> _loadKlineData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 根据图表类型调整请求天数
      // 日K：正常计算
      // 周K：需要更多自然日（一周约5个交易日，60个交易日约需要84个自然日）
      // 月K：需要更多自然日（一月约22个交易日，60个交易日约需要90个自然日）
      int requestDays;
      if (_selectedChartType == 'weekly') {
        // 周K：每个数据点代表一周，60个数据点需要约420个自然日（60周）
        requestDays = (_selectedDays * 7).round() + 30;
      } else if (_selectedChartType == 'monthly') {
        // 月K：每个数据点代表一月，60个数据点需要约1800个自然日（60个月，约5年）
        requestDays = (_selectedDays * 30).round() + 60;
      } else {
        // 日K：正常计算
        requestDays = (_selectedDays * 1.5).round() + 20;
      }
      
      // 并行加载K线数据和MACD数据
      // 对于月K，确保endDate包含本月最后一天，以便获取本月数据
      DateTime endDate = DateTime.now();
      if (_selectedChartType == 'monthly') {
        // 月K：使用本月最后一天作为结束日期，确保包含本月数据
        final now = DateTime.now();
        final lastDayOfMonth = DateTime(now.year, now.month + 1, 0); // 下个月的第0天 = 本月的最后一天
        endDate = lastDayOfMonth;
      }
      final DateTime startDate = endDate.subtract(Duration(days: requestDays));
      final String startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final String endDateStr = DateFormat('yyyy-MM-dd').format(endDate);
      
      // 根据图表类型调用不同的API
      final results = await Future.wait([
        StockApiService.getKlineData(
          tsCode: widget.stockInfo.tsCode,
          kLineType: _selectedChartType, // 使用选择的图表类型
          days: requestDays,
        ),
        // MACD数据目前只支持日K，周K和月K暂时不加载MACD
        _selectedChartType == 'daily' 
          ? StockApiService.getMacdData(
              tsCode: widget.stockInfo.tsCode,
              startDate: startDateStr,
              endDate: endDateStr,
            )
          : Future.value(<MacdData>[]), // 周K和月K暂时返回空MACD数据
      ]);

      List<KlineData> klineDataList = results[0] as List<KlineData>;
      final macdDataList = results[1] as List<MacdData>;

      // 数据已经按时间排序，直接使用
      // 确保数据按时间正序排列（从早到晚）
      List<KlineData> sortedData = klineDataList.toList()
        ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
      
      final sortedMacdData = macdDataList.toList()
        ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));

      // 根据K线类型决定是否获取实时数据
      final now = DateTime.now();
      KlineData? latestData;
      
      if (_selectedChartType == 'monthly') {
        // 月K：任何月中日期都要获取最新交易日数据
        print('📊 月K模式：尝试获取最新交易日数据...');
        try {
          latestData = await StockApiService.getLatestTradingDayData(
            tsCode: widget.stockInfo.tsCode,
          );
        } catch (e) {
          print('❌ 获取最新交易日数据失败: $e');
        }
      } else if (_selectedChartType == 'daily' || _selectedChartType == 'weekly') {
        // 日K和周K：只在交易日且交易时间内获取实时数据
        if (StockApiService.isTradingDay(now) && StockApiService.isWithinRealTimeWindow()) {
          print('📊 当前是交易日且在交易时间内，尝试获取实时数据...');
          try {
            latestData = await StockApiService.getSingleStockRealTimeData(
              tsCode: widget.stockInfo.tsCode,
            );
          } catch (e) {
            print('❌ 获取实时数据失败: $e');
          }
        }
      }
      
      // 如果获取到最新数据，合并到K线数据中
      if (latestData != null) {
        print('✅ 获取到最新数据: 日期=${latestData.tradeDate}, 收盘价=${latestData.close}');
        
        // 根据K线类型合并实时数据
        sortedData = await _mergeRealTimeData(sortedData, latestData, _selectedChartType, widget.stockInfo.tsCode);
        print('✅ 最新数据合并完成，最终数据量: ${sortedData.length}条');
      } else {
        print('⚠️ 未能获取到最新数据');
      }

      print('✅ K线数据: ${sortedData.length}条');
      if (sortedData.isNotEmpty) {
        print('✅ 最后一条K线数据: 日期=${sortedData.last.tradeDate}, 收盘价=${sortedData.last.close}, 成交量=${sortedData.last.vol}');
        // 对于月K，打印最后几条数据的成交量
        if (_selectedChartType == 'monthly' && sortedData.length >= 3) {
          print('📊 月K最后3条数据的成交量:');
          for (int i = sortedData.length - 3; i < sortedData.length; i++) {
            print('  ${i + 1}. ${sortedData[i].tradeDate}: 成交量=${sortedData[i].vol}');
          }
        }
      }
      print('✅ MACD数据: ${sortedMacdData.length}条');
      if (sortedMacdData.isNotEmpty) {
        print('✅ MACD数据示例: 日期=${sortedMacdData.first.tradeDate}, DIF=${sortedMacdData.first.dif}, DEA=${sortedMacdData.first.dea}, MACD=${sortedMacdData.first.macd}');
      }

      setState(() {
        _klineDataList = sortedData;
        _macdDataList = sortedMacdData;
        _isLoading = false;
      });
      
      // 验证数据是否正确设置
      if (_klineDataList.isNotEmpty) {
        print('✅ 验证: _klineDataList最后一条数据: 日期=${_klineDataList.last.tradeDate}, 成交量=${_klineDataList.last.vol}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = '加载K线数据失败: $e';
        _isLoading = false;
      });
    }
  }

  // 获取指定日期范围内的所有日K数据（用于计算月K和周K）
  Future<List<KlineData>> _getDailyDataForPeriod({
    required String tsCode,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startDateStr = DateFormat('yyyyMMdd').format(startDate);
      final endDateStr = DateFormat('yyyyMMdd').format(endDate);
      
      // 计算需要请求的天数（多请求一些天数确保覆盖所有交易日）
      final daysDiff = endDate.difference(startDate).inDays;
      final requestDays = (daysDiff * 1.5).round() + 20; // 多请求50%的天数以确保覆盖所有交易日
      
      print('📊 获取日K数据: 日期范围 $startDateStr - $endDateStr, 请求天数=$requestDays');
      
      final dailyData = await StockApiService.getKlineData(
        tsCode: tsCode,
        kLineType: 'daily',
        days: requestDays,
        endDate: endDateStr,
      );
      
      // 过滤出指定日期范围内的数据（包含边界日期）
      // 将startDate和endDate转换为只包含年月日的DateTime（去掉时分秒）
      final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);
      final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
      
      final filteredData = dailyData.where((data) {
        final dataDate = DateTime.parse(
          '${data.tradeDate.substring(0,4)}-${data.tradeDate.substring(4,6)}-${data.tradeDate.substring(6,8)}'
        );
        final dataDateOnly = DateTime(dataDate.year, dataDate.month, dataDate.day);
        
        // 包含边界日期：>= startDate 且 <= endDate
        final isInRange = (dataDateOnly.isAtSameMomentAs(startDateOnly) || dataDateOnly.isAfter(startDateOnly)) &&
                          (dataDateOnly.isAtSameMomentAs(endDateOnly) || dataDateOnly.isBefore(endDateOnly));
        return isInRange;
      }).toList();
      
      // 按日期排序
      filteredData.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
      
      // 去重：确保同一天只有一条数据（如果同一天有多条数据，保留最后一条）
      final Map<String, KlineData> uniqueDataMap = {};
      for (final data in filteredData) {
        // 如果该日期还没有数据，或者当前数据的日期更新，则更新
        if (!uniqueDataMap.containsKey(data.tradeDate)) {
          uniqueDataMap[data.tradeDate] = data;
        }
      }
      final finalFilteredData = uniqueDataMap.values.toList()..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
      
      print('✅ 获取到 ${finalFilteredData.length} 条日K数据 (日期范围: ${finalFilteredData.isNotEmpty ? finalFilteredData.first.tradeDate : '无'} - ${finalFilteredData.isNotEmpty ? finalFilteredData.last.tradeDate : '无'})');
      if (finalFilteredData.isNotEmpty) {
        final totalVol = finalFilteredData.map((e) => e.vol).fold(0.0, (sum, vol) => sum + vol);
        print('📊 日K数据成交量总计: $totalVol');
      }
      
      return finalFilteredData;
    } catch (e) {
      print('❌ 获取日K数据失败: $e');
      return [];
    }
  }

  // 合并实时数据到K线数据中
  Future<List<KlineData>> _mergeRealTimeData(
    List<KlineData> existingData,
    KlineData realTimeData,
    String chartType,
    String tsCode,
  ) async {
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final todayDate = DateTime.now();
    
    if (chartType == 'daily') {
      // 日K：直接替换或添加当天的数据
      final existingIndex = existingData.indexWhere((data) => data.tradeDate == today);
      if (existingIndex >= 0) {
        // 如果已存在当天数据，替换它
        existingData[existingIndex] = realTimeData;
        print('📊 日K: 替换当天数据');
      } else {
        // 如果不存在，添加到末尾
        existingData.add(realTimeData);
        existingData.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
        print('📊 日K: 添加当天数据');
      }
      return existingData;
    } else if (chartType == 'weekly') {
      // 周K：将实时数据作为本周的最新数据，累加本周前面几天的交易量
      // 找到本周的开始日期（周一）
      final daysFromMonday = todayDate.weekday - 1; // 0=Monday, 6=Sunday
      final weekStart = todayDate.subtract(Duration(days: daysFromMonday));
      final weekStartStr = DateFormat('yyyyMMdd').format(weekStart);
      
      // 找到本周的数据（周K数据通常以周一的日期或本周最后一个交易日的日期标识）
      // 由于周K数据可能以不同方式标识，我们需要找到最接近今天的那条周K数据
      int targetIndex = -1;
      DateTime? targetWeekStart;
      
      // 查找包含今天的那一周的K线数据
      for (int i = existingData.length - 1; i >= 0; i--) {
        final dataDate = DateTime.parse(
          '${existingData[i].tradeDate.substring(0,4)}-${existingData[i].tradeDate.substring(4,6)}-${existingData[i].tradeDate.substring(6,8)}'
        );
        final dataWeekStart = dataDate.subtract(Duration(days: dataDate.weekday - 1));
        final todayWeekStart = weekStart;
        
        // 如果数据所在周的开始日期与本周开始日期相同，说明是本周的数据
        if (dataWeekStart.year == todayWeekStart.year &&
            dataWeekStart.month == todayWeekStart.month &&
            dataWeekStart.day == todayWeekStart.day) {
          targetIndex = i;
          targetWeekStart = dataWeekStart;
          break;
        }
      }
      
      // 获取本周的所有日K数据（从本周第一个交易日到最新交易日）
      final weekEnd = todayDate;
      final weekDailyData = await _getDailyDataForPeriod(
        tsCode: tsCode,
        startDate: weekStart,
        endDate: weekEnd,
      );
      
      if (weekDailyData.isEmpty) {
        print('⚠️ 周K: 无法获取本周的日K数据');
        return existingData;
      }
      
      // 计算本周的统计数据
      final firstDayData = weekDailyData.first; // 本周第一个交易日
      final lastDayData = weekDailyData.last; // 本周最新交易日（使用实时数据更新）
      
      // 更新最新交易日数据为实时数据
      final updatedLastDayData = KlineData(
        tsCode: lastDayData.tsCode,
        tradeDate: lastDayData.tradeDate,
        open: lastDayData.open,
        high: realTimeData.high > lastDayData.high ? realTimeData.high : lastDayData.high,
        low: realTimeData.low < lastDayData.low ? realTimeData.low : lastDayData.low,
        close: realTimeData.close, // 使用实时收盘价
        preClose: lastDayData.preClose,
        change: realTimeData.close - lastDayData.open,
        pctChg: lastDayData.open > 0 ? ((realTimeData.close - lastDayData.open) / lastDayData.open * 100) : 0.0,
        vol: realTimeData.vol, // 使用实时交易量
        amount: realTimeData.amount, // 使用实时成交额
      );
      
      // 替换最新交易日数据
      weekDailyData[weekDailyData.length - 1] = updatedLastDayData;
      
      // 统计本周的最高价、最低价、累积成交量、累积成交额
      double weekHigh = weekDailyData.map((e) => e.high).reduce((a, b) => a > b ? a : b);
      double weekLow = weekDailyData.map((e) => e.low).reduce((a, b) => a < b ? a : b);
      double weekVol = weekDailyData.map((e) => e.vol).fold(0.0, (sum, vol) => sum + vol);
      double weekAmount = weekDailyData.map((e) => e.amount).fold(0.0, (sum, amount) => sum + amount);
      
      if (targetIndex >= 0) {
        // 找到本周的数据，更新统计数据
        final existingWeekData = existingData[targetIndex];
        
        final updatedWeekData = KlineData(
          tsCode: existingWeekData.tsCode,
          tradeDate: existingWeekData.tradeDate, // 保持周K的日期标识
          open: firstDayData.open, // 本周第一个交易日的开盘价
          high: weekHigh, // 本周所有交易日的最高价
          low: weekLow, // 本周所有交易日的最低价
          close: realTimeData.close, // 最新交易日的收盘价
          preClose: existingWeekData.preClose,
          change: realTimeData.close - firstDayData.open, // 相对于周开盘价的变化
          pctChg: firstDayData.open > 0 
              ? ((realTimeData.close - firstDayData.open) / firstDayData.open * 100)
              : 0.0,
          vol: weekVol, // 累积交易量
          amount: weekAmount, // 累积成交额
        );
        
        existingData[targetIndex] = updatedWeekData;
        print('📊 周K: 更新本周数据 (开盘=${firstDayData.open}, 收盘=${realTimeData.close}, 最高=$weekHigh, 最低=$weekLow, 成交量=$weekVol)');
      } else {
        // 如果找不到本周的数据，创建新的周K数据
        print('📊 周K: 未找到本周数据，创建新的周K数据');
        
        // 使用本周第一天的日期作为周K的tradeDate
        final weekFirstDay = DateFormat('yyyyMMdd').format(weekStart);
        
        // 查找上周最后一条数据，用于获取preClose
        double preClose = 0.0;
        if (existingData.isNotEmpty) {
          final lastData = existingData.last;
          preClose = lastData.close;
        }
        
        final newWeekData = KlineData(
          tsCode: tsCode,
          tradeDate: weekFirstDay,
          open: firstDayData.open, // 本周第一个交易日的开盘价
          high: weekHigh, // 本周所有交易日的最高价
          low: weekLow, // 本周所有交易日的最低价
          close: realTimeData.close, // 最新交易日的收盘价
          preClose: preClose,
          change: realTimeData.close - firstDayData.open,
          pctChg: firstDayData.open > 0 
              ? ((realTimeData.close - firstDayData.open) / firstDayData.open * 100)
              : 0.0,
          vol: weekVol, // 累积交易量
          amount: weekAmount, // 累积成交额
        );
        
        existingData.add(newWeekData);
        existingData.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
        
        print('✅ 周K: 创建新的周K数据成功，日期=$weekFirstDay');
      }
      return existingData;
    } else if (chartType == 'monthly') {
      // 月K：将实时数据作为本月的最新数据，累加本月前面几天的交易量
      final monthStart = DateTime(todayDate.year, todayDate.month, 1);
      final monthStartStr = DateFormat('yyyyMMdd').format(monthStart);
      
      // 找到本月的数据（月K数据通常以月初的日期或本月最后一个交易日的日期标识）
      int targetIndex = -1;
      
      print('📊 月K: 开始查找本月数据，当前月份=${todayDate.year}年${todayDate.month}月，已有数据量=${existingData.length}');
      
      // 查找包含今天的那一月的K线数据
      // 月K数据的tradeDate可能是YYYYMM01（月初）或YYYYMMDD（月末交易日）
      // 所以需要检查tradeDate的前6位（YYYYMM）是否匹配
      for (int i = existingData.length - 1; i >= 0; i--) {
        final dataTradeDate = existingData[i].tradeDate;
        final dataDate = DateTime.parse(
          '${dataTradeDate.substring(0,4)}-${dataTradeDate.substring(4,6)}-${dataTradeDate.length >= 8 ? dataTradeDate.substring(6,8) : '01'}'
        );
        
        // 检查年月是否匹配（月K数据可能以月初或月末日期标识）
        final dataYearMonth = '${dataDate.year}${dataDate.month.toString().padLeft(2, '0')}';
        final targetYearMonth = '${todayDate.year}${todayDate.month.toString().padLeft(2, '0')}';
        
        if (dataYearMonth == targetYearMonth) {
          targetIndex = i;
          print('📊 月K: 找到本月数据，索引=$i, tradeDate=${dataTradeDate}, 成交量=${existingData[i].vol}');
          break;
        }
      }
      
      if (targetIndex < 0) {
        print('📊 月K: 未找到本月数据，将创建新的月K数据');
        // 再次检查：可能已有数据但tradeDate格式不同，检查前6位是否匹配
        for (int i = existingData.length - 1; i >= 0; i--) {
          final dataTradeDate = existingData[i].tradeDate;
          if (dataTradeDate.length >= 6) {
            final dataYearMonth = dataTradeDate.substring(0, 6);
            final targetYearMonth = '${todayDate.year}${todayDate.month.toString().padLeft(2, '0')}';
            if (dataYearMonth == targetYearMonth) {
              targetIndex = i;
              print('📊 月K: 通过前6位匹配找到本月数据，索引=$i, tradeDate=${dataTradeDate}');
              break;
            }
          }
        }
      }
      
      // 获取本月的所有日K数据（从本月第一个交易日到最新交易日）
      final monthEnd = todayDate;
      final monthDailyData = await _getDailyDataForPeriod(
        tsCode: tsCode,
        startDate: monthStart,
        endDate: monthEnd,
      );
      
      if (monthDailyData.isEmpty) {
        print('⚠️ 月K: 无法获取本月的日K数据');
        return existingData;
      }
      
      // 计算本月的统计数据
      final firstDayData = monthDailyData.first; // 本月第一个交易日
      final lastDayData = monthDailyData.last; // 本月最新交易日（使用实时数据更新）
      
      // 检查最新交易日是否是今天，如果是，使用实时数据更新
      final lastDayDate = DateTime.parse(
        '${lastDayData.tradeDate.substring(0,4)}-${lastDayData.tradeDate.substring(4,6)}-${lastDayData.tradeDate.substring(6,8)}'
      );
      final isLastDayToday = lastDayDate.year == todayDate.year &&
                             lastDayDate.month == todayDate.month &&
                             lastDayDate.day == todayDate.day;
      
      // 更新最新交易日数据为实时数据（如果是今天）
      KlineData updatedLastDayData;
      if (isLastDayToday) {
        // 最新交易日是今天，使用实时数据更新
        updatedLastDayData = KlineData(
          tsCode: lastDayData.tsCode,
          tradeDate: lastDayData.tradeDate,
          open: lastDayData.open,
          high: realTimeData.high > lastDayData.high ? realTimeData.high : lastDayData.high,
          low: realTimeData.low < lastDayData.low ? realTimeData.low : lastDayData.low,
          close: realTimeData.close, // 使用实时收盘价
          preClose: lastDayData.preClose,
          change: realTimeData.close - lastDayData.open,
          pctChg: lastDayData.open > 0 ? ((realTimeData.close - lastDayData.open) / lastDayData.open * 100) : 0.0,
          vol: realTimeData.vol, // 使用实时交易量
          amount: realTimeData.amount, // 使用实时成交额
        );
        // 替换最新交易日数据
        monthDailyData[monthDailyData.length - 1] = updatedLastDayData;
        print('📊 月K: 最新交易日是今天，使用实时数据更新 (成交量: ${lastDayData.vol} -> ${realTimeData.vol})');
      } else {
        // 最新交易日不是今天，保持原有数据
        updatedLastDayData = lastDayData;
        print('📊 月K: 最新交易日不是今天 (${lastDayData.tradeDate})，保持历史数据');
      }
      
      // 统计本月的最高价、最低价、累积成交量、累积成交额
      // 确保使用所有交易日的数据进行累积
      double monthHigh = monthDailyData.map((e) => e.high).reduce((a, b) => a > b ? a : b);
      double monthLow = monthDailyData.map((e) => e.low).reduce((a, b) => a < b ? a : b);
      // 累积成交量：从本月第一个交易日到最新交易日的所有交易日的成交量
      // 重要：使用循环累加，确保每个交易日的成交量都被正确累加
      double monthVol = 0.0;
      double monthAmount = 0.0;
      for (final data in monthDailyData) {
        monthVol += data.vol;
        monthAmount += data.amount;
      }
      
      print('📊 月K成交量累积: 交易日数=${monthDailyData.length}, 累积成交量=$monthVol, 累积成交额=$monthAmount');
      if (monthDailyData.isNotEmpty) {
        print('📊 月K数据详情: 第一条=${monthDailyData.first.tradeDate} 成交量=${monthDailyData.first.vol}, 最后一条=${monthDailyData.last.tradeDate} 成交量=${monthDailyData.last.vol}');
        // 打印所有交易日的成交量，用于调试
        print('📊 月K所有交易日成交量明细:');
        for (int i = 0; i < monthDailyData.length; i++) {
          print('  ${i + 1}. ${monthDailyData[i].tradeDate}: 成交量=${monthDailyData[i].vol}');
        }
      }
      
      if (targetIndex >= 0) {
        // 找到本月的数据，更新统计数据
        final existingMonthData = existingData[targetIndex];
        
        // 使用最新交易日的日期作为月K的tradeDate（而不是保持原有日期）
        // 这样确保月K数据始终使用最新交易日的日期标识
        final latestTradingDay = monthDailyData.last.tradeDate; // 最新交易日的日期
        
        final updatedMonthData = KlineData(
          tsCode: existingMonthData.tsCode,
          tradeDate: latestTradingDay, // 使用最新交易日的日期（而不是保持原有日期）
          open: firstDayData.open, // 本月第一个交易日的开盘价
          high: monthHigh, // 本月所有交易日的最高价
          low: monthLow, // 本月所有交易日的最低价
          close: realTimeData.close, // 最新交易日的收盘价
          preClose: existingMonthData.preClose,
          change: realTimeData.close - firstDayData.open, // 相对于月开盘价的变化
          pctChg: firstDayData.open > 0 
              ? ((realTimeData.close - firstDayData.open) / firstDayData.open * 100)
              : 0.0,
          vol: monthVol, // 累积交易量
          amount: monthAmount, // 累积成交额
        );
        
        existingData[targetIndex] = updatedMonthData;
        print('📊 月K: 更新本月数据 (开盘=${firstDayData.open}, 收盘=${realTimeData.close}, 最高=$monthHigh, 最低=$monthLow, 成交量=$monthVol)');
        print('📊 月K: 日期从 ${existingMonthData.tradeDate} 更新为 $latestTradingDay（最新交易日）');
        print('📊 月K: 验证更新后的数据 - 索引=$targetIndex, tradeDate=${existingData[targetIndex].tradeDate}, 成交量=${existingData[targetIndex].vol}');
      } else {
        // 如果找不到本月的数据，创建新的月K数据
        print('📊 月K: 未找到本月数据，创建新的月K数据');
        
        // 使用最新交易日的日期作为月K的tradeDate（而不是月初日期）
        // 这样月K数据会按时间顺序正确排序，并且日期标识更准确
        final latestTradingDay = monthDailyData.last.tradeDate; // 最新交易日的日期
        
        // 查找上个月最后一条数据，用于获取preClose
        double preClose = 0.0;
        if (existingData.isNotEmpty) {
          final lastData = existingData.last;
          preClose = lastData.close;
        }
        
        // 在添加新数据前，检查是否已存在相同日期的数据（避免重复）
        // 注意：这里检查的是最新交易日的日期，而不是月初日期
        final existingIndex = existingData.indexWhere((data) => data.tradeDate == latestTradingDay);
        if (existingIndex >= 0) {
          // 如果已存在，更新而不是添加
          print('📊 月K: 发现已存在相同日期的数据（索引=$existingIndex），将更新而不是创建新数据');
          final existingMonthData = existingData[existingIndex];
          final updatedMonthData = KlineData(
            tsCode: existingMonthData.tsCode,
            tradeDate: existingMonthData.tradeDate, // 保持原有日期
            open: firstDayData.open, // 本月第一个交易日的开盘价
            high: monthHigh, // 本月所有交易日的最高价
            low: monthLow, // 本月所有交易日的最低价
            close: realTimeData.close, // 最新交易日的收盘价
            preClose: existingMonthData.preClose,
            change: realTimeData.close - firstDayData.open,
            pctChg: firstDayData.open > 0 
                ? ((realTimeData.close - firstDayData.open) / firstDayData.open * 100)
                : 0.0,
            vol: monthVol, // 累积交易量
            amount: monthAmount, // 累积成交额
          );
          existingData[existingIndex] = updatedMonthData;
          print('✅ 月K: 更新已有月K数据成功，日期=${existingMonthData.tradeDate}, 收盘价=${updatedMonthData.close}, 成交量=$monthVol (原成交量=${existingMonthData.vol})');
          print('📊 月K: 验证更新后的数据 - 索引=$existingIndex, tradeDate=${existingData[existingIndex].tradeDate}, 成交量=${existingData[existingIndex].vol}');
        } else {
          // 如果不存在，创建新数据
          final newMonthData = KlineData(
            tsCode: tsCode,
            tradeDate: latestTradingDay, // 使用最新交易日的日期（而不是月初日期）
            open: firstDayData.open, // 本月第一个交易日的开盘价
            high: monthHigh, // 本月所有交易日的最高价
            low: monthLow, // 本月所有交易日的最低价
            close: realTimeData.close, // 最新交易日的收盘价
            preClose: preClose,
            change: realTimeData.close - firstDayData.open,
            pctChg: firstDayData.open > 0 
                ? ((realTimeData.close - firstDayData.open) / firstDayData.open * 100)
                : 0.0,
            vol: monthVol, // 累积交易量
            amount: monthAmount, // 累积成交额
          );
          
          existingData.add(newMonthData);
          existingData.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
          
          print('✅ 月K: 创建新的月K数据成功，日期=$latestTradingDay（最新交易日）, 收盘价=${newMonthData.close}, 成交量=$monthVol');
          // 查找新添加的数据在排序后的位置
          final newIndex = existingData.indexWhere((data) => data.tradeDate == latestTradingDay);
          if (newIndex >= 0) {
            print('📊 月K: 验证新创建的数据 - 索引=$newIndex, tradeDate=${existingData[newIndex].tradeDate}, 成交量=${existingData[newIndex].vol}');
          }
        }
      }
      
      // 验证返回数据：打印最后几条数据的成交量
      if (existingData.isNotEmpty) {
        final lastIndex = existingData.length - 1;
        print('📊 月K: 返回数据验证 - 最后一条数据: 索引=$lastIndex, 日期=${existingData[lastIndex].tradeDate}, 成交量=${existingData[lastIndex].vol}');
        if (existingData.length >= 3) {
          print('📊 月K: 返回数据最后3条的成交量:');
          for (int i = existingData.length - 3; i < existingData.length; i++) {
            print('  ${i + 1}. ${existingData[i].tradeDate}: 成交量=${existingData[i].vol}');
          }
        }
      }
      
      return existingData;
    }
    
    // 未知类型，返回原数据
    return existingData;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stockInfo.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadKlineData,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    // 股票基本信息
                    SliverToBoxAdapter(
                      child: _buildStockInfoCard(),
                    ),
                    // K线图（包含图表类型选择和设置）
                    SliverToBoxAdapter(
                      child: _buildKlineChart(),
                    ),
                    // 数据统计
                    SliverToBoxAdapter(
                      child: _buildStatisticsCard(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStockInfoCard() {
    final currentData = widget.currentKlineData ?? 
        (_klineDataList.isNotEmpty ? _klineDataList.last : null);
    final pctChg = currentData != null 
        ? (currentData.preClose > 0 
            ? ((currentData.close - currentData.preClose) / currentData.preClose * 100)
            : currentData.pctChg)
        : 0.0;
    final isPositive = pctChg >= 0;

    return Container(
      margin: const EdgeInsets.all(4), // 减小底部边距
      padding: const EdgeInsets.all(4), // 减小内边距
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.stockInfo.name,
                      style: const TextStyle(
                        fontSize: 20, // 减小字体
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2), // 减小间距
                    Text(
                      '${widget.stockInfo.symbol} | ${widget.stockInfo.market}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11, // 减小字体
                      ),
                    ),
                  ],
                ),
              ),
              if (currentData != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '¥${currentData.close.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 22, // 减小字体
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.red[700] : Colors.green[700],
                      ),
                    ),
                    Text(
                      '${isPositive ? '+' : ''}${pctChg.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 13, // 减小字体
                        color: isPositive ? Colors.red[700] : Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (currentData != null) ...[
            const SizedBox(height: 8), // 减小间距
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem('今开', '¥${currentData.open.toStringAsFixed(2)}'),
                ),
                Expanded(
                  child: _buildInfoItem('最高', '¥${currentData.high.toStringAsFixed(2)}'),
                ),
                Expanded(
                  child: _buildInfoItem('最低', '¥${currentData.low.toStringAsFixed(2)}'),
                ),
                Expanded(
                  child: _buildInfoItem('昨收', '¥${currentData.preClose.toStringAsFixed(2)}'),
                ),
              ],
            ),
            const SizedBox(height: 6), // 减小间距
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem('成交量', '${(currentData.vol / 10000).toStringAsFixed(0)}万手'),
                ),
                Expanded(
                  child: _buildInfoItem('成交额', '${currentData.amountInYi.toStringAsFixed(2)}亿元'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 10, // 减小字体
          ),
        ),
        const SizedBox(height: 2), // 减小间距
        Text(
          value,
          style: const TextStyle(
            fontSize: 12, // 减小字体
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // 显示设置对话框
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return _SettingsDialog(
          initialDays: _selectedDays,
          initialSubChartCount: _subChartCount,
          onConfirm: (days, subChartCount) {
            final daysChanged = _selectedDays != days;
            setState(() {
              _selectedDays = days;
              _subChartCount = subChartCount;
            });
            _saveSettings(); // 保存设置
            if (daysChanged) {
              _loadKlineData(); // 如果天数改变，重新加载数据
            }
          },
        );
      },
    );
  }


  Widget _buildChartTypeButton(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        // 根据标签确定图表类型
        String chartType;
        if (label == '日K') {
          chartType = 'daily';
        } else if (label == '周K') {
          chartType = 'weekly';
        } else if (label == '月K') {
          chartType = 'monthly';
        } else {
          return; // 未知类型，不处理
        }
        
        // 如果点击的是已选中的类型，不执行任何操作
        if (_selectedChartType == chartType) {
          return;
        }
        
        // 切换图表类型并重新加载数据
        setState(() {
          _selectedChartType = chartType;
        });
        _loadKlineData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // 减小上下边距
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12, // 稍微减小字体
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // 计算最新交易日的均线值
  Map<String, double?> _calculateLatestMovingAverages() {
    if (_klineDataList.length < 5) {
      return {'ma5': null, 'ma10': null, 'ma20': null, 'prevMa5': null, 'prevMa10': null, 'prevMa20': null};
    }
    
    // 计算MA5
    double? ma5;
    double? prevMa5;
    if (_klineDataList.length >= 5) {
      final last5 = _klineDataList.sublist(_klineDataList.length - 5);
      ma5 = last5.map((e) => e.close).reduce((a, b) => a + b) / 5;
      
      // 计算前一个交易日的MA5
      if (_klineDataList.length >= 6) {
        final prev5 = _klineDataList.sublist(_klineDataList.length - 6, _klineDataList.length - 1);
        prevMa5 = prev5.map((e) => e.close).reduce((a, b) => a + b) / 5;
      }
    }
    
    // 计算MA10
    double? ma10;
    double? prevMa10;
    if (_klineDataList.length >= 10) {
      final last10 = _klineDataList.sublist(_klineDataList.length - 10);
      ma10 = last10.map((e) => e.close).reduce((a, b) => a + b) / 10;
      
      // 计算前一个交易日的MA10
      if (_klineDataList.length >= 11) {
        final prev10 = _klineDataList.sublist(_klineDataList.length - 11, _klineDataList.length - 1);
        prevMa10 = prev10.map((e) => e.close).reduce((a, b) => a + b) / 10;
      }
    }
    
    // 计算MA20
    double? ma20;
    double? prevMa20;
    if (_klineDataList.length >= 20) {
      final last20 = _klineDataList.sublist(_klineDataList.length - 20);
      ma20 = last20.map((e) => e.close).reduce((a, b) => a + b) / 20;
      
      // 计算前一个交易日的MA20
      if (_klineDataList.length >= 21) {
        final prev20 = _klineDataList.sublist(_klineDataList.length - 21, _klineDataList.length - 1);
        prevMa20 = prev20.map((e) => e.close).reduce((a, b) => a + b) / 20;
      }
    }
    
    return {'ma5': ma5, 'ma10': ma10, 'ma20': ma20, 'prevMa5': prevMa5, 'prevMa10': prevMa10, 'prevMa20': prevMa20};
  }

  // 构建均线展示行
  Widget _buildMovingAverageRow() {
    final maValues = _calculateLatestMovingAverages();
    
    // 判断均线趋势（与前一个交易日的均线值比较）
    String getTrend(double? currentMa, double? prevMa) {
      if (currentMa == null || prevMa == null) return '';
      return currentMa >= prevMa ? '↑' : '↓';
    }
    
    return Row(
      children: [
        // MA5（黑色）
        Expanded(
          child: Row(
            children: [
              Text(
                'MA5:',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                maValues['ma5'] != null 
                  ? '${maValues['ma5']!.toStringAsFixed(2)}${getTrend(maValues['ma5'], maValues['prevMa5'])}'
                  : '--',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black, // 与K线图MA5颜色一致
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // MA10（黄色）
        Expanded(
          child: Row(
            children: [
              Text(
                'MA10:',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                maValues['ma10'] != null 
                  ? '${maValues['ma10']!.toStringAsFixed(2)}${getTrend(maValues['ma10'], maValues['prevMa10'])}'
                  : '--',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.yellow[700], // 与K线图MA10颜色一致
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // MA20（紫色）
        Expanded(
          child: Row(
            children: [
              Text(
                'MA20:',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                maValues['ma20'] != null 
                  ? '${maValues['ma20']!.toStringAsFixed(2)}${getTrend(maValues['ma20'], maValues['prevMa20'])}'
                  : '--',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.purple, // 与K线图MA20颜色一致
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKlineChart() {
    if (_klineDataList.isEmpty) {
      return Container(
        height: 400,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('暂无K线数据'),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图表类型选择和设置按钮
          Row(
            children: [
              // 图表类型选择按钮
              Expanded(
                child: Row(
                  children: [
                    _buildChartTypeButton('日K', _selectedChartType == 'daily'),
                    const SizedBox(width: 4),
                    _buildChartTypeButton('周K', _selectedChartType == 'weekly'),
                    const SizedBox(width: 4),
                    _buildChartTypeButton('月K', _selectedChartType == 'monthly'),
                  ],
                ),
              ),
              // 设置按钮
              IconButton(
                icon: const Icon(Icons.settings, size: 18), // 稍微减小图标
                onPressed: _showSettingsDialog,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4), // 减小间距
          // 均线展示行
          _buildMovingAverageRow(),
          const SizedBox(height: 8), // 减小间距
          SizedBox(
            height: 500,
            child: KlineChartWidget(
              klineDataList: _klineDataList,
              macdDataList: _macdDataList,
              displayDays: _selectedDays, // 只显示选择的天数，但均线计算用全部数据
              subChartCount: _subChartCount, // 显示选择的副图数量
              chartType: _selectedChartType, // 传递图表类型，用于格式化日期标签
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard() {
    if (_klineDataList.isEmpty) {
      return const SizedBox.shrink();
    }

    // 计算统计数据
    final prices = _klineDataList.map((e) => e.close).toList();
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final firstPrice = _klineDataList.first.close;
    final lastPrice = _klineDataList.last.close;
    final totalChange = lastPrice - firstPrice;
    final totalPctChg = firstPrice > 0 ? (totalChange / firstPrice * 100) : 0.0;

    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '统计信息',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem('最高价', '¥${maxPrice.toStringAsFixed(2)}', Colors.red[700]!),
              ),
              Expanded(
                child: _buildStatItem('最低价', '¥${minPrice.toStringAsFixed(2)}', Colors.green[700]!),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem('区间涨跌', '${totalChange >= 0 ? '+' : ''}${totalChange.toStringAsFixed(2)}', 
                    totalChange >= 0 ? Colors.red[700]! : Colors.green[700]!),
              ),
              Expanded(
                child: _buildStatItem('区间涨跌幅', '${totalPctChg >= 0 ? '+' : ''}${totalPctChg.toStringAsFixed(2)}%',
                    totalPctChg >= 0 ? Colors.red[700]! : Colors.green[700]!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// 设置对话框组件
class _SettingsDialog extends StatefulWidget {
  final int initialDays;
  final int initialSubChartCount;
  final Function(int, int) onConfirm;

  const _SettingsDialog({
    required this.initialDays,
    required this.initialSubChartCount,
    required this.onConfirm,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late int _selectedDays;
  late int _subChartCount;

  @override
  void initState() {
    super.initState();
    _selectedDays = widget.initialDays;
    _subChartCount = widget.initialSubChartCount;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('图表设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '显示天数',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildDayButton(60, '60日'),
                _buildDayButton(90, '90日'),
                _buildDayButton(180, '180日'),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '副图数量',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSubChartButton(1, '1个'),
                _buildSubChartButton(2, '2个'),
                _buildSubChartButton(3, '3个'),
                _buildSubChartButton(4, '4个'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            widget.onConfirm(_selectedDays, _subChartCount);
            Navigator.of(context).pop();
          },
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildDayButton(int days, String label) {
    final isSelected = _selectedDays == days;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _selectedDays = days;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue[600] : Colors.grey[200],
        foregroundColor: isSelected ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        minimumSize: const Size(60, 36),
      ),
      child: Text(label),
    );
  }

  Widget _buildSubChartButton(int count, String label) {
    final isSelected = _subChartCount == count;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _subChartCount = count;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue[600] : Colors.grey[200],
        foregroundColor: isSelected ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        minimumSize: const Size(70, 36),
      ),
      child: Text(label),
    );
  }
}

