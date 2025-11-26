import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import 'batch_optimizer.dart';
import 'stock_pool_config_service.dart';
import 'stock_api_service.dart';
import 'stock_api_service.dart';

class StockPoolService {
  static const String baseUrl = 'http://api.tushare.pro';
  static const String token = 'ddff564aabaeee65ad88faf07073d3ba40d62c657d0b1850f47834ce';
  static const double defaultPoolThreshold = 5.0; // 默认成交额阈值（亿元）
  static double _currentThreshold = defaultPoolThreshold;
  
  // 缓存的股票池
  static List<StockInfo> _cachedStockPool = [];
  static DateTime? _lastUpdateTime;
  static const Duration cacheValidDuration = Duration(hours: 1); // 缓存有效期1小时

  // 从本地JSON文件加载股票基础信息
  static Future<List<StockInfo>> loadStockData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/stock_data.json');
      final Map<String, dynamic> jsonMap = json.decode(jsonString);
      
      // 将Map转换为StockInfo列表
      return jsonMap.entries
          .map((entry) => StockInfo.fromMapEntry(entry))
          .toList();
    } catch (e) {
      print('加载股票数据失败: $e');
      return [];
    }
  }

  // 批量获取单日K线数据（优化版本，支持智能分组查询）
  static Future<Map<String, KlineData>> getBatchDailyKlineData({
    required List<String> tsCodes,
    DateTime? targetDate,
    int? customBatchSize, // 自定义分组大小，如果为null则使用智能优化
    Function(int current, int total)? onProgress, // 进度回调
  }) async {
    Map<String, KlineData> result = {};
    
    // 使用智能优化器计算最优分组大小
    final batchSize = customBatchSize ?? BatchOptimizer.getOptimalBatchSize(tsCodes.length, 'daily');
    final delay = BatchOptimizer.getOptimalDelay(batchSize);
    
    // 将股票代码分组
    List<List<String>> batches = [];
    for (int i = 0; i < tsCodes.length; i += batchSize) {
      int end = (i + batchSize < tsCodes.length) ? i + batchSize : tsCodes.length;
      batches.add(tsCodes.sublist(i, end));
    }
    
    final optimizationInfo = BatchOptimizer.getOptimizationInfo(tsCodes.length, 'daily');
    print('📊 开始批量获取 ${tsCodes.length} 只股票的单日K线数据');
    print('🚀 优化策略: 分组大小=${batchSize}, 延时=${delay.inMilliseconds}ms, 预估时间=${optimizationInfo['estimatedTime']}秒');
    
    for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      final batch = batches[batchIndex];
      print('🔄 处理第 ${batchIndex + 1}/${batches.length} 批，包含 ${batch.length} 只股票');
      
      // 报告进度
      onProgress?.call(batchIndex + 1, batches.length);
      
      try {
        // 使用批量查询接口
        final batchResult = await getBatchDailyKlineDataSingleRequest(
          tsCodes: batch,
          targetDate: targetDate,
        );
        
        // 合并结果
        result.addAll(batchResult);
        
        // 使用优化的延时策略
        if (batchIndex < batches.length - 1) {
          await Future.delayed(delay);
        }
      } catch (e) {
        print('❌ 第 ${batchIndex + 1} 批查询失败: $e');
        // 如果批量查询失败，回退到单个查询
        for (String tsCode in batch) {
          try {
            final klineData = await getDailyKlineData(
              tsCode: tsCode,
              targetDate: targetDate,
            );
            if (klineData != null) {
              result[tsCode] = klineData;
            }
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            print('获取 $tsCode 的单日K线数据失败: $e');
          }
        }
      }
    }
    
    print('✅ 批量获取完成，成功获取 ${result.length} 只股票的数据');
    return result;
  }

  // 单次请求获取多个股票的单日K线数据
  static Future<Map<String, KlineData>> getBatchDailyKlineDataSingleRequest({
    required List<String> tsCodes,
    DateTime? targetDate,
  }) async {
    try {
      DateTime endDate;
      DateTime startDate;
      
      if (targetDate != null) {
        // 如果指定了目标日期，请求该日期前后5天的数据
        endDate = targetDate.add(const Duration(days: 5));
        startDate = targetDate.subtract(const Duration(days: 5));
      } else {
        // 默认请求最近5天的数据，取最新的交易日数据
        endDate = DateTime.now();
        startDate = endDate.subtract(const Duration(days: 5));
      }
      
      final String formattedStartDate = DateFormat('yyyyMMdd').format(startDate);
      final String formattedEndDate = DateFormat('yyyyMMdd').format(endDate);
      
      // 将多个股票代码用逗号分隔
      final String tsCodesString = tsCodes.join(',');

      final Map<String, dynamic> requestData = {
        "api_name": "daily",
        "token": token,
        "params": {
          "ts_code": tsCodesString,
          "start_date": formattedStartDate,
          "end_date": formattedEndDate
        },
        "fields": "ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount"
      };

      print('📡 批量请求单日数据: ${tsCodes.length}只股票，日期范围: $formattedStartDate - $formattedEndDate');

      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestData),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData['code'] == 0) {
          final data = responseData['data'];
          if (data != null) {
            final List<dynamic> items = data['items'] ?? [];
            final List<dynamic> fieldsData = data['fields'] ?? [];
            final List<String> fields = fieldsData.cast<String>();
            
            // 静默处理批量响应
            
            // 按股票代码分组数据
            Map<String, KlineData> result = {};
            
            if (targetDate != null) {
              // 如果指定了目标日期，为每个股票找到最接近目标日期的数据
              final targetDateStr = DateFormat('yyyyMMdd').format(targetDate);
              
              for (var item in items) {
                Map<String, dynamic> itemMap = {};
                for (int i = 0; i < fields.length && i < item.length; i++) {
                  itemMap[fields[i]] = item[i];
                }
                
                try {
                  final klineData = KlineData.fromJson(itemMap);
                  final tsCode = klineData.tsCode;
                  
                  if (!result.containsKey(tsCode)) {
                    result[tsCode] = klineData;
                  } else {
                    // 比较哪个数据更接近目标日期
                    final currentTradeDate = result[tsCode]!.tradeDate;
                    final newTradeDate = klineData.tradeDate;
                    
                    final currentDaysDiff = DateTime.parse('${targetDateStr.substring(0,4)}-${targetDateStr.substring(4,6)}-${targetDateStr.substring(6,8)}')
                        .difference(DateTime.parse('${currentTradeDate.substring(0,4)}-${currentTradeDate.substring(4,6)}-${currentTradeDate.substring(6,8)}')).inDays.abs();
                    final newDaysDiff = DateTime.parse('${targetDateStr.substring(0,4)}-${targetDateStr.substring(4,6)}-${targetDateStr.substring(6,8)}')
                        .difference(DateTime.parse('${newTradeDate.substring(0,4)}-${newTradeDate.substring(4,6)}-${newTradeDate.substring(6,8)}')).inDays.abs();
                    
                    if (newDaysDiff < currentDaysDiff) {
                      result[tsCode] = klineData;
                    }
                  }
                } catch (e) {
                  // 静默处理解析错误
                }
              }
            } else {
              // 如果没有指定目标日期，取最新的数据
              for (var item in items) {
                Map<String, dynamic> itemMap = {};
                for (int i = 0; i < fields.length && i < item.length; i++) {
                  itemMap[fields[i]] = item[i];
                }
                
                try {
                  final klineData = KlineData.fromJson(itemMap);
                  final tsCode = klineData.tsCode;
                  
                  // 如果该股票还没有数据，或者当前数据更新，则更新
                  if (!result.containsKey(tsCode) || 
                      klineData.tradeDate.compareTo(result[tsCode]!.tradeDate) > 0) {
                    result[tsCode] = klineData;
                  }
                } catch (e) {
                  // 静默处理解析错误
                }
              }
            }
            
            return result;
          } else {
            return {};
          }
        } else {
          return {};
        }
      } else {
        return {};
      }
    } catch (e) {
      return {};
    }
  }

  // 获取单日K线数据（用于快速筛选）
  static Future<KlineData?> getDailyKlineData({
    required String tsCode,
    DateTime? targetDate,
  }) async {
    try {
      DateTime endDate;
      DateTime startDate;
      
      if (targetDate != null) {
        // 如果指定了目标日期，请求该日期前后5天的数据
        endDate = targetDate.add(const Duration(days: 5));
        startDate = targetDate.subtract(const Duration(days: 5));
      } else {
        // 默认请求最近5天的数据，取最新的交易日数据
        endDate = DateTime.now();
        startDate = endDate.subtract(const Duration(days: 5));
      }
      
      final String formattedStartDate = DateFormat('yyyyMMdd').format(startDate);
      final String formattedEndDate = DateFormat('yyyyMMdd').format(endDate);

      final Map<String, dynamic> requestData = {
        "api_name": "daily",
        "token": token,
        "params": {
          "ts_code": tsCode,
          "start_date": formattedStartDate,
          "end_date": formattedEndDate
        },
        "fields": "ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount"
      };

      // 静默处理单个股票K线数据请求

      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestData),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData['code'] == 0) {
          final data = responseData['data'];
          if (data != null) {
            final List<dynamic> items = data['items'] ?? [];
            final List<dynamic> fieldsData = data['fields'] ?? [];
            final List<String> fields = fieldsData.cast<String>();
            
            if (items.isNotEmpty) {
              if (targetDate != null) {
                // 如果指定了目标日期，找到最接近的交易日数据
                final targetDateStr = DateFormat('yyyyMMdd').format(targetDate);
                String? closestTradeDate;
                dynamic closestItem;
                int minDaysDiff = 999;
                
                for (final item in items) {
                  final tradeDateStr = item[fields.indexOf('trade_date')]?.toString() ?? '';
                  if (tradeDateStr.isNotEmpty) {
                    final tradeDate = DateTime.parse('${tradeDateStr.substring(0,4)}-${tradeDateStr.substring(4,6)}-${tradeDateStr.substring(6,8)}');
                    final daysDiff = targetDate.difference(tradeDate).inDays.abs();
                    if (daysDiff < minDaysDiff) {
                      minDaysDiff = daysDiff;
                      closestTradeDate = tradeDateStr;
                      closestItem = item;
                    }
                  }
                }
                
                if (closestItem != null) {
                  Map<String, dynamic> itemMap = {};
                  for (int i = 0; i < fields.length && i < closestItem.length; i++) {
                    itemMap[fields[i]] = closestItem[i];
                  }
                  return KlineData.fromJson(itemMap);
                }
              } else {
                // 默认取最新的交易日数据（按交易日期排序，取最新的）
                items.sort((a, b) {
                  final tradeDateA = a[fields.indexOf('trade_date')]?.toString() ?? '';
                  final tradeDateB = b[fields.indexOf('trade_date')]?.toString() ?? '';
                  return tradeDateB.compareTo(tradeDateA); // 降序排列，最新的在前
                });
                
                final item = items.first;
                Map<String, dynamic> itemMap = {};
                for (int i = 0; i < fields.length && i < item.length; i++) {
                  itemMap[fields[i]] = item[i];
                }
                return KlineData.fromJson(itemMap);
              }
            }
          }
        }
      }
    } catch (e) {
      // 静默处理错误
    }
    return null;
  }


  // 获取股票总市值数据（优化版本）
  static Future<Map<String, double>> getBatchMarketValueData({
    required List<String> tsCodes,
    DateTime? targetDate,
    int? customBatchSize, // 自定义分组大小
    Function(int current, int total)? onProgress, // 进度回调
  }) async {
    // 如果指定了精确日期，优先使用 trade_date 一次性获取，避免多股票 multi-query 的兼容性问题
    if (targetDate != null) {
      print('📊 使用 trade_date 精确获取 ${tsCodes.length} 只股票的总市值数据，目标日期: ${DateFormat('yyyy-MM-dd').format(targetDate)}');
      onProgress?.call(0, 1);
      final result = await _getMarketValueDataByTradeDate(
        tsCodes: tsCodes,
        tradeDate: targetDate,
      );
      onProgress?.call(1, 1);
      print('✅ 精确日期总市值查询完成，成功获取 ${result.length} 只股票的数据');
      return result;
    }
    
    Map<String, double> result = {};
    
    // 使用智能优化器计算最优分组大小
    final batchSize = customBatchSize ?? BatchOptimizer.getOptimalBatchSize(tsCodes.length, 'market_value');
    final delay = BatchOptimizer.getOptimalDelay(batchSize);
    
    // 将股票代码分组
    List<List<String>> batches = [];
    for (int i = 0; i < tsCodes.length; i += batchSize) {
      int end = (i + batchSize < tsCodes.length) ? i + batchSize : tsCodes.length;
      batches.add(tsCodes.sublist(i, end));
    }
    
    final optimizationInfo = BatchOptimizer.getOptimizationInfo(tsCodes.length, 'market_value');
    print('📊 开始批量获取 ${tsCodes.length} 只股票的总市值数据');
    print('🚀 优化策略: 分组大小=${batchSize}, 延时=${delay.inMilliseconds}ms, 预估时间=${optimizationInfo['estimatedTime']}秒');
    
    for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      final batch = batches[batchIndex];
      print('🔄 处理第 ${batchIndex + 1}/${batches.length} 批，包含 ${batch.length} 只股票');
      
      // 报告进度
      onProgress?.call(batchIndex + 1, batches.length);
      
      try {
        // 使用daily_basic接口获取总市值数据
        final batchResult = await getBatchMarketValueDataSingleRequest(
          tsCodes: batch,
          targetDate: targetDate,
        );
        
        // 合并结果
        result.addAll(batchResult);
        
        // 使用优化的延时策略
        if (batchIndex < batches.length - 1) {
          await Future.delayed(delay);
        }
      } catch (e) {
        print('❌ 第 ${batchIndex + 1} 批总市值查询失败: $e');
      }
    }
    
    print('✅ 批量获取总市值数据完成，成功获取 ${result.length} 只股票的数据');
    return result;
  }

  // 根据 trade_date 一次性获取需要股票的总市值数据，并在必要时向前回溯补齐
  static Future<Map<String, double>> _getMarketValueDataByTradeDate({
    required List<String> tsCodes,
    required DateTime tradeDate,
  }) async {
    final Set<String> targetCodes = tsCodes.toSet();
    final int maxLookBackDays = 5; // 最多回溯 5 天，处理节假日/周末
    
    DateTime currentDate = tradeDate;
    for (int attempt = 0; attempt <= maxLookBackDays; attempt++) {
      final String tradeDateStr = DateFormat('yyyyMMdd').format(currentDate);
      print('📡 请求 trade_date=$tradeDateStr 的总市值数据 (尝试 ${attempt + 1}/${maxLookBackDays + 1})');
      
      final Map<String, double> result = await _fetchMarketValueForTradeDate(
        tradeDateStr: tradeDateStr,
        targetCodes: targetCodes,
      );
      
      if (result.isNotEmpty) {
        if (result.length < targetCodes.length) {
          final missing = targetCodes.difference(result.keys.toSet());
          if (missing.isNotEmpty) {
            print('⚠️ 以下股票在 trade_date=$tradeDateStr 未获取到总市值数据: ${missing.join(', ')}');
          }
        }
        return result;
      }
      
      // 若当天没有数据，则回溯一天继续尝试
      currentDate = currentDate.subtract(const Duration(days: 1));
    }
    
    print('❌ 在指定日期及向前 ${maxLookBackDays} 天范围内未能获取到所需股票的总市值数据');
    return {};
  }

  // 实际向 TuShare 请求指定 trade_date 的市值数据，并按需求筛选
  static Future<Map<String, double>> _fetchMarketValueForTradeDate({
    required String tradeDateStr,
    required Set<String> targetCodes,
  }) async {
    Map<String, double> result = {};
    const int pageSize = 5000;
    int offset = 0;
    
    while (true) {
      final Map<String, dynamic> requestData = {
        "api_name": "daily_basic",
        "token": token,
        "params": {
          "trade_date": tradeDateStr,
          "limit": pageSize,
          "offset": offset,
        },
        "fields": "ts_code,total_mv",
      };
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestData),
      );
      
      if (response.statusCode != 200) {
        print('❌ trade_date=$tradeDateStr 市值请求失败: HTTP ${response.statusCode}');
        return {};
      }
      
      final Map<String, dynamic> responseData = json.decode(response.body);
      if (responseData['code'] != 0) {
        print('❌ trade_date=$tradeDateStr 市值请求返回错误: ${responseData['code']} - ${responseData['msg']}');
        return {};
      }
      
      final data = responseData['data'];
      if (data == null) {
        return {};
      }
      
      final List<dynamic> items = data['items'] ?? [];
      final List<dynamic> fieldsData = data['fields'] ?? [];
      final List<String> fields = fieldsData.cast<String>();
      
      final int tsCodeIndex = fields.indexOf('ts_code');
      final int totalMvIndex = fields.indexOf('total_mv');
      
      for (final item in items) {
        if (tsCodeIndex < 0 || tsCodeIndex >= item.length) continue;
        final String tsCode = item[tsCodeIndex]?.toString() ?? '';
        if (tsCode.isEmpty || !targetCodes.contains(tsCode)) continue;
        if (result.containsKey(tsCode)) continue;
        
        double totalMv = 0.0;
        if (totalMvIndex >= 0 && totalMvIndex < item.length && item[totalMvIndex] != null) {
          totalMv = double.tryParse(item[totalMvIndex].toString()) ?? 0.0;
        }
        
        if (totalMv > 0) {
          // TuShare 返回单位为万元，转换为亿元
          result[tsCode] = totalMv / 10000.0;
        }
      }
      
      if (items.length < pageSize || result.length == targetCodes.length) {
        break;
      }
      
      offset += pageSize;
    }
    
    return result;
  }

  // 单次请求获取多个股票的总市值数据
  static Future<Map<String, double>> getBatchMarketValueDataSingleRequest({
    required List<String> tsCodes,
    DateTime? targetDate,
  }) async {
    try {
      DateTime endDate;
      DateTime startDate;
      
      if (targetDate != null) {
        // 如果指定了目标日期，请求该日期前后5天的数据
        endDate = targetDate.add(const Duration(days: 5));
        startDate = targetDate.subtract(const Duration(days: 5));
      } else {
        // 默认请求最近5天的数据
        endDate = DateTime.now();
        startDate = endDate.subtract(const Duration(days: 5));
      }
      
      final String formattedStartDate = DateFormat('yyyyMMdd').format(startDate);
      final String formattedEndDate = DateFormat('yyyyMMdd').format(endDate);
      
      // 将多个股票代码用逗号分隔
      final String tsCodesString = tsCodes.join(',');

      final Map<String, dynamic> requestData = {
        "api_name": "daily_basic",
        "token": token,
        "params": {
          "ts_code": tsCodesString,
          "start_date": formattedStartDate,
          "end_date": formattedEndDate
        },
        "fields": "ts_code,trade_date,total_mv"
      };

      print('📡 批量请求总市值数据: ${tsCodes.length}只股票，日期范围: $formattedStartDate - $formattedEndDate');
      print('📡 请求的股票代码: $tsCodesString');
      print('📡 请求参数: ${json.encode(requestData)}');

      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestData),
      );

      print('📡 HTTP响应状态码: ${response.statusCode}');
      print('📡 HTTP响应体: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        print('📡 API返回code: ${responseData['code']}, msg: ${responseData['msg']}');
        
        if (responseData['code'] == 0) {
          final data = responseData['data'];
          if (data != null) {
            final List<dynamic> items = data['items'] ?? [];
            final List<dynamic> fieldsData = data['fields'] ?? [];
            final List<String> fields = fieldsData.cast<String>();
            
            print('📊 批量总市值响应: 获取到 ${items.length} 条数据');
            print('📊 返回的字段: $fields');
            
            // 按股票代码分组数据，每个股票取最新的数据
            Map<String, double> result = {};
            
            for (var item in items) {
              Map<String, dynamic> itemMap = {};
              for (int i = 0; i < fields.length && i < item.length; i++) {
                itemMap[fields[i]] = item[i];
              }
              
              try {
                final tsCode = itemMap['ts_code']?.toString() ?? '';
                final totalMv = itemMap['total_mv']?.toDouble() ?? 0.0;
                
                if (tsCode.isNotEmpty && totalMv > 0) {
                  // 将万元转换为亿元
                  final totalMvInYi = totalMv / 10000.0;
                  
                  // 如果该股票还没有数据，或者当前数据更新，则更新
                  if (!result.containsKey(tsCode) || 
                      (itemMap['trade_date']?.toString() ?? '').compareTo(
                        items.firstWhere((i) => i[fields.indexOf('ts_code')] == tsCode, orElse: () => [])[fields.indexOf('trade_date')]?.toString() ?? ''
                      ) > 0) {
                    result[tsCode] = totalMvInYi;
                  }
                }
              } catch (e) {
                print('解析总市值数据项失败: $e, 数据: $itemMap');
              }
            }
            
            // 如果TuShare返回空数据，尝试使用iFind接口作为备选
            if (result.isEmpty && items.isEmpty) {
              print('⚠️ TuShare返回空数据，尝试使用iFind接口获取总市值...');
              final iFindResult = await _getMarketValueFromIFinD(tsCodes);
              if (iFindResult.isNotEmpty) {
                print('✅ iFind接口成功获取 ${iFindResult.length} 只股票的总市值数据');
                return iFindResult;
              } else {
                print('⚠️ iFind接口也未能获取到数据');
              }
            }
            
            return result;
          } else {
            print('❌ API返回data为null，尝试使用iFind接口...');
            final iFindResult = await _getMarketValueFromIFinD(tsCodes);
            if (iFindResult.isNotEmpty) {
              print('✅ iFind接口成功获取 ${iFindResult.length} 只股票的总市值数据');
              return iFindResult;
            }
            return {};
          }
        } else {
          print('❌ API返回错误: ${responseData['msg']}，尝试使用iFind接口...');
          final iFindResult = await _getMarketValueFromIFinD(tsCodes);
          if (iFindResult.isNotEmpty) {
            print('✅ iFind接口成功获取 ${iFindResult.length} 只股票的总市值数据');
            return iFindResult;
          }
          return {};
        }
      } else {
        print('❌ HTTP请求失败: ${response.statusCode}，尝试使用iFind接口...');
        final iFindResult = await _getMarketValueFromIFinD(tsCodes);
        if (iFindResult.isNotEmpty) {
          print('✅ iFind接口成功获取 ${iFindResult.length} 只股票的总市值数据');
          return iFindResult;
        }
        return {};
      }
    } catch (e) {
      print('❌ 批量获取总市值数据失败: $e，尝试使用iFind接口...');
      try {
        final iFindResult = await _getMarketValueFromIFinD(tsCodes);
        if (iFindResult.isNotEmpty) {
          print('✅ iFind接口成功获取 ${iFindResult.length} 只股票的总市值数据');
          return iFindResult;
        }
      } catch (e2) {
        print('❌ iFind接口获取总市值也失败: $e2');
      }
      return {};
    }
  }
  
  // 使用iFind接口获取总市值数据
  static Future<Map<String, double>> _getMarketValueFromIFinD(List<String> tsCodes) async {
    try {
      print('📡 使用iFind接口获取总市值数据: ${tsCodes.length}只股票');
      
      // 使用iFind实时行情接口，请求mv字段（总市值）
      final String codesString = tsCodes.join(',');
      final Map<String, dynamic> requestData = {
        "codes": codesString,
        "indicators": "mv" // 只请求总市值字段
      };
      
      final currentToken = StockApiService.getCurrentAccessToken();
      // iFind实时行情接口URL
      const String iFinDBaseUrl = 'https://quantapi.51ifind.com/api/v1/real_time_quotation';
      var response = await http.post(
        Uri.parse(iFinDBaseUrl),
        headers: {
          'Content-Type': 'application/json',
          'access_token': currentToken,
        },
        body: json.encode(requestData),
      );
      
      print('📡 iFind总市值HTTP响应状态码: ${response.statusCode}');
      print('📡 iFind总市值HTTP响应体: ${response.body}');
      
      // 检查响应是否表示token不合法，如果是则刷新token并重试
      Map<String, dynamic>? responseData;
      try {
        responseData = json.decode(response.body) as Map<String, dynamic>?;
      } catch (e) {
        print('⚠️ 解析iFind总市值响应JSON失败: $e');
      }
      
      if (StockApiService.isTokenInvalidResponse(response.statusCode, responseData)) {
        print('⚠️ iFind总市值接口提示token不合法，错误码: ${responseData?['errorcode']}, 错误信息: ${responseData?['errmsg']}');
        print('🔄 开始刷新token...');
        final newToken = await StockApiService.refreshAccessToken();
        if (newToken != null && newToken != currentToken) {
          print('🔄 使用新token重试iFind总市值请求...');
          response = await http.post(
            Uri.parse(iFinDBaseUrl),
            headers: {
              'Content-Type': 'application/json',
              'access_token': newToken,
            },
            body: json.encode(requestData),
          );
          print('📡 iFind总市值重试后HTTP响应状态码: ${response.statusCode}');
          print('📡 iFind总市值重试后HTTP响应体: ${response.body}');
          // 重新解析重试后的响应
          try {
            responseData = json.decode(response.body) as Map<String, dynamic>?;
          } catch (e) {
            print('⚠️ 解析iFind总市值重试后响应JSON失败: $e');
          }
        } else {
          print('❌ Token刷新失败，无法重试iFind总市值请求');
        }
      }
      
      if (response.statusCode == 200) {
        // 如果responseData已经在上面解析过了，直接使用；否则重新解析
        if (responseData == null) {
          try {
            responseData = json.decode(response.body) as Map<String, dynamic>?;
          } catch (e) {
            print('⚠️ 解析iFind总市值响应JSON失败: $e');
            return {};
          }
        }
        
        if (responseData != null && 
            (responseData['errorcode'] == 0 || responseData['errorcode'] == null)) {
          final tables = responseData['tables'];
          if (tables != null && tables is List) {
            Map<String, double> result = {};
            
            for (var tableItem in tables) {
              try {
                final String stockCode = tableItem['thscode'] ?? '';
                final table = tableItem['table'];
                
                if (stockCode.isNotEmpty && table != null) {
                  // iFind返回的mv是数组格式，取第一个元素
                  final mv = (table['mv'] as List?)?.isNotEmpty == true 
                      ? table['mv'][0] 
                      : null;
                  
                  if (mv != null) {
                    // iFind返回的总市值单位是元，需要转换为亿元
                    final mvValue = double.tryParse(mv.toString()) ?? 0.0;
                    if (mvValue > 0) {
                      final mvInYi = mvValue / 100000000.0; // 元转亿元
                      result[stockCode] = mvInYi;
                      print('✅ iFind获取${stockCode}总市值: ${mvInYi.toStringAsFixed(2)}亿元');
                    }
                  }
                }
              } catch (e) {
                print('❌ iFind解析股票${tableItem['thscode']}总市值失败: $e');
              }
            }
            
            return result;
          }
        } else {
          print('❌ iFind接口返回错误: ${responseData?['errorcode']} - ${responseData?['errmsg']}');
        }
      } else {
        print('❌ iFind总市值HTTP请求失败: ${response.statusCode}');
      }
      
      return {};
    } catch (e) {
      print('❌ iFind接口获取总市值异常: $e');
      return {};
    }
  }

  // 构建股票池（成交额超过5亿的股票）
  static Future<List<StockInfo>> buildStockPool({
    bool forceRefresh = false,
    double? amountThreshold, // 成交额阈值（亿元）
    double? minMarketValue, // 最小总市值（亿元）
    double? maxMarketValue, // 最大总市值（亿元）
    DateTime? targetDate, // 目标日期，如果指定则筛选该日期的数据
    Function(int progress)? onProgress, // 进度回调函数
  }) async {
    double effectiveAmountThreshold = amountThreshold ?? defaultPoolThreshold;
    if (amountThreshold == null) {
      try {
        final config = await StockPoolConfigService.getConfig();
        effectiveAmountThreshold = config.amountThreshold;
      } catch (e) {
        print('⚠️ 加载成交额阈值配置失败，使用默认值 $defaultPoolThreshold 亿: $e');
        effectiveAmountThreshold = defaultPoolThreshold;
      }
    }

    final bool thresholdChanged = (_currentThreshold - effectiveAmountThreshold).abs() > 1e-6;

    // 检查缓存是否有效
    if (!forceRefresh &&
        !thresholdChanged &&
        _cachedStockPool.isNotEmpty &&
        _lastUpdateTime != null &&
        DateTime.now().difference(_lastUpdateTime!) < cacheValidDuration) {
      print('使用缓存的股票池，共 ${_cachedStockPool.length} 只股票');
      print('缓存时间: $_lastUpdateTime');
      print('当前成交额阈值: ${_currentThreshold.toStringAsFixed(2)}亿元');
      _currentThreshold = effectiveAmountThreshold;
      return _cachedStockPool;
    }

    print('开始构建股票池... (forceRefresh: $forceRefresh)');
    print('缓存状态: 股票数量=${_cachedStockPool.length}, 最后更新时间=$_lastUpdateTime');
    
    try {
      // 1. 加载股票基础数据 (0-20%)
      onProgress?.call(10);
      final List<StockInfo> stockList = await loadStockData();
      if (stockList.isEmpty) {
        return [];
      }

      print('加载了 ${stockList.length} 只股票的基础数据');
      onProgress?.call(20);

      // 2. 批量获取单日K线数据 (20-60%)
      final List<String> tsCodes = stockList.map((stock) => stock.tsCode).toList();
      print('准备请求 ${tsCodes.length} 只股票的K线数据...');
      if (targetDate != null) {
        print('目标日期: ${DateFormat('yyyy-MM-dd').format(targetDate)}');
      }
      onProgress?.call(25);
      
      final Map<String, KlineData> klineDataMap = await getBatchDailyKlineData(
        tsCodes: tsCodes,
        targetDate: targetDate, // 传递目标日期
        onProgress: (current, total) {
          // K线数据获取进度：25% - 55%
          final progress = 25 + (current / total) * 30;
          onProgress?.call(progress.round());
        },
      );
      print('获取了 ${klineDataMap.length} 只股票的K线数据');
      onProgress?.call(55);

      // 3. 批量获取总市值数据（如果需要市值筛选）(55-75%)
      Map<String, double> marketValueMap = {};
      if (minMarketValue != null || maxMarketValue != null) {
        print('准备请求 ${tsCodes.length} 只股票的总市值数据...');
        onProgress?.call(60);
        marketValueMap = await getBatchMarketValueData(
          tsCodes: tsCodes,
          targetDate: targetDate, // 传递目标日期
          onProgress: (current, total) {
            // 总市值数据获取进度：60% - 75%
            final progress = 60 + (current / total) * 15;
            onProgress?.call(progress.round());
          },
        );
        print('获取了 ${marketValueMap.length} 只股票的总市值数据');
        onProgress?.call(75);
      } else {
        onProgress?.call(75);
      }

      // 4. 筛选成交额超过阈值和总市值在范围内的股票，跳过ST股票 (80-90%)
      onProgress?.call(85);
      List<StockInfo> stockPool = [];
      
      for (StockInfo stock in stockList) {
        // 跳过ST股票
        if (stock.name.contains('ST')) {
          continue;
        }
        
        final KlineData? klineData = klineDataMap[stock.tsCode];
        
        // 检查成交额条件
        if (klineData == null || klineData.amountInYi < effectiveAmountThreshold) {
          continue;
        }
        
        // 检查总市值条件
        if (minMarketValue != null || maxMarketValue != null) {
          final double? marketValue = marketValueMap[stock.tsCode];
          if (marketValue == null) {
            print('⚠️ ${stock.name} 未获取到总市值数据，跳过');
            continue;
          }
          
          if (minMarketValue != null && marketValue < minMarketValue) {
            print('❌ ${stock.name} 总市值${marketValue.toStringAsFixed(2)}亿元 < ${minMarketValue}亿元，跳过');
            continue;
          }
          
          if (maxMarketValue != null && marketValue > maxMarketValue) {
            print('❌ ${stock.name} 总市值${marketValue.toStringAsFixed(2)}亿元 > ${maxMarketValue}亿元，跳过');
            continue;
          }
          
          print('✅ ${stock.name} 总市值${marketValue.toStringAsFixed(2)}亿元 在范围内[${minMarketValue ?? 0}亿, ${maxMarketValue ?? '∞'}亿]');
        }
        
        // 创建包含总市值的StockInfo对象
        final stockWithMarketValue = StockInfo(
          tsCode: stock.tsCode,
          name: stock.name,
          symbol: stock.symbol,
          area: stock.area,
          industry: stock.industry,
          market: stock.market,
          listDate: stock.listDate,
          totalMarketValue: marketValueMap[stock.tsCode],
        );
        
        stockPool.add(stockWithMarketValue);
      }

      // 5. 更新缓存 (90-95%)
      onProgress?.call(90);
      _cachedStockPool = stockPool;
      _lastUpdateTime = DateTime.now();

      // 6. 保存到本地（包含K线数据）(95-100%)
      onProgress?.call(95);
      await saveStockPoolToLocal(
        stockPool,
        klineDataMap,
        minMarketValue: minMarketValue,
        maxMarketValue: maxMarketValue,
        targetDate: targetDate,
        threshold: effectiveAmountThreshold,
      );
      onProgress?.call(100);

      String conditionText = '成交额 ≥ ${effectiveAmountThreshold.toStringAsFixed(2)}亿元';
      if (targetDate != null) {
        conditionText += ' (${DateFormat('yyyy-MM-dd').format(targetDate)})';
      }
      if (minMarketValue != null || maxMarketValue != null) {
        conditionText += ', 总市值在[${minMarketValue ?? 0}亿, ${maxMarketValue ?? '∞'}亿]范围内';
      }
      print('股票池构建完成，共 ${stockPool.length} 只股票（$conditionText）');
      _currentThreshold = effectiveAmountThreshold;
      return stockPool;
      
    } catch (e) {
      print('构建股票池失败: $e');
      return [];
    }
  }

  // 获取股票池信息
  static Map<String, dynamic> getPoolInfo() {
    return {
      'stockCount': _cachedStockPool.length,
      'lastUpdateTime': _lastUpdateTime,
      'isValid': _lastUpdateTime != null && 
                 DateTime.now().difference(_lastUpdateTime!) < cacheValidDuration,
      'threshold': _currentThreshold,
    };
  }

  // 清空缓存
  static void clearCache() {
    _cachedStockPool.clear();
    _lastUpdateTime = null;
    print('股票池缓存已清空');
  }

  // 强制清空缓存并重新构建
  static Future<List<StockInfo>> rebuildStockPool() async {
    clearCache();
    return buildStockPool(forceRefresh: true);
  }

  // 获取本地文件路径
  static Future<String> _getLocalFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/stock_pool.json';
  }

  // 保存股票池到本地（包含K线数据）
  static Future<void> saveStockPoolToLocal(
    List<StockInfo> stockPool,
    Map<String, KlineData> klineDataMap, {
    double? minMarketValue,
    double? maxMarketValue,
    DateTime? targetDate,
    double threshold = defaultPoolThreshold,
  }) async {
    try {
      final file = File(await _getLocalFilePath());
      final jsonData = {
        'stockPool': stockPool.map((stock) => stock.toJson()).toList(),
        'klineData': klineDataMap.map((key, value) => MapEntry(key, value.toJson())),
        'lastUpdateTime': DateTime.now().toIso8601String(),
        'threshold': threshold,
        'minMarketValue': minMarketValue,
        'maxMarketValue': maxMarketValue,
        'targetDate': targetDate?.toIso8601String(),
        'enableMarketValueFilter': minMarketValue != null || maxMarketValue != null,
      };
      await file.writeAsString(json.encode(jsonData));
      print('股票池已保存到本地，共 ${stockPool.length} 只股票');
    } catch (e) {
      print('保存股票池到本地失败: $e');
    }
  }

  // 从本地加载股票池和K线数据
  static Future<Map<String, dynamic>> loadStockPoolFromLocal() async {
    try {
      final file = File(await _getLocalFilePath());
      if (!await file.exists()) {
        print('本地股票池文件不存在');
        _currentThreshold = defaultPoolThreshold;
        return {
          'stockPool': <StockInfo>[],
          'klineData': <String, KlineData>{},
          'threshold': defaultPoolThreshold,
        };
      }

      final jsonString = await file.readAsString();
      final jsonData = json.decode(jsonString);
      
      final double savedThreshold =
          (jsonData['threshold'] is num) ? (jsonData['threshold'] as num).toDouble() : defaultPoolThreshold;
      _currentThreshold = savedThreshold;

      final List<dynamic> stockList = jsonData['stockPool'] ?? [];
      final List<StockInfo> stockPool = stockList
          .map((json) => StockInfo.fromJson(json))
          .toList();

      final Map<String, dynamic> klineDataJson = jsonData['klineData'] ?? {};
      final Map<String, KlineData> klineData = klineDataJson.map(
        (key, value) => MapEntry(key, KlineData.fromJson(value)),
      );

      print('从本地加载股票池，共 ${stockPool.length} 只股票');
      return {
        'stockPool': stockPool,
        'klineData': klineData,
        'threshold': savedThreshold,
      };
    } catch (e) {
      print('从本地加载股票池失败: $e');
      _currentThreshold = defaultPoolThreshold;
      return {
        'stockPool': <StockInfo>[],
        'klineData': <String, KlineData>{},
        'threshold': defaultPoolThreshold,
      };
    }
  }

  // 获取本地股票池信息
  static Future<Map<String, dynamic>> getLocalPoolInfo() async {
    try {
      final file = File(await _getLocalFilePath());
      if (!await file.exists()) {
        return {
          'stockCount': 0,
          'lastUpdateTime': null,
          'isValid': false,
          'threshold': defaultPoolThreshold,
          'enableMarketValueFilter': false,
          'minMarketValue': null,
          'maxMarketValue': null,
          'targetDate': null,
        };
      }

      final jsonString = await file.readAsString();
      final jsonData = json.decode(jsonString);
      
      final lastUpdateTime = DateTime.tryParse(jsonData['lastUpdateTime'] ?? '');
      final now = DateTime.now();
      final isValid = lastUpdateTime != null && 
                     now.difference(lastUpdateTime) < const Duration(days: 1); // 本地数据1天有效

      final threshold =
          (jsonData['threshold'] is num) ? (jsonData['threshold'] as num).toDouble() : defaultPoolThreshold;
      _currentThreshold = threshold;

      return {
        'stockCount': (jsonData['stockPool'] as List?)?.length ?? 0,
        'lastUpdateTime': lastUpdateTime,
        'isValid': isValid,
        'threshold': threshold,
        'enableMarketValueFilter': jsonData['enableMarketValueFilter'] ?? false,
        'minMarketValue': jsonData['minMarketValue'],
        'maxMarketValue': jsonData['maxMarketValue'],
        'targetDate': jsonData['targetDate'] != null ? DateTime.tryParse(jsonData['targetDate']) : null,
      };
    } catch (e) {
      print('获取本地股票池信息失败: $e');
      _currentThreshold = defaultPoolThreshold;
      return {
        'stockCount': 0,
        'lastUpdateTime': null,
        'isValid': false,
        'threshold': defaultPoolThreshold,
        'enableMarketValueFilter': false,
        'minMarketValue': null,
        'maxMarketValue': null,
        'targetDate': null,
      };
    }
  }

  // 检查是否需要更新K线数据
  static Future<bool> needUpdateKlineData() async {
    try {
      final file = File(await _getLocalFilePath());
      if (!await file.exists()) {
        return true;
      }

      final jsonString = await file.readAsString();
      final jsonData = json.decode(jsonString);
      
      final lastUpdateTime = DateTime.tryParse(jsonData['lastUpdateTime'] ?? '');
      if (lastUpdateTime == null) {
        return true;
      }

      final now = DateTime.now();
      // 如果超过1天，需要更新K线数据
      return now.difference(lastUpdateTime) > const Duration(days: 1);
    } catch (e) {
      print('检查K线数据更新状态失败: $e');
      return true;
    }
  }

  // 更新K线数据（如果超过1天）
  static Future<Map<String, KlineData>> updateKlineDataIfNeeded(List<StockInfo> stockPool) async {
    if (!await needUpdateKlineData()) {
      print('K线数据仍然有效，无需更新');
      return {};
    }

    print('K线数据超过1天，开始更新...');
    final List<String> tsCodes = stockPool.map((stock) => stock.tsCode).toList();
    return await getBatchDailyKlineData(tsCodes: tsCodes);
  }

  // 获取历史K线数据（用于计算均线）
  static Future<List<KlineData>> getHistoricalKlineData({
    required String tsCode,
    int days = 30,
    DateTime? targetDate,
  }) async {
    try {
      DateTime endDate;
      DateTime startDate;
      
      if (targetDate != null) {
        // 如果指定了目标日期，以该日期为结束日期
        endDate = targetDate;
        startDate = endDate.subtract(Duration(days: days));
      } else {
        // 默认以当前日期为结束日期
        endDate = DateTime.now();
        startDate = endDate.subtract(Duration(days: days));
      }
      
      final String formattedStartDate = DateFormat('yyyyMMdd').format(startDate);
      final String formattedEndDate = DateFormat('yyyyMMdd').format(endDate);

      final Map<String, dynamic> requestData = {
        "api_name": "daily",
        "token": token,
        "params": {
          "ts_code": tsCode,
          "start_date": formattedStartDate,
          "end_date": formattedEndDate
        },
        "fields": "ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount"
      };

      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestData),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData['code'] == 0) {
          final data = responseData['data'];
          if (data != null) {
            final List<dynamic> items = data['items'] ?? [];
            final List<dynamic> fieldsData = data['fields'] ?? [];
            final List<String> fields = fieldsData.cast<String>();
            
            List<KlineData> klineDataList = [];
            
            for (var item in items) {
              Map<String, dynamic> itemMap = {};
              for (int i = 0; i < fields.length && i < item.length; i++) {
                itemMap[fields[i]] = item[i];
              }
              try {
                klineDataList.add(KlineData.fromJson(itemMap));
              } catch (e) {
                print('解析历史K线数据项失败: $e, 数据: $itemMap');
              }
            }
            
            // 按交易日期排序（从早到晚，与其他方法保持一致）
            klineDataList.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
            return klineDataList;
          }
        } else {
          print('获取历史K线数据API返回错误: ${responseData['msg']}');
        }
      } else {
        print('获取历史K线数据HTTP请求失败: ${response.statusCode}');
      }
    } catch (e) {
      print('获取历史K线数据失败: $e');
    }
    return [];
  }

  // 批量获取历史K线数据（优化版本）
  static Future<Map<String, List<KlineData>>> getBatchHistoricalKlineData({
    required List<String> tsCodes,
    int days = 30,
    DateTime? targetDate,
    int? customBatchSize, // 自定义分组大小
  }) async {
    Map<String, List<KlineData>> result = {};
    
    // 使用智能优化器计算最优分组大小
    final batchSize = customBatchSize ?? BatchOptimizer.getOptimalBatchSize(tsCodes.length, 'historical');
    final delay = BatchOptimizer.getOptimalDelay(batchSize);
    
    // 将股票代码分组
    List<List<String>> batches = [];
    for (int i = 0; i < tsCodes.length; i += batchSize) {
      int end = (i + batchSize < tsCodes.length) ? i + batchSize : tsCodes.length;
      batches.add(tsCodes.sublist(i, end));
    }
    
    final optimizationInfo = BatchOptimizer.getOptimizationInfo(tsCodes.length, 'historical');
    print('📊 开始批量获取 ${tsCodes.length} 只股票的历史K线数据');
    print('🚀 优化策略: 分组大小=${batchSize}, 延时=${delay.inMilliseconds}ms, 预估时间=${optimizationInfo['estimatedTime']}秒');
    
    for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      final batch = batches[batchIndex];
      print('🔄 处理第 ${batchIndex + 1}/${batches.length} 批，包含 ${batch.length} 只股票');
      
      try {
        // 使用批量查询接口
        final batchResult = await getBatchHistoricalKlineDataSingleRequest(
          tsCodes: batch,
          days: days,
          targetDate: targetDate,
        );
        
        // 合并结果
        result.addAll(batchResult);
        
        // 使用优化的延时策略
        if (batchIndex < batches.length - 1) {
          await Future.delayed(delay);
        }
      } catch (e) {
        print('❌ 第 ${batchIndex + 1} 批查询失败: $e');
        // 如果批量查询失败，回退到单个查询
        for (String tsCode in batch) {
          try {
            final klineData = await getHistoricalKlineData(tsCode: tsCode, days: days, targetDate: targetDate);
            result[tsCode] = klineData;
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            print('获取 $tsCode 的历史K线数据失败: $e');
            result[tsCode] = [];
          }
        }
      }
    }
    
    print('✅ 批量获取历史K线数据完成，成功获取 ${result.length} 只股票的数据');
    return result;
  }

  // 单次请求获取多个股票的历史K线数据
  static Future<Map<String, List<KlineData>>> getBatchHistoricalKlineDataSingleRequest({
    required List<String> tsCodes,
    int days = 30,
    DateTime? targetDate,
  }) async {
    try {
      DateTime endDate;
      DateTime startDate;
      
      if (targetDate != null) {
        // 如果指定了目标日期，请求该日期前days天的数据
        endDate = targetDate;
        startDate = targetDate.subtract(Duration(days: days * 2)); // 多请求一些数据确保有足够的交易日
      } else {
        // 默认请求最近days天的数据
        endDate = DateTime.now();
        startDate = endDate.subtract(Duration(days: days * 2));
      }
      
      final String formattedStartDate = DateFormat('yyyyMMdd').format(startDate);
      final String formattedEndDate = DateFormat('yyyyMMdd').format(endDate);
      
      // 将多个股票代码用逗号分隔
      final String tsCodesString = tsCodes.join(',');

      final Map<String, dynamic> requestData = {
        "api_name": "daily",
        "token": token,
        "params": {
          "ts_code": tsCodesString,
          "start_date": formattedStartDate,
          "end_date": formattedEndDate
        },
        "fields": "ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount"
      };

      print('📡 批量请求历史数据: ${tsCodes.length}只股票，日期范围: $formattedStartDate - $formattedEndDate');

      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestData),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData['code'] == 0) {
          final data = responseData['data'];
          if (data != null) {
            final List<dynamic> items = data['items'] ?? [];
            final List<dynamic> fieldsData = data['fields'] ?? [];
            final List<String> fields = fieldsData.cast<String>();
            
            print('📊 批量历史数据响应: 获取到 ${items.length} 条数据');
            
            // 按股票代码分组数据
            Map<String, List<KlineData>> result = {};
            
            for (var item in items) {
              Map<String, dynamic> itemMap = {};
              for (int i = 0; i < fields.length && i < item.length; i++) {
                itemMap[fields[i]] = item[i];
              }
              
              try {
                final klineData = KlineData.fromJson(itemMap);
                final tsCode = klineData.tsCode;
                
                if (!result.containsKey(tsCode)) {
                  result[tsCode] = [];
                }
                result[tsCode]!.add(klineData);
              } catch (e) {
                print('解析历史K线数据项失败: $e, 数据: $itemMap');
              }
            }
            
            // 对每个股票的数据按时间排序
            for (String tsCode in result.keys) {
              result[tsCode]!.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
            }
            
            return result;
          } else {
            print('API返回数据为空');
            return {};
          }
        } else {
          print('API返回错误: ${responseData['msg']}');
          return {};
        }
      } else {
        print('HTTP请求失败: ${response.statusCode}');
        return {};
      }
    } catch (e) {
      print('批量获取历史K线数据失败: $e');
      return {};
    }
  }
}
