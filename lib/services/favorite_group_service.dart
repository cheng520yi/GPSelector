import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/favorite_group.dart';

class FavoriteGroupService {
  static const String _groupsKey = 'favorite_groups';
  static const String _defaultGroupId = 'default';
  static const String _defaultGroupName = '全部';

  // 获取所有分组
  static Future<List<FavoriteGroup>> getAllGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final groupsJson = prefs.getString(_groupsKey);
      if (groupsJson != null) {
        final List<dynamic> groupsList = json.decode(groupsJson);
        final groups = groupsList
            .map((json) => FavoriteGroup.fromJson(json))
            .toList();
        
        // 确保有默认分组
        if (!groups.any((g) => g.id == _defaultGroupId)) {
          groups.insert(0, _createDefaultGroup());
        }
        
        // 排序：置顶的在前，然后按order排序
        groups.sort((a, b) {
          if (a.isPinned != b.isPinned) {
            return a.isPinned ? -1 : 1;
          }
          return a.order.compareTo(b.order);
        });
        
        return groups;
      }
      // 如果没有分组，创建默认分组
      return [_createDefaultGroup()];
    } catch (e) {
      print('获取分组列表失败: $e');
      return [_createDefaultGroup()];
    }
  }

  // 创建默认分组
  static FavoriteGroup _createDefaultGroup() {
    return FavoriteGroup(
      id: _defaultGroupId,
      name: _defaultGroupName,
      isPinned: false,
      order: 0,
    );
  }

  // 保存所有分组
  static Future<bool> _saveGroups(List<FavoriteGroup> groups) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final groupsJson = json.encode(
        groups.map((g) => g.toJson()).toList(),
      );
      await prefs.setString(_groupsKey, groupsJson);
      return true;
    } catch (e) {
      print('保存分组列表失败: $e');
      return false;
    }
  }

  // 创建新分组
  static Future<FavoriteGroup?> createGroup({
    required String name,
    String? color,
  }) async {
    try {
      final groups = await getAllGroups();
      final newGroup = FavoriteGroup(
        id: const Uuid().v4(),
        name: name,
        color: color,
        isPinned: false,
        order: groups.length,
      );
      groups.add(newGroup);
      await _saveGroups(groups);
      return newGroup;
    } catch (e) {
      print('创建分组失败: $e');
      return null;
    }
  }

  // 删除分组
  static Future<bool> deleteGroup(String groupId) async {
    try {
      if (groupId == _defaultGroupId) {
        print('不能删除默认分组');
        return false;
      }
      final groups = await getAllGroups();
      groups.removeWhere((g) => g.id == groupId);
      await _saveGroups(groups);
      return true;
    } catch (e) {
      print('删除分组失败: $e');
      return false;
    }
  }

  // 更新分组
  static Future<bool> updateGroup(FavoriteGroup group) async {
    try {
      final groups = await getAllGroups();
      final index = groups.indexWhere((g) => g.id == group.id);
      if (index != -1) {
        // 创建新的分组对象来更新
        final updatedGroup = FavoriteGroup(
          id: group.id,
          name: group.name,
          color: group.color,
          isPinned: group.isPinned,
          order: group.order,
          stockCodes: List<String>.from(group.stockCodes),
        );
        groups[index] = updatedGroup;
        await _saveGroups(groups);
        return true;
      }
      return false;
    } catch (e) {
      print('更新分组失败: $e');
      return false;
    }
  }

  // 将股票添加到分组
  static Future<bool> addStockToGroup(String groupId, String stockCode) async {
    try {
      final groups = await getAllGroups();
      final group = groups.firstWhere((g) => g.id == groupId);
      if (!group.stockCodes.contains(stockCode)) {
        group.stockCodes.add(stockCode);
        await _saveGroups(groups);
        return true;
      }
      return false;
    } catch (e) {
      print('添加股票到分组失败: $e');
      return false;
    }
  }

  // 从分组移除股票
  static Future<bool> removeStockFromGroup(String groupId, String stockCode) async {
    try {
      final groups = await getAllGroups();
      final group = groups.firstWhere((g) => g.id == groupId);
      group.stockCodes.remove(stockCode);
      await _saveGroups(groups);
      return true;
    } catch (e) {
      print('从分组移除股票失败: $e');
      return false;
    }
  }

  // 切换置顶状态
  static Future<bool> togglePin(String groupId) async {
    try {
      final groups = await getAllGroups();
      final group = groups.firstWhere((g) => g.id == groupId);
      group.isPinned = !group.isPinned;
      await _saveGroups(groups);
      return true;
    } catch (e) {
      print('切换置顶状态失败: $e');
      return false;
    }
  }

  // 更新分组顺序
  static Future<bool> updateGroupOrder(List<String> groupIds) async {
    try {
      final groups = await getAllGroups();
      for (int i = 0; i < groupIds.length; i++) {
        final group = groups.firstWhere((g) => g.id == groupIds[i]);
        group.order = i;
      }
      await _saveGroups(groups);
      return true;
    } catch (e) {
      print('更新分组顺序失败: $e');
      return false;
    }
  }

  // 获取分组中的股票代码列表
  static Future<List<String>> getGroupStockCodes(String groupId) async {
    try {
      final groups = await getAllGroups();
      if (groupId == _defaultGroupId) {
        // 默认分组返回所有关注股票
        final favoriteStocks = await _getAllFavoriteStockCodes();
        return favoriteStocks;
      }
      final group = groups.firstWhere((g) => g.id == groupId);
      return group.stockCodes;
    } catch (e) {
      print('获取分组股票代码失败: $e');
      return [];
    }
  }

  // 获取所有关注股票的代码
  static Future<List<String>> _getAllFavoriteStockCodes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoriteJson = prefs.getString('favorite_stocks');
      if (favoriteJson != null) {
        final List<dynamic> favoriteList = json.decode(favoriteJson);
        return favoriteList
            .map((json) => json['ts_code'] as String)
            .toList();
      }
      return [];
    } catch (e) {
      print('获取所有关注股票代码失败: $e');
      return [];
    }
  }
}

