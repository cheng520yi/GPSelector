import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock_info.dart';

/// 股票信息服务
/// 用于存储和管理所有添加到分组的股票信息
class StockInfoService {
  static const String _stockInfoKey = 'stock_info_map';

  /// 保存股票信息
  static Future<bool> saveStockInfo(StockInfo stock) async {
    try {
      final allStocks = await getAllStockInfos();
      // 更新或添加股票信息
      allStocks[stock.tsCode] = stock;
      final prefs = await SharedPreferences.getInstance();
      final stockInfoMap = allStocks.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString(_stockInfoKey, json.encode(stockInfoMap));
      return true;
    } catch (e) {
      print('保存股票信息失败: $e');
      return false;
    }
  }

  /// 批量保存股票信息
  static Future<bool> saveStockInfos(List<StockInfo> stocks) async {
    try {
      final allStocks = await getAllStockInfos();
      for (final stock in stocks) {
        allStocks[stock.tsCode] = stock;
      }
      final prefs = await SharedPreferences.getInstance();
      final stockInfoMap = allStocks.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString(_stockInfoKey, json.encode(stockInfoMap));
      return true;
    } catch (e) {
      print('批量保存股票信息失败: $e');
      return false;
    }
  }

  /// 获取所有股票信息
  static Future<Map<String, StockInfo>> getAllStockInfos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stockInfoJson = prefs.getString(_stockInfoKey);
      if (stockInfoJson != null) {
        final Map<String, dynamic> stockInfoMap = json.decode(stockInfoJson);
        return stockInfoMap.map((key, value) => MapEntry(key, StockInfo.fromJson(value)));
      }
      return {};
    } catch (e) {
      print('获取所有股票信息失败: $e');
      return {};
    }
  }

  /// 根据股票代码列表获取股票信息
  static Future<List<StockInfo>> getStockInfosByCodes(List<String> tsCodes) async {
    try {
      final allStocks = await getAllStockInfos();
      return tsCodes
          .where((code) => allStocks.containsKey(code))
          .map((code) => allStocks[code]!)
          .toList();
    } catch (e) {
      print('根据代码列表获取股票信息失败: $e');
      return [];
    }
  }

  /// 获取单个股票信息
  static Future<StockInfo?> getStockInfo(String tsCode) async {
    try {
      final allStocks = await getAllStockInfos();
      return allStocks[tsCode];
    } catch (e) {
      print('获取股票信息失败: $e');
      return null;
    }
  }

  /// 删除股票信息（当股票从所有分组中移除时）
  static Future<bool> removeStockInfo(String tsCode) async {
    try {
      final allStocks = await getAllStockInfos();
      allStocks.remove(tsCode);
      final prefs = await SharedPreferences.getInstance();
      final stockInfoMap = allStocks.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString(_stockInfoKey, json.encode(stockInfoMap));
      return true;
    } catch (e) {
      print('删除股票信息失败: $e');
      return false;
    }
  }

  /// 批量删除股票信息
  static Future<bool> removeStockInfos(List<String> tsCodes) async {
    try {
      final allStocks = await getAllStockInfos();
      for (final tsCode in tsCodes) {
        allStocks.remove(tsCode);
      }
      final prefs = await SharedPreferences.getInstance();
      final stockInfoMap = allStocks.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString(_stockInfoKey, json.encode(stockInfoMap));
      return true;
    } catch (e) {
      print('批量删除股票信息失败: $e');
      return false;
    }
  }
}

