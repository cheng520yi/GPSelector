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
  
  // iFinD实时行情接口配置
  static const String iFinDBaseUrl = 'https://quantapi.51ifind.com/api/v1/real_time_quotation';
  
  // TODO: 暂时注释掉动态token刷新相关配置，使用固定token
  // static const String iFinDTokenRefreshUrl = 'https://quantapi.51ifind.com/api/v1/get_access_token';
  // static const String iFinDRefreshToken = 'eyJzaWduX3RpbWUiOiIyMDI1LTA5LTEwIDE2OjA3OjQ5In0=.eyJ1aWQiOiI4MDYxODQ4ODUiLCJ1c2VyIjp7ImFjY291bnQiOiJzaGl5b25nMTI5NyIsImF1dGhVc2VySW5mbyI6e30sImNvZGVDU0kiOltdLCJjb2RlWnpBdXRoIjpbXSwiaGFzQUlQcmVkaWN0IjpmYWxzZSwiaGFzQUlUYWxrIjpmYWxzZSwiaGFzQ0lDQyI6ZmFsc2UsImhhc0NTSSI6ZmFsc2UsImhhc0V2ZW50RHJpdmUiOmZhbHNlLCJoYXNGVFNFIjpmYWxzZSwiaGFzRmFzdCI6ZmFsc2UsImhhc0Z1bmRWYWx1YXRpb24iOmZhbHNlLCJoYXNISyI6dHJ1ZSwiaGFzTE1FIjpmYWxzZSwiaGFzTGV2ZWwyIjpmYWxzZSwiaGFzUmVhbENNRSI6ZmFsc2UsImhhc1RyYW5zZmVyIjpmYWxzZSwiaGFzVVMiOmZhbHNlLCJoYXNVU0FJbmRleCI6ZmFsc2UsImhhc1VTREVCVCI6ZmFsc2UsIm1hcmtldEF1dGgiOnsiRENFIjpmYWxzZX0sIm1heE9uTGluZSI6MSwibm9EaXNrIjpmYWxzZSwicHJvZHVjdFR5cGUiOiJTVVBFUkNPTU1BTkRQUk9EVUNUIiwicmVmcmVzaFRva2VuIjoiIiwicmVmcmVzaFRva2VuRXhwaXJlZFRpbWUiOiIyMDI1LTEwLTEwIDE2OjA3OjIwIiwic2Vzc3Npb24iOiIyOWQwNjZkOTM4MzNiMTA3MTlkZDAxNmNlMTYxZjIxNSIsInNpZEluZm8iOns2NDoiMTExMTExMTExMTExMTExMTExMTExMTExIiwxOiIxMDEiLDI6IjEiLDY3OiIxMDExMTExMTExMTExMTExMTExMTExMTEiLDM6IjEiLDY5OiIxMTExMTExMTExMTExMTExMTExMTExMTExIiw1OiIxIiw2OiIxIiw3MToiMTExMTExMTExMTExMTExMTExMTExMTAwIiw3OiIxMTExMTExMTExMSIsODoiMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDEiLDEzODoiMTExMTExMTExMTExMTExMTExMTExMTExMSIsMTM5OiIxMTExMTExMTExMTExMTExMTExMTExMTExIiwxNDA6IjExMTExMTExMTExMTExMTExMTExMTExMTEiLDE0MToiMTExMTExMTExMTExMTExMTExMTExMTExMSIsMTQyOiIxMTExMTExMTExMTExMTExMTExMTExMTExIiwxNDM6IjExIiw4MDoiMTExMTExMTExMTExMTExMTExMTExMTExIiw4MToiMTExMTExMTExMTExMTExMTExMTExMTExIiw4MjoiMTExMTExMTExMTExMTExMTExMTAxMTAiLDgzOiIxMTExMTExMTExMTExMTExMTExMDAwMDAwIiw4NToiMDExMTExMTExMTExMTExMTExMTExMTExIiw4NzoiMTExMTExMTEwMDExMTExMDExMTExMTExIiw4OToiMTExMTExMTEwMTEwMTAwMDAwMDAxMTExIiw5MDoiMTExMTEwMTExMTExMTExMTEwMDAxMTExMTAiLDkzOiIxMTExMTExMTExMTExMTExMTAwMDAxMTExIiw5NDoiMTExMTExMTExMTExMTExMTExMTExMTExMSIsOTY6IjExMTExMTExMTExMTExMTExMTExMTExMTEiLDk5OiIxMDAiLDEwMDoiMTExMTAxMTExMTExMTExMTExMCIsMTAyOiIxIiw0NDoiMTEiLDEwOToiMSIsNTM6IjExMTExMTExMTExMTExMTExMTExMTExMSIsNTQ6IjExMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwIiw1NzoiMDAwMDAwMDAwMDAwMDAwMDAwMDAxMDAwMDAwMDAiLDYyOiIxMTExMTExMTExMTExMTExMTExMTExMTEiLDYzOiIxMTExMTExMTExMTExMTExMTExMTExMTEifSwidGltZXN0YW1wIjoiMTc1NzQ5MTY2ODk4MyIsInRyYW5zQXV0aCI6ZmFsc2UsInR0bFZhbHVlIjowLCJ1aWQiOiI4MDYxODQ4ODUiLCJ1c2VyVHlwZSI6IkZSRUVJQUwiLCJ3aWZpbmRMaW1pdE1hcCI6e319fQ==.87A28522BEA4446B318DCE02DC7DDA5D9A0AE4E7E4CB2EC45EA7F3A82F13903F';
  
  // 固定的access_token（不再动态刷新）
  static const String _currentAccessToken = '1e2121f953472942dedfd7513856a000b8764061.signs_ODA2MTg0ODg1';
  
  // TODO: 暂时注释掉token过期时间管理
  // static DateTime? _tokenExpireTime;

  // 获取固定的access_token（不再使用动态刷新）
  static String getCurrentAccessToken() {
    return _currentAccessToken;
  }
  
  // TODO: 暂时注释掉动态token刷新相关函数，保留代码以便将来恢复
  /*
  // 通过refresh_token获取新的access_token
  static Future<String?> refreshAccessToken() async {
    try {
      print('🔄 开始刷新iFinD access_token...');
      
      final response = await http.post(
        Uri.parse(iFinDTokenRefreshUrl),
        headers: {
          'Content-Type': 'application/json',
          'refresh_token': iFinDRefreshToken,
        },
      );
      
      print('🔍 Token刷新HTTP响应状态码: ${response.statusCode}');
      print('🔍 Token刷新HTTP响应体: ${response.body}');
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData['errorcode'] == 0) {
          final data = responseData['data'];
          if (data != null) {
            final String newAccessToken = data['access_token'] ?? '';
            final String expiredTimeStr = data['expired_time'] ?? '';
            
            if (newAccessToken.isNotEmpty) {
              _currentAccessToken = newAccessToken;
              
              // 解析过期时间
              try {
                _tokenExpireTime = DateTime.parse(expiredTimeStr);
                print('✅ Token刷新成功，新token: ${newAccessToken.substring(0, 20)}...');
                print('✅ Token过期时间: $_tokenExpireTime');
                return newAccessToken;
              } catch (e) {
                print('⚠️ 解析token过期时间失败: $e');
                // 即使解析过期时间失败，也使用新token
                return newAccessToken;
              }
            } else {
              print('❌ Token刷新响应中access_token为空');
              return null;
            }
          } else {
            print('❌ Token刷新响应中data为空');
            return null;
          }
        } else {
          print('❌ Token刷新API返回错误: ${responseData['errorcode']} - ${responseData['errmsg']}');
          return null;
        }
      } else {
        print('❌ Token刷新HTTP请求失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Token刷新异常: $e');
      return null;
    }
  }
  
  // 检查token是否需要刷新
  static bool isTokenExpired() {
    if (_tokenExpireTime == null) {
      // 如果没有过期时间信息，假设token可能已过期，需要刷新
      return true;
    }
    
    // 提前5分钟刷新token，避免在关键时刻过期
    final now = DateTime.now();
    final refreshTime = _tokenExpireTime!.subtract(const Duration(minutes: 5));
    
    return now.isAfter(refreshTime);
  }
  
  // 获取当前有效的access_token，如果过期则自动刷新
  static Future<String> getCurrentAccessToken() async {
    if (isTokenExpired()) {
      print('🔄 Token已过期或即将过期，开始刷新...');
      final newToken = await refreshAccessToken();
      if (newToken != null) {
        return newToken;
      } else {
        print('⚠️ Token刷新失败，使用当前token');
        return _currentAccessToken;
      }
    }
    
    return _currentAccessToken;
  }
  
  // 测试token刷新功能
  static Future<void> testTokenRefresh() async {
    print('🧪 开始测试iFinD token刷新功能...');
    
    try {
      final newToken = await refreshAccessToken();
      if (newToken != null) {
        print('✅ Token刷新测试成功！');
        print('✅ 新token: ${newToken.substring(0, 30)}...');
        print('✅ Token过期时间: $_tokenExpireTime');
      } else {
        print('❌ Token刷新测试失败！');
      }
    } catch (e) {
      print('❌ Token刷新测试异常: $e');
    }
  }
  */

  // 判断当前时间是否为交易日且在交易时间内（9:30-15:00）
  static bool isTradingTime() {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=Monday, 7=Sunday
    
    // 检查是否为工作日（周一到周五）
    if (weekday < 1 || weekday > 5) {
      return false;
    }
    
    // 检查时间是否在9:30-15:00之间
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 100 + minute;
    
    // 9:30 = 930, 15:00 = 1500
    return currentTime >= 930 && currentTime <= 1500;
  }

  // 判断是否应该使用iFinD实时接口（当天且在9:30-16:30时间内）
  static bool shouldUseIFinDRealTime() {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 100 + minute;
    
    // 使用iFinD的时间范围：9:30-16:30
    // 9:30 = 930, 16:30 = 1630
    return currentTime >= 930 && currentTime <= 1630;
  }

  // 判断是否应该使用实时K线数据
  // 条件：1. 选择的日期是交易日 2. 当前时间在选择日期当天的09:30之后
  static bool shouldUseRealTimeData(DateTime selectedDate) {
    final now = DateTime.now();
    
    // 检查选择的日期是否为交易日（周一到周五）
    final selectedWeekday = selectedDate.weekday; // 1=Monday, 7=Sunday
    if (selectedWeekday < 1 || selectedWeekday > 5) {
      return false;
    }
    
    // 检查选择的日期是否为今天
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    if (selectedDay != today) {
      return false;
    }
    
    // 检查当前时间是否在09:30之后
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 100 + minute;
    
    // 9:30 = 930
    return currentTime >= 930;
  }

  // 获取实时K线数据（单个股票）
  static Future<KlineData?> getRealTimeKlineData({
    required String tsCode,
  }) async {
    try {
      final Map<String, dynamic> requestData = {
        "api_name": "rt_k",
        "token": token,
        "params": {
          "ts_code": tsCode,
        },
        "fields": "ts_code,name,pre_close,high,open,low,close,vol,amount,num,ask_volume1,bid_volume1"
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
        
        print('🔍 单个股票API响应状态码: ${responseData['code']}');
        print('🔍 单个股票API响应消息: ${responseData['msg'] ?? '无消息'}');
        
        if (responseData['code'] == 0) {
          final data = responseData['data'];
          if (data != null) {
            final List<dynamic> items = data['items'] ?? [];
            final List<dynamic> fieldsData = data['fields'] ?? [];
            final List<String> fields = fieldsData.cast<String>();
            
            print('🔍 单个股票返回数据项数量: ${items.length}');
            
            if (items.isNotEmpty) {
              Map<String, dynamic> itemMap = {};
              for (int i = 0; i < fields.length && i < items[0].length; i++) {
                itemMap[fields[i]] = items[0][i];
              }
              
              // 构造KlineData对象，实时数据需要特殊处理
              final today = DateFormat('yyyyMMdd').format(DateTime.now());
              final klineData = KlineData(
                tsCode: itemMap['ts_code'] ?? tsCode,
                tradeDate: today,
                open: double.tryParse(itemMap['open']?.toString() ?? '0') ?? 0.0,
                high: double.tryParse(itemMap['high']?.toString() ?? '0') ?? 0.0,
                low: double.tryParse(itemMap['low']?.toString() ?? '0') ?? 0.0,
                close: double.tryParse(itemMap['close']?.toString() ?? '0') ?? 0.0,
                preClose: double.tryParse(itemMap['pre_close']?.toString() ?? '0') ?? 0.0,
                change: 0.0, // 实时数据中可能没有change字段，稍后计算
                pctChg: 0.0, // 实时数据中可能没有pct_chg字段，稍后计算
                vol: double.tryParse(itemMap['vol']?.toString() ?? '0') ?? 0.0,
                amount: double.tryParse(itemMap['amount']?.toString() ?? '0') ?? 0.0,
              );
              print('✅ 单个股票成功解析: $tsCode, 成交额: ${klineData.amountInYi}亿元');
              return klineData;
            } else {
              print('❌ 单个股票返回数据为空: $tsCode');
            }
          } else {
            print('❌ 单个股票API返回数据为null: $tsCode');
          }
        } else {
          print('❌ 单个股票API返回错误: ${responseData['code']} - ${responseData['msg']}');
        }
      } else {
        print('❌ 单个股票HTTP请求失败: ${response.statusCode}');
      }
      return null;
    } catch (e) {
      print('获取实时K线数据失败: $e');
      return null;
    }
  }

  // 使用iFinD接口获取实时行情数据（支持分组请求）
  static Future<Map<String, KlineData>> getIFinDRealTimeData({
    required List<String> tsCodes,
  }) async {
    Map<String, KlineData> result = {};
    
    // iFinD API建议每次请求不超过50只股票
    const int iFinDBatchSize = 50;
    
    // 将股票代码分组
    List<List<String>> batches = [];
    for (int i = 0; i < tsCodes.length; i += iFinDBatchSize) {
      int end = (i + iFinDBatchSize < tsCodes.length) ? i + iFinDBatchSize : tsCodes.length;
      batches.add(tsCodes.sublist(i, end));
    }
    
    print('📊 iFinD开始批量获取 ${tsCodes.length} 只股票的实时数据，分为 ${batches.length} 批');
    
    for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      final batch = batches[batchIndex];
      print('🔄 iFinD处理第 ${batchIndex + 1}/${batches.length} 批，包含 ${batch.length} 只股票');
      
      try {
        final batchResult = await _getIFinDRealTimeDataSingleBatch(tsCodes: batch);
        result.addAll(batchResult);
        
        // 批次间延时，避免请求过于频繁
        if (batchIndex < batches.length - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (e) {
        print('❌ iFinD第 ${batchIndex + 1} 批请求失败: $e');
      }
    }
    
    print('✅ iFinD批量获取完成，成功获取 ${result.length} 只股票的实时数据');
    return result;
  }
  
  // 单批次iFinD实时数据请求
  static Future<Map<String, KlineData>> _getIFinDRealTimeDataSingleBatch({
    required List<String> tsCodes,
  }) async {
    try {
      // 保持原始股票代码格式（包含.SH/.SZ后缀）
      final String codesString = tsCodes.join(',');
      
      final Map<String, dynamic> requestData = {
        "codes": codesString,
        "indicators": "tradeDate,tradeTime,preClose,open,high,low,latest,latestAmount,latestVolume,avgPrice,change,changeRatio,upperLimit,downLimit,amount,volume,turnoverRatio,sellVolume,buyVolume,totalBidVol,totalAskVol,totalShares,totalCapital,pb,riseDayCount,suspensionFlag,tradeStatus,chg_1min,chg_3min,chg_5min,chg_5d,chg_10d,chg_20d,chg_60d,chg_120d,chg_250d,chg_year,mv,vol_ratio,committee,commission_diff,pe_ttm,pbr_lf,swing,lastest_price,af_backward"
      };

      print('📡 iFinD单批次请求: ${tsCodes.length}只股票');
      print('🔍 iFinD请求URL: $iFinDBaseUrl');
      print('🔍 iFinD请求数据: ${json.encode(requestData)}');

      // 获取固定的access_token
      final currentToken = getCurrentAccessToken();
      
      final response = await http.post(
        Uri.parse(iFinDBaseUrl),
        headers: {
          'Content-Type': 'application/json',
          'access_token': currentToken,
        },
        body: json.encode(requestData),
      );
      
      print('🔍 iFinD HTTP响应状态码: ${response.statusCode}');
      print('🔍 iFinD HTTP响应体: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        // 检查iFinD API的响应格式
        if (responseData['errorcode'] == 0 || responseData['errorcode'] == null) {
          final tables = responseData['tables'];
          if (tables != null && tables is List) {
            Map<String, KlineData> result = {};
            
            for (var tableItem in tables) {
              try {
                final String stockCode = tableItem['thscode'] ?? '';
                final table = tableItem['table'];
                
                if (stockCode.isNotEmpty && table != null) {
                  final today = DateFormat('yyyyMMdd').format(DateTime.now());
                  
                  // iFinD返回的数据是数组格式，取第一个元素
                  final open = (table['open'] as List?)?.isNotEmpty == true ? table['open'][0] : 0.0;
                  final high = (table['high'] as List?)?.isNotEmpty == true ? table['high'][0] : 0.0;
                  final low = (table['low'] as List?)?.isNotEmpty == true ? table['low'][0] : 0.0;
                  final latest = (table['latest'] as List?)?.isNotEmpty == true ? table['latest'][0] : 0.0;
                  final preClose = (table['preClose'] as List?)?.isNotEmpty == true ? table['preClose'][0] : 0.0;
                  final change = (table['change'] as List?)?.isNotEmpty == true ? table['change'][0] : 0.0;
                  final changeRatio = (table['changeRatio'] as List?)?.isNotEmpty == true ? table['changeRatio'][0] : 0.0;
                  final volume = (table['volume'] as List?)?.isNotEmpty == true ? table['volume'][0] : 0.0;
                  final amount = (table['amount'] as List?)?.isNotEmpty == true ? table['amount'][0] : 0.0;
                  
                  // iFinD API返回的成交额单位是元，需要转换为千元以匹配KlineData模型
                  final rawAmount = double.tryParse(amount?.toString() ?? '0') ?? 0.0;
                  final amountInQianYuan = rawAmount / 1000; // 元转换为千元
                  
                  final klineData = KlineData(
                    tsCode: stockCode,
                    tradeDate: today,
                    open: double.tryParse(open?.toString() ?? '0') ?? 0.0,
                    high: double.tryParse(high?.toString() ?? '0') ?? 0.0,
                    low: double.tryParse(low?.toString() ?? '0') ?? 0.0,
                    close: double.tryParse(latest?.toString() ?? '0') ?? 0.0,
                    preClose: double.tryParse(preClose?.toString() ?? '0') ?? 0.0,
                    change: double.tryParse(change?.toString() ?? '0') ?? 0.0,
                    pctChg: double.tryParse(changeRatio?.toString() ?? '0') ?? 0.0,
                    vol: double.tryParse(volume?.toString() ?? '0') ?? 0.0,
                    amount: amountInQianYuan, // 使用转换后的千元单位
                  );
                  result[stockCode] = klineData;
                  print('✅ iFinD成功解析股票: $stockCode, 成交额: ${klineData.amountInYi}亿元, 涨跌幅: ${klineData.pctChg}%');
                }
              } catch (e) {
                print('❌ iFinD解析股票数据失败: $e, 数据: $tableItem');
              }
            }
            
            print('🔍 iFinD单批次解析结果: ${result.length}只股票');
            return result;
          } else {
            print('❌ iFinD API返回tables为空');
            return {};
          }
        } else {
          print('❌ iFinD API返回错误: ${responseData['errorcode']} - ${responseData['errmsg']}');
          return {};
        }
      } else {
        print('❌ iFinD HTTP请求失败: ${response.statusCode}');
        return {};
      }
    } catch (e) {
      print('❌ iFinD获取实时数据异常: $e');
      return {};
    }
  }

  // 批量获取实时K线数据（优先使用iFinD，失败时回退到Tushare）
  static Future<Map<String, KlineData>> getBatchRealTimeKlineData({
    required List<String> tsCodes,
  }) async {
    print('📊 开始批量获取 ${tsCodes.length} 只股票的实时K线数据');
    
    // 检查是否应该使用iFinD实时接口
    if (shouldUseIFinDRealTime()) {
      print('🚀 当前时间适合使用iFinD接口获取实时数据...');
      Map<String, KlineData> iFinDResult = await getIFinDRealTimeData(tsCodes: tsCodes);
      
      if (iFinDResult.isNotEmpty) {
        print('✅ iFinD接口成功获取 ${iFinDResult.length} 只股票的实时数据');
        return iFinDResult;
      } else {
        print('❌ iFinD接口获取失败，查询失败');
        return {}; // 直接返回空结果，不再回退到TuShare
      }
    }
    
    print('⚠️ 当前时间不适合使用iFinD接口，直接使用Tushare历史数据接口...');
    
    // 如果iFinD失败，回退到Tushare接口
    Map<String, KlineData> result = {};
    
    // 使用智能优化器计算最优分组大小
    final batchSize = BatchOptimizer.getOptimalBatchSize(tsCodes.length, 'realtime');
    final delay = BatchOptimizer.getOptimalDelay(batchSize);
    
    // 将股票代码分组
    List<List<String>> batches = [];
    for (int i = 0; i < tsCodes.length; i += batchSize) {
      int end = (i + batchSize < tsCodes.length) ? i + batchSize : tsCodes.length;
      batches.add(tsCodes.sublist(i, end));
    }
    
    final optimizationInfo = BatchOptimizer.getOptimizationInfo(tsCodes.length, 'realtime');
    print('🚀 Tushare优化策略: 分组大小=${batchSize}, 延时=${delay.inMilliseconds}ms, 预估时间=${optimizationInfo['estimatedTime']}秒');
    
    for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      final batch = batches[batchIndex];
      print('🔄 处理第 ${batchIndex + 1}/${batches.length} 批，包含 ${batch.length} 只股票');
      
      try {
        // 使用批量查询接口
        final batchResult = await getBatchRealTimeKlineDataSingleRequest(
          tsCodes: batch,
        );
        
        // 合并结果
        result.addAll(batchResult);
        
        // 使用优化的延时策略
        if (batchIndex < batches.length - 1) {
          await Future.delayed(delay);
        }
      } catch (e) {
        print('❌ 第 ${batchIndex + 1} 批实时查询失败: $e');
        // 如果批量查询失败，回退到单个查询
        for (String tsCode in batch) {
          try {
            final klineData = await getRealTimeKlineData(tsCode: tsCode);
            if (klineData != null) {
              result[tsCode] = klineData;
            }
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            print('获取 $tsCode 的实时K线数据失败: $e');
          }
        }
      }
    }
    
    print('✅ 批量获取完成，成功获取 ${result.length} 只股票的实时数据');
    return result;
  }

  // 单次请求获取多个股票的实时K线数据
  static Future<Map<String, KlineData>> getBatchRealTimeKlineDataSingleRequest({
    required List<String> tsCodes,
  }) async {
    try {
      // 将多个股票代码用逗号分隔
      final String tsCodesString = tsCodes.join(',');

      final Map<String, dynamic> requestData = {
        "api_name": "rt_k",
        "token": token,
        "params": {
          "ts_code": tsCodesString,
        },
        "fields": "ts_code,name,pre_close,high,open,low,close,vol,amount,num,ask_volume1,bid_volume1"
      };

      print('📡 批量请求实时数据: ${tsCodes.length}只股票');
      print('🔍 请求URL: $baseUrl');
      print('🔍 请求数据: ${json.encode(requestData)}');

      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestData),
      );
      
      print('🔍 HTTP响应状态码: ${response.statusCode}');
      print('🔍 HTTP响应体: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        print('🔍 API响应状态码: ${responseData['code']}');
        print('🔍 API响应消息: ${responseData['msg'] ?? '无消息'}');
        
        if (responseData['code'] == 0) {
          final data = responseData['data'];
          if (data != null) {
            final List<dynamic> items = data['items'] ?? [];
            final List<dynamic> fieldsData = data['fields'] ?? [];
            final List<String> fields = fieldsData.cast<String>();
            
            print('🔍 返回数据项数量: ${items.length}');
            print('🔍 字段列表: $fields');
            
            // 按股票代码分组数据
            Map<String, KlineData> result = {};
            
            for (var item in items) {
              Map<String, dynamic> itemMap = {};
              for (int i = 0; i < fields.length && i < item.length; i++) {
                itemMap[fields[i]] = item[i];
              }
              
              try {
                final tsCode = itemMap['ts_code'] ?? '';
                if (tsCode.isNotEmpty) {
                  final today = DateFormat('yyyyMMdd').format(DateTime.now());
                  final klineData = KlineData(
                    tsCode: tsCode,
                    tradeDate: today,
                    open: double.tryParse(itemMap['open']?.toString() ?? '0') ?? 0.0,
                    high: double.tryParse(itemMap['high']?.toString() ?? '0') ?? 0.0,
                    low: double.tryParse(itemMap['low']?.toString() ?? '0') ?? 0.0,
                    close: double.tryParse(itemMap['close']?.toString() ?? '0') ?? 0.0,
                    preClose: double.tryParse(itemMap['pre_close']?.toString() ?? '0') ?? 0.0,
                    change: 0.0, // 实时数据中可能没有change字段，稍后计算
                    pctChg: 0.0, // 实时数据中可能没有pct_chg字段，稍后计算
                    vol: double.tryParse(itemMap['vol']?.toString() ?? '0') ?? 0.0,
                    amount: double.tryParse(itemMap['amount']?.toString() ?? '0') ?? 0.0,
                  );
                  result[tsCode] = klineData;
                  print('✅ 成功解析股票: $tsCode, 成交额: ${klineData.amountInYi}亿元');
                }
              } catch (e) {
                print('❌ 解析股票数据失败: $e, 数据: $itemMap');
              }
            }
            
            print('🔍 最终解析结果: ${result.length}只股票');
            return result;
          } else {
            print('❌ API返回数据为空');
            return {};
          }
        } else {
          print('❌ API返回错误: ${responseData['code']} - ${responseData['msg']}');
          return {};
        }
      } else {
        print('❌ HTTP请求失败: ${response.statusCode}');
        return {};
      }
    } catch (e) {
      return {};
    }
  }

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
