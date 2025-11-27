import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/favorite_group.dart';
import '../models/stock_info.dart';
import 'stock_info_service.dart';

class FavoriteGroupService {
  static const String _groupsKey = 'favorite_groups';

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
        
        // 排序：置顶的在前，然后按order排序
        groups.sort((a, b) {
          if (a.isPinned != b.isPinned) {
            return a.isPinned ? -1 : 1;
          }
          return a.order.compareTo(b.order);
        });
        
        return groups;
      }
      // 如果没有分组，返回空列表
      return [];
    } catch (e) {
      print('获取分组列表失败: $e');
      return [];
    }
  }

  // 保存所有分组
  static Future<bool> _saveGroups(List<FavoriteGroup> groups) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 确保每个分组的stockCodes是独立的列表（深拷贝）
      final groupsToSave = groups.map((g) {
        return {
          'id': g.id,
          'name': g.name,
          'color': g.color,
          'is_pinned': g.isPinned,
          'order': g.order,
          'stock_codes': List<String>.from(g.stockCodes), // 深拷贝股票代码列表
        };
      }).toList();
      final groupsJson = json.encode(groupsToSave);
      await prefs.setString(_groupsKey, groupsJson);
      
      // 调试：打印每个分组的股票数量
      print('💾 保存分组数据:');
      for (final group in groups) {
        print('  分组 "${group.name}" (${group.id}): ${group.stockCodes.length} 只股票');
        if (group.stockCodes.isNotEmpty) {
          print('    股票代码: ${group.stockCodes.join(", ")}');
        }
      }
      
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
      final groups = await getAllGroups();
      
      // 删除分组（分组下的股票会自动从该分组中移除，但不影响其他分组）
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

  // 将股票添加到分组（内部方法，使用传入的分组列表）
  static Future<bool> _addStockToGroupInternal(
    List<FavoriteGroup> groups,
    String groupId,
    String stockCode,
  ) async {
    try {
      final group = groups.firstWhere((g) => g.id == groupId);
      if (!group.stockCodes.contains(stockCode)) {
        group.stockCodes.add(stockCode);
        return true;
      }
      return false;
    } catch (e) {
      print('添加股票到分组失败: $e');
      return false;
    }
  }

  // 将股票添加到分组
  static Future<bool> addStockToGroup(String groupId, String stockCode, {StockInfo? stockInfo}) async {
    try {
      final groups = await getAllGroups();
      final success = await _addStockToGroupInternal(groups, groupId, stockCode);
      if (success) {
        await _saveGroups(groups);
        
        // 如果提供了股票信息，保存到StockInfoService
        if (stockInfo != null) {
          await StockInfoService.saveStockInfo(stockInfo);
        }
      }
      return success;
    } catch (e) {
      print('添加股票到分组失败: $e');
      return false;
    }
  }

  // 从分组移除股票（内部方法，使用传入的分组列表）
  static bool _removeStockFromGroupInternal(
    List<FavoriteGroup> groups,
    String groupId,
    String stockCode,
  ) {
    try {
      final group = groups.firstWhere((g) => g.id == groupId);
      return group.stockCodes.remove(stockCode);
    } catch (e) {
      print('从分组移除股票失败: $e');
      return false;
    }
  }

  // 从分组移除股票
  static Future<bool> removeStockFromGroup(String groupId, String stockCode) async {
    try {
      final groups = await getAllGroups();
      final removed = _removeStockFromGroupInternal(groups, groupId, stockCode);
      if (removed) {
        await _saveGroups(groups);
        
        // 检查股票是否还在其他分组中
        bool isInOtherGroups = false;
        for (final g in groups) {
          if (g.id != groupId && g.stockCodes.contains(stockCode)) {
            isInOtherGroups = true;
            break;
          }
        }
        
        // 如果不在任何分组中，删除股票信息
        if (!isInOtherGroups) {
          await StockInfoService.removeStockInfo(stockCode);
        }
      }
      return removed;
    } catch (e) {
      print('从分组移除股票失败: $e');
      return false;
    }
  }

  // 批量更新股票的分组（原子操作，确保数据一致性）
  static Future<bool> updateStockGroups(
    String stockCode,
    List<String> targetGroupIds, {
    StockInfo? stockInfo,
  }) async {
    try {
      final groups = await getAllGroups();
      
      print('🔄 开始更新股票分组: $stockCode');
      print('   目标分组: ${targetGroupIds.join(", ")}');
      print('   当前所有分组:');
      for (final group in groups) {
        print('     - ${group.name} (${group.id}): ${group.stockCodes.length} 只股票');
        if (group.stockCodes.contains(stockCode)) {
          print('       ✓ 包含股票 $stockCode');
        }
      }
      
      // 从所有分组中移除该股票
      for (final group in groups) {
        final removed = group.stockCodes.remove(stockCode);
        if (removed) {
          print('   ✓ 从分组 "${group.name}" 移除股票 $stockCode');
        }
      }
      
      // 添加到目标分组
      for (final groupId in targetGroupIds) {
        final added = await _addStockToGroupInternal(groups, groupId, stockCode);
        if (added) {
          print('   ✓ 添加股票 $stockCode 到分组 $groupId');
        }
      }
      
      // 一次性保存所有更改
      await _saveGroups(groups);
      
      print('✅ 更新完成后的分组状态:');
      for (final group in groups) {
        print('     - ${group.name} (${group.id}): ${group.stockCodes.length} 只股票');
        if (group.stockCodes.contains(stockCode)) {
          print('       ✓ 包含股票 $stockCode');
        }
      }
      
      // 如果提供了股票信息，保存到StockInfoService
      if (stockInfo != null) {
        await StockInfoService.saveStockInfo(stockInfo);
      }
      
      // 如果股票不在任何分组中，删除股票信息
      if (targetGroupIds.isEmpty) {
        await StockInfoService.removeStockInfo(stockCode);
      }
      
      return true;
    } catch (e) {
      print('批量更新股票分组失败: $e');
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
      final group = groups.firstWhere((g) => g.id == groupId);
      print('📋 获取分组 "${group.name}" 股票代码: ${group.stockCodes.length} 只股票');
      if (group.stockCodes.isNotEmpty) {
        print('   股票代码: ${group.stockCodes.join(", ")}');
      }
      // 返回分组的股票代码列表的副本，避免外部修改
      return List<String>.from(group.stockCodes);
    } catch (e) {
      print('获取分组股票代码失败: $e');
      return [];
    }
  }
}

