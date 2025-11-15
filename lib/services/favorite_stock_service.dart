import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock_info.dart';

class FavoriteStockService {
  static const String _favoriteKey = 'favorite_stocks';
  
  // 获取关注的股票列表
  static Future<List<StockInfo>> getFavoriteStocks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoriteJson = prefs.getString(_favoriteKey);
      if (favoriteJson != null) {
        final List<dynamic> favoriteList = json.decode(favoriteJson);
        return favoriteList.map((json) => StockInfo.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('获取关注股票列表失败: $e');
      return [];
    }
  }
  
  // 添加到关注列表
  static Future<bool> addFavorite(StockInfo stock) async {
    try {
      final favorites = await getFavoriteStocks();
      if (!favorites.any((s) => s.tsCode == stock.tsCode)) {
        favorites.add(stock);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_favoriteKey, json.encode(
          favorites.map((s) => s.toJson()).toList()
        ));
        print('✅ 已添加 ${stock.name} 到关注列表');
        return true;
      }
      return false;
    } catch (e) {
      print('添加到关注列表失败: $e');
      return false;
    }
  }
  
  // 从关注列表移除
  static Future<bool> removeFavorite(String tsCode) async {
    try {
      final favorites = await getFavoriteStocks();
      favorites.removeWhere((s) => s.tsCode == tsCode);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_favoriteKey, json.encode(
        favorites.map((s) => s.toJson()).toList()
      ));
      print('✅ 已从关注列表移除 $tsCode');
      return true;
    } catch (e) {
      print('从关注列表移除失败: $e');
      return false;
    }
  }
  
  // 检查是否在关注列表中
  static Future<bool> isFavorite(String tsCode) async {
    final favorites = await getFavoriteStocks();
    return favorites.any((s) => s.tsCode == tsCode);
  }
  
  // 清空关注列表
  static Future<bool> clearFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_favoriteKey);
      print('✅ 已清空关注列表');
      return true;
    } catch (e) {
      print('清空关注列表失败: $e');
      return false;
    }
  }
}

