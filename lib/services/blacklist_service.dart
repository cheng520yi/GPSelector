import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock_info.dart';
import 'stock_pool_service.dart';

class BlacklistService {
  static const String _blacklistKey = 'stock_blacklist';
  
  // 获取黑名单
  static Future<List<String>> getBlacklist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blacklistJson = prefs.getString(_blacklistKey);
      if (blacklistJson != null) {
        final List<dynamic> blacklist = json.decode(blacklistJson);
        return blacklist.cast<String>();
      }
      return [];
    } catch (e) {
      print('获取黑名单失败: $e');
      return [];
    }
  }
  
  // 添加到黑名单
  static Future<bool> addToBlacklist(String tsCode) async {
    try {
      final blacklist = await getBlacklist();
      if (!blacklist.contains(tsCode)) {
        blacklist.add(tsCode);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_blacklistKey, json.encode(blacklist));
        print('✅ 已添加 $tsCode 到黑名单');
        return true;
      }
      return false;
    } catch (e) {
      print('添加到黑名单失败: $e');
      return false;
    }
  }
  
  // 从黑名单移除
  static Future<bool> removeFromBlacklist(String tsCode) async {
    try {
      final blacklist = await getBlacklist();
      if (blacklist.remove(tsCode)) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_blacklistKey, json.encode(blacklist));
        print('✅ 已从黑名单移除 $tsCode');
        return true;
      }
      return false;
    } catch (e) {
      print('从黑名单移除失败: $e');
      return false;
    }
  }
  
  // 检查是否在黑名单中
  static Future<bool> isInBlacklist(String tsCode) async {
    final blacklist = await getBlacklist();
    return blacklist.contains(tsCode);
  }
  
  // 清空黑名单
  static Future<bool> clearBlacklist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_blacklistKey);
      print('✅ 已清空黑名单');
      return true;
    } catch (e) {
      print('清空黑名单失败: $e');
      return false;
    }
  }
  
  // 获取黑名单股票信息
  static Future<List<StockInfo>> getBlacklistStockInfo() async {
    try {
      final blacklist = await getBlacklist();
      if (blacklist.isEmpty) return [];
      
      // 从本地股票池获取股票信息
      final localData = await StockPoolService.loadStockPoolFromLocal();
      final List<StockInfo> stockPool = localData['stockPool'] as List<StockInfo>;
      
      return stockPool.where((stock) => blacklist.contains(stock.tsCode)).toList();
    } catch (e) {
      print('获取黑名单股票信息失败: $e');
      return [];
    }
  }
}
