import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// 排名评分配置服务
/// 支持动态修改评分规则
class RankingConfigService {
  static const String _configKey = 'ranking_config';
  
  // 默认配置
  static RankingConfig getDefaultConfig() {
    return RankingConfig(
      marketValueRanges: [
        MarketValueRange(min: 0, max: 100, score: 0),
        MarketValueRange(min: 100, max: 200, score: 3),
        MarketValueRange(min: 200, max: 800, score: 5),
        MarketValueRange(min: 800, max: 1200, score: 4),
        MarketValueRange(min: 1200, max: double.infinity, score: 3),
      ],
      bollDeviationRanges: [
        DeviationRange(min: 0, max: 2, score: 5),
        DeviationRange(min: 2, max: 4, score: 4),
        DeviationRange(min: 4, max: double.infinity, score: 3),
      ],
    );
  }
  
  /// 保存配置
  static Future<bool> saveConfig(RankingConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(config.toJson());
      return await prefs.setString(_configKey, jsonString);
    } catch (e) {
      print('保存排名配置失败: $e');
      return false;
    }
  }
  
  /// 加载配置
  static Future<RankingConfig> getConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_configKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return RankingConfig.fromJson(json);
      }
    } catch (e) {
      print('加载排名配置失败: $e');
    }
    return getDefaultConfig();
  }
}

/// 排名配置
class RankingConfig {
  final List<MarketValueRange> marketValueRanges;
  final List<DeviationRange> bollDeviationRanges;
  
  RankingConfig({
    required this.marketValueRanges,
    required this.bollDeviationRanges,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'marketValueRanges': marketValueRanges.map((r) => r.toJson()).toList(),
      'bollDeviationRanges': bollDeviationRanges.map((r) => r.toJson()).toList(),
    };
  }
  
  factory RankingConfig.fromJson(Map<String, dynamic> json) {
    return RankingConfig(
      marketValueRanges: (json['marketValueRanges'] as List<dynamic>)
          .map((r) => MarketValueRange.fromJson(r))
          .toList(),
      bollDeviationRanges: (json['bollDeviationRanges'] as List<dynamic>)
          .map((r) => DeviationRange.fromJson(r))
          .toList(),
    );
  }
  
  RankingConfig copyWith({
    List<MarketValueRange>? marketValueRanges,
    List<DeviationRange>? bollDeviationRanges,
  }) {
    return RankingConfig(
      marketValueRanges: marketValueRanges ?? this.marketValueRanges,
      bollDeviationRanges: bollDeviationRanges ?? this.bollDeviationRanges,
    );
  }
}

/// 市值范围
class MarketValueRange {
  final double min;
  final double max;
  final int score;
  
  MarketValueRange({
    required this.min,
    required this.max,
    required this.score,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'min': min,
      'max': max == double.infinity ? 'infinity' : max,
      'score': score,
    };
  }
  
  factory MarketValueRange.fromJson(Map<String, dynamic> json) {
    return MarketValueRange(
      min: (json['min'] as num).toDouble(),
      max: json['max'] == 'infinity' ? double.infinity : (json['max'] as num).toDouble(),
      score: json['score'] as int,
    );
  }
}

/// 偏离范围
class DeviationRange {
  final double min;
  final double max;
  final int score;
  
  DeviationRange({
    required this.min,
    required this.max,
    required this.score,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'min': min,
      'max': max == double.infinity ? 'infinity' : max,
      'score': score,
    };
  }
  
  factory DeviationRange.fromJson(Map<String, dynamic> json) {
    return DeviationRange(
      min: (json['min'] as num).toDouble(),
      max: json['max'] == 'infinity' ? double.infinity : (json['max'] as num).toDouble(),
      score: json['score'] as int,
    );
  }
}


