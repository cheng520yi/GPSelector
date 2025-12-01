import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../services/stock_api_service.dart';
import '../services/stock_pool_config_service.dart';

class StockPredictionScreen extends StatefulWidget {
  final StockInfo stockInfo;
  final KlineData? currentKlineData;

  const StockPredictionScreen({
    super.key,
    required this.stockInfo,
    this.currentKlineData,
  });

  @override
  State<StockPredictionScreen> createState() => _StockPredictionScreenState();
}

class _StockPredictionScreenState extends State<StockPredictionScreen> {
  // K线类型：daily, weekly, monthly
  String _kLineType = 'daily';
  
  // 均线分析模式：none, 5, 10, 20
  String _maMode = 'none';
  
  // 输入字段
  final TextEditingController _manualPriceController = TextEditingController();
  DateTime _endDate = DateTime.now();
  DateTime? _maStartDate;
  DateTime? _maEndDate;
  
  // 是否启用手动输入价格
  bool _useManualInput = false;
  
  // 加载状态
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;
  
  // 预测结果数据
  Map<String, dynamic>? _predictionData;
  List<KlineData> _klineDataList = [];
  
  // 历史预测数据列表
  List<Map<String, dynamic>> _predictionHistoryList = [];
  
  // 计算结果是否展开
  bool _isResultExpanded = false;
  
  // 筛选区域是否展开
  bool _isFilterExpanded = false;
  
  @override
  void initState() {
    super.initState();
    _endDate = DateTime.now();
    _maStartDate = DateTime.now().subtract(const Duration(days: 30));
    _maEndDate = DateTime.now();
  }

  @override
  void dispose() {
    _manualPriceController.dispose();
    super.dispose();
  }

  // 安全处理股票代码格式
  String _ensureStockCodeFormat(String stockCode) {
    final cleanCode = stockCode.trim().toUpperCase();
    if (cleanCode.endsWith('.SH') || cleanCode.endsWith('.SZ')) {
      return cleanCode;
    }
    if (cleanCode.startsWith('0') || cleanCode.startsWith('3')) {
      return '$cleanCode.SZ';
    } else {
      return '$cleanCode.SH';
    }
  }

  // 计算开始日期（跳过周末）
  String _calculateStartDate(DateTime endDate, int days) {
    final dateObj = DateTime(endDate.year, endDate.month, endDate.day);
    int count = 0;
    DateTime currentDate = dateObj;

    while (count < days) {
      currentDate = currentDate.subtract(const Duration(days: 1));
      if (currentDate.weekday != 6 && currentDate.weekday != 7) {
        count++;
      }
    }

    return DateFormat('yyyyMMdd').format(currentDate);
  }

  // 计算移动平均线
  List<double?> _calculateMA(List<double> data, int period) {
    final result = <double?>[];
    for (int i = 0; i < data.length; i++) {
      if (i < period - 1) {
        result.add(null);
      } else {
        final sum = data.sublist(i - period + 1, i + 1)
            .fold(0.0, (a, b) => a + b);
        result.add(sum / period);
      }
    }
    return result;
  }

  // 获取下一个交易日
  DateTime _getNextTradingDay(DateTime date) {
    DateTime nextDate = date;
    do {
      nextDate = nextDate.add(const Duration(days: 1));
    } while (nextDate.weekday == 6 || nextDate.weekday == 7);
    return nextDate;
  }

  // 获取前一个交易日
  DateTime _getPreviousTradingDay(DateTime date) {
    DateTime prevDate = date;
    do {
      prevDate = prevDate.subtract(const Duration(days: 1));
    } while (prevDate.weekday == 6 || prevDate.weekday == 7);
    return prevDate;
  }

  // 获取预测日期对应的D1日期（交易日）
  DateTime _getD1Date(DateTime selectedDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    
    // 如果所选日期为交易日且在今天或之前，则把所选时间作为D1
    if (StockApiService.isTradingDay(selectedDate) && (selectedDay.isBefore(today) || selectedDay.isAtSameMomentAs(today))) {
      return selectedDate;
    }
    
    // 如果为非交易日，则预测时间显示为所选日期向前最近的一个交易日作为D1
    return _getPreviousTradingDay(selectedDate);
  }

  // 查询股票数据
  Future<void> _queryStockData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
      _predictionData = null;
    });

    try {
      // 直接使用传入的股票代码
      final fullCode = widget.stockInfo.tsCode;
      
      if (_maMode != 'none') {
        // 均线分析模式
        await _fetchMAData(fullCode);
      } else {
        // 普通查询模式
        await _fetchStockData(fullCode);
      }
    } catch (e) {
      setState(() {
        _errorMessage = '查询失败: $e';
        _isLoading = false;
      });
    }
  }

  // 获取普通股票数据
  Future<void> _fetchStockData(String tsCode) async {
    try {
      // 计算D1日期（预测日期对应的交易日）
      final d1Date = _getD1Date(_endDate);
      final d1DateStr = DateFormat('yyyy-MM-dd').format(d1Date);
      
      // 根据K线类型调整请求的数据量（用于绘制60天走势图）
      int daysToFetch = 90; // 多请求一些天数确保有60个交易日
      if (_kLineType == 'weekly') {
        daysToFetch = 420; // 60周约需要420个自然日
      } else if (_kLineType == 'monthly') {
        daysToFetch = 1800; // 60个月约需要1800个自然日
      }
      
      final startDateStr = _calculateStartDate(d1Date, daysToFetch);
      final actualApiName = (_kLineType == 'weekly' || _kLineType == 'monthly') 
          ? 'daily' 
          : _kLineType;

      // 获取K线数据
      List<KlineData> klineDataList = await StockApiService.getKlineData(
        tsCode: tsCode,
        kLineType: actualApiName,
        days: daysToFetch,
        stockName: widget.stockInfo.name,
      );

      if (klineDataList.isEmpty) {
        setState(() {
          _errorMessage = '未找到股票数据';
          _isLoading = false;
        });
        return;
      }

      // 按日期排序
      List<KlineData> sortedData = List<KlineData>.from(klineDataList)
        ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));

      // 判断是否应该使用实时接口（适用于所有K线类型）
      final now = DateTime.now();
      final config = await StockPoolConfigService.getConfig();
      final currentTime = now.hour * 100 + now.minute;
      
      bool shouldUseRealTime = false;
      String interfaceReason = '';
      
      if (StockApiService.isTradingDay(now) && currentTime >= 930) {
        if (config.enableRealtimeInterface) {
          // 开关打开时，检查是否在配置的时间窗口内
          final endTime = config.realtimeEndTime ?? const TimeOfDay(hour: 24, minute: 0);
          final endTimeMinutes = endTime.hour * 100 + endTime.minute;
          if (currentTime <= endTimeMinutes) {
            shouldUseRealTime = true;
            interfaceReason = 'iFinD实时接口（交易日 ${currentTime >= 930 ? '9:30' : ''}-${endTime.hour}:${endTime.minute.toString().padLeft(2, '0')}）';
          } else {
            interfaceReason = 'Tushare接口（超出实时接口时间窗口 ${endTime.hour}:${endTime.minute.toString().padLeft(2, '0')}）';
          }
        } else {
          // 开关关闭时，9:30-24:00都使用iFinD接口
          shouldUseRealTime = true;
          interfaceReason = 'iFinD实时接口（开关关闭，9:30-24:00）';
        }
      } else {
        if (!StockApiService.isTradingDay(now)) {
          interfaceReason = 'Tushare接口（非交易日）';
        } else if (currentTime < 930) {
          interfaceReason = 'Tushare接口（未到交易时间 9:30）';
        } else {
          interfaceReason = 'Tushare接口（不在交易时间窗口内）';
        }
      }

      print('📊 预测分析页面 - ${_kLineType}K: 使用${interfaceReason}');

      // 对于所有K线类型，尝试获取实时数据
      KlineData? realTimeData;
      if (shouldUseRealTime) {
        try {
          print('🔍 预测分析页面 - ${_kLineType}K: 尝试使用iFinD实时接口获取数据...');
          // 对于周K和月K，获取实时日K数据；对于日K，获取实时日K数据
          final realTimeDataMap = await StockApiService.getIFinDRealTimeData(
            tsCodes: [tsCode],
          );
          if (realTimeDataMap.containsKey(tsCode)) {
            realTimeData = realTimeDataMap[tsCode];
            print('✅ 预测分析页面 - ${_kLineType}K: iFinD实时接口获取成功，日期=${realTimeData!.tradeDate}, 收盘价=${realTimeData!.close}');
          } else {
            print('⚠️ 预测分析页面 - ${_kLineType}K: iFinD实时接口返回数据为空，将尝试Tushare接口');
          }
        } catch (e) {
          print('❌ 预测分析页面 - ${_kLineType}K: iFinD实时接口获取失败: $e，将尝试Tushare接口');
        }
      }

      // 如果没有获取到实时数据，尝试使用Tushare获取最新交易日数据
      if (realTimeData == null) {
        try {
          print('🔍 预测分析页面 - ${_kLineType}K: 尝试使用Tushare接口获取最新交易日数据...');
          final latestData = await StockApiService.getLatestTradingDayData(
            tsCode: tsCode,
          );
          if (latestData != null) {
            realTimeData = latestData;
            print('✅ 预测分析页面 - ${_kLineType}K: Tushare接口获取成功，日期=${realTimeData!.tradeDate}, 收盘价=${realTimeData!.close}');
          } else {
            print('⚠️ 预测分析页面 - ${_kLineType}K: Tushare接口返回数据为空');
          }
        } catch (e) {
          print('❌ 预测分析页面 - ${_kLineType}K: Tushare接口获取失败: $e');
        }
      }

      // 如果获取到实时数据，更新sortedData
      if (realTimeData != null) {
        // 对于周K和月K，需要判断实时数据是否属于当前周/月
        bool shouldUseRealTimeData = true;
        
        if (_kLineType == 'weekly' || _kLineType == 'monthly') {
          final realTimeDate = DateTime.parse(
            '${realTimeData.tradeDate.substring(0,4)}-'
            '${realTimeData.tradeDate.substring(4,6)}-'
            '${realTimeData.tradeDate.substring(6,8)}'
          );
          
          if (_kLineType == 'weekly') {
            // 检查实时数据是否属于当前周
            final daysFromMonday = now.weekday - 1;
            final currentWeekStart = now.subtract(Duration(days: daysFromMonday));
            final realTimeWeekStart = realTimeDate.subtract(Duration(days: realTimeDate.weekday - 1));
            
            if (realTimeWeekStart.year != currentWeekStart.year ||
                realTimeWeekStart.month != currentWeekStart.month ||
                realTimeWeekStart.day != currentWeekStart.day) {
              shouldUseRealTimeData = false;
              print('⚠️ 周K: 实时数据不属于当前周，不使用实时数据');
            }
          } else if (_kLineType == 'monthly') {
            // 检查实时数据是否属于当前月
            if (realTimeDate.year != now.year || realTimeDate.month != now.month) {
              shouldUseRealTimeData = false;
              print('⚠️ 月K: 实时数据不属于当前月，不使用实时数据');
            }
          }
        }

        if (shouldUseRealTimeData) {
          // 检查sortedData中是否已有该日期的数据，如果有则替换，否则添加
          final existingIndex = sortedData.indexWhere(
            (data) => data.tradeDate == realTimeData!.tradeDate
          );
          
          if (existingIndex >= 0) {
            sortedData[existingIndex] = realTimeData!;
            print('✅ ${_kLineType}K: 替换历史数据中的实时数据');
          } else {
            sortedData.add(realTimeData!);
            sortedData.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
            print('✅ ${_kLineType}K: 添加实时数据到历史数据');
          }
        }
      }


      // 如果没有手动输入，确保使用预测日期（d1Date）的收盘价作为D1
      // 找到sortedData中日期等于d1Date的数据
      final d1DateStr8 = DateFormat('yyyyMMdd').format(d1Date);
      final d1DateStr10 = d1DateStr;
      
      KlineData? d1KlineData;
      int d1Index = -1;
      for (int i = sortedData.length - 1; i >= 0; i--) {
        final data = sortedData[i];
        if (data.tradeDate == d1DateStr8 || data.tradeDate == d1DateStr10) {
          d1KlineData = data;
          d1Index = i;
          break;
        }
      }
      
      if (d1KlineData == null) {
        setState(() {
          _errorMessage = '未找到预测日期（${d1DateStr}）的K线数据';
          _isLoading = false;
        });
        return;
      }
      
      print('✅ 找到预测日期（${d1DateStr}）的K线数据，收盘价=${d1KlineData.close}');

      // 提取收盘价（用于计算指标）
      final closes = sortedData.map((e) => e.close).toList();
      final dates = sortedData.map((e) => e.tradeDate).toList();
      
      // 保存完整的K线数据（用于绘制预测走势图）
      // 只展示预测日期前40个交易单位的数据（包含预测日期）
      // 找到d1Index，然后取前40个交易单位的数据
      final chartDataCountForKline = 40;
      final startIndex = math.max(0, d1Index - chartDataCountForKline + 1); // 包含d1Date，所以+1
      final klineDataForChart = sortedData.sublist(
        startIndex,
        d1Index + 1, // 包含d1Date
      );

      // 对于周K和月K，如果启用手动输入，需要先将手动输入添加到日K数据，然后再分组
      // 对于日K，手动输入直接添加到数据末尾
      double? manualPrice;
      List<double> displayCloses;
      List<String> displayDates;
      
      if (_useManualInput && _manualPriceController.text.isNotEmpty) {
        manualPrice = double.tryParse(_manualPriceController.text);
        if (manualPrice != null && manualPrice > 0) {
          if (_kLineType == 'weekly' || _kLineType == 'monthly') {
            // 周K和月K：先将手动输入添加到日K数据，然后分组
            // 计算下一个交易日
            String lastDateStr = dates.last;
            DateTime lastDate;
            if (lastDateStr.length == 8) {
              lastDate = DateTime.parse(
                '${lastDateStr.substring(0, 4)}-'
                '${lastDateStr.substring(4, 6)}-'
                '${lastDateStr.substring(6, 8)}',
              );
            } else {
              lastDate = DateTime.parse(lastDateStr);
            }
            final nextDate = _getNextTradingDay(lastDate);
            final nextDateStr = DateFormat('yyyy-MM-dd').format(nextDate);
            
            // 将手动输入添加到日K数据
            final closesWithManual = List<double>.from(closes)..add(manualPrice);
            final datesWithManual = List<String>.from(dates)..add(nextDateStr);
            
            // 对包含手动输入的日K数据进行分组
            final grouped = _groupDailyToPeriods(
              closesWithManual,
              datesWithManual,
              _kLineType,
              closesWithManual.length - 1, // 包含手动输入后的总长度
            );
            displayCloses = List.from(grouped['periodCloses'] as List<double>);
            displayDates = List.from(grouped['periodDates'] as List<String>);
          } else {
            // 日K：直接添加到数据末尾
            displayCloses = List.from(closes)..add(manualPrice);
            displayDates = List.from(dates);
            String lastDateStr = dates.last;
            DateTime lastDate;
            if (lastDateStr.length == 8) {
              lastDate = DateTime.parse(
                '${lastDateStr.substring(0, 4)}-'
                '${lastDateStr.substring(4, 6)}-'
                '${lastDateStr.substring(6, 8)}',
              );
            } else {
              lastDate = DateTime.parse(lastDateStr);
            }
            final nextDate = _getNextTradingDay(lastDate);
            final nextDateStr = DateFormat('yyyy-MM-dd').format(nextDate);
            displayDates.add(nextDateStr);
          }
        } else {
          setState(() {
            _errorMessage = '请输入有效的价格';
            _isLoading = false;
          });
          return;
        }
      } else {
        // 没有手动输入，确保使用预测日期（d1Date）的收盘价作为D1
        if (_kLineType == 'weekly' || _kLineType == 'monthly') {
          // 周K和月K：对日K数据进行分组，但确保最后一条数据的日期是d1Date
          // 需要找到包含d1Date的周期，确保该周期的收盘价是d1Date的收盘价
          
          // 截取到d1Date的数据（包含d1Date）
          final closesToD1 = closes.sublist(0, d1Index + 1);
          final datesToD1 = dates.sublist(0, d1Index + 1);
          
          // 对包含d1Date的日K数据进行分组
          final grouped = _groupDailyToPeriods(
            closesToD1,
            datesToD1,
            _kLineType,
            d1Index, // 使用d1Index作为目标日期索引
          );
          displayCloses = List.from(grouped['periodCloses'] as List<double>);
          displayDates = List.from(grouped['periodDates'] as List<String>);
          
          // 验证最后一条数据的日期是否是d1Date
          final lastPeriodDate = displayDates.last;
          final lastPeriodDate8 = lastPeriodDate.length == 8 
              ? lastPeriodDate 
              : lastPeriodDate.replaceAll('-', '');
          if (lastPeriodDate8 != d1DateStr8) {
            print('⚠️ 警告：周K/月K最后一条数据的日期（$lastPeriodDate）不是预测日期（$d1DateStr）');
            // 如果最后一条数据的日期不是d1Date，需要确保使用d1Date的收盘价
            // 这种情况不应该发生，因为_groupDailyToPeriods应该会包含d1Date
          }
          
          print('✅ 周K/月K分组完成，最后一条数据日期=${displayDates.last}，收盘价=${displayCloses.last}');
        } else {
          // 日K：确保最后一条数据的日期是d1Date
          // 截取到d1Date的数据（包含d1Date）
          displayCloses = closes.sublist(0, d1Index + 1);
          displayDates = dates.sublist(0, d1Index + 1);
          
          // 验证最后一条数据的日期是否是d1Date
          final lastDate = displayDates.last;
          final lastDate8 = lastDate.length == 8 
              ? lastDate 
              : lastDate.replaceAll('-', '');
          if (lastDate8 != d1DateStr8) {
            setState(() {
              _errorMessage = '数据错误：最后一条数据的日期（$lastDate）不是预测日期（$d1DateStr）';
              _isLoading = false;
            });
            return;
          }
          
          print('✅ 日K数据准备完成，最后一条数据日期=${displayDates.last}，收盘价=${displayCloses.last}');
        }
      }

      // 计算指标（基于最后10个数据，如果启用手动输入，手动价格就是新的D1）
      double D1, D5, D10, C5, C10;
      
      if (displayCloses.length >= 10) {
        // 获取最后10个收盘价
        final last10Closes = displayCloses.sublist(
          displayCloses.length - 10,
        );
        
        // 打印计算过程（手动输入情况下）
        if (_useManualInput && _kLineType == 'monthly') {
          print('📊 月K手动输入计算过程：');
          print('   最后10个${_kLineType == 'monthly' ? '月' : _kLineType == 'weekly' ? '周' : '日'}K收盘价（从旧到新）：');
          for (int i = 0; i < last10Closes.length; i++) {
            final dateIndex = displayDates.length - 10 + i;
            final dateStr = dateIndex >= 0 && dateIndex < displayDates.length 
                ? displayDates[dateIndex] 
                : '未知';
            print('   [${i}] ${dateStr}: ${last10Closes[i].toStringAsFixed(4)}');
          }
        }
        
        // D1是最后一天（如果启用手动输入，就是手动输入的价格）
        D1 = last10Closes[9];
        // D5是倒数第6天（原来的D1变成了D2，D2变成D3...）
        D5 = last10Closes[5];
        // D10是倒数第10天
        D10 = last10Closes[0];
        
        if (_useManualInput && _kLineType == 'monthly') {
          final d1Date = displayDates.length >= 10 ? displayDates[displayDates.length - 1] : '未知';
          final d5Date = displayDates.length >= 10 ? displayDates[displayDates.length - 6] : '未知';
          final d10Date = displayDates.length >= 10 ? displayDates[displayDates.length - 10] : '未知';
          print('   D1 (最后一个月) = ${D1.toStringAsFixed(4)} (日期: $d1Date)');
          print('   D5 (倒数第6个月) = ${D5.toStringAsFixed(4)} (日期: $d5Date)');
          print('   D10 (倒数第10个月) = ${D10.toStringAsFixed(4)} (日期: $d10Date)');
        }
        
        // C5 - 最近5个周期收盘价的平均值（包括手动输入的价格）
        // 注意：对于月K，这是最后5个月的平均值；对于周K，这是最后5周的平均值；对于日K，这是最后5日的平均值
        final c5Data = last10Closes.sublist(5); // 索引5-9，共5个数据
        C5 = c5Data.fold(0.0, (a, b) => a + b) / c5Data.length;
        
        if (_useManualInput && _kLineType == 'monthly') {
          print('   C5计算过程：');
          print('   用于计算C5的数据（最后5个月，索引5-9）：');
          double sum = 0.0;
          for (int i = 5; i < last10Closes.length; i++) {
            final dateIndex = displayDates.length - 10 + i;
            final dateStr = dateIndex >= 0 && dateIndex < displayDates.length 
                ? displayDates[dateIndex] 
                : '未知';
            final value = last10Closes[i];
            sum += value;
            print('     [${i}] ${dateStr}: ${value.toStringAsFixed(4)}');
          }
          print('   总和 = ${sum.toStringAsFixed(4)}');
          print('   平均值 C5 = ${sum.toStringAsFixed(4)} / ${c5Data.length} = ${C5.toStringAsFixed(4)}');
        }
        
        // C10 - 最近10个周期收盘价的平均值（包括手动输入的价格）
        C10 = last10Closes.fold(0.0, (a, b) => a + b) / last10Closes.length;
        
        if (_useManualInput && _kLineType == 'monthly') {
          print('   C10计算过程：');
          print('   用于计算C10的数据（最后10个月，索引0-9）：');
          double sum10 = 0.0;
          for (int i = 0; i < last10Closes.length; i++) {
            final dateIndex = displayDates.length - 10 + i;
            final dateStr = dateIndex >= 0 && dateIndex < displayDates.length 
                ? displayDates[dateIndex] 
                : '未知';
            final value = last10Closes[i];
            sum10 += value;
            print('     [${i}] ${dateStr}: ${value.toStringAsFixed(4)}');
          }
          print('   总和 = ${sum10.toStringAsFixed(4)}');
          print('   平均值 C10 = ${sum10.toStringAsFixed(4)} / ${last10Closes.length} = ${C10.toStringAsFixed(4)}');
        }
      } else {
        setState(() {
          _errorMessage = '数据不足，无法计算指标';
          _isLoading = false;
        });
        return;
      }

      // 计算其他指标（使用更新后的D1）
      final M5 = (D1 - D5) / 5 + C5;
      final L5 = (M5 * 5 - D1) / 4;
      final H5 = (M5 * 5 - D1) / 3.76;
      final M10 = (D1 - D10) / 10 + C10;
      final QW = D1 + (D1 - M5) * 5;
      final FW = M5 + 0.1 * D1 / 5;

      // 打印其他指标的计算过程（手动输入情况下，月K）
      if (_useManualInput && _kLineType == 'monthly') {
        print('   其他指标计算：');
        print('   M5 = (D1 - D5) / 5 + C5');
        print('      = (${D1.toStringAsFixed(4)} - ${D5.toStringAsFixed(4)}) / 5 + ${C5.toStringAsFixed(4)}');
        print('      = ${((D1 - D5) / 5).toStringAsFixed(4)} + ${C5.toStringAsFixed(4)}');
        print('      = ${M5.toStringAsFixed(4)}');
        print('   L5 = (M5 × 5 - D1) / 4');
        print('      = (${M5.toStringAsFixed(4)} × 5 - ${D1.toStringAsFixed(4)}) / 4');
        print('      = ${((M5 * 5 - D1) / 4).toStringAsFixed(4)}');
        print('      = ${L5.toStringAsFixed(4)}');
        print('   H5 = (M5 × 5 - D1) / 3.76');
        print('      = (${M5.toStringAsFixed(4)} × 5 - ${D1.toStringAsFixed(4)}) / 3.76');
        print('      = ${((M5 * 5 - D1) / 3.76).toStringAsFixed(4)}');
        print('      = ${H5.toStringAsFixed(4)}');
        print('   M10 = (D1 - D10) / 10 + C10');
        print('       = (${D1.toStringAsFixed(4)} - ${D10.toStringAsFixed(4)}) / 10 + ${C10.toStringAsFixed(4)}');
        print('       = ${((D1 - D10) / 10).toStringAsFixed(4)} + ${C10.toStringAsFixed(4)}');
        print('       = ${M10.toStringAsFixed(4)}');
        print('   QW = D1 + (D1 - M5) × 5');
        print('      = ${D1.toStringAsFixed(4)} + (${D1.toStringAsFixed(4)} - ${M5.toStringAsFixed(4)}) × 5');
        print('      = ${D1.toStringAsFixed(4)} + ${((D1 - M5) * 5).toStringAsFixed(4)}');
        print('      = ${QW.toStringAsFixed(4)}');
        print('   FW = M5 + 0.1 × D1 / 5');
        print('      = ${M5.toStringAsFixed(4)} + 0.1 × ${D1.toStringAsFixed(4)} / 5');
        print('      = ${M5.toStringAsFixed(4)} + ${(0.1 * D1 / 5).toStringAsFixed(4)}');
        print('      = ${FW.toStringAsFixed(4)}');
        print('📊 月K手动输入计算完成');
      }

      // 计算预测日期
      // D1日期就是d1Date（已经计算好的交易日）
      // 如果没有手动输入：预测日期是D1所在的交易日
      // 如果有手动输入：预测日期是手动输入日期本身（即D1所在交易日的下一个交易日）
      String nextDateStr;
      if (_useManualInput && manualPrice != null) {
        // 如果启用了手动输入，预测日期就是手动输入日期本身（已经在上面添加到displayDates了）
        nextDateStr = displayDates.last;
      } else {
        // 如果没有手动输入，预测日期就是D1所在的交易日
        nextDateStr = d1DateStr;
      }
      
      // 保存真实的操作时间（当前时间）作为查询时间
      final queryTime = DateTime.now();

      // 计算5日、10日和20日均线（用于绘制预测走势图）
      final ma5 = _calculateMA(displayCloses, 5);
      final displayMA5 = ma5.where((e) => e != null).map((e) => e!).toList();
      final ma10 = _calculateMA(displayCloses, 10);
      final displayMA10 = ma10.where((e) => e != null).map((e) => e!).toList();
      final ma20 = _calculateMA(displayCloses, 20);
      final displayMA20 = ma20.where((e) => e != null).map((e) => e!).toList();

      // 对于图表数据，需要找到对应的displayDates和displayCloses的索引
      // 计算displayDates中对应d1Date的索引
      int d1DisplayIndex = -1;
      final d1DateStrForMatch = d1DateStr8.length == 8 
          ? '${d1DateStr8.substring(0, 4)}-${d1DateStr8.substring(4, 6)}-${d1DateStr8.substring(6, 8)}'
          : d1DateStr10;
      for (int i = displayDates.length - 1; i >= 0; i--) {
        final dateStr = displayDates[i];
        final dateStr8 = dateStr.length == 10 
            ? dateStr.replaceAll('-', '')
            : dateStr;
        if (dateStr == d1DateStrForMatch || dateStr8 == d1DateStr8) {
          d1DisplayIndex = i;
          break;
        }
      }
      
      // 如果找不到，使用最后一条数据
      if (d1DisplayIndex < 0) {
        d1DisplayIndex = displayDates.length - 1;
      }
      
      // 取前40个交易单位的数据（包含d1Date）
      final chartDataCount = 40;
      final chartStartIndex = math.max(0, d1DisplayIndex - chartDataCount + 1);
      final chartEndIndex = d1DisplayIndex + 1;
      
      // 计算MA数据的起始索引（MA数据可能少于价格数据）
      final ma5StartIndex = math.max(0, chartStartIndex - (displayCloses.length - displayMA5.length));
      final ma5EndIndex = chartEndIndex - (displayCloses.length - displayMA5.length);
      final ma10StartIndex = math.max(0, chartStartIndex - (displayCloses.length - displayMA10.length));
      final ma10EndIndex = chartEndIndex - (displayCloses.length - displayMA10.length);
      final ma20StartIndex = math.max(0, chartStartIndex - (displayCloses.length - displayMA20.length));
      final ma20EndIndex = chartEndIndex - (displayCloses.length - displayMA20.length);

      // 创建预测数据
      final predictionData = {
        'stockCode': tsCode,
        'stockName': widget.stockInfo.name,
        'date': nextDateStr,
        'queryDate': DateFormat('yyyy-MM-dd HH:mm:ss').format(queryTime), // 真实的操作时间
        'predictionDate': d1DateStr, // D1日期（交易日）
        'klineData': klineDataForChart.map((k) => k.toJson()).toList(),
        'dates': displayDates.sublist(chartStartIndex, chartEndIndex).map((d) {
          // 确保日期格式为 yyyy-MM-dd
          if (d.length == 8) {
            return '${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)}';
          }
          return d;
        }).toList(),
        'prices': displayCloses.sublist(chartStartIndex, chartEndIndex),
        'ma5': displayMA5.length >= ma5EndIndex && ma5EndIndex > ma5StartIndex
            ? displayMA5.sublist(ma5StartIndex, ma5EndIndex)
            : displayMA5.length > (chartEndIndex - chartStartIndex)
                ? displayMA5.sublist(displayMA5.length - (chartEndIndex - chartStartIndex))
                : displayMA5,
        'ma10': displayMA10.length >= ma10EndIndex && ma10EndIndex > ma10StartIndex
            ? displayMA10.sublist(ma10StartIndex, ma10EndIndex)
            : displayMA10.length > (chartEndIndex - chartStartIndex)
                ? displayMA10.sublist(displayMA10.length - (chartEndIndex - chartStartIndex))
                : displayMA10,
        'ma20': displayMA20.length >= ma20EndIndex && ma20EndIndex > ma20StartIndex
            ? displayMA20.sublist(ma20StartIndex, ma20EndIndex)
            : displayMA20.length > (chartEndIndex - chartStartIndex)
                ? displayMA20.sublist(displayMA20.length - (chartEndIndex - chartStartIndex))
                : displayMA20,
        'D1': D1,
        'D5': D5,
        'D10': D10,
        'C5': C5,
        'C10': C10,
        'M5': M5,
        'L5': L5,
        'H5': H5,
        'M10': M10,
        'QW': QW,
        'FW': FW,
        'manualPrice': manualPrice,
        'kLineType': _kLineType,
        'createTime': DateTime.now().toIso8601String(),
      };

      setState(() {
        _predictionData = predictionData;
        // 添加到历史记录（避免重复）
        final existingIndex = _predictionHistoryList.indexWhere(
          (item) => item['stockCode'] == tsCode && 
                    item['queryDate'] == predictionData['queryDate'] &&
                    item['kLineType'] == _kLineType &&
                    (item['manualPrice'] == manualPrice || 
                     (item['manualPrice'] == null && manualPrice == null)),
        );
        if (existingIndex >= 0) {
          _predictionHistoryList[existingIndex] = predictionData;
        } else {
          _predictionHistoryList.insert(0, predictionData);
        }
        // 限制历史记录数量（最多保存50条）
        if (_predictionHistoryList.length > 50) {
          _predictionHistoryList = _predictionHistoryList.sublist(0, 50);
        }
        _klineDataList = sortedData;
        _isLoading = false;
        // 显示成功消息，3秒后自动消失
        setState(() {
          _successMessage = '数据获取成功！';
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _successMessage = null;
            });
          }
        });
      });
    } catch (e) {
      setState(() {
        _errorMessage = '获取数据失败: $e';
        _isLoading = false;
      });
    }
  }

  // 获取均线分析数据
  Future<void> _fetchMAData(String tsCode) async {
    try {
      if (_maStartDate == null || _maEndDate == null) {
        setState(() {
          _errorMessage = '请选择开始日期和结束日期';
          _isLoading = false;
        });
        return;
      }

      final startDateStr = DateFormat('yyyyMMdd').format(_maStartDate!);
      final endDateStr = DateFormat('yyyyMMdd').format(_maEndDate!);
      final maPeriod = int.parse(_maMode);

      // 扩展开始日期以计算均线
      final extendedStartDate = _calculateStartDate(_maStartDate!, maPeriod);
      
      // 获取K线数据
      final klineDataList = await StockApiService.getKlineData(
        tsCode: tsCode,
        kLineType: _kLineType,
        days: _maEndDate!.difference(_maStartDate!).inDays + maPeriod * 2,
        stockName: widget.stockInfo.name,
      );

      if (klineDataList.isEmpty) {
        setState(() {
          _errorMessage = '未找到股票数据';
          _isLoading = false;
        });
        return;
      }

      // 按日期排序
      final sortedData = List<KlineData>.from(klineDataList)
        ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));

      // 提取收盘价和日期
      final closes = sortedData.map((e) => e.close).toList();
      final dates = sortedData.map((e) {
        final d = e.tradeDate;
        return '${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)}';
      }).toList();

      // 找到用户指定日期范围的数据
      final startDateStrForCompare = DateFormat('yyyy-MM-dd').format(_maStartDate!);
      final endDateStrForCompare = DateFormat('yyyy-MM-dd').format(_maEndDate!);
      int startIndex = dates.indexWhere((date) => date.compareTo(startDateStrForCompare) >= 0);
      int endIndex = dates.indexWhere((date) => date.compareTo(endDateStrForCompare) > 0);
      
      if (endIndex == -1) endIndex = dates.length;
      if (startIndex == -1) startIndex = 0;

      // 截取指定日期范围的数据
      final displayDates = dates.sublist(startIndex, endIndex);
      final displayCloses = closes.sublist(startIndex, endIndex);

      // 计算均线
      final ma = _calculateMA(displayCloses, maPeriod);
      final displayMA = ma.where((e) => e != null).map((e) => e!).toList();

      // 计算连涨连跌天数
      final consecutiveDays = _calculateConsecutiveDays(displayMA);

      setState(() {
        _predictionData = {
          'stockCode': tsCode,
          'stockName': widget.stockInfo.name,
          'dates': displayDates,
          'prices': displayCloses,
          'ma': displayMA,
          'maPeriod': maPeriod,
          'consecutiveUpDays': consecutiveDays['maxRise'],
          'consecutiveDownDays': consecutiveDays['maxFall'],
          'kLineType': _kLineType,
        };
        _klineDataList = sortedData;
        _isLoading = false;
        // 显示成功消息，3秒后自动消失
        setState(() {
          _successMessage = '均线分析数据获取成功！';
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _successMessage = null;
            });
          }
        });
      });
    } catch (e) {
      setState(() {
        _errorMessage = '获取均线数据失败: $e';
        _isLoading = false;
      });
    }
  }

  // 将日K线数据按周或月进行分组
  Map<String, dynamic> _groupDailyToPeriods(
    List<double> dailyCloses,
    List<String> dailyDates,
    String periodType,
    int targetDateIndex,
  ) {
    final periodCloses = <double>[];
    final periodDates = <String>[];
    DateTime? currentPeriodStart;
    double? lastCloseOfCurrentPeriod;
    String? lastDateOfCurrentPeriod;

    for (int i = 0; i <= targetDateIndex && i < dailyCloses.length; i++) {
      final dateStr = dailyDates[i];
      // 处理两种日期格式：yyyyMMdd 或 yyyy-MM-dd
      DateTime date;
      if (dateStr.length == 8) {
        // yyyyMMdd格式
        date = DateTime.parse(
          '${dateStr.substring(0, 4)}-'
          '${dateStr.substring(4, 6)}-'
          '${dateStr.substring(6, 8)}',
        );
      } else {
        // yyyy-MM-dd格式，直接解析
        date = DateTime.parse(dateStr);
      }
      final close = dailyCloses[i];
      DateTime periodStartDate;

      if (periodType == 'weekly') {
        final dayOfWeek = date.weekday;
        final diff = date.day - dayOfWeek + (dayOfWeek == 7 ? -6 : 1);
        periodStartDate = DateTime(date.year, date.month, diff);
      } else {
        periodStartDate = DateTime(date.year, date.month, 1);
      }
      periodStartDate = DateTime(periodStartDate.year, periodStartDate.month, periodStartDate.day);

      if (currentPeriodStart == null || 
          periodStartDate.year != currentPeriodStart.year ||
          periodStartDate.month != currentPeriodStart.month ||
          (periodType == 'weekly' && periodStartDate.day != currentPeriodStart.day)) {
        if (lastCloseOfCurrentPeriod != null) {
          periodCloses.add(lastCloseOfCurrentPeriod);
          periodDates.add(lastDateOfCurrentPeriod!);
        }
        currentPeriodStart = periodStartDate;
        lastCloseOfCurrentPeriod = close;
        lastDateOfCurrentPeriod = dateStr;
      } else {
        lastCloseOfCurrentPeriod = close;
        lastDateOfCurrentPeriod = dateStr;
      }
    }
    
    if (lastCloseOfCurrentPeriod != null) {
      periodCloses.add(lastCloseOfCurrentPeriod);
      periodDates.add(lastDateOfCurrentPeriod!);
    }
    
    return {
      'periodCloses': periodCloses,
      'periodDates': periodDates,
    };
  }

  // 计算最长连续上涨/下跌天数
  Map<String, int> _calculateConsecutiveDays(List<double> data) {
    if (data.length < 2) {
      return {'maxRise': 0, 'maxFall': 0};
    }

    int currentRise = 0;
    int currentFall = 0;
    int maxRise = 0;
    int maxFall = 0;

    for (int i = 1; i < data.length; i++) {
      if (data[i] > data[i - 1]) {
        currentRise++;
        currentFall = 0;
        maxRise = maxRise > currentRise ? maxRise : currentRise;
      } else if (data[i] < data[i - 1]) {
        currentFall++;
        currentRise = 0;
        maxFall = maxFall > currentFall ? maxFall : currentFall;
      } else {
        currentRise = 0;
        currentFall = 0;
      }
    }

    return {'maxRise': maxRise, 'maxFall': maxFall};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('股票预测分析'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              _showIndicatorExplanation();
            },
            tooltip: '指标说明',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 股票信息展示
            _buildStockInfoCard(),
            const SizedBox(height: 16),
            
            // 预测条件区域（可折叠，包含查询按钮和计算结果）
            _buildFilterSection(),
            
            // 消息显示
            if (_errorMessage != null) _buildErrorMessage(),
            if (_successMessage != null) _buildSuccessMessage(),
            
            // 加载指示器
            if (_isLoading) _buildLoader(),
            
            // 历史预测记录（只显示当前K线类型的记录）
            if (_getFilteredHistoryList().isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildPredictionHistoryList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStockInfoCard() {
    final currentData = widget.currentKlineData;
    final pctChg = currentData != null 
        ? (currentData.preClose > 0 
            ? ((currentData.close - currentData.preClose) / currentData.preClose * 100)
            : currentData.pctChg)
        : 0.0;
    final isPositive = pctChg >= 0;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.stockInfo.tsCode.split('.').first} | ${widget.stockInfo.market}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
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
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: isPositive ? Colors.red[700] : Colors.green[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${isPositive ? '+' : ''}${currentData.change.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: isPositive ? Colors.red[700] : Colors.green[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${isPositive ? '+' : ''}${pctChg.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontSize: 14,
                              color: isPositive ? Colors.red[700] : Colors.green[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
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
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterSection() {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          title: Row(
            children: [
              const Text(
                '预测条件',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getKLineTypeColor(_kLineType),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getKLineTypeText(_kLineType),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          initiallyExpanded: _isFilterExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _isFilterExpanded = expanded;
            });
          },
          childrenPadding: EdgeInsets.zero,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  // K线类型和均线模式选择
                  _buildModeSelectors(),
                  const SizedBox(height: 16),
                  // 输入区域
                  _buildInputArea(),
                  const SizedBox(height: 16),
                  // 查询按钮
                  _buildQueryButton(),
                  // 预测结果
                  if (_predictionData != null && !_isLoading) ...[
                    const SizedBox(height: 16),
                    _buildPredictionResult(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 过滤历史记录，只显示当前K线类型的记录
  void _filterHistoryByKLineType() {
    // 历史记录已经在保存时包含了kLineType，这里不需要额外过滤
    // 因为显示时会根据当前_kLineType过滤
  }

  // 获取当前K线类型的历史记录
  List<Map<String, dynamic>> _getFilteredHistoryList() {
    return _predictionHistoryList
        .where((item) => item['kLineType'] == _kLineType)
        .toList();
  }

  Widget _buildModeSelectors() {
    return Row(
      children: [
        Expanded(
          child: _buildSelector(
            'K线周期',
            _kLineType,
            ['daily', 'weekly', 'monthly'],
            ['日K', '周K', '月K'],
            (value) {
              setState(() {
                _kLineType = value;
                // 切换K线类型时，清空当前预测结果
                _predictionData = null;
              });
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSelector(
            '均线分析',
            _maMode,
            ['none', '5', '10', '20'],
            ['不使用', '5日均线', '10日均线', '20日均线'],
            (value) {
              setState(() {
                _maMode = value;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSelector(
    String label,
    String value,
    List<String> options,
    List<String> labels,
    Function(String) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            items: List.generate(
              options.length,
              (index) => DropdownMenuItem(
                value: options[index],
                child: Text(labels[index]),
              ),
            ),
            onChanged: (newValue) {
              if (newValue != null) {
                onChanged(newValue);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInputArea() {
    return Column(
      children: [
        // 预测日期（非均线模式）
        if (_maMode == 'none')
          Row(
            children: [
              Expanded(
                child: _buildDatePicker(
                  '预测日期',
                  _endDate,
                  (date) {
                    setState(() {
                      _endDate = date;
                    });
                  },
                ),
              ),
            ],
          ),
        
        // 均线分析日期范围
        if (_maMode != 'none') ...[
          Row(
            children: [
              Expanded(
                child: _buildDatePicker(
                  '开始日期',
                  _maStartDate ?? DateTime.now(),
                  (date) {
                    setState(() {
                      _maStartDate = date;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDatePicker(
                  '结束日期',
                  _maEndDate ?? DateTime.now(),
                  (date) {
                    setState(() {
                      _maEndDate = date;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
        
        const SizedBox(height: 16),
        
        // 手动输入价格开关
        if (_maMode == 'none')
          Row(
            children: [
              Checkbox(
                value: _useManualInput,
                onChanged: (value) {
                  setState(() {
                    _useManualInput = value ?? false;
                  });
                },
              ),
              const Text('实时输入价格'),
              if (_useManualInput) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _manualPriceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '最新价格',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildDatePicker(String label, DateTime date, Function(DateTime) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2000),
              lastDate: DateTime.now(),
            );
            if (picked != null) {
              onChanged(picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 20),
                const SizedBox(width: 8),
                Text(DateFormat('yyyy-MM-dd').format(date)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQueryButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _queryStockData,
        icon: const Icon(Icons.search),
        label: const Text('查询数据'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessMessage() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _successMessage != null ? null : 0,
      child: _successMessage != null
          ? Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _successMessage!,
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildLoader() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildPredictionResult() {
    if (_maMode != 'none') {
      return _buildMAAnalysisResult();
    } else {
      return _buildNormalPredictionResult();
    }
  }

  Widget _buildNormalPredictionResult() {
    final data = _predictionData!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 指标计算结果（可展开）
        Card(
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              title: const Text(
                '动量指标计算结果',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              initiallyExpanded: _isResultExpanded,
              onExpansionChanged: (expanded) {
                setState(() {
                  _isResultExpanded = expanded;
                });
              },
              childrenPadding: EdgeInsets.zero,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      _buildIndicatorRow('D1', data['D1']),
                      _buildIndicatorRow('D5', data['D5']),
                      _buildIndicatorRow('D10', data['D10']),
                      _buildIndicatorRow('C5', data['C5']),
                      _buildIndicatorRow('C10', data['C10']),
                      _buildIndicatorRow('M5', data['M5']),
                      _buildIndicatorRow('L5', data['L5']),
                      _buildIndicatorRow('H5', data['H5']),
                      _buildIndicatorRow('M10', data['M10']),
                      _buildIndicatorRow('QW', data['QW']),
                      _buildIndicatorRow('FW', data['FW']),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 构建预测走势图
  Widget _buildPredictionChart(Map<String, dynamic> data) {
    // 从K线数据中提取信息
    List<KlineData> klineDataList = [];
    if (data['klineData'] != null) {
      klineDataList = (data['klineData'] as List<dynamic>)
          .map((json) => KlineData.fromJson(json))
          .toList();
    }
    
    List<String> dates = (data['dates'] as List<dynamic>).cast<String>();
    final ma5 = (data['ma5'] as List<dynamic>?)?.cast<double>() ?? [];
    final ma10 = (data['ma10'] as List<dynamic>?)?.cast<double>() ?? [];
    final ma20 = (data['ma20'] as List<dynamic>?)?.cast<double>() ?? [];
    
    // 获取预测相关数据
    final D1 = data['D1'] as double;
    final FW = data['FW'] as double;
    final QW = data['QW'] as double;
    final M5 = data['M5'] as double;
    final tsCode = data['tsCode'] as String? ?? '';
    
    if (klineDataList.isEmpty) {
      return const Center(
        child: Text('暂无数据'),
      );
    }

    // 创建预测K线数据
    KlineData? predictionKline;
    String? predictionDateStr;
    int? predictionIndex;
    
    // 获取最后一个K线的日期，计算下一个交易日作为预测日期
    final lastKline = klineDataList.last;
    String lastDateStr = lastKline.tradeDate;
    DateTime lastDate;
    if (lastDateStr.length == 8) {
      lastDate = DateTime.parse(
        '${lastDateStr.substring(0, 4)}-'
        '${lastDateStr.substring(4, 6)}-'
        '${lastDateStr.substring(6, 8)}',
      );
    } else {
      lastDate = DateTime.parse(lastDateStr);
    }
    
    // 获取下一个交易日作为预测日期
    final nextDate = _getNextTradingDay(lastDate);
    predictionDateStr = DateFormat('yyyy-MM-dd').format(nextDate);
    
    // 根据QW和D1的关系创建预测K线数据
    if (QW > D1) {
      // QW > D1: 开盘价=D1, 最高价=QW, 收盘价=QW, 最低价=M5
      predictionKline = KlineData(
        tsCode: tsCode,
        tradeDate: predictionDateStr,
        open: D1,
        high: QW,
        low: M5,
        close: QW,
        preClose: D1,
        change: QW - D1,
        pctChg: ((QW - D1) / D1) * 100,
        vol: 0.0,
        amount: 0.0,
      );
    } else {
      // QW <= D1: 开盘价=D1, 最高价=M5, 最低价=QW, 收盘价=QW
      predictionKline = KlineData(
        tsCode: tsCode,
        tradeDate: predictionDateStr,
        open: D1,
        high: M5,
        low: QW,
        close: QW,
        preClose: D1,
        change: QW - D1,
        pctChg: ((QW - D1) / D1) * 100,
        vol: 0.0,
        amount: 0.0,
      );
    }
    
    // 将预测K线添加到列表中
    klineDataList = List<KlineData>.from(klineDataList)..add(predictionKline);
    dates = List<String>.from(dates)..add(predictionDateStr);
    predictionIndex = klineDataList.length - 1; // 最后一个K线是预测K线
    
    // 重新计算包含预测收盘价的MA5/MA10/MA20
    // 获取当前显示的收盘价列表（从data中获取prices）
    final currentPrices = (data['prices'] as List<dynamic>?)?.cast<double>() ?? [];
    // 添加预测收盘价
    final pricesWithPrediction = List<double>.from(currentPrices)..add(predictionKline.close);
    
    // 重新计算MA值（包含预测收盘价）
    final ma5WithPrediction = _calculateMA(pricesWithPrediction, 5);
    final ma10WithPrediction = _calculateMA(pricesWithPrediction, 10);
    final ma20WithPrediction = _calculateMA(pricesWithPrediction, 20);
    
    // 提取非空的MA值
    final finalMA5 = ma5WithPrediction.where((e) => e != null).map((e) => e!).toList();
    final finalMA10 = ma10WithPrediction.where((e) => e != null).map((e) => e!).toList();
    final finalMA20 = ma20WithPrediction.where((e) => e != null).map((e) => e!).toList();

    return _PredictionChartWidget(
      klineDataList: klineDataList,
      dates: dates,
      ma5: finalMA5,
      ma10: finalMA10,
      ma20: finalMA20,
      kLineType: _kLineType,
      predictionIndex: predictionIndex,
      QW: QW,
      D1: D1,
    );
  }

  Widget _buildMAAnalysisResult() {
    final data = _predictionData!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data['stockName']} (${data['stockCode']})',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '分析期间: ${data['dates'][0]} 至 ${data['dates'][data['dates'].length - 1]}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        '连涨天数',
                        '${data['consecutiveUpDays']} 天',
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        '连跌天数',
                        '${data['consecutiveDownDays']} 天',
                        Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIndicatorRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            value.toStringAsFixed(2),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionHistoryList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  '历史预测记录',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getKLineTypeColor(_kLineType),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getKLineTypeText(_kLineType),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  // 只清除当前K线类型的记录
                  _predictionHistoryList.removeWhere(
                    (item) => item['kLineType'] == _kLineType,
                  );
                });
              },
              child: const Text('清除全部'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final filteredList = _getFilteredHistoryList();
            if (filteredList.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    '暂无历史预测记录',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: [
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredList.length,
                  itemBuilder: (context, index) {
                final item = filteredList[index];
                final isCurrent = _predictionData != null &&
                    item['queryDate'] == _predictionData!['queryDate'] &&
                    item['kLineType'] == _predictionData!['kLineType'] &&
                    (item['manualPrice'] == _predictionData!['manualPrice'] || 
                     (item['manualPrice'] == null && _predictionData!['manualPrice'] == null));
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: isCurrent ? Colors.blue.withOpacity(0.1) : null,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _predictionData = Map<String, dynamic>.from(item);
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${item['stockName']} (${item['stockCode']})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (isCurrent)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    '当前',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '查询时间: ${item['queryDate']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                              Text(
                                '预测日期: ${item['date']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Text(
                                      'K线类型: ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _getKLineTypeColor(item['kLineType']),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        _getKLineTypeText(item['kLineType']),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (item['manualPrice'] != null)
                                Text(
                                  '手动价格: ${item['manualPrice'].toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildHistoryIndicator('D1', item['D1']),
                              _buildHistoryIndicator('QW', item['QW']),
                              _buildHistoryIndicator('FW', item['FW']                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
                );
              },
            ),
                // 在列表最下方添加预测图表
                if (_predictionData != null) ...[
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '预测走势图',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 300,
                            child: _buildPredictionChart(_predictionData!),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  String _getKLineTypeText(String? type) {
    switch (type) {
      case 'daily':
        return '日K';
      case 'weekly':
        return '周K';
      case 'monthly':
        return '月K';
      default:
        return '日K';
    }
  }

  // 获取K线类型对应的颜色
  Color _getKLineTypeColor(String? type) {
    switch (type) {
      case 'daily':
        return Colors.blue; // 日K使用蓝色
      case 'weekly':
        return Colors.orange; // 周K使用橙色
      case 'monthly':
        return Colors.purple; // 月K使用紫色
      default:
        return Colors.blue;
    }
  }

  Widget _buildHistoryIndicator(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value.toStringAsFixed(2),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // 显示指标说明对话框
  void _showIndicatorExplanation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('指标说明'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '指标说明',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildExplanationItem('D1', '当天的收盘价'),
                _buildExplanationItem('D5', '第5天的收盘价'),
                _buildExplanationItem('D10', '第10天的收盘价'),
                _buildExplanationItem('C5', '最新的5日均价（最近5个交易日收盘价的平均值）'),
                _buildExplanationItem('C10', '最新的10日均价（最近10个交易日收盘价的平均值）'),
                _buildExplanationItem('M5 和 M10', '短期和中期动量指标，反映价格变化的速度'),
                _buildExplanationItem('L5 和 QW', '基于动量的支撑/阻力水平指标'),
                _buildExplanationItem('H5', '价格波动性指标，用于衡量市场波动程度'),
                const SizedBox(height: 20),
                const Text(
                  '计算公式',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildFormulaItem('M5 = (D1 - D5)/5 + C5'),
                _buildFormulaItem('L5 = (M5 × 5 - D1)/4'),
                _buildFormulaItem('H5 = (M5 × 5 - D1)/3.76'),
                _buildFormulaItem('M10 = (D1 - D10)/10 + C10'),
                _buildFormulaItem('QW = D1 + (D1 - M5) × 5'),
                _buildFormulaItem('FW = M5 + 0.1×D1/5'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildExplanationItem(String label, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label - ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(description),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulaItem(String formula) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        formula,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
        ),
      ),
    );
  }
}

// 预测走势图绘制器
class PredictionChartPainter extends CustomPainter {
  final List<KlineData> klineDataList;
  final List<String> dates;
  final List<double> ma5;
  final List<double> ma10;
  final List<double> ma20;
  final String kLineType;
  final int? predictionIndex; // 预测K线的索引
  final double? QW; // 预测值QW
  final double? D1; // D1值
  final int? selectedIndex; // 选中的K线索引
  final Map<String, double?>? selectedMaValues; // 选中K线的均线值

  static const double leftPadding = 0.0; // 左侧padding（设为0，让图表铺满宽度，参照主图）
  static const double rightPadding = 0.0; // 右侧padding（设为0，让图表铺满宽度，参照主图）
  static const double topPadding = 0.0; // 顶部padding（设为0，完全占满，参照主图）
  static const double bottomPadding = 18.0; // 底部padding（用于日期标签，参照主图）
  static const double priceLabelPadding = 1.0; // 价格标签距离左侧的间距（覆盖在图表上，偏左展示，参照主图）
  static const double candleWidth = 7.0;
  static const double candleSpacing = 1.0;

  PredictionChartPainter({
    required this.klineDataList,
    required this.dates,
    required this.ma5,
    required this.ma10,
    required this.ma20,
    required this.kLineType,
    this.predictionIndex,
    this.QW,
    this.D1,
    this.selectedIndex,
    this.selectedMaValues,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (klineDataList.isEmpty) return;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;

    // 计算价格范围（包括K线的高低价）
    double maxPrice = klineDataList.map((e) => e.high).reduce(math.max);
    double minPrice = klineDataList.map((e) => e.low).reduce(math.min);
    
    // 添加一些边距
    final priceRange = maxPrice - minPrice;
    final pricePadding = priceRange * 0.05;
    maxPrice += pricePadding;
    minPrice -= pricePadding;
    final adjustedPriceRange = maxPrice - minPrice;

    // 绘制K线图背景网格（参照主图）
    _drawKlineGrid(canvas, size, maxPrice, minPrice, chartHeight);

    // 绘制价格标签（参照主图）
    _drawPriceLabels(canvas, size, chartWidth, chartHeight, maxPrice, minPrice, adjustedPriceRange);

    // 绘制日期标签
    _drawDateLabels(canvas, size, chartWidth, dates);

    // 绘制K线柱形图
    _drawCandles(canvas, chartWidth, chartHeight, maxPrice, adjustedPriceRange);

    // 绘制MA5线（实线，黑色，与主图一致）
    if (ma5.isNotEmpty) {
      _drawMALine(canvas, chartWidth, chartHeight, maxPrice, adjustedPriceRange, ma5, Colors.black, false);
    }

    // 绘制MA10线（实线，黄色，与主图一致）
    if (ma10.isNotEmpty) {
      _drawMALine(canvas, chartWidth, chartHeight, maxPrice, adjustedPriceRange, ma10, Colors.yellow, false);
    }

    // 绘制MA20线（实线，紫色，与主图一致）
    if (ma20.isNotEmpty) {
      _drawMALine(canvas, chartWidth, chartHeight, maxPrice, adjustedPriceRange, ma20, Colors.purple, false);
    }

    // 绘制图例（在顶部，不与K线重叠）
    _drawLegend(canvas, size);
  }

  // 绘制K线图背景网格（参照主图）
  void _drawKlineGrid(Canvas canvas, Size size, double maxPrice, double minPrice, double chartHeight) {
    final gridPaint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 0.5;

    // 水平网格线（价格）
    for (int i = 0; i <= 4; i++) {
      final y = topPadding + (chartHeight / 4) * i;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
    }

    // 垂直网格线（日期）- 参照主图，不绘制垂直网格线
    // 主图中没有垂直网格线，所以这里也不绘制
  }

  void _drawPriceLabels(Canvas canvas, Size size, double chartWidth, double chartHeight,
      double maxPrice, double minPrice, double priceRange) {
    final textStyle = TextStyle(
      color: Colors.grey[700],
      fontSize: 9, // 减小字体大小，参照主图
    );
    final textPainter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: ui.TextDirection.ltr,
    );

    // 绘制价格标签（覆盖在图表上，在图表内部显示，展示在网格横线上，偏左展示，参照主图）
    for (int i = 0; i <= 4; i++) {
      final price = maxPrice - (priceRange / 4) * i;
      textPainter.text = TextSpan(
        text: price.toStringAsFixed(2), // 去掉¥符号，更简洁
        style: textStyle,
      );
      textPainter.layout();
      // 价格标签覆盖在图表上，展示在网格横线上（向上微调），偏左展示（向左微调）
      final y = topPadding + chartHeight * i / 4;
      // 向上微调：减去一个小的偏移量，让标签稍微在网格线上方
      textPainter.paint(
        canvas,
        Offset(priceLabelPadding, y - textPainter.height / 2 - 4),
      );
    }
  }

  void _drawDateLabels(Canvas canvas, Size size, double chartWidth, List<String> dates) {
    if (dates.isEmpty) return;

    final textStyle = TextStyle(
      fontSize: 9, // 参照主图
      color: Colors.grey[700],
    );
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    );

    // 计算K线宽度和间距（与_drawCandles保持一致）
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    if (klineDataList.length == 1) {
      dynamicCandleWidth = chartWidth;
      dynamicCandleSpacing = 0;
    } else if (klineDataList.length > 1) {
      final availableWidthPerCandle = chartWidth / klineDataList.length;
      final totalRatio = candleWidth + candleSpacing;
      dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
      dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
    }
    final dynamicCandleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;

    // 参照主图，显示4个日期标签
    final step = math.max(1, (dates.length - 1) ~/ 4);
    for (int i = 0; i < dates.length; i += step) {
      if (i >= dates.length) break;
      
      final date = dates[i];
      // 简化日期显示
      String displayDate = date;
      if (date.length >= 10) {
        displayDate = date.substring(5); // 显示 MM-DD
      }
      
      // 确保第一个和最后一个日期标签对齐到K线中心（参照主图）
      final x = i * dynamicCandleTotalWidth + dynamicCandleWidth / 2;
      
      textPainter.text = TextSpan(text: displayDate, style: textStyle);
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, size.height - bottomPadding + 8),
      );
    }
  }

  // 绘制K线柱形图
  void _drawCandles(Canvas canvas, double chartWidth, double chartHeight,
      double maxPrice, double priceRange) {
    if (klineDataList.isEmpty) return;

    // 计算K线宽度和间距（参照主图，确保第一个和最后一个K线完全铺满）
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;

    if (klineDataList.length == 1) {
      // 只有一根K线，完全铺满
      dynamicCandleWidth = chartWidth;
      dynamicCandleSpacing = 0;
    } else if (klineDataList.length > 1) {
      // 多个K线，计算每个K线应该占用的宽度，使第一个和最后一个K线完全铺满
      final availableWidthPerCandle = chartWidth / klineDataList.length;
      final totalRatio = candleWidth + candleSpacing;
      dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
      dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
    }

    final dynamicCandleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;

    for (int i = 0; i < klineDataList.length; i++) {
      final data = klineDataList[i];
      // 确保第一个K线从0开始，最后一个K线延伸到chartWidth（参照主图）
      // 第一个K线的中心应该在dynamicCandleWidth/2位置
      // 最后一个K线的中心应该在chartWidth - dynamicCandleWidth/2位置
      final x = i * dynamicCandleTotalWidth + dynamicCandleWidth / 2;

      // 计算价格对应的Y坐标
      final highY = topPadding + (maxPrice - data.high) / priceRange * chartHeight;
      final lowY = topPadding + (maxPrice - data.low) / priceRange * chartHeight;
      final openY = topPadding + (maxPrice - data.open) / priceRange * chartHeight;
      final closeY = topPadding + (maxPrice - data.close) / priceRange * chartHeight;

      // 判断是否是预测K线
      final isPredictionKline = predictionIndex != null && i == predictionIndex;
      
      // 判断涨跌
      final isRising = data.close >= data.open;
      // 预测K线根据QW和D1的关系选择颜色，普通K线使用红绿
      Color color;
      if (isPredictionKline) {
        // 如果QW大于D1使用橙色实体，反之使用蓝色实体
        final qwValue = QW;
        final d1Value = D1;
        if (qwValue != null && d1Value != null && qwValue > d1Value) {
          color = Colors.orange[700]!;
        } else {
          color = Colors.blue[700]!;
        }
      } else {
        color = isRising ? Colors.red[800]! : Colors.green[700]!;
      }
      
      // 判断是否被选中
      final isSelected = selectedIndex != null && i == selectedIndex;

      // 计算实体位置
      final bodyTop = math.min(openY, closeY);
      final bodyBottom = math.max(openY, closeY);
      final bodyHeight = math.max(bodyBottom - bodyTop, 1.0);

      // 绘制实体（矩形）
      // 确保第一个K线从0开始，最后一个K线延伸到chartWidth
      double rectX = x - dynamicCandleWidth / 2;
      double rectWidth = dynamicCandleWidth;
      
      if (i == 0) {
        // 第一个K线，从0开始
        rectX = 0;
      } else if (i == klineDataList.length - 1) {
        // 最后一个K线，延伸到chartWidth
        rectX = x - dynamicCandleWidth / 2;
        rectWidth = chartWidth - rectX;
      }
      
      final bodyPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(
          rectX,
          bodyTop,
          rectWidth,
          bodyHeight,
        ),
        bodyPaint,
      );

      // 如果是涨（红柱）且不是预测K线，绘制白色内部矩形实现空心效果
      // 预测K线不绘制白色内部矩形，保持实心
      if (isRising && !isPredictionKline) {
        final whitePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;

        // 确保白色矩形与实体矩形对齐
        final whiteRectWidth = math.max(rectWidth - 2.0, 1.0);
        final whiteRectHeight = math.max(bodyHeight - 2.0, 1.0);
        final whiteRectLeft = rectX + 1.0;
        final whiteRectTop = bodyTop + 1.0;

        canvas.drawRect(
          Rect.fromLTWH(
            whiteRectLeft,
            whiteRectTop,
            whiteRectWidth,
            whiteRectHeight,
          ),
          whitePaint,
        );
      }

      // 绘制上下影线
      final shadowPaint = Paint()
        ..color = color
        ..strokeWidth = 1.0;

      // 上影线：从最高价到实体顶部
      if (highY < bodyTop) {
        canvas.drawLine(
          Offset(x, highY),
          Offset(x, bodyTop),
          shadowPaint,
        );
      }

      // 下影线：从实体底部到最低价
      if (lowY > bodyBottom) {
        canvas.drawLine(
          Offset(x, bodyBottom),
          Offset(x, lowY),
          shadowPaint,
        );
      }
      
      // 如果被选中，绘制高亮边框
      if (isSelected) {
        final highlightPaint = Paint()
          ..color = Colors.yellow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;
        
        // 绘制整个K线的高亮边框（包括影线）
        final highlightRect = Rect.fromLTWH(
          rectX - 2,
          math.min(highY, bodyTop) - 2,
          rectWidth + 4,
          (math.max(lowY, bodyBottom) - math.min(highY, bodyTop)) + 4,
        );
        canvas.drawRect(highlightRect, highlightPaint);
      }
    }
  }

  void _drawMALine(Canvas canvas, double chartWidth, double chartHeight,
      double maxPrice, double priceRange, List<double> maValues, Color color, bool isDashed) {
    if (maValues.length < 2) return;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 计算K线宽度和间距（与_drawCandles保持一致）
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    if (klineDataList.length == 1) {
      dynamicCandleWidth = chartWidth;
      dynamicCandleSpacing = 0;
    } else if (klineDataList.length > 1) {
      final availableWidthPerCandle = chartWidth / klineDataList.length;
      final totalRatio = candleWidth + candleSpacing;
      dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
      dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
    }
    final dynamicCandleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;
    
    // MA数据点可能少于K线数据点（因为需要多个数据点才能计算MA）
    final maStartIndex = klineDataList.length - maValues.length;
    
    if (isDashed) {
      // 绘制虚线
      final dashLength = 5.0;
      final gapLength = 3.0;
      
      for (int i = 0; i < maValues.length - 1; i++) {
        final priceIndex1 = maStartIndex + i;
        final priceIndex2 = maStartIndex + i + 1;
        // 确保第一个和最后一个点对齐到K线中心（参照主图）
        final x1 = priceIndex1 * dynamicCandleTotalWidth + dynamicCandleWidth / 2;
        final y1 = topPadding + (maxPrice - maValues[i]) / priceRange * chartHeight;
        final x2 = priceIndex2 * dynamicCandleTotalWidth + dynamicCandleWidth / 2;
        final y2 = topPadding + (maxPrice - maValues[i + 1]) / priceRange * chartHeight;
        
        final totalLength = math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
        final dx = (x2 - x1) / totalLength;
        final dy = (y2 - y1) / totalLength;
        
        double currentLength = 0.0;
        while (currentLength < totalLength) {
          final startX = x1 + dx * currentLength;
          final startY = y1 + dy * currentLength;
          final dashEndLength = math.min(currentLength + dashLength, totalLength);
          final endX = x1 + dx * dashEndLength;
          final endY = y1 + dy * dashEndLength;
          
          canvas.drawLine(
            Offset(startX, startY),
            Offset(endX, endY),
            linePaint,
          );
          
          currentLength += dashLength + gapLength;
        }
      }
    } else {
      // 绘制平滑的实线（使用贝塞尔曲线）
      // 收集所有有效的点
      List<Offset> validPoints = [];
      for (int i = 0; i < maValues.length; i++) {
        final priceIndex = maStartIndex + i;
        final x = priceIndex * dynamicCandleTotalWidth + dynamicCandleWidth / 2;
        final y = topPadding + (maxPrice - maValues[i]) / priceRange * chartHeight;
        validPoints.add(Offset(x, y));
      }
      
      if (validPoints.isEmpty) return;
      
      final path = Path();
      
      if (validPoints.length == 1) {
        path.moveTo(validPoints[0].dx, validPoints[0].dy);
        path.lineTo(validPoints[0].dx, validPoints[0].dy);
      } else if (validPoints.length == 2) {
        path.moveTo(validPoints[0].dx, validPoints[0].dy);
        path.lineTo(validPoints[1].dx, validPoints[1].dy);
      } else {
        // 多个点，使用贝塞尔曲线平滑连接
        path.moveTo(validPoints[0].dx, validPoints[0].dy);
        
        for (int i = 1; i < validPoints.length; i++) {
          final prev = validPoints[i - 1];
          final curr = validPoints[i];
          
          if (i == 1) {
            // 第二个点：使用二次贝塞尔曲线
            final controlX = (prev.dx + curr.dx) / 2;
            final controlY = (prev.dy + curr.dy) / 2;
            path.quadraticBezierTo(controlX, controlY, curr.dx, curr.dy);
          } else if (i == validPoints.length - 1) {
            // 最后一个点：使用二次贝塞尔曲线
            final controlX = (prev.dx + curr.dx) / 2;
            final controlY = (prev.dy + curr.dy) / 2;
            path.quadraticBezierTo(controlX, controlY, curr.dx, curr.dy);
          } else {
            // 中间点：使用三次贝塞尔曲线，计算更平滑的控制点
            final prevPoint = validPoints[i - 1];
            final currentPoint = validPoints[i];
            final nextPoint = validPoints[i + 1];
            
            // 计算方向向量
            final dx1 = currentPoint.dx - prevPoint.dx;
            final dy1 = currentPoint.dy - prevPoint.dy;
            final dx2 = nextPoint.dx - currentPoint.dx;
            final dy2 = nextPoint.dy - currentPoint.dy;
            
            // 使用张力系数控制曲线的平滑程度
            final tension = 0.3;
            final cp1 = Offset(
              prevPoint.dx + dx1 * tension,
              prevPoint.dy + dy1 * tension,
            );
            final cp2 = Offset(
              currentPoint.dx - dx2 * tension,
              currentPoint.dy - dy2 * tension,
            );
            
            path.cubicTo(
              cp1.dx, cp1.dy,
              cp2.dx, cp2.dy,
              currentPoint.dx, currentPoint.dy,
            );
          }
        }
      }
      
      canvas.drawPath(path, linePaint);
    }
  }

  void _drawPredictionLine(Canvas canvas, double chartWidth, double chartHeight,
      double maxPrice, double priceRange, double predictionValue, Color color, String label, List<double>? maValues) {
    if (klineDataList.isEmpty) return;

    // 计算K线宽度和间距（与_drawCandles保持一致）
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    if (klineDataList.length == 1) {
      dynamicCandleWidth = chartWidth;
      dynamicCandleSpacing = 0;
    } else if (klineDataList.length > 1) {
      final availableWidthPerCandle = chartWidth / klineDataList.length;
      final totalRatio = candleWidth + candleSpacing;
      dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
      dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
    }
    final dynamicCandleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;
    
    // 计算起点：如果提供了MA值，使用上一天的MA终点；否则使用最后一个K线的收盘价
    final lastPriceIndex = klineDataList.length - 1;
    // 起点X坐标（最后一个K线的中心）
    final startX = lastPriceIndex * dynamicCandleTotalWidth + dynamicCandleWidth / 2;
    double startY;
    
    if (maValues != null && maValues.isNotEmpty) {
      // 使用上一天的MA终点作为起点
      // 上一天的MA值（最后一个MA值）
      final lastMaValue = maValues.last;
      startY = topPadding + (maxPrice - lastMaValue) / priceRange * chartHeight;
    } else {
      // 从最后一个K线的收盘价绘制到预测值
      final lastKline = klineDataList.last;
      startY = topPadding + (maxPrice - lastKline.close) / priceRange * chartHeight;
    }

    // 预测点位置（在图表右侧延伸）
    final predictionX = chartWidth + 10;
    final predictionY = topPadding + (maxPrice - predictionValue) / priceRange * chartHeight;

    // 绘制预测线（虚线）
    final dashPaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // 绘制虚线效果（手动绘制）
    final dashLength = 5.0;
    final gapLength = 3.0;
    final totalLength = math.sqrt(
      math.pow(predictionX - startX, 2) + math.pow(predictionY - startY, 2),
    );
    final dx = (predictionX - startX) / totalLength;
    final dy = (predictionY - startY) / totalLength;

    double currentLength = 0.0;
    while (currentLength < totalLength) {
      final dashStartX = startX + dx * currentLength;
      final dashStartY = startY + dy * currentLength;
      final dashEndLength = math.min(currentLength + dashLength, totalLength);
      final dashEndX = startX + dx * dashEndLength;
      final dashEndY = startY + dy * dashEndLength;

      canvas.drawLine(
        Offset(dashStartX, dashStartY),
        Offset(dashEndX, dashEndY),
        dashPaint,
      );

      currentLength += dashLength + gapLength;
    }

    // 绘制预测点
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(predictionX, predictionY), 4, pointPaint);

    // 绘制预测值标签
    final textStyle = TextStyle(
      fontSize: 10,
      color: color,
      fontWeight: FontWeight.bold,
    );
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$label: ${predictionValue.toStringAsFixed(2)}',
        style: textStyle,
      ),
      textAlign: TextAlign.left,
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(predictionX + 8, predictionY - textPainter.height / 2),
    );
  }

  void _drawLegend(Canvas canvas, Size size) {
    final legendItems = [
      if (ma5.isNotEmpty) {'label': 'MA5', 'color': Colors.black, 'value': selectedMaValues?['ma5']},
      if (ma10.isNotEmpty) {'label': 'MA10', 'color': Colors.yellow, 'value': selectedMaValues?['ma10']},
      if (ma20.isNotEmpty) {'label': 'MA20', 'color': Colors.purple, 'value': selectedMaValues?['ma20']},
    ];

    final textStyle = TextStyle(
      fontSize: 10,
      color: Colors.grey[700],
    );
    final valueTextStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );
    final textPainter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: ui.TextDirection.ltr,
    );

    // 图例放在顶部左侧，不与K线重叠
    double x = leftPadding;
    double y = 8.0; // 距离顶部8像素
    double itemSpacing = 8.0; // 图例项之间的间距

    for (var item in legendItems) {
      final color = item['color'] as Color;
      final label = item['label'] as String;
      final value = item['value'] as double?;

      // 绘制颜色块
      final colorPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(x, y, 12, 12),
        colorPaint,
      );

      // 绘制标签和值（如果选中）
      String displayText = label;
      if (value != null) {
        displayText = '$label:${value.toStringAsFixed(2)}';
        textPainter.text = TextSpan(
          text: displayText,
          style: valueTextStyle.copyWith(color: color),
        );
      } else {
        textPainter.text = TextSpan(text: displayText, style: textStyle);
      }
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 16, y));

      // 计算下一个图例项的位置
      x += 16 + textPainter.width + itemSpacing;
      
      // 如果超出宽度，换行
      if (x + 50 > size.width - rightPadding) {
        x = leftPadding;
        y += 18;
      }
    }
  }

  @override
  bool shouldRepaint(PredictionChartPainter oldDelegate) {
    return oldDelegate.klineDataList != klineDataList ||
        oldDelegate.dates != dates ||
        oldDelegate.ma5 != ma5 ||
        oldDelegate.ma10 != ma10 ||
        oldDelegate.ma20 != ma20 ||
        oldDelegate.kLineType != kLineType ||
        oldDelegate.predictionIndex != predictionIndex ||
        oldDelegate.QW != QW ||
        oldDelegate.D1 != D1 ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.selectedMaValues != selectedMaValues;
  }
}

// 预测图表Widget（支持选中功能）
class _PredictionChartWidget extends StatefulWidget {
  final List<KlineData> klineDataList;
  final List<String> dates;
  final List<double> ma5;
  final List<double> ma10;
  final List<double> ma20;
  final String kLineType;
  final int? predictionIndex;
  final double? QW;
  final double? D1;

  const _PredictionChartWidget({
    required this.klineDataList,
    required this.dates,
    required this.ma5,
    required this.ma10,
    required this.ma20,
    required this.kLineType,
    this.predictionIndex,
    this.QW,
    this.D1,
  });

  @override
  State<_PredictionChartWidget> createState() => _PredictionChartWidgetState();
}

class _PredictionChartWidgetState extends State<_PredictionChartWidget> {
  int? _selectedIndex;
  Timer? _autoResetTimer;
  KlineData? _selectedKlineData;
  Map<String, double?> _selectedMaValues = {};

  @override
  void dispose() {
    _autoResetTimer?.cancel();
    super.dispose();
  }
  
  // 计算选中K线的均线值
  Map<String, double?> _calculateMaValuesForIndex(int index) {
    if (index < 0 || index >= widget.klineDataList.length) {
      return {'ma5': null, 'ma10': null, 'ma20': null};
    }
    
    Map<String, double?> maValues = {};
    
    // 计算MA5
    if (index >= 4) {
      final last5 = widget.klineDataList.sublist(index - 4, index + 1);
      maValues['ma5'] = last5.map((e) => e.close).reduce((a, b) => a + b) / 5;
    } else {
      maValues['ma5'] = null;
    }
    
    // 计算MA10
    if (index >= 9) {
      final last10 = widget.klineDataList.sublist(index - 9, index + 1);
      maValues['ma10'] = last10.map((e) => e.close).reduce((a, b) => a + b) / 10;
    } else {
      maValues['ma10'] = null;
    }
    
    // 计算MA20
    if (index >= 19) {
      final last20 = widget.klineDataList.sublist(index - 19, index + 1);
      maValues['ma20'] = last20.map((e) => e.close).reduce((a, b) => a + b) / 20;
    } else {
      maValues['ma20'] = null;
    }
    
    return maValues;
  }

  // 根据触摸位置找到对应的K线数据点
  int? _findDataIndexAtPosition(double x, Size size) {
    if (widget.klineDataList.isEmpty) return null;

    final chartWidth = size.width;
    const candleWidth = 7.0;
    const candleSpacing = 1.0;
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;

    if (widget.klineDataList.length == 1) {
      dynamicCandleWidth = chartWidth;
      dynamicCandleSpacing = 0;
    } else if (widget.klineDataList.length > 1) {
      final availableWidthPerCandle = chartWidth / widget.klineDataList.length;
      final totalRatio = candleWidth + candleSpacing;
      dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
      dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
    }

    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;
    final index = (x / candleTotalWidth).round();
    if (index >= 0 && index < widget.klineDataList.length) {
      return index;
    }
    return null;
  }

  void _handleTapDown(TapDownDetails details) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final index = _findDataIndexAtPosition(details.localPosition.dx, size);
    if (index != null && index >= 0 && index < widget.klineDataList.length) {
      final selectedData = widget.klineDataList[index];
      final maValues = _calculateMaValuesForIndex(index);
      setState(() {
        _selectedIndex = index;
        _selectedKlineData = selectedData;
        _selectedMaValues = maValues;
      });
      _autoResetTimer?.cancel();
      _autoResetTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _selectedIndex = null;
            _selectedKlineData = null;
            _selectedMaValues = {};
          });
        }
      });
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final index = _findDataIndexAtPosition(details.localPosition.dx, size);
    if (index != null && index >= 0 && index < widget.klineDataList.length) {
      final selectedData = widget.klineDataList[index];
      final maValues = _calculateMaValuesForIndex(index);
      setState(() {
        _selectedIndex = index;
        _selectedKlineData = selectedData;
        _selectedMaValues = maValues;
      });
      _autoResetTimer?.cancel();
      _autoResetTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _selectedIndex = null;
            _selectedKlineData = null;
            _selectedMaValues = {};
          });
        }
      });
    }
  }
  
  // 构建MA值显示Widget（带趋势箭头）
  Widget _buildMaValue(String label, double? value, Color color) {
    if (value == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '-',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey[400],
            ),
          ),
        ],
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.rectangle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value.toStringAsFixed(2),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
  
  // 构建K线价格信息显示
  Widget _buildKlineInfo(KlineData? klineData) {
    if (klineData == null) {
      return const SizedBox.shrink();
    }
    
    // 计算涨跌幅
    double pctChg = 0.0;
    if (klineData.preClose > 0) {
      pctChg = ((klineData.close - klineData.preClose) / klineData.preClose) * 100;
    } else if (klineData.pctChg != null) {
      pctChg = klineData.pctChg;
    }
    final isPositive = pctChg >= 0;
    final pctChgText = '${isPositive ? '+' : ''}${pctChg.toStringAsFixed(2)}%';
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '开盘',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '¥${klineData.open.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '涨跌幅',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    pctChgText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isPositive ? Colors.red[700] : Colors.green[700],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _buildInfoItem('收盘', '¥${klineData.close.toStringAsFixed(2)}'),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _buildInfoItem('最高', '¥${klineData.high.toStringAsFixed(2)}'),
        ),
        _buildInfoItem('最低', '¥${klineData.low.toStringAsFixed(2)}'),
      ],
    );
  }
  
  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // K线图表
        GestureDetector(
          onTapDown: _handleTapDown,
          onPanUpdate: _handlePanUpdate,
          child: CustomPaint(
            painter: PredictionChartPainter(
              klineDataList: widget.klineDataList,
              dates: widget.dates,
              ma5: widget.ma5,
              ma10: widget.ma10,
              ma20: widget.ma20,
              kLineType: widget.kLineType,
              predictionIndex: widget.predictionIndex,
              QW: widget.QW,
              D1: widget.D1,
              selectedIndex: _selectedIndex,
              selectedMaValues: _selectedMaValues,
            ),
            size: Size.infinite,
          ),
        ),
        // 显示MA值和K线信息（选中时，覆盖在图表上方）
        if (_selectedKlineData != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildKlineInfo(_selectedKlineData),
              ),
            ),
          ),
      ],
    );
  }
}

