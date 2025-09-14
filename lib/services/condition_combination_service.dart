import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 均线偏离配置
class MaDistanceConfig {
  final bool enabled;
  final double distance;
  
  MaDistanceConfig({
    required this.enabled,
    required this.distance,
  });
  
  factory MaDistanceConfig.fromJson(Map<String, dynamic> json) {
    return MaDistanceConfig(
      enabled: json['enabled'] as bool,
      distance: (json['distance'] as num).toDouble(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'distance': distance,
    };
  }
}

/// 连续天数配置
class ConsecutiveDaysConfig {
  final bool enabled;
  final int days;
  final String maType; // 'ma5', 'ma10', 'ma20'
  
  ConsecutiveDaysConfig({
    required this.enabled,
    required this.days,
    required this.maType,
  });
  
  factory ConsecutiveDaysConfig.fromJson(Map<String, dynamic> json) {
    return ConsecutiveDaysConfig(
      enabled: json['enabled'] as bool,
      days: json['days'] as int,
      maType: json['maType'] as String,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'days': days,
      'maType': maType,
    };
  }
}

/// 筛选条件组合数据模型
class ConditionCombination {
  final String id;
  final String name;
  final String description;
  
  // 必填项
  final double amountThreshold;
  final DateTime selectedDate;
  
  // 可选项
  final bool enablePctChg;
  final int pctChgMin; // -10 到 10 的整数
  final int pctChgMax; // -10 到 10 的整数
  
  final bool enableMaDistance;
  final MaDistanceConfig ma5Config;
  final MaDistanceConfig ma10Config;
  final MaDistanceConfig ma20Config;
  
  final bool enableConsecutiveDays;
  final ConsecutiveDaysConfig consecutiveDaysConfig;
  
  final DateTime createdAt;
  final DateTime updatedAt;

  ConditionCombination({
    required this.id,
    required this.name,
    required this.description,
    required this.amountThreshold,
    required this.selectedDate,
    required this.enablePctChg,
    required this.pctChgMin,
    required this.pctChgMax,
    required this.enableMaDistance,
    required this.ma5Config,
    required this.ma10Config,
    required this.ma20Config,
    required this.enableConsecutiveDays,
    required this.consecutiveDaysConfig,
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
      enablePctChg: json['enablePctChg'] as bool? ?? false,
      pctChgMin: json['pctChgMin'] as int? ?? -10,
      pctChgMax: json['pctChgMax'] as int? ?? 10,
      enableMaDistance: json['enableMaDistance'] as bool? ?? false,
      ma5Config: MaDistanceConfig.fromJson(json['ma5Config'] as Map<String, dynamic>? ?? {'enabled': false, 'distance': 5.0}),
      ma10Config: MaDistanceConfig.fromJson(json['ma10Config'] as Map<String, dynamic>? ?? {'enabled': false, 'distance': 5.0}),
      ma20Config: MaDistanceConfig.fromJson(json['ma20Config'] as Map<String, dynamic>? ?? {'enabled': false, 'distance': 5.0}),
      enableConsecutiveDays: json['enableConsecutiveDays'] as bool? ?? false,
      consecutiveDaysConfig: ConsecutiveDaysConfig.fromJson(json['consecutiveDaysConfig'] as Map<String, dynamic>? ?? {'enabled': false, 'days': 10, 'maType': 'ma20'}),
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
      'enablePctChg': enablePctChg,
      'pctChgMin': pctChgMin,
      'pctChgMax': pctChgMax,
      'enableMaDistance': enableMaDistance,
      'ma5Config': ma5Config.toJson(),
      'ma10Config': ma10Config.toJson(),
      'ma20Config': ma20Config.toJson(),
      'enableConsecutiveDays': enableConsecutiveDays,
      'consecutiveDaysConfig': consecutiveDaysConfig.toJson(),
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
    bool? enablePctChg,
    int? pctChgMin,
    int? pctChgMax,
    bool? enableMaDistance,
    MaDistanceConfig? ma5Config,
    MaDistanceConfig? ma10Config,
    MaDistanceConfig? ma20Config,
    bool? enableConsecutiveDays,
    ConsecutiveDaysConfig? consecutiveDaysConfig,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ConditionCombination(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      amountThreshold: amountThreshold ?? this.amountThreshold,
      selectedDate: selectedDate ?? this.selectedDate,
      enablePctChg: enablePctChg ?? this.enablePctChg,
      pctChgMin: pctChgMin ?? this.pctChgMin,
      pctChgMax: pctChgMax ?? this.pctChgMax,
      enableMaDistance: enableMaDistance ?? this.enableMaDistance,
      ma5Config: ma5Config ?? this.ma5Config,
      ma10Config: ma10Config ?? this.ma10Config,
      ma20Config: ma20Config ?? this.ma20Config,
      enableConsecutiveDays: enableConsecutiveDays ?? this.enableConsecutiveDays,
      consecutiveDaysConfig: consecutiveDaysConfig ?? this.consecutiveDaysConfig,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 获取条件组合的简要描述
  String get shortDescription {
    List<String> conditions = ['成交额≥${amountThreshold.toStringAsFixed(0)}亿'];
    
    if (enablePctChg) {
      conditions.add('涨跌幅${pctChgMin}%~${pctChgMax}%');
    }
    
    if (enableMaDistance) {
      List<String> maConditions = [];
      if (ma5Config.enabled) maConditions.add('MA5偏离${ma5Config.distance}%');
      if (ma10Config.enabled) maConditions.add('MA10偏离${ma10Config.distance}%');
      if (ma20Config.enabled) maConditions.add('MA20偏离${ma20Config.distance}%');
      if (maConditions.isNotEmpty) {
        conditions.add('均线偏离: ${maConditions.join(', ')}');
      }
    }
    
    if (enableConsecutiveDays) {
      String maTypeName = consecutiveDaysConfig.maType == 'ma5' ? 'MA5' : 
                          consecutiveDaysConfig.maType == 'ma10' ? 'MA10' : 'MA20';
      conditions.add('连续${consecutiveDaysConfig.days}天高于${maTypeName}');
    }
    
    return conditions.join(' | ');
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
    bool enablePctChg = false,
    int pctChgMin = -10,
    int pctChgMax = 10,
    bool enableMaDistance = false,
    MaDistanceConfig? ma5Config,
    MaDistanceConfig? ma10Config,
    MaDistanceConfig? ma20Config,
    bool enableConsecutiveDays = false,
    ConsecutiveDaysConfig? consecutiveDaysConfig,
  }) {
    final now = DateTime.now();
    return ConditionCombination(
      id: '${now.millisecondsSinceEpoch}_${name.hashCode}',
      name: name,
      description: description,
      amountThreshold: amountThreshold,
      selectedDate: selectedDate,
      enablePctChg: enablePctChg,
      pctChgMin: pctChgMin,
      pctChgMax: pctChgMax,
      enableMaDistance: enableMaDistance,
      ma5Config: ma5Config ?? MaDistanceConfig(enabled: false, distance: 5.0),
      ma10Config: ma10Config ?? MaDistanceConfig(enabled: false, distance: 5.0),
      ma20Config: ma20Config ?? MaDistanceConfig(enabled: false, distance: 5.0),
      enableConsecutiveDays: enableConsecutiveDays,
      consecutiveDaysConfig: consecutiveDaysConfig ?? ConsecutiveDaysConfig(enabled: false, days: 10, maType: 'ma20'),
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
