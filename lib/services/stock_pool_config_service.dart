import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StockPoolConfigService {
  static const String _keyEnableMarketValueFilter = 'enable_market_value_filter';
  static const String _keyMinMarketValue = 'min_market_value';
  static const String _keyMaxMarketValue = 'max_market_value';
  static const String _keyAmountThreshold = 'amount_threshold';
  static const String _keySelectedDate = 'selected_date';
  static const String _keyAutoUpdate = 'auto_update';
  static const String _keyUpdateInterval = 'update_interval';
  static const String _keyEnableRealtimeInterface = 'enable_realtime_interface';

  // 股票池配置模型
  static Future<StockPoolConfig> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    
    return StockPoolConfig(
      enableMarketValueFilter: prefs.getBool(_keyEnableMarketValueFilter) ?? false,
      minMarketValue: prefs.getDouble(_keyMinMarketValue),
      maxMarketValue: prefs.getDouble(_keyMaxMarketValue),
      amountThreshold: prefs.getDouble(_keyAmountThreshold) ?? 5.0,
      selectedDate: DateTime.tryParse(prefs.getString(_keySelectedDate) ?? '') ?? DateTime.now(),
      autoUpdate: prefs.getBool(_keyAutoUpdate) ?? false,
      updateInterval: prefs.getInt(_keyUpdateInterval) ?? 24, // 默认24小时
      enableRealtimeInterface: prefs.getBool(_keyEnableRealtimeInterface) ?? false,
    );
  }

  // 保存配置
  static Future<void> saveConfig(StockPoolConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    
    print('💾 配置服务保存: enableMarketValueFilter=${config.enableMarketValueFilter}, minMarketValue=${config.minMarketValue}, maxMarketValue=${config.maxMarketValue}');
    
    await prefs.setBool(_keyEnableMarketValueFilter, config.enableMarketValueFilter);
    if (config.minMarketValue != null) {
      await prefs.setDouble(_keyMinMarketValue, config.minMarketValue!);
    } else {
      await prefs.remove(_keyMinMarketValue);
    }
    if (config.maxMarketValue != null) {
      await prefs.setDouble(_keyMaxMarketValue, config.maxMarketValue!);
    } else {
      await prefs.remove(_keyMaxMarketValue);
    }
    await prefs.setDouble(_keyAmountThreshold, config.amountThreshold);
    await prefs.setString(_keySelectedDate, config.selectedDate.toIso8601String());
    await prefs.setBool(_keyAutoUpdate, config.autoUpdate);
    await prefs.setInt(_keyUpdateInterval, config.updateInterval);
    await prefs.setBool(_keyEnableRealtimeInterface, config.enableRealtimeInterface);
    
    print('💾 配置服务保存完成');
  }

  // 单独更新实时接口开关
  static Future<void> setRealtimeInterfaceEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableRealtimeInterface, enabled);
  }

  // 重置为默认配置
  static Future<void> resetToDefault() async {
    final defaultConfig = StockPoolConfig();
    await saveConfig(defaultConfig);
  }

  // 导出配置为JSON
  static Future<String> exportConfig() async {
    final config = await getConfig();
    return json.encode(config.toJson());
  }

  // 从JSON导入配置
  static Future<void> importConfig(String jsonString) async {
    try {
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      final config = StockPoolConfig.fromJson(jsonData);
      await saveConfig(config);
    } catch (e) {
      throw Exception('配置导入失败: $e');
    }
  }
}

// 股票池配置数据模型
class StockPoolConfig {
  final bool enableMarketValueFilter;
  final double? minMarketValue;
  final double? maxMarketValue;
  final double amountThreshold;
  final DateTime selectedDate;
  final bool autoUpdate;
  final int updateInterval; // 小时
  final bool enableRealtimeInterface;

  StockPoolConfig({
    this.enableMarketValueFilter = false,
    this.minMarketValue,
    this.maxMarketValue,
    this.amountThreshold = 5.0,
    DateTime? selectedDate,
    this.autoUpdate = false,
    this.updateInterval = 24,
    this.enableRealtimeInterface = false,
  }) : selectedDate = selectedDate ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'enableMarketValueFilter': enableMarketValueFilter,
      'minMarketValue': minMarketValue,
      'maxMarketValue': maxMarketValue,
      'amountThreshold': amountThreshold,
      'selectedDate': selectedDate.toIso8601String(),
      'autoUpdate': autoUpdate,
      'updateInterval': updateInterval,
      'enableRealtimeInterface': enableRealtimeInterface,
    };
  }

  factory StockPoolConfig.fromJson(Map<String, dynamic> json) {
    return StockPoolConfig(
      enableMarketValueFilter: json['enableMarketValueFilter'] ?? false,
      minMarketValue: json['minMarketValue']?.toDouble(),
      maxMarketValue: json['maxMarketValue']?.toDouble(),
      amountThreshold: json['amountThreshold']?.toDouble() ?? 5.0,
      selectedDate: DateTime.tryParse(json['selectedDate'] ?? '') ?? DateTime.now(),
      autoUpdate: json['autoUpdate'] ?? false,
      updateInterval: json['updateInterval'] ?? 24,
      enableRealtimeInterface: json['enableRealtimeInterface'] ?? false,
    );
  }

  StockPoolConfig copyWith({
    bool? enableMarketValueFilter,
    double? minMarketValue,
    double? maxMarketValue,
    double? amountThreshold,
    DateTime? selectedDate,
    bool? autoUpdate,
    int? updateInterval,
    bool? enableRealtimeInterface,
  }) {
    return StockPoolConfig(
      enableMarketValueFilter: enableMarketValueFilter ?? this.enableMarketValueFilter,
      minMarketValue: minMarketValue ?? this.minMarketValue,
      maxMarketValue: maxMarketValue ?? this.maxMarketValue,
      amountThreshold: amountThreshold ?? this.amountThreshold,
      selectedDate: selectedDate ?? this.selectedDate,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      updateInterval: updateInterval ?? this.updateInterval,
      enableRealtimeInterface: enableRealtimeInterface ?? this.enableRealtimeInterface,
    );
  }
}
