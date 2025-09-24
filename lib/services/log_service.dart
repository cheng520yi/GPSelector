import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

/// 日志级别枚举
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// LogLevel 扩展方法
extension LogLevelExtension on LogLevel {
  String get levelString {
    switch (this) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }
}

/// 日志条目模型
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String category; // 分类：API, FILTER, ERROR等
  final String message;
  final Map<String, dynamic>? data; // 额外的结构化数据

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.data,
  });


  String get formattedTimestamp {
    return DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(timestamp);
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.levelString,
      'category': category,
      'message': message,
      'data': data,
    };
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp']),
      level: LogLevel.values.firstWhere(
        (e) => e.levelString == json['level'],
        orElse: () => LogLevel.info,
      ),
      category: json['category'],
      message: json['message'],
      data: json['data'],
    );
  }

  @override
  String toString() {
    final dataStr = data != null ? ' | ${json.encode(data)}' : '';
    return '[${formattedTimestamp}] ${level.levelString} | $category | $message$dataStr';
  }
}

/// 日志服务
class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  static const int _maxLogEntries = 10000; // 最大日志条目数
  final List<LogEntry> _logs = [];
  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');

  /// 获取日志实例
  static LogService get instance => _instance;

  /// 添加日志条目
  void log(LogLevel level, String category, String message, {Map<String, dynamic>? data}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      data: data,
    );

    _logs.add(entry);

    // 控制日志数量，移除最旧的条目
    if (_logs.length > _maxLogEntries) {
      _logs.removeRange(0, _logs.length - _maxLogEntries);
    }

    // 打印到控制台（用于调试）
    print(entry.toString());
  }

  /// 添加控制台输出日志（用于捕获print语句）
  void addConsoleOutput(String output) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.debug,
      category: 'CONSOLE',
      message: output,
    );

    _logs.add(entry);

    // 控制日志数量，移除最旧的条目
    if (_logs.length > _maxLogEntries) {
      _logs.removeRange(0, _logs.length - _maxLogEntries);
    }
  }

  /// 便捷方法：记录调试日志
  void debug(String category, String message, {Map<String, dynamic>? data}) {
    log(LogLevel.debug, category, message, data: data);
  }

  /// 便捷方法：记录信息日志
  void info(String category, String message, {Map<String, dynamic>? data}) {
    log(LogLevel.info, category, message, data: data);
  }

  /// 便捷方法：记录警告日志
  void warning(String category, String message, {Map<String, dynamic>? data}) {
    log(LogLevel.warning, category, message, data: data);
  }

  /// 便捷方法：记录错误日志
  void error(String category, String message, {Map<String, dynamic>? data}) {
    log(LogLevel.error, category, message, data: data);
  }

  /// 获取所有日志
  List<LogEntry> getAllLogs() {
    return List.unmodifiable(_logs);
  }

  /// 根据级别筛选日志
  List<LogEntry> getLogsByLevel(LogLevel level) {
    return _logs.where((log) => log.level == level).toList();
  }

  /// 根据分类筛选日志
  List<LogEntry> getLogsByCategory(String category) {
    return _logs.where((log) => log.category == category).toList();
  }

  /// 根据时间范围筛选日志
  List<LogEntry> getLogsByTimeRange(DateTime start, DateTime end) {
    return _logs.where((log) => 
      log.timestamp.isAfter(start) && log.timestamp.isBefore(end)
    ).toList();
  }

  /// 获取最近的日志
  List<LogEntry> getRecentLogs(int count) {
    final startIndex = _logs.length - count;
    if (startIndex <= 0) return List.unmodifiable(_logs);
    return List.unmodifiable(_logs.sublist(startIndex));
  }

  /// 清空所有日志
  void clearLogs() {
    _logs.clear();
  }

  /// 导出日志到文件
  Future<String?> exportLogs({
    LogLevel? level,
    String? category,
    DateTime? startTime,
    DateTime? endTime,
    String? filename,
  }) async {
    try {
      // 筛选日志
      List<LogEntry> logsToExport = _logs;
      
      if (level != null) {
        logsToExport = logsToExport.where((log) => log.level == level).toList();
      }
      
      if (category != null) {
        logsToExport = logsToExport.where((log) => log.category == category).toList();
      }
      
      if (startTime != null) {
        logsToExport = logsToExport.where((log) => log.timestamp.isAfter(startTime)).toList();
      }
      
      if (endTime != null) {
        logsToExport = logsToExport.where((log) => log.timestamp.isBefore(endTime)).toList();
      }

      // 生成文件名
      final timestamp = _dateFormatter.format(DateTime.now());
      final finalFilename = filename ?? 'stock_selector_logs_$timestamp.log';

      // 获取应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$finalFilename');

      // 写入日志内容
      final logContent = logsToExport.map((entry) => entry.toString()).join('\n');
      await file.writeAsString(logContent);

      return file.path;
    } catch (e) {
      error('LOG_EXPORT', '导出日志失败: $e');
      return null;
    }
  }

  /// 导出日志为JSON格式
  Future<String?> exportLogsAsJson({
    LogLevel? level,
    String? category,
    DateTime? startTime,
    DateTime? endTime,
    String? filename,
  }) async {
    try {
      // 筛选日志
      List<LogEntry> logsToExport = _logs;
      
      if (level != null) {
        logsToExport = logsToExport.where((log) => log.level == level).toList();
      }
      
      if (category != null) {
        logsToExport = logsToExport.where((log) => log.category == category).toList();
      }
      
      if (startTime != null) {
        logsToExport = logsToExport.where((log) => log.timestamp.isAfter(startTime)).toList();
      }
      
      if (endTime != null) {
        logsToExport = logsToExport.where((log) => log.timestamp.isBefore(endTime)).toList();
      }

      // 生成文件名
      final timestamp = _dateFormatter.format(DateTime.now());
      final finalFilename = filename ?? 'stock_selector_logs_$timestamp.json';

      // 获取应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$finalFilename');

      // 转换为JSON
      final jsonData = {
        'exportTime': DateTime.now().toIso8601String(),
        'totalLogs': logsToExport.length,
        'filters': {
          'level': level?.levelString,
          'category': category,
          'startTime': startTime?.toIso8601String(),
          'endTime': endTime?.toIso8601String(),
        },
        'logs': logsToExport.map((entry) => entry.toJson()).toList(),
      };

      await file.writeAsString(json.encode(jsonData));
      return file.path;
    } catch (e) {
      error('LOG_EXPORT', '导出JSON日志失败: $e');
      return null;
    }
  }

  /// 获取日志统计信息
  Map<String, dynamic> getLogStats() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    
    final todayLogs = _logs.where((log) => log.timestamp.isAfter(today)).length;
    final yesterdayLogs = _logs.where((log) => 
      log.timestamp.isAfter(yesterday) && log.timestamp.isBefore(today)
    ).length;
    
    final levelCounts = <String, int>{};
    for (final level in LogLevel.values) {
      levelCounts[level.levelString] = _logs.where((log) => log.level == level).length;
    }
    
    final categoryCounts = <String, int>{};
    for (final log in _logs) {
      categoryCounts[log.category] = (categoryCounts[log.category] ?? 0) + 1;
    }
    
    return {
      'totalLogs': _logs.length,
      'todayLogs': todayLogs,
      'yesterdayLogs': yesterdayLogs,
      'levelCounts': levelCounts,
      'categoryCounts': categoryCounts,
      'oldestLog': _logs.isNotEmpty ? _logs.first.timestamp.toIso8601String() : null,
      'newestLog': _logs.isNotEmpty ? _logs.last.timestamp.toIso8601String() : null,
    };
  }
}
