import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import 'batch_optimizer.dart';

class StockApiService {
  static const String baseUrl = 'http://api.tushare.pro';
  static const String token = 'ddff564aabaeee65ad88faf07073d3ba40d62c657d0b1850f47834ce';

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

  // 获取K线数据（单个股票）
  static Future<List<KlineData>> getKlineData({
    required String tsCode,
    required String kLineType,
    int days = 60,
    String? endDate, // 可选的结束日期，格式为yyyyMMdd
  }) async {
    try {
      // 计算开始和结束日期
      final DateTime endDateTime = endDate != null 
          ? DateTime.parse('${endDate.substring(0,4)}-${endDate.substring(4,6)}-${endDate.substring(6,8)}')
          : DateTime.now();
      final DateTime startDate = endDateTime.subtract(Duration(days: days));
      
      final String formattedStartDate = DateFormat('yyyyMMdd').format(startDate);
      final String formattedEndDate = DateFormat('yyyyMMdd').format(endDateTime);

      final Map<String, dynamic> requestData = {
        "api_name": kLineType,
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
                // 静默处理解析错误
              }
            }
            
            // 按交易日期排序，确保时间顺序正确（从早到晚）
            klineDataList.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
            
            return klineDataList;
          } else {
            return [];
          }
        } else {
          return [];
        }
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // 批量获取多个股票的K线数据（优化版本，支持智能分组查询）
  static Future<Map<String, List<KlineData>>> getBatchKlineData({
    required List<String> tsCodes,
    required String kLineType,
    int days = 60,
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
    print('📊 开始批量获取 ${tsCodes.length} 只股票的K线数据');
    print('🚀 优化策略: 分组大小=${batchSize}, 延时=${delay.inMilliseconds}ms, 预估时间=${optimizationInfo['estimatedTime']}秒');
    
    for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      final batch = batches[batchIndex];
      print('🔄 处理第 ${batchIndex + 1}/${batches.length} 批，包含 ${batch.length} 只股票');
      
      try {
        // 使用批量查询接口
        final batchResult = await getBatchKlineDataSingleRequest(
          tsCodes: batch,
          kLineType: kLineType,
          days: days,
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
            final klineData = await getKlineData(
              tsCode: tsCode,
              kLineType: kLineType,
              days: days,
            );
            result[tsCode] = klineData;
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            print('获取 $tsCode 的K线数据失败: $e');
            result[tsCode] = [];
          }
        }
      }
    }
    
    print('✅ 批量获取完成，成功获取 ${result.length} 只股票的数据');
    return result;
  }

  // 单次请求获取多个股票的K线数据
  static Future<Map<String, List<KlineData>>> getBatchKlineDataSingleRequest({
    required List<String> tsCodes,
    required String kLineType,
    int days = 60,
  }) async {
    try {
      // 计算开始和结束日期
      final DateTime endDate = DateTime.now();
      final DateTime startDate = endDate.subtract(Duration(days: days));
      
      final String formattedStartDate = DateFormat('yyyyMMdd').format(startDate);
      final String formattedEndDate = DateFormat('yyyyMMdd').format(endDate);
      
      // 将多个股票代码用逗号分隔
      final String tsCodesString = tsCodes.join(',');

      final Map<String, dynamic> requestData = {
        "api_name": kLineType,
        "token": token,
        "params": {
          "ts_code": tsCodesString,
          "start_date": formattedStartDate,
          "end_date": formattedEndDate
        },
        "fields": "ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount"
      };

      print('📡 批量请求: ${tsCodes.length}只股票，日期范围: $formattedStartDate - $formattedEndDate');

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
                // 静默处理解析错误
              }
            }
            
            // 对每个股票的数据按交易日期排序
            for (String tsCode in result.keys) {
              result[tsCode]!.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
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
}
