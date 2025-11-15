import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../services/stock_api_service.dart';
import '../widgets/kline_chart_widget.dart';

class StockDetailScreen extends StatefulWidget {
  final StockInfo stockInfo;
  final KlineData? currentKlineData;

  const StockDetailScreen({
    super.key,
    required this.stockInfo,
    this.currentKlineData,
  });

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  List<KlineData> _klineDataList = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _selectedDays = 60; // 默认显示60天
  int _subChartCount = 1; // 默认显示1个副图

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  // 初始化数据：先加载设置，再加载K线数据
  Future<void> _initializeData() async {
    await _loadSettings();
    _loadKlineData();
  }

  // 加载保存的设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDays = prefs.getInt('kline_display_days');
      final savedSubChartCount = prefs.getInt('kline_sub_chart_count');
      
      if (savedDays != null) {
        setState(() {
          _selectedDays = savedDays;
        });
      }
      
      if (savedSubChartCount != null) {
        setState(() {
          _subChartCount = savedSubChartCount;
        });
      }
    } catch (e) {
      // 如果加载失败，使用默认值
      print('加载设置失败: $e');
    }
  }

  // 保存设置
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('kline_display_days', _selectedDays);
      await prefs.setInt('kline_sub_chart_count', _subChartCount);
    } catch (e) {
      print('保存设置失败: $e');
    }
  }

  Future<void> _loadKlineData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 根据选择的自然日数，从当前日期倒退N个自然日
      // 为了确保20日均线能从最左侧开始显示，需要多请求足够的数据
      // 通常30个自然日约等于21-22个交易日，为了安全，我们请求更多数据
      // 确保有足够的交易日数据：请求_selectedDays * 1.5 + 20个自然日
      final requestDays = (_selectedDays * 1.5).round() + 20;
      final klineDataList = await StockApiService.getKlineData(
        tsCode: widget.stockInfo.tsCode,
        kLineType: 'daily',
        days: requestDays, // 多请求数据，确保有足够的交易日和20日均线从最左侧开始显示
      );

      // 数据已经按时间排序，直接使用
      // 确保数据按时间正序排列（从早到晚）
      final sortedData = klineDataList.toList()
        ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));

      setState(() {
        _klineDataList = sortedData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '加载K线数据失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stockInfo.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadKlineData,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    // 股票基本信息
                    SliverToBoxAdapter(
                      child: _buildStockInfoCard(),
                    ),
                    // K线图（包含图表类型选择和设置）
                    SliverToBoxAdapter(
                      child: _buildKlineChart(),
                    ),
                    // 数据统计
                    SliverToBoxAdapter(
                      child: _buildStatisticsCard(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStockInfoCard() {
    final currentData = widget.currentKlineData ?? 
        (_klineDataList.isNotEmpty ? _klineDataList.last : null);
    final pctChg = currentData != null 
        ? (currentData.preClose > 0 
            ? ((currentData.close - currentData.preClose) / currentData.preClose * 100)
            : currentData.pctChg)
        : 0.0;
    final isPositive = pctChg >= 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8), // 减小底部边距
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), // 减小内边距
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.stockInfo.name,
                      style: const TextStyle(
                        fontSize: 20, // 减小字体
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2), // 减小间距
                    Text(
                      '${widget.stockInfo.symbol} | ${widget.stockInfo.market}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11, // 减小字体
                      ),
                    ),
                  ],
                ),
              ),
              if (currentData != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '¥${currentData.close.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 22, // 减小字体
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.red[700] : Colors.green[700],
                      ),
                    ),
                    Text(
                      '${isPositive ? '+' : ''}${pctChg.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 13, // 减小字体
                        color: isPositive ? Colors.red[700] : Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (currentData != null) ...[
            const SizedBox(height: 8), // 减小间距
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem('今开', '¥${currentData.open.toStringAsFixed(2)}'),
                ),
                Expanded(
                  child: _buildInfoItem('最高', '¥${currentData.high.toStringAsFixed(2)}'),
                ),
                Expanded(
                  child: _buildInfoItem('最低', '¥${currentData.low.toStringAsFixed(2)}'),
                ),
                Expanded(
                  child: _buildInfoItem('昨收', '¥${currentData.preClose.toStringAsFixed(2)}'),
                ),
              ],
            ),
            const SizedBox(height: 6), // 减小间距
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem('成交量', '${(currentData.vol / 10000).toStringAsFixed(0)}万手'),
                ),
                Expanded(
                  child: _buildInfoItem('成交额', '${currentData.amountInYi.toStringAsFixed(2)}亿元'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 10, // 减小字体
          ),
        ),
        const SizedBox(height: 2), // 减小间距
        Text(
          value,
          style: const TextStyle(
            fontSize: 12, // 减小字体
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // 显示设置对话框
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return _SettingsDialog(
          initialDays: _selectedDays,
          initialSubChartCount: _subChartCount,
          onConfirm: (days, subChartCount) {
            final daysChanged = _selectedDays != days;
            setState(() {
              _selectedDays = days;
              _subChartCount = subChartCount;
            });
            _saveSettings(); // 保存设置
            if (daysChanged) {
              _loadKlineData(); // 如果天数改变，重新加载数据
            }
          },
        );
      },
    );
  }


  Widget _buildChartTypeButton(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        // 暂时只支持日K，周K和月K功能待实现
        if (label == '日K') {
          // 日K已选中，无需操作
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildKlineChart() {
    if (_klineDataList.isEmpty) {
      return Container(
        height: 400,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('暂无K线数据'),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图表类型选择和设置按钮
          Row(
            children: [
              // 图表类型选择按钮
              Expanded(
                child: Row(
                  children: [
                    _buildChartTypeButton('日K', true), // 默认选择日K
                    const SizedBox(width: 4),
                    _buildChartTypeButton('周K', false),
                    const SizedBox(width: 4),
                    _buildChartTypeButton('月K', false),
                  ],
                ),
              ),
              // 设置按钮
              IconButton(
                icon: const Icon(Icons.settings, size: 20),
                onPressed: _showSettingsDialog,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 500,
            child: KlineChartWidget(
              klineDataList: _klineDataList,
              displayDays: _selectedDays, // 只显示选择的天数，但均线计算用全部数据
              subChartCount: _subChartCount, // 显示选择的副图数量
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard() {
    if (_klineDataList.isEmpty) {
      return const SizedBox.shrink();
    }

    // 计算统计数据
    final prices = _klineDataList.map((e) => e.close).toList();
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final firstPrice = _klineDataList.first.close;
    final lastPrice = _klineDataList.last.close;
    final totalChange = lastPrice - firstPrice;
    final totalPctChg = firstPrice > 0 ? (totalChange / firstPrice * 100) : 0.0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '统计信息',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem('最高价', '¥${maxPrice.toStringAsFixed(2)}', Colors.red[700]!),
              ),
              Expanded(
                child: _buildStatItem('最低价', '¥${minPrice.toStringAsFixed(2)}', Colors.green[700]!),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem('区间涨跌', '${totalChange >= 0 ? '+' : ''}${totalChange.toStringAsFixed(2)}', 
                    totalChange >= 0 ? Colors.red[700]! : Colors.green[700]!),
              ),
              Expanded(
                child: _buildStatItem('区间涨跌幅', '${totalPctChg >= 0 ? '+' : ''}${totalPctChg.toStringAsFixed(2)}%',
                    totalPctChg >= 0 ? Colors.red[700]! : Colors.green[700]!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// 设置对话框组件
class _SettingsDialog extends StatefulWidget {
  final int initialDays;
  final int initialSubChartCount;
  final Function(int, int) onConfirm;

  const _SettingsDialog({
    required this.initialDays,
    required this.initialSubChartCount,
    required this.onConfirm,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late int _selectedDays;
  late int _subChartCount;

  @override
  void initState() {
    super.initState();
    _selectedDays = widget.initialDays;
    _subChartCount = widget.initialSubChartCount;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('图表设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '显示天数',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildDayButton(60, '60日'),
                _buildDayButton(90, '90日'),
                _buildDayButton(180, '180日'),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '副图数量',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSubChartButton(1, '1个'),
                _buildSubChartButton(2, '2个'),
                _buildSubChartButton(3, '3个'),
                _buildSubChartButton(4, '4个'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            widget.onConfirm(_selectedDays, _subChartCount);
            Navigator.of(context).pop();
          },
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildDayButton(int days, String label) {
    final isSelected = _selectedDays == days;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _selectedDays = days;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue[600] : Colors.grey[200],
        foregroundColor: isSelected ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        minimumSize: const Size(80, 36),
      ),
      child: Text(label),
    );
  }

  Widget _buildSubChartButton(int count, String label) {
    final isSelected = _subChartCount == count;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _subChartCount = count;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue[600] : Colors.grey[200],
        foregroundColor: isSelected ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        minimumSize: const Size(70, 36),
      ),
      child: Text(label),
    );
  }
}

