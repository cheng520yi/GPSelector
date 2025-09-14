import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class TestApiService {
  static const String baseUrl = 'http://api.tushare.pro';
  static const String token = 'ddff564aabaeee65ad88faf07073d3ba40d62c657d0b1850f47834ce';

  // 测试API连接
  static Future<void> testApiConnection() async {
    try {
      print('开始测试API连接...');
      
      // 计算日期
      final DateTime endDate = DateTime.now();
      final DateTime startDate = endDate.subtract(const Duration(days: 5));
      
      final String formattedStartDate = DateFormat('yyyyMMdd').format(startDate);
      final String formattedEndDate = DateFormat('yyyyMMdd').format(endDate);

      print('请求日期范围: $formattedStartDate 到 $formattedEndDate');

      final Map<String, dynamic> requestData = {
        "api_name": "daily",
        "token": token,
        "params": {
          "ts_code": "000001.SZ",
          "start_date": formattedStartDate,
          "end_date": formattedEndDate
        },
        "fields": "ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount"
      };

      print('请求数据: $requestData');

      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestData),
      );

      print('HTTP状态码: ${response.statusCode}');
      print('响应体: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        print('解析后的响应数据: $responseData');
        
        if (responseData['code'] == 0) {
          print('API调用成功！');
          final data = responseData['data'];
          if (data != null) {
            print('数据字段: ${data['fields']}');
            print('数据项数量: ${data['items']?.length ?? 0}');
            if (data['items'] != null && data['items'].isNotEmpty) {
              print('第一条数据: ${data['items'][0]}');
            }
          }
        } else {
          print('API返回错误: ${responseData['msg']}');
        }
      } else {
        print('HTTP请求失败: ${response.statusCode}');
      }
    } catch (e) {
      print('测试API连接失败: $e');
    }
  }
}
