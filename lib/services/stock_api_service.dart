import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../models/macd_data.dart';
import 'batch_optimizer.dart';
import 'log_service.dart';
import 'console_capture_service.dart';

class StockApiService {
  static const String baseUrl = 'http://api.tushare.pro';
  static const String token = 'ddff564aabaeee65ad88faf07073d3ba40d62c657d0b1850f47834ce';
  //e7b48cdaaf2dac19f35a9ed39eb59dfbdec09d1b1f2c8a8290dcbf99
  
  // iFinD实时行情接口配置
  static const String iFinDBaseUrl = 'https://quantapi.51ifind.com/api/v1/real_time_quotation';
  
  // iFinD日期序列接口配置（用于MACD等指标）
  static const String iFinDDateSequenceUrl = 'https://quantapi.51ifind.com/api/v1/date_sequence';
  
  // TODO: 暂时注释掉动态token刷新相关配置，使用固定token
  // static const String iFinDTokenRefreshUrl = 'https://quantapi.51ifind.com/api/v1/get_access_token';
  // static const String iFinDRefreshToken = 'eyJzaWduX3RpbWUiOiIyMDI1LTA5LTEwIDE2OjA3OjQ5In0=.eyJ1aWQiOiI4MDYxODQ4ODUiLCJ1c2VyIjp7ImFjY291bnQiOiJzaGl5b25nMTI5NyIsImF1dGhVc2VySW5mbyI6e30sImNvZGVDU0kiOltdLCJjb2RlWnpBdXRoIjpbXSwiaGFzQUlQcmVkaWN0IjpmYWxzZSwiaGFzQUlUYWxrIjpmYWxzZSwiaGFzQ0lDQyI6ZmFsc2UsImhhc0NTSSI6ZmFsc2UsImhhc0V2ZW50RHJpdmUiOmZhbHNlLCJoYXNGVFNFIjpmYWxzZSwiaGFzRmFzdCI6ZmFsc2UsImhhc0Z1bmRWYWx1YXRpb24iOmZhbHNlLCJoYXNISyI6dHJ1ZSwiaGFzTE1FIjpmYWxzZSwiaGFzTGV2ZWwyIjpmYWxzZSwiaGFzUmVhbENNRSI6ZmFsc2UsImhhc1RyYW5zZmVyIjpmYWxzZSwiaGFzVVMiOmZhbHNlLCJoYXNVU0FJbmRleCI6ZmFsc2UsImhhc1VTREVCVCI6ZmFsc2UsIm1hcmtldEF1dGgiOnsiRENFIjpmYWxzZX0sIm1heE9uTGluZSI6MSwibm9EaXNrIjpmYWxzZSwicHJvZHVjdFR5cGUiOiJTVVBFUkNPTU1BTkRQUk9EVUNUIiwicmVmcmVzaFRva2VuIjoiIiwicmVmcmVzaFRva2VuRXhwaXJlZFRpbWUiOiIyMDI1LTEwLTEwIDE2OjA3OjIwIiwic2Vzc3Npb24iOiIyOWQwNjZkOTM4MzNiMTA3MTlkZDAxNmNlMTYxZjIxNSIsInNpZEluZm8iOns2NDoiMTExMTExMTExMTExMTExMTExMTExMTExIiwxOiIxMDEiLDI6IjEiLDY3OiIxMDExMTExMTExMTExMTExMTExMTExMTEiLDM6IjEiLDY5OiIxMTExMTExMTExMTExMTExMTExMTExMTExIiw1OiIxIiw2OiIxIiw3MToiMTExMTExMTExMTExMTExMTExMTExMTAwIiw3OiIxMTExMTExMTExMSIsODoiMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDEiLDEzODoiMTExMTExMTExMTExMTExMTExMTExMTExMSIsMTM5OiIxMTExMTExMTExMTExMTExMTExMTExMTExIiwxNDA6IjExMTExMTExMTExMTExMTExMTExMTExMTEiLDE0MToiMTExMTExMTExMTExMTExMTExMTExMTExMSIsMTQyOiIxMTExMTExMTExMTExMTExMTExMTExMTExIiwxNDM6IjExIiw4MDoiMTExMTExMTExMTExMTExMTExMTExMTExIiw4MToiMTExMTExMTExMTExMTExMTExMTExMTExIiw4MjoiMTExMTExMTExMTExMTExMTExMTAxMTAiLDgzOiIxMTExMTExMTExMTExMTExMTExMDAwMDAwIiw4NToiMDExMTExMTExMTExMTExMTExMTExMTExIiw4NzoiMTExMTExMTEwMDExMTExMDExMTExMTExIiw4OToiMTExMTExMTEwMTEwMTAwMDAwMDAxMTExIiw5MDoiMTExMTEwMTExMTExMTExMTEwMDAxMTExMTAiLDkzOiIxMTExMTExMTExMTExMTExMTAwMDAxMTExIiw5NDoiMTExMTExMTExMTExMTExMTExMTExMTExMSIsOTY6IjExMTExMTExMTExMTExMTExMTExMTExMTEiLDk5OiIxMDAiLDEwMDoiMTExMTAxMTExMTExMTExMTExMCIsMTAyOiIxIiw0NDoiMTEiLDEwOToiMSIsNTM6IjExMTExMTExMTExMTExMTExMTExMTExMSIsNTQ6IjExMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwIiw1NzoiMDAwMDAwMDAwMDAwMDAwMDAwMDAxMDAwMDAwMDAiLDYyOiIxMTExMTExMTExMTExMTExMTExMTExMTEiLDYzOiIxMTExMTExMTExMTExMTExMTExMTExMTEifSwidGltZXN0YW1wIjoiMTc1NzQ5MTY2ODk4MyIsInRyYW5zQXV0aCI6ZmFsc2UsInR0bFZhbHVlIjowLCJ1aWQiOiI4MDYxODQ4ODUiLCJ1c2VyVHlwZSI6IkZSRUVJQUwiLCJ3aWZpbmRMaW1pdE1hcCI6e319fQ==.87A28522BEA4446B318DCE02DC7DDA5D9A0AE4E7E4CB2EC45EA7F3A82F13903F';
  
  // 固定的access_token（不再动态刷新）
  static const String _currentAccessToken = 'fff8acc44c6183bddf175621f9adf620758fee22.signs_ODE5NjIzMzgx';
  
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

  // 判断给定日期是否为交易日（目前仅排除周末）
  static bool isTradingDay(DateTime date) {
    final weekday = date.weekday; // 1=Monday, 7=Sunday
    return weekday >= 1 && weekday <= 5;
  }

  // 判断当前时间是否在交易时间窗口（默认9:30-16:30）
  static bool isTradingTime() {
    return isWithinRealTimeWindow();
  }

  // 判断当前时间是否在实时窗口内（≥ 09:30，当天交易日）
  static bool isWithinRealTimeWindow({DateTime? referenceTime}) {
    final now = referenceTime ?? DateTime.now();
    if (!isTradingDay(now)) {
      return false;
    }
    final currentTime = now.hour * 100 + now.minute;
    return currentTime >= 930;
  }

  // 判断当前时间是否已经过了交易开始时间（9:30）
  static bool isAfterTradingStart({DateTime? referenceTime}) {
    final now = referenceTime ?? DateTime.now();
    final currentTime = now.hour * 100 + now.minute;
    return currentTime >= 930;
  }

  /// 判断是否应该使用实时数据接口（iFinD或TuShare rt_k）
  /// 仅在交易日且当前时间晚于09:30时使用实时接口，其他情况使用历史接口
  static bool shouldUseRealTimeData(DateTime selectedDate) {
    final now = DateTime.now();
    
    if (!isTradingDay(selectedDate)) {
      return false;
    }
    
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    if (selectedDay != today) {
      return false;
    }
    
    return isWithinRealTimeWindow(referenceTime: now);
  }

  /// 判断当前时间是否在历史接口可用窗口（当日 16:30 之后）
  static bool isAfterHistoryAvailability({DateTime? referenceTime}) {
    final now = referenceTime ?? DateTime.now();
    if (!isTradingDay(now)) {
      return true; // 非交易日默认允许直接使用历史数据
    }
    final currentTime = now.hour * 100 + now.minute;
    return currentTime >= 1630;
  }

  /// 判断是否应该使用iFinD实时接口（默认选择）
  /// 如果iFinD不可用，则使用TuShare rt_k接口作为备选
  static bool shouldUseIFinDRealTime() {
    // 默认使用iFinD接口
    return true;
  }

  /// 获取应该查询的日期
  /// 如果当前时间在交易日9:30之前，返回前一个交易日
  /// 否则返回选择的日期
  static DateTime getQueryDate(DateTime selectedDate) {
    final now = DateTime.now();
    
    // 检查选择的日期是否为交易日（周一到周五）
    final selectedWeekday = selectedDate.weekday; // 1=Monday, 7=Sunday
    if (selectedWeekday < 1 || selectedWeekday > 5) {
      return selectedDate; // 非交易日直接返回选择的日期
    }
    
    // 检查选择的日期是否为今天
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    if (selectedDay != today) {
      return selectedDate; // 不是今天，直接返回选择的日期
    }
    
    // 检查当前时间是否在交易日9:30之前
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 100 + minute;
    
    if (currentTime < 930) {
      // 9:30之前，返回前一个交易日
      DateTime prevTradingDay = selectedDate.subtract(const Duration(days: 1));
      
      // 如果前一个交易日是周末，继续往前推
      while (prevTradingDay.weekday > 5) {
        prevTradingDay = prevTradingDay.subtract(const Duration(days: 1));
      }
      
      return prevTradingDay;
    }
    
    return selectedDate;
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
      ConsoleCaptureService.instance.capturePrint('📡 iFinD单批次请求: ${tsCodes.length}只股票');
      print('🔍 iFinD请求URL: $iFinDBaseUrl');
      ConsoleCaptureService.instance.capturePrint('🔍 iFinD请求URL: $iFinDBaseUrl');
      print('🔍 iFinD请求数据: ${json.encode(requestData)}');
      ConsoleCaptureService.instance.capturePrint('🔍 iFinD请求数据: ${json.encode(requestData)}');

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

  // 批量获取K线数据（根据时间和日期选择实时或历史接口）
  static Future<Map<String, KlineData>> getBatchRealTimeKlineData({
    required List<String> tsCodes,
    required DateTime selectedDate,
  }) async {
    final logService = LogService.instance;
    
    logService.info('API', '开始批量获取K线数据', data: {
      'stockCount': tsCodes.length,
      'selectedDate': DateFormat('yyyy-MM-dd').format(selectedDate),
    });
    
    print('📊 开始批量获取 ${tsCodes.length} 只股票的K线数据');
    print('📅 选择日期: ${DateFormat('yyyy-MM-dd').format(selectedDate)}');
    
    // 捕获控制台输出
    ConsoleCaptureService.instance.capturePrint('📊 开始批量获取 ${tsCodes.length} 只股票的K线数据');
    ConsoleCaptureService.instance.capturePrint('📅 选择日期: ${DateFormat('yyyy-MM-dd').format(selectedDate)}');
    
    // 检查是否应该使用实时数据接口
    if (shouldUseRealTimeData(selectedDate)) {
      logService.info('API', '使用实时数据接口');
      print('🚀 当前时间适合使用实时数据接口...');
      ConsoleCaptureService.instance.capturePrint('🚀 当前时间适合使用实时数据接口...');
      
      // 优先使用iFinD实时接口
      if (shouldUseIFinDRealTime()) {
        logService.info('API', '使用iFinD实时接口');
        print('🔧 使用iFinD实时接口获取数据...');
        ConsoleCaptureService.instance.capturePrint('🔧 使用iFinD实时接口获取数据...');
        Map<String, KlineData> iFinDResult = await getIFinDRealTimeData(tsCodes: tsCodes);
        
        if (iFinDResult.isNotEmpty) {
          logService.info('API', 'iFinD接口成功', data: {
            'successCount': iFinDResult.length,
            'interface': 'iFinD_realtime'
          });
          print('✅ iFinD接口成功获取 ${iFinDResult.length} 只股票的实时数据');
          ConsoleCaptureService.instance.capturePrint('✅ iFinD接口成功获取 ${iFinDResult.length} 只股票的实时数据');
          return iFinDResult;
        } else {
          logService.warning('API', 'iFinD接口失败，尝试TuShare rt_k接口');
          print('❌ iFinD接口获取失败，尝试TuShare rt_k接口...');
          ConsoleCaptureService.instance.capturePrint('❌ iFinD接口获取失败，尝试TuShare rt_k接口...');
          
          // iFinD失败，尝试TuShare rt_k接口
          Map<String, KlineData> tuShareResult = await _getTuShareRealTimeData(tsCodes: tsCodes);
          if (tuShareResult.isNotEmpty) {
            logService.info('API', 'TuShare rt_k接口成功', data: {
              'successCount': tuShareResult.length,
              'interface': 'TuShare_rt_k'
            });
            print('✅ TuShare rt_k接口成功获取 ${tuShareResult.length} 只股票的实时数据');
            return tuShareResult;
          } else {
            logService.error('API', '所有实时接口都失败');
            print('❌ 所有实时接口都失败，查询失败');
            return {}; // 实时接口都失败，返回空结果
          }
        }
      } else {
        // 使用TuShare rt_k接口
        logService.info('API', '使用TuShare rt_k接口');
        print('🔧 使用TuShare rt_k接口获取实时数据...');
        Map<String, KlineData> tuShareResult = await _getTuShareRealTimeData(tsCodes: tsCodes);
        if (tuShareResult.isNotEmpty) {
          logService.info('API', 'TuShare rt_k接口成功', data: {
            'successCount': tuShareResult.length,
            'interface': 'TuShare_rt_k'
          });
          print('✅ TuShare rt_k接口成功获取 ${tuShareResult.length} 只股票的实时数据');
          return tuShareResult;
        } else {
          logService.error('API', 'TuShare rt_k接口失败');
          print('❌ TuShare rt_k接口获取失败，查询失败');
          return {}; // TuShare rt_k失败，返回空结果
        }
      }
    }
    
    print('⚠️ 当前时间不适合使用实时接口，使用历史数据接口...');
    
    // 获取应该查询的日期
    final queryDate = getQueryDate(selectedDate);
    print('📅 实际查询日期: ${DateFormat('yyyy-MM-dd').format(queryDate)}');
    
    // 使用历史数据接口
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
        // 使用历史数据批量查询接口
        final batchResult = await getBatchHistoricalKlineDataSingleRequest(
          tsCodes: batch,
          queryDate: queryDate,
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
            final klineData = await getHistoricalKlineData(tsCode: tsCode, queryDate: queryDate);
            if (klineData != null) {
              result[tsCode] = klineData;
            }
            await Future.delayed(const Duration(milliseconds: 100));
          } catch (e) {
            print('获取 $tsCode 的历史K线数据失败: $e');
          }
        }
      }
    }
    
    print('✅ 批量获取完成，成功获取 ${result.length} 只股票的实时数据');
    return result;
  }

  // 使用TuShare rt_k接口获取实时数据
  static Future<Map<String, KlineData>> _getTuShareRealTimeData({
    required List<String> tsCodes,
  }) async {
    print('🔧 使用TuShare rt_k接口获取实时数据...');
    
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
    print('🚀 TuShare rt_k优化策略: 分组大小=${batchSize}, 延时=${delay.inMilliseconds}ms, 预估时间=${optimizationInfo['estimatedTime']}秒');
    
    Map<String, KlineData> result = {};
    
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
        print('❌ 第 ${batchIndex + 1} 批TuShare rt_k查询失败: $e');
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
    
    print('✅ TuShare rt_k批量获取完成，成功获取 ${result.length} 只股票的实时数据');
    return result;
  }

  // 获取单个股票的历史K线数据（指定日期）
  static Future<KlineData?> getHistoricalKlineData({
    required String tsCode,
    required DateTime queryDate,
  }) async {
    try {
      final String formattedDate = DateFormat('yyyyMMdd').format(queryDate);
      
      final Map<String, dynamic> requestData = {
        "api_name": "daily",
        "token": token,
        "params": {
          "ts_code": tsCode,
          "start_date": formattedDate,
          "end_date": formattedDate
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
            
            if (items.isNotEmpty) {
              final item = items[0]; // 取第一条记录
              Map<String, dynamic> itemMap = {};
              for (int i = 0; i < fields.length && i < item.length; i++) {
                itemMap[fields[i]] = item[i];
              }
              
              return KlineData(
                tsCode: itemMap['ts_code'] ?? '',
                tradeDate: itemMap['trade_date'] ?? '',
                open: (itemMap['open'] ?? 0.0).toDouble(),
                high: (itemMap['high'] ?? 0.0).toDouble(),
                low: (itemMap['low'] ?? 0.0).toDouble(),
                close: (itemMap['close'] ?? 0.0).toDouble(),
                preClose: (itemMap['pre_close'] ?? 0.0).toDouble(),
                change: (itemMap['change'] ?? 0.0).toDouble(),
                pctChg: (itemMap['pct_chg'] ?? 0.0).toDouble(),
                vol: (itemMap['vol'] ?? 0.0).toDouble(),
                amount: (itemMap['amount'] ?? 0.0).toDouble(),
              );
            }
          }
        } else {
          print('❌ 获取历史数据API返回错误: ${responseData['code']} - ${responseData['msg']}');
        }
      } else {
        print('❌ 获取历史数据HTTP请求失败: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 获取历史数据异常: $e');
    }
    
    return null;
  }

  // 批量获取历史K线数据（单次请求）
  static Future<Map<String, KlineData>> getBatchHistoricalKlineDataSingleRequest({
    required List<String> tsCodes,
    required DateTime queryDate,
  }) async {
    try {
      final String formattedDate = DateFormat('yyyyMMdd').format(queryDate);
      final String tsCodeStr = tsCodes.join(',');
      
      final Map<String, dynamic> requestData = {
        "api_name": "daily",
        "token": token,
        "params": {
          "ts_code": tsCodeStr,
          "start_date": formattedDate,
          "end_date": formattedDate
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
            
            Map<String, KlineData> result = {};
            
            for (var item in items) {
              Map<String, dynamic> itemMap = {};
              for (int i = 0; i < fields.length && i < item.length; i++) {
                itemMap[fields[i]] = item[i];
              }
              
              try {
                final klineData = KlineData(
                  tsCode: itemMap['ts_code'] ?? '',
                  tradeDate: itemMap['trade_date'] ?? '',
                  open: (itemMap['open'] ?? 0.0).toDouble(),
                  high: (itemMap['high'] ?? 0.0).toDouble(),
                  low: (itemMap['low'] ?? 0.0).toDouble(),
                  close: (itemMap['close'] ?? 0.0).toDouble(),
                  preClose: (itemMap['pre_close'] ?? 0.0).toDouble(),
                  change: (itemMap['change'] ?? 0.0).toDouble(),
                  pctChg: (itemMap['pct_chg'] ?? 0.0).toDouble(),
                  vol: (itemMap['vol'] ?? 0.0).toDouble(),
                  amount: (itemMap['amount'] ?? 0.0).toDouble(),
                );
                result[klineData.tsCode] = klineData;
              } catch (e) {
                print('❌ 解析历史数据失败: $e, 数据: $itemMap');
              }
            }
            
            return result;
          }
        } else {
          print('❌ 批量获取历史数据API返回错误: ${responseData['code']} - ${responseData['msg']}');
        }
      } else {
        print('❌ 批量获取历史数据HTTP请求失败: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 批量获取历史数据异常: $e');
    }
    
    return {};
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
      ConsoleCaptureService.instance.capturePrint('📡 批量请求实时数据: ${tsCodes.length}只股票');
      print('🔍 请求URL: $baseUrl');
      ConsoleCaptureService.instance.capturePrint('🔍 请求URL: $baseUrl');
      print('🔍 请求数据: ${json.encode(requestData)}');
      ConsoleCaptureService.instance.capturePrint('🔍 请求数据: ${json.encode(requestData)}');

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
        ConsoleCaptureService.instance.capturePrint('🔍 API响应状态码: ${responseData['code']}');
        print('🔍 API响应消息: ${responseData['msg'] ?? '无消息'}');
        ConsoleCaptureService.instance.capturePrint('🔍 API响应消息: ${responseData['msg'] ?? '无消息'}');
        
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
          ConsoleCaptureService.instance.capturePrint('❌ API返回错误: ${responseData['code']} - ${responseData['msg']}');
          return {};
        }
      } else {
        print('❌ HTTP请求失败: ${response.statusCode}');
        ConsoleCaptureService.instance.capturePrint('❌ HTTP请求失败: ${response.statusCode}');
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
      ConsoleCaptureService.instance.capturePrint('📡 批量请求: ${tsCodes.length}只股票，日期范围: $formattedStartDate - $formattedEndDate');

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

  // 获取MACD指标数据
  static Future<List<MacdData>> getMacdData({
    required String tsCode,
    required String startDate,
    required String endDate,
  }) async {
    try {
      // 将股票代码转换为iFinD格式（例如：600170.SH）
      String iFinDCode = tsCode;
      if (!iFinDCode.contains('.')) {
        // 如果没有后缀，根据代码判断
        if (tsCode.startsWith('6')) {
          iFinDCode = '$tsCode.SH';
        } else {
          iFinDCode = '$tsCode.SZ';
        }
      }

      // 尝试多种参数组合以获取DIF、DEA、M
      // 根据iFinD API文档，indiparams第一个参数可能用于指定输出字段
      // 如果第一个参数格式不对，API可能只返回默认的M值
      final Map<String, dynamic> requestData = {
        "codes": iFinDCode,
        "startdate": startDate,
        "enddate": endDate,
        "indipara": [
          {
            "indicator": "ths_macd_stock",
            // 尝试多种参数格式：
            // 1. 空字符串（默认，可能只返回M值）
            // 2. "DIF,DEA,M"（尝试指定返回字段）
            // 3. "1"（可能是指定输出格式的代码）
            // 参数含义：["输出格式/字段", "长期EMA(26)", "短期EMA(12)", "信号线(9)", "其他参数..."]
            "indiparams": ["", "26", "12", "9", "1", "0", "100"]
            // 注意：如果API只返回M值，代码会自动创建DIF和DEA占位数据
          }
        ]
      };

      print('📡 请求MACD数据: $iFinDCode, 日期范围: $startDate - $endDate');
      
      final currentToken = getCurrentAccessToken();
      
      final response = await http.post(
        Uri.parse(iFinDDateSequenceUrl),
        headers: {
          'Content-Type': 'application/json',
          'access_token': currentToken,
        },
        body: json.encode(requestData),
      );

      print('🔍 MACD HTTP响应状态码: ${response.statusCode}');
      print('🔍 MACD HTTP响应体（完整）: ${response.body}');
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        print('🔍 MACD API响应: errorcode=${responseData['errorcode']}, errmsg=${responseData['errmsg']}');
        
        if (responseData['errorcode'] == 0 || responseData['errorcode'] == null) {
          final tables = responseData['tables'];
          print('🔍 MACD tables数量: ${tables != null ? (tables as List).length : 0}');
          
          if (tables != null && tables is List && tables.isNotEmpty) {
            final table = tables[0];
            
            print('🔍 MACD table keys: ${(table as Map).keys.toList()}');
            
            // 打印完整的table结构以便调试
            print('🔍 MACD table完整内容: ${json.encode(table)}');
            
            // 根据实际API返回，数据可能在table对象中，也可能在table['table']中
            Map<String, dynamic>? tableData;
            if (table['table'] != null) {
              tableData = table['table'] as Map<String, dynamic>?;
              print('🔍 使用table[\'table\']');
            } else {
              tableData = table as Map<String, dynamic>?;
              print('🔍 直接使用table');
            }
            
            print('🔍 MACD tableData keys: ${tableData != null ? tableData.keys.toList() : 'null'}');
            
            // 打印tableData的所有内容以便调试
            if (tableData != null) {
              print('🔍 MACD tableData完整内容: ${json.encode(tableData)}');
            }
            
            // 检查table顶层是否有其他字段包含DIF/DEA
            if (table is Map) {
              print('🔍 检查table顶层所有keys: ${table.keys.toList()}');
              for (var key in table.keys) {
                if (key.toString().toLowerCase().contains('dif') || 
                    key.toString().toLowerCase().contains('dea') ||
                    key.toString().toLowerCase().contains('macd')) {
                  print('🔍 table顶层发现相关字段: $key = ${table[key].runtimeType}');
                  if (table[key] is List) {
                    print('🔍 $key 数组长度: ${(table[key] as List).length}');
                    if ((table[key] as List).isNotEmpty) {
                      print('🔍 $key 第一个元素: ${(table[key] as List)[0]}');
                    }
                  }
                }
              }
            }
            
            if (tableData != null) {
              List<MacdData> macdDataList = [];
              
              // 获取日期数组（可能是'time'或'date'）
              // 先从tableData获取，如果没有则从table获取
              final dates = (tableData['time'] as List?) ?? 
                           (tableData['date'] as List?) ?? 
                           (table['time'] as List?);
              print('🔍 日期数组: ${dates?.length ?? 0}条, 前3个: ${dates?.take(3).toList()}');
              
              // 获取MACD指标数据
              // 根据iFinD API，ths_macd_stock可能是一个数组，包含MACD值
              // DIF、DEA、M可能分别在ths_macd_stock_DIF、ths_macd_stock_DEA、ths_macd_stock_M中
              final macdIndicator = tableData['ths_macd_stock'];
              
              List? difs;
              List? deas;
              List? macds;
              
              print('🔍 MACD indicator类型: ${macdIndicator.runtimeType}');
              
              // 首先尝试从tableData中直接获取DIF、DEA、M数组
              difs = tableData['ths_macd_stock_DIF'] as List?;
              deas = tableData['ths_macd_stock_DEA'] as List?;
              macds = tableData['ths_macd_stock_M'] as List?;
              print('🔍 直接获取: DIF=${difs?.length}, DEA=${deas?.length}, M=${macds?.length}');
              
              // 如果直接获取失败，尝试从ths_macd_stock对象/数组中提取
              if ((difs == null || deas == null || macds == null) && macdIndicator != null) {
                if (macdIndicator is Map) {
                  print('🔍 MACD indicator keys: ${macdIndicator.keys.toList()}');
                  difs = difs ?? macdIndicator['DIF'] as List? ?? 
                                macdIndicator['dif'] as List? ?? 
                                macdIndicator['ths_macd_stock_DIF'] as List?;
                  deas = deas ?? macdIndicator['DEA'] as List? ?? 
                                macdIndicator['dea'] as List? ?? 
                                macdIndicator['ths_macd_stock_DEA'] as List?;
                  macds = macds ?? macdIndicator['M'] as List? ?? 
                                 macdIndicator['macd'] as List? ?? 
                                 macdIndicator['m'] as List? ?? 
                                 macdIndicator['ths_macd_stock_M'] as List?;
                  print('🔍 从Map提取: DIF=${difs?.length}, DEA=${deas?.length}, M=${macds?.length}');
                  } else if (macdIndicator is List) {
                  // 如果ths_macd_stock是数组
                  print('🔍 MACD指标是数组类型，长度: ${macdIndicator.length}');
                  if (macdIndicator.isNotEmpty) {
                    print('🔍 MACD数组第一个元素类型: ${macdIndicator[0].runtimeType}');
                    print('🔍 MACD数组第一个元素: ${macdIndicator[0]}');
                    
                    // 如果数组元素是double，说明这是MACD值（M值）
                    if (macdIndicator[0] is double) {
                      macds = macds ?? macdIndicator;
                      print('🔍 识别为MACD值数组（M值），长度: ${macds.length}');
                      
                      // 如果只有M值，尝试从tableData中查找DIF和DEA
                      // 可能字段名是 ths_macd_stock_DIF, ths_macd_stock_DEA
                      if (difs == null) {
                        // 尝试查找所有可能的DIF字段
                        for (var key in tableData.keys) {
                          if (key.toString().toLowerCase().contains('dif') && 
                              !key.toString().toLowerCase().contains('macd')) {
                            difs = tableData[key] as List?;
                            print('🔍 找到DIF字段: $key, 长度: ${difs?.length}');
                            break;
                          }
                        }
                      }
                      if (deas == null) {
                        // 尝试查找所有可能的DEA字段
                        for (var key in tableData.keys) {
                          if (key.toString().toLowerCase().contains('dea') && 
                              !key.toString().toLowerCase().contains('macd')) {
                            deas = tableData[key] as List?;
                            print('🔍 找到DEA字段: $key, 长度: ${deas?.length}');
                            break;
                          }
                        }
                      }
                    } else if (macdIndicator[0] is List) {
                      // 数组元素是数组，可能是[DIF, DEA, M]的格式
                      print('🔍 MACD数组元素是数组类型，第一个元素长度: ${(macdIndicator[0] as List).length}');
                      List<dynamic> difsList = [];
                      List<dynamic> deasList = [];
                      List<dynamic> macdsList = [];
                      for (var item in macdIndicator) {
                        if (item is List && item.length >= 3) {
                          difsList.add(item[0] ?? 0.0);
                          deasList.add(item[1] ?? 0.0);
                          macdsList.add(item[2] ?? 0.0);
                        }
                      }
                      difs = difs ?? difsList;
                      deas = deas ?? deasList;
                      macds = macds ?? macdsList;
                      print('🔍 从嵌套数组提取: DIF=${difs.length}, DEA=${deas.length}, M=${macds.length}');
                    }
                  }
                }
              }
              
              // 如果仍然没有找到DIF和DEA，尝试从table顶层获取
              if ((difs == null || deas == null) && table is Map) {
                difs = difs ?? table['ths_macd_stock_DIF'] as List?;
                deas = deas ?? table['ths_macd_stock_DEA'] as List?;
                print('🔍 从table顶层获取: DIF=${difs?.length}, DEA=${deas?.length}');
              }
              
              // 打印tableData的所有keys以便调试
              if (tableData != null) {
                print('🔍 tableData所有keys: ${tableData.keys.toList()}');
                // 查找所有包含DIF、DEA、MACD的字段
                for (var key in tableData.keys) {
                  if (key.toString().toLowerCase().contains('dif') || 
                      key.toString().toLowerCase().contains('dea') || 
                      key.toString().toLowerCase().contains('macd')) {
                    print('🔍 发现相关字段: $key = ${tableData[key].runtimeType}');
                  }
                }
              }
              
              print('🔍 MACD数据: dates=${dates?.length}, difs=${difs?.length}, deas=${deas?.length}, macds=${macds?.length}');
              
              // 如果数据仍然为空，尝试从table['table']['ths_macd_stock']中获取
              if ((difs == null || deas == null || macds == null) && table['table'] != null) {
                final nestedTable = table['table'] as Map?;
                if (nestedTable != null) {
                  final nestedMacdIndicator = nestedTable['ths_macd_stock'];
                  print('🔍 尝试从嵌套table获取MACD数据: ${nestedMacdIndicator.runtimeType}');
                  
                  if (nestedMacdIndicator is Map) {
                    difs = nestedMacdIndicator['DIF'] as List? ?? 
                           nestedMacdIndicator['dif'] as List? ?? 
                           nestedMacdIndicator['ths_macd_stock_DIF'] as List?;
                    deas = nestedMacdIndicator['DEA'] as List? ?? 
                           nestedMacdIndicator['dea'] as List? ?? 
                           nestedMacdIndicator['ths_macd_stock_DEA'] as List?;
                    macds = nestedMacdIndicator['M'] as List? ?? 
                            nestedMacdIndicator['macd'] as List? ?? 
                            nestedMacdIndicator['m'] as List? ?? 
                            nestedMacdIndicator['ths_macd_stock_M'] as List?;
                    print('🔍 从嵌套table获取: DIF=${difs?.length}, DEA=${deas?.length}, M=${macds?.length}');
                  }
                }
              }
              
              // 如果只有M值（macds）但没有DIF和DEA，检查是否可能是嵌套数组结构
              if (dates != null && macds != null && (difs == null || deas == null)) {
                print('⚠️ 只获取到MACD值（M），缺少DIF和DEA');
                print('🔍 检查ths_macd_stock数组结构，长度: ${macds.length}');
                print('🔍 MACD值示例（前5个）: ${macds.take(5).toList()}');
                
                // 检查ths_macd_stock是否可能是嵌套数组（每个元素包含[DIF, DEA, M]）
                final macdIndicator = tableData['ths_macd_stock'];
                if (macdIndicator is List && macdIndicator.isNotEmpty) {
                  final firstElement = macdIndicator[0];
                  print('🔍 ths_macd_stock第一个元素类型: ${firstElement.runtimeType}');
                  print('🔍 ths_macd_stock第一个元素值: $firstElement');
                  
                  // 如果第一个元素是List，说明是嵌套数组
                  if (firstElement is List && firstElement.length >= 3) {
                    print('✅ 发现嵌套数组结构！每个元素包含${firstElement.length}个值');
                    List<dynamic> difsList = [];
                    List<dynamic> deasList = [];
                    List<dynamic> macdsList = [];
                    for (var item in macdIndicator) {
                      if (item is List && item.length >= 3) {
                        difsList.add(item[0] ?? 0.0);
                        deasList.add(item[1] ?? 0.0);
                        macdsList.add(item[2] ?? 0.0);
                      }
                    }
                    difs = difsList;
                    deas = deasList;
                    macds = macdsList;
                    print('✅ 从嵌套数组提取: DIF=${difs.length}, DEA=${deas.length}, M=${macds.length}');
                  }
                }
                
                // 如果仍然没有DIF和DEA，不进行估算，直接返回空数据
                if (difs == null || deas == null) {
                  print('❌ API未提供DIF和DEA数据，无法绘制MACD指标');
                  print('❌ 请检查API参数或联系API提供商确认如何获取完整的MACD数据（DIF、DEA、M）');
                  return [];
                }
              }
              
              if (dates != null && difs != null && deas != null && macds != null) {
                int length = math.min(
                  dates.length,
                  math.min(difs.length, math.min(deas.length, macds.length))
                );
                
                for (int i = 0; i < length; i++) {
                  try {
                    final dateStr = dates[i]?.toString() ?? '';
                    // 将日期格式从yyyy-MM-dd转换为yyyyMMdd
                    String formattedDate = dateStr;
                    if (dateStr.contains('-')) {
                      formattedDate = dateStr.replaceAll('-', '');
                    }
                    
                    final dif = double.tryParse(difs[i]?.toString() ?? '0') ?? 0.0;
                    final dea = double.tryParse(deas[i]?.toString() ?? '0') ?? 0.0;
                    final macd = double.tryParse(macds[i]?.toString() ?? '0') ?? 0.0;
                    
                    macdDataList.add(MacdData(
                      tsCode: tsCode,
                      tradeDate: formattedDate,
                      dif: dif,
                      dea: dea,
                      macd: macd,
                    ));
                  } catch (e) {
                    print('❌ 解析MACD数据项失败: $e');
                  }
                }
                
                // 按交易日期排序
                macdDataList.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
                
                print('✅ MACD数据获取成功: ${macdDataList.length}条记录');
                return macdDataList;
              }
            }
          }
        } else {
          print('❌ MACD API返回错误: ${responseData['errorcode']} - ${responseData['errmsg']}');
        }
      } else {
        print('❌ MACD HTTP请求失败: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 获取MACD数据异常: $e');
    }
    
    return [];
  }
}
