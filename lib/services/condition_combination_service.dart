import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 筛选条件组合数据模型
class ConditionCombination {
  final String id;
  final String name;
  final String description;
  final double amountThreshold;
  final DateTime selectedDate;
  final double pctChgMin;
  final double pctChgMax;
  final double ma5Distance;
  final double ma10Distance;
  final double ma20Distance;
  final int consecutiveDays;
  final DateTime createdAt;
  final DateTime updatedAt;

  ConditionCombination({
    required this.id,
    required this.name,
    required this.description,
    required this.amountThreshold,
    required this.selectedDate,
    required this.pctChgMin,
    required this.pctChgMax,
    required this.ma5Distance,
    required this.ma10Distance,
    required this.ma20Distance,
    required this.consecutiveDays,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 从JSON创建对象
  factory ConditionCombination.fromJson(Map<String, dynamic> json) {
    return ConditionCombination(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      amountThreshold: (json['amountThreshold'] as num).toDouble(),
      selectedDate: DateTime.parse(json['selectedDate'] as String),
      pctChgMin: (json['pctChgMin'] as num).toDouble(),
      pctChgMax: (json['pctChgMax'] as num).toDouble(),
      ma5Distance: (json['ma5Distance'] as num).toDouble(),
      ma10Distance: (json['ma10Distance'] as num).toDouble(),
      ma20Distance: (json['ma20Distance'] as num).toDouble(),
      consecutiveDays: json['consecutiveDays'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'amountThreshold': amountThreshold,
      'selectedDate': selectedDate.toIso8601String(),
      'pctChgMin': pctChgMin,
      'pctChgMax': pctChgMax,
      'ma5Distance': ma5Distance,
      'ma10Distance': ma10Distance,
      'ma20Distance': ma20Distance,
      'consecutiveDays': consecutiveDays,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 创建副本并更新部分字段
  ConditionCombination copyWith({
    String? id,
    String? name,
    String? description,
    double? amountThreshold,
    DateTime? selectedDate,
    double? pctChgMin,
    double? pctChgMax,
    double? ma5Distance,
    double? ma10Distance,
    double? ma20Distance,
    int? consecutiveDays,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ConditionCombination(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      amountThreshold: amountThreshold ?? this.amountThreshold,
      selectedDate: selectedDate ?? this.selectedDate,
      pctChgMin: pctChgMin ?? this.pctChgMin,
      pctChgMax: pctChgMax ?? this.pctChgMax,
      ma5Distance: ma5Distance ?? this.ma5Distance,
      ma10Distance: ma10Distance ?? this.ma10Distance,
      ma20Distance: ma20Distance ?? this.ma20Distance,
      consecutiveDays: consecutiveDays ?? this.consecutiveDays,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 获取条件组合的简要描述
  String get shortDescription {
    return '成交额≥${amountThreshold.toStringAsFixed(0)}亿 | 涨跌幅${pctChgMin.toStringAsFixed(1)}%~${pctChgMax.toStringAsFixed(1)}% | 连续${consecutiveDays}天';
  }
  
  /// 获取条件组合的简化描述（用于下拉框显示）
  String get displayName {
    return name;
  }
}

/// 条件组合管理服务
class ConditionCombinationService {
  static const String _keyCombinations = 'condition_combinations';
  static const String _keyDefaultCombination = 'default_combination_id';

  /// 获取所有保存的条件组合
  static Future<List<ConditionCombination>> getAllCombinations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final combinationsJson = prefs.getString(_keyCombinations);
      
      if (combinationsJson == null || combinationsJson.isEmpty) {
        return [];
      }
      
      final List<dynamic> combinationsList = json.decode(combinationsJson);
      return combinationsList
          .map((json) => ConditionCombination.fromJson(json as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // 按更新时间倒序排列
    } catch (e) {
      print('获取条件组合失败: $e');
      return [];
    }
  }

  /// 保存条件组合
  static Future<bool> saveCombination(ConditionCombination combination) async {
    try {
      final combinations = await getAllCombinations();
      
      // 检查是否已存在相同ID的组合
      final existingIndex = combinations.indexWhere((c) => c.id == combination.id);
      
      if (existingIndex >= 0) {
        // 更新现有组合
        combinations[existingIndex] = combination.copyWith(updatedAt: DateTime.now());
      } else {
        // 添加新组合
        combinations.add(combination);
      }
      
      final prefs = await SharedPreferences.getInstance();
      final combinationsJson = json.encode(combinations.map((c) => c.toJson()).toList());
      
      return await prefs.setString(_keyCombinations, combinationsJson);
    } catch (e) {
      print('保存条件组合失败: $e');
      return false;
    }
  }

  /// 删除条件组合
  static Future<bool> deleteCombination(String combinationId) async {
    try {
      final combinations = await getAllCombinations();
      combinations.removeWhere((c) => c.id == combinationId);
      
      final prefs = await SharedPreferences.getInstance();
      final combinationsJson = json.encode(combinations.map((c) => c.toJson()).toList());
      
      // 如果删除的是默认组合，清除默认组合设置
      final defaultId = await getDefaultCombinationId();
      if (defaultId == combinationId) {
        await prefs.remove(_keyDefaultCombination);
      }
      
      return await prefs.setString(_keyCombinations, combinationsJson);
    } catch (e) {
      print('删除条件组合失败: $e');
      return false;
    }
  }

  /// 根据ID获取条件组合
  static Future<ConditionCombination?> getCombinationById(String id) async {
    try {
      final combinations = await getAllCombinations();
      return combinations.firstWhere(
        (c) => c.id == id,
        orElse: () => throw StateError('未找到指定ID的条件组合'),
      );
    } catch (e) {
      print('获取条件组合失败: $e');
      return null;
    }
  }

  /// 设置默认条件组合
  static Future<bool> setDefaultCombination(String combinationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_keyDefaultCombination, combinationId);
    } catch (e) {
      print('设置默认条件组合失败: $e');
      return false;
    }
  }

  /// 获取默认条件组合ID
  static Future<String?> getDefaultCombinationId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyDefaultCombination);
    } catch (e) {
      print('获取默认条件组合ID失败: $e');
      return null;
    }
  }

  /// 获取默认条件组合
  static Future<ConditionCombination?> getDefaultCombination() async {
    try {
      final defaultId = await getDefaultCombinationId();
      if (defaultId == null) return null;
      return await getCombinationById(defaultId);
    } catch (e) {
      print('获取默认条件组合失败: $e');
      return null;
    }
  }

  /// 创建新的条件组合
  static ConditionCombination createCombination({
    required String name,
    required String description,
    required double amountThreshold,
    required DateTime selectedDate,
    required double pctChgMin,
    required double pctChgMax,
    required double ma5Distance,
    required double ma10Distance,
    required double ma20Distance,
    required int consecutiveDays,
  }) {
    final now = DateTime.now();
    return ConditionCombination(
      id: '${now.millisecondsSinceEpoch}_${name.hashCode}',
      name: name,
      description: description,
      amountThreshold: amountThreshold,
      selectedDate: selectedDate,
      pctChgMin: pctChgMin,
      pctChgMax: pctChgMax,
      ma5Distance: ma5Distance,
      ma10Distance: ma10Distance,
      ma20Distance: ma20Distance,
      consecutiveDays: consecutiveDays,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 检查是否有保存的条件组合
  static Future<bool> hasCombinations() async {
    final combinations = await getAllCombinations();
    return combinations.isNotEmpty;
  }

  /// 清空所有条件组合
  static Future<bool> clearAllCombinations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyCombinations);
      await prefs.remove(_keyDefaultCombination);
      return true;
    } catch (e) {
      print('清空条件组合失败: $e');
      return false;
    }
  }

  /// 导出条件组合数据
  static Future<String> exportCombinations() async {
    try {
      final combinations = await getAllCombinations();
      final exportData = {
        'exportTime': DateTime.now().toIso8601String(),
        'combinations': combinations.map((c) => c.toJson()).toList(),
      };
      return json.encode(exportData);
    } catch (e) {
      print('导出条件组合失败: $e');
      return '';
    }
  }

  /// 导入条件组合数据
  static Future<bool> importCombinations(String jsonData) async {
    try {
      final Map<String, dynamic> importData = json.decode(jsonData);
      final List<dynamic> combinationsList = importData['combinations'] as List<dynamic>;
      
      final List<ConditionCombination> importedCombinations = combinationsList
          .map((json) => ConditionCombination.fromJson(json as Map<String, dynamic>))
          .toList();
      
      // 保存导入的组合
      for (final combination in importedCombinations) {
        await saveCombination(combination);
      }
      
      return true;
    } catch (e) {
      print('导入条件组合失败: $e');
      return false;
    }
  }
}
