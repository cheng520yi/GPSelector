import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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
      final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate);
      
      // 根据K线类型调整请求的数据量
      int daysToFetch = 15;
      if (_kLineType == 'weekly') {
        daysToFetch = 120;
      } else if (_kLineType == 'monthly') {
        daysToFetch = 500;
      }
      
      final startDateStr = _calculateStartDate(_endDate, daysToFetch);
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


      // 提取收盘价
      final closes = sortedData.map((e) => e.close).toList();
      final dates = sortedData.map((e) => e.tradeDate).toList();

      // 处理周K和月K数据分组
      List<double> displayCloses = List.from(closes);
      List<String> displayDates = List.from(dates);

      if (_kLineType == 'weekly' || _kLineType == 'monthly') {
        final grouped = _groupDailyToPeriods(
          closes,
          dates,
          _kLineType,
          sortedData.length - 1,
        );
        displayCloses = List.from(grouped['periodCloses'] as List<double>);
        displayDates = List.from(grouped['periodDates'] as List<String>);
      }

      // 如果启用手动输入，将手动价格添加到数据末尾
      double? manualPrice;
      if (_useManualInput && _manualPriceController.text.isNotEmpty) {
        manualPrice = double.tryParse(_manualPriceController.text);
        if (manualPrice != null && manualPrice > 0) {
          // 计算下一个交易日
          // displayDates可能是yyyyMMdd格式或yyyy-MM-dd格式
          String lastDateStr = displayDates.last;
          DateTime lastDate;
          if (lastDateStr.length == 8) {
            // yyyyMMdd格式
            lastDate = DateTime.parse(
              '${lastDateStr.substring(0, 4)}-'
              '${lastDateStr.substring(4, 6)}-'
              '${lastDateStr.substring(6, 8)}',
            );
          } else {
            // yyyy-MM-dd格式
            lastDate = DateTime.parse(lastDateStr);
          }
          final nextDate = _getNextTradingDay(lastDate);
          final nextDateStr = DateFormat('yyyy-MM-dd').format(nextDate);
          
          // 将手动输入的价格作为新一天的收盘价添加到数组末尾
          displayCloses.add(manualPrice);
          // 保持日期格式一致（使用yyyy-MM-dd格式）
          displayDates.add(nextDateStr);
        } else {
          setState(() {
            _errorMessage = '请输入有效的价格';
            _isLoading = false;
          });
          return;
        }
      }

      // 计算指标（基于最后10个数据，如果启用手动输入，手动价格就是新的D1）
      double D1, D5, D10, C5, C10;
      
      if (displayCloses.length >= 10) {
        // 获取最后10个收盘价
        final last10Closes = displayCloses.sublist(
          displayCloses.length - 10,
        );
        
        // D1是最后一天（如果启用手动输入，就是手动输入的价格）
        D1 = last10Closes[9];
        // D5是倒数第6天（原来的D1变成了D2，D2变成D3...）
        D5 = last10Closes[5];
        // D10是倒数第10天
        D10 = last10Closes[0];
        
        // C5 - 最近5个交易日收盘价的平均值（包括手动输入的价格）
        final c5Data = last10Closes.sublist(5);
        C5 = c5Data.fold(0.0, (a, b) => a + b) / c5Data.length;
        
        // C10 - 最近10个交易日收盘价的平均值（包括手动输入的价格）
        C10 = last10Closes.fold(0.0, (a, b) => a + b) / last10Closes.length;
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

      // 计算预测日期
      // 如果没有手动输入：预测日期是D1所在的交易日
      // 如果有手动输入：预测日期是手动输入日期本身（即D1所在交易日的下一个交易日）
      String nextDateStr;
      if (_useManualInput && manualPrice != null) {
        // 如果启用了手动输入，预测日期就是手动输入日期本身（已经在上面添加到displayDates了）
        nextDateStr = displayDates.last;
      } else {
        // 如果没有手动输入，预测日期就是D1所在的交易日
        // D1对应的是displayDates中最后一项（因为D1是displayCloses的最后一项）
        String d1DateStr = displayDates.last;
        // 确保日期格式为yyyy-MM-dd
        if (d1DateStr.length == 8) {
          nextDateStr = '${d1DateStr.substring(0, 4)}-${d1DateStr.substring(4, 6)}-${d1DateStr.substring(6, 8)}';
        } else {
          nextDateStr = d1DateStr;
        }
      }

      // 计算5日均线
      final ma5 = _calculateMA(displayCloses, 5);
      final displayMA5 = ma5.where((e) => e != null).map((e) => e!).toList();

      // 创建预测数据
      final predictionData = {
        'stockCode': tsCode,
        'stockName': widget.stockInfo.name,
        'date': nextDateStr,
        'queryDate': DateFormat('yyyy-MM-dd').format(_endDate),
        'dates': displayDates.sublist(
          displayDates.length - 10 > 0 ? displayDates.length - 10 : 0,
        ).map((d) {
          // 确保日期格式为 yyyy-MM-dd
          if (d.length == 8) {
            return '${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)}';
          }
          return d;
        }).toList(),
        'prices': displayCloses.sublist(
          displayCloses.length - 10 > 0 ? displayCloses.length - 10 : 0,
        ),
        'ma5': displayMA5.sublist(
          displayMA5.length - 10 > 0 ? displayMA5.length - 10 : 0,
        ),
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
      final date = DateTime.parse(
        '${dateStr.substring(0, 4)}-'
        '${dateStr.substring(4, 6)}-'
        '${dateStr.substring(6, 8)}',
      );
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
                  color: Colors.orange,
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
        // 查询日期（非均线模式）
        if (_maMode == 'none')
          Row(
            children: [
              Expanded(
                child: _buildDatePicker(
                  '查询日期',
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
                    color: Colors.orange,
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
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredList.length,
              itemBuilder: (context, index) {
                final item = filteredList[index];
                final isCurrent = _predictionData != null &&
                    item['queryDate'] == _predictionData!['queryDate'] &&
                    item['kLineType'] == _predictionData!['kLineType'] &&
                    item['manualPrice'] == _predictionData!['manualPrice'];
                
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
                                  '查询日期: ${item['queryDate']}',
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
                                child: Text(
                                  'K线类型: ${_getKLineTypeText(item['kLineType'])}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
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

