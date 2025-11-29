import 'package:intl/intl.dart';
import 'stock_api_service.dart';

class TestApiService {
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

      final responseData = await StockApiService.callTushareApi(
        apiName: "daily",
        params: {
          "ts_code": "000001.SZ",
          "start_date": formattedStartDate,
          "end_date": formattedEndDate
        },
        fields: "ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount",
      );

      if (responseData != null) {
        print('解析后的响应数据: $responseData');
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
        print('API调用失败');
      }
    } catch (e) {
      print('测试API连接失败: $e');
    }
  }
}
