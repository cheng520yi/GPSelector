import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/log_service.dart';
import '../services/console_capture_service.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({Key? key}) : super(key: key);

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final LogService _logService = LogService.instance;
  final ConsoleCaptureService _consoleCapture = ConsoleCaptureService.instance;
  final ScrollController _scrollController = ScrollController();
  
  List<LogEntry> _displayedLogs = [];
  LogLevel? _selectedLevel;
  String? _selectedCategory;
  bool _isExporting = false;
  bool _showConsoleOutput = true;
  Timer? _refreshTimer; // 定时器用于定期刷新日志
  
  final List<String> _categories = ['API', 'FILTER', 'ERROR', 'STOCK_SELECTOR', 'LOG_EXPORT', 'CONSOLE'];
  final DateFormat _timeFormatter = DateFormat('HH:mm:ss.SSS');

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _scrollController.addListener(_onScroll);
    
    // 启动控制台输出捕获
    _consoleCapture.startCapture();
    
    // 启动定时器，每2秒刷新一次日志
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _loadLogs();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // 停止控制台输出捕获
    _consoleCapture.stopCapture();
    // 停止定时器
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _loadLogs() {
    setState(() {
      _displayedLogs = _logService.getAllLogs();
      _applyFilters();
    });
  }

  void _onScroll() {
    // 移除自动滚动逻辑，因为它会干扰手动滚动
    // 用户可以通过点击自动滚动按钮来控制
  }

  void _applyFilters() {
    setState(() {
      _displayedLogs = _logService.getAllLogs().where((log) {
        if (_selectedLevel != null && log.level != _selectedLevel) {
          return false;
        }
        if (_selectedCategory != null && log.category != _selectedCategory) {
          return false;
        }
        // 如果不显示控制台输出，则过滤掉CONSOLE类别的日志
        if (!_showConsoleOutput && log.category == 'CONSOLE') {
          return false;
        }
        return true;
      }).toList();
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedLevel = null;
      _selectedCategory = null;
      _showConsoleOutput = true;
      _displayedLogs = _logService.getAllLogs();
    });
  }

  void _clearAllLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('确定要清空所有日志吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              _logService.clearLogs();
              _loadLogs();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已清空')),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportLogs() async {
    setState(() {
      _isExporting = true;
    });

    try {
      final filePath = await _logService.exportLogs(
        level: _selectedLevel,
        category: _selectedCategory,
      );

      if (filePath != null) {
        // 复制文件路径到剪贴板
        await Clipboard.setData(ClipboardData(text: filePath));
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('日志已导出到: $filePath\n文件路径已复制到剪贴板'),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: '确定',
                onPressed: () {},
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导出失败')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  Future<void> _exportLogsAsJson() async {
    setState(() {
      _isExporting = true;
    });

    try {
      final filePath = await _logService.exportLogsAsJson(
        level: _selectedLevel,
        category: _selectedCategory,
      );

      if (filePath != null) {
        // 复制文件路径到剪贴板
        await Clipboard.setData(ClipboardData(text: filePath));
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('JSON日志已导出到: $filePath\n文件路径已复制到剪贴板'),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: '确定',
                onPressed: () {},
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导出失败')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  IconData _getLevelIcon(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Icons.bug_report;
      case LogLevel.info:
        return Icons.info;
      case LogLevel.warning:
        return Icons.warning;
      case LogLevel.error:
        return Icons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _logService.getLogStats();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志查看器'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.vertical_align_bottom),
            onPressed: () {
              // 手动滚动到底部
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            },
            tooltip: '滚动到底部',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: '刷新日志',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'export':
                  _exportLogs();
                  break;
                case 'export_json':
                  _exportLogsAsJson();
                  break;
                case 'clear':
                  _clearAllLogs();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.file_download),
                  title: Text('导出日志 (.log)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_json',
                child: ListTile(
                  leading: Icon(Icons.file_download),
                  title: Text('导出日志 (.json)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.clear_all, color: Colors.red),
                  title: Text('清空日志', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // 统计信息
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[100],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '日志统计',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStatItem('总计', '${stats['totalLogs']}', Colors.blue),
                      const SizedBox(width: 16),
                      _buildStatItem('今日', '${stats['todayLogs']}', Colors.green),
                      const SizedBox(width: 16),
                      _buildStatItem('昨日', '${stats['yesterdayLogs']}', Colors.orange),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // 筛选器
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[50],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '筛选器',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 使用更紧凑的布局来避免溢出
                  Column(
                    children: [
                      // 第一行：级别和分类筛选
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<LogLevel?>(
                              value: _selectedLevel,
                              decoration: const InputDecoration(
                                labelText: '级别',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem<LogLevel?>(
                                  value: null,
                                  child: Text('全部', style: TextStyle(fontSize: 12)),
                                ),
                                ...LogLevel.values.map((level) => DropdownMenuItem<LogLevel?>(
                                  value: level,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(_getLevelIcon(level), color: _getLevelColor(level), size: 14),
                                      const SizedBox(width: 4),
                                      Text(level.levelString, style: const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                )),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedLevel = value;
                                });
                                _applyFilters();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              value: _selectedCategory,
                              decoration: const InputDecoration(
                                labelText: '分类',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('全部', style: TextStyle(fontSize: 12)),
                                ),
                                ..._categories.map((category) => DropdownMenuItem<String?>(
                                  value: category,
                                  child: Text(category, style: const TextStyle(fontSize: 12)),
                                )),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedCategory = value;
                                });
                                _applyFilters();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      // 第二行：控制台开关和清空筛选按钮
                      Row(
                        children: [
                          // 控制台输出开关
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: _showConsoleOutput,
                                onChanged: (value) {
                                  setState(() {
                                    _showConsoleOutput = value;
                                  });
                                  _applyFilters();
                                },
                              ),
                              const Text('控制台', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          const Spacer(),
                          
                          // 清空筛选
                          ElevatedButton(
                            onPressed: _clearFilters,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: const Text('清空筛选', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // 日志列表
          _displayedLogs.isEmpty
              ? SliverFillRemaining(
                  child: const Center(
                    child: Text(
                      '暂无日志',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final log = _displayedLogs[index];
                      return _buildLogItem(log);
                    },
                    childCount: _displayedLogs.length,
                  ),
                ),
          
          // 底部操作栏
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[100],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isExporting ? null : _exportLogs,
                    icon: _isExporting 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download),
                    label: Text(_isExporting ? '导出中...' : '导出日志'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isExporting ? null : _exportLogsAsJson,
                    icon: _isExporting 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.code),
                    label: Text(_isExporting ? '导出中...' : '导出JSON'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(LogEntry log) {
    final levelColor = _getLevelColor(log.level);
    final levelIcon = _getLevelIcon(log.level);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: levelColor, width: 4),
        ),
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(levelIcon, color: levelColor, size: 16),
        title: Text(
          log.message,
          style: const TextStyle(fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _timeFormatter.format(log.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: levelColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.level.levelString,
                    style: TextStyle(
                      fontSize: 10,
                      color: levelColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.category,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
            if (log.data != null) ...[
              const SizedBox(height: 4),
              Text(
                '数据: ${log.data.toString()}',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[500],
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        onTap: () {
          _showLogDetails(log);
        },
      ),
    );
  }

  void _showLogDetails(LogEntry log) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Row(
                children: [
                  Icon(_getLevelIcon(log.level), color: _getLevelColor(log.level)),
                  const SizedBox(width: 8),
                  const Text(
                    '日志详情',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              
              // 可滚动的内容区域
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('时间', log.formattedTimestamp),
                      const SizedBox(height: 12),
                      _buildDetailRow('级别', log.level.levelString),
                      const SizedBox(height: 12),
                      _buildDetailRow('分类', log.category),
                      const SizedBox(height: 12),
                      _buildDetailRow('消息', log.message, isMessage: true),
                      if (log.data != null) ...[
                        const SizedBox(height: 12),
                        _buildDetailRow('数据', log.data.toString(), isMessage: true),
                      ],
                    ],
                  ),
                ),
              ),
              
              const Divider(),
              
              // 底部按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: log.toString()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('日志内容已复制到剪贴板')),
                      );
                    },
                    child: const Text('复制'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isMessage = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(4),
            ),
            child: isMessage 
                ? SelectableText(
                    value,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  )
                : Text(
                    value,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
          ),
        ],
      ),
    );
  }
}
