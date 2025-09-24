import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/stock_ranking.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../services/stock_pool_service.dart';
import '../services/ma_calculation_service.dart';
import '../services/blacklist_service.dart';
import '../services/condition_combination_service.dart';
import '../services/stock_filter_service.dart';
import '../services/log_service.dart';
import 'stock_pool_config_screen.dart';
import 'condition_management_screen.dart';
import 'log_viewer_screen.dart';

class StockSelectorScreen extends StatefulWidget {
  const StockSelectorScreen({super.key});

  @override
  State<StockSelectorScreen> createState() => _StockSelectorScreenState();
}

class _StockSelectorScreenState extends State<StockSelectorScreen> {
  List<StockRanking> _stockRankings = [];
  bool _isLoading = false;
  List<ConditionCombination> _combinations = [];
  ConditionCombination? _selectedCombination;
  Map<String, dynamic> _poolInfo = {};
  String _currentProgressText = ''; // 当前进度提示文本
  int _currentStockIndex = 0; // 当前处理的股票索引
  int _totalStocks = 0; // 总股票数
  final ScrollController _scrollController = ScrollController(); // 滚动控制器
  bool _isDetailsExpanded = false; // 详细条件是否展开

  @override
  void initState() {
    super.initState();
    _updatePoolInfo();
    _loadCombinations();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _updatePoolInfo() async {
    final localInfo = await StockPoolService.getLocalPoolInfo();
    setState(() {
      _poolInfo = localInfo;
    });
  }

  Future<void> _loadCombinations() async {
    try {
      final combinations = await ConditionCombinationService.getAllCombinations();
      final defaultCombination = await ConditionCombinationService.getDefaultCombination();
      
      setState(() {
        _combinations = combinations;
        _selectedCombination = defaultCombination;
      });
    } catch (e) {
      print('加载条件组合失败: $e');
    }
  }

  Future<void> _loadStocks() async {
    // 收起键盘
    FocusScope.of(context).unfocus();
    
    if (_selectedCombination == null) {
      _showErrorDialog('请先选择一个条件组合');
      return;
    }
    
    print('🚀 开始筛选股票...');
    print('📊 筛选条件:');
    print('   - 成交额: ≥ ${_selectedCombination!.amountThreshold}亿元');
    print('   - 黑名单过滤: 移除黑名单中的股票');
    print('   - 日期: ${DateFormat('yyyy-MM-dd').format(_selectedCombination!.selectedDate)}');
    if (_selectedCombination!.enablePctChg) {
      print('   - 涨跌幅: ${_selectedCombination!.pctChgMin}%~${_selectedCombination!.pctChgMax}%');
    }
    if (_selectedCombination!.enableMaDistance) {
      print('   - 均线偏离: ${_selectedCombination!.shortDescription}');
    }
    if (_selectedCombination!.enableConsecutiveDays) {
      print('   - 连续天数: ${_selectedCombination!.consecutiveDaysConfig.days}天收盘价高于${_selectedCombination!.consecutiveDaysConfig.maType}');
    }
    
    setState(() {
      _isLoading = true;
      _currentProgressText = '开始筛选...';
      _currentStockIndex = 0;
      _totalStocks = 0;
    });
    
    // 延迟滑动到底部
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    try {
      // 使用新的条件组合筛选方法
      print('🔍 使用条件组合筛选股票...');
      List<StockRanking> rankings = await StockFilterService.filterStocksWithCombination(
        combination: _selectedCombination!,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _currentProgressText = '正在筛选股票... ($current/$total)';
              _currentStockIndex = current;
              _totalStocks = total;
            });
          }
        },
      );

      print('🎯 筛选完成! 找到 ${rankings.length} 只符合条件的股票');
      if (rankings.isNotEmpty) {
        print('📋 前5只股票:');
        for (int i = 0; i < math.min(5, rankings.length); i++) {
          final ranking = rankings[i];
          print('   ${i + 1}. ${ranking.stockInfo.name} (${ranking.stockInfo.symbol}) - 当前价: ${ranking.klineData.close.toStringAsFixed(2)}元, 成交额: ${ranking.amountInYi.toStringAsFixed(2)}亿元, 涨跌幅: ${ranking.klineData.pctChg.toStringAsFixed(2)}%');
        }
      }

      setState(() {
        _stockRankings = rankings;
        _isLoading = false;
        _currentProgressText = '筛选完成！共找到 ${rankings.length} 只符合条件的股票';
      });
      
      _updatePoolInfo();
    } catch (e) {
      print('❌ 筛选过程出错: $e');
      setState(() {
        _isLoading = false;
        _currentProgressText = '';
        _currentStockIndex = 0;
        _totalStocks = 0;
      });
      _showErrorDialog('加载股票数据失败: $e');
    }
  }



  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('股票筛选器'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () async {
              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ConditionManagementScreen(),
                ),
              );
              
              // 如果从条件管理页面返回，刷新条件组合列表
              if (result == true) {
                await _loadCombinations();
              }
            },
            tooltip: '条件组合管理',
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const LogViewerScreen(),
                ),
              );
            },
            tooltip: '查看日志',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const StockPoolConfigScreen(),
                ),
              );
              
              // 如果从配置页面返回时带有更新标志，刷新股票池信息
              if (result == true) {
                await _updatePoolInfo();
              }
            },
            tooltip: '股票池配置',
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // 筛选条件区域
          SliverToBoxAdapter(
            child: _buildFilterSection(),
          ),
          // 股票列表
          _isLoading
              ? const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              : _buildStockListSliver(),
        ],
      ),
    );
  }



  Widget _buildFilterSection() {
    return Container(
      margin: const EdgeInsets.all(16.0),
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
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
          // 条件组合选择
          _buildConditionCombinationSelector(),
          const SizedBox(height: 16),
          
          // 股票池信息
          _buildPoolInfoCard(),
          const SizedBox(height: 16),
          
          
          // 进度提示
          if (_currentProgressText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Text(
                _currentProgressText,
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 16),
          
          // 筛选按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _loadStocks,
              icon: _isLoading 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_isLoading ? '筛选中...' : '开始筛选'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionCombinationSelector() {
    if (_combinations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Column(
          children: [
            Icon(
              Icons.warning_amber,
              color: Colors.orange[700],
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              '暂无保存的条件组合',
              style: TextStyle(
                color: Colors.orange[700],
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '请先创建至少一个条件组合',
              style: TextStyle(
                color: Colors.orange[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const ConditionManagementScreen(),
                  ),
                );
                if (result == true) {
                  await _loadCombinations();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('创建条件组合'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.filter_list, color: Colors.blue[700], size: 20),
            const SizedBox(width: 8),
            Text(
              '选择条件组合',
              style: TextStyle(
                color: Colors.blue[700],
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<ConditionCombination>(
          value: _selectedCombination,
          decoration: const InputDecoration(
            labelText: '条件组合',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          hint: const Text('请选择条件组合'),
          items: _combinations.map((combination) {
            return DropdownMenuItem(
              value: combination,
              child: Text(
                combination.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCombination = value;
            });
          },
        ),
        if (_selectedCombination != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前选择: ${_selectedCombination!.name}',
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (_selectedCombination!.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _selectedCombination!.description,
                    style: TextStyle(
                      color: Colors.blue[600],
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // 显示详细的筛选条件（可展开收起）
                _buildExpandableConditions(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExpandableConditions() {
    final combination = _selectedCombination!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 展开/收起按钮
        InkWell(
          onTap: () {
            setState(() {
              _isDetailsExpanded = !_isDetailsExpanded;
            });
          },
          child: Row(
            children: [
              Text(
                '详细筛选条件:',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                _isDetailsExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.blue[700],
                size: 16,
              ),
            ],
          ),
        ),
        // 详细条件内容（可展开收起）
        if (_isDetailsExpanded) ...[
          const SizedBox(height: 4),
          _buildConditionRow('📅 筛选日期', DateFormat('yyyy-MM-dd').format(combination.selectedDate)),
          _buildConditionRow('💰 成交额', '≥ ${combination.amountThreshold}亿元'),
          if (combination.enablePctChg)
            _buildConditionRow('📈 涨跌幅', '${combination.pctChgMin}%~${combination.pctChgMax}%'),
          if (combination.enableMaDistance) ...[
            if (combination.ma5Config.enabled)
              _buildConditionRow('📊 5日线偏离', '≤ ${combination.ma5Config.distance}%'),
            if (combination.ma10Config.enabled)
              _buildConditionRow('📊 10日线偏离', '≤ ${combination.ma10Config.distance}%'),
            if (combination.ma20Config.enabled)
              _buildConditionRow('📊 20日线偏离', '≤ ${combination.ma20Config.distance}%'),
          ],
          if (combination.enableConsecutiveDays) ...[
            _buildConditionRow('⏰ 连续天数', '${combination.consecutiveDaysConfig.days}天收盘价高于${combination.consecutiveDaysConfig.maType == 'ma5' ? 'MA5' : combination.consecutiveDaysConfig.maType == 'ma10' ? 'MA10' : 'MA20'}'),
          ],
        ],
      ],
    );
  }

  Widget _buildConditionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.blue[600],
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.blue[800],
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoolInfoCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.storage, color: Colors.grey[600], size: 20),
          const SizedBox(width: 8),
          Text(
            '股票池: ${_poolInfo['stockCount'] ?? 0}只股票',
            style: TextStyle(
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (_poolInfo['lastUpdate'] != null)
            Text(
              '更新: ${_poolInfo['lastUpdate']}',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStockListSliver() {
    if (_stockRankings.isEmpty) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  '暂无符合条件的股票',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final ranking = _stockRankings[index];
          return _buildStockCard(ranking);
        },
        childCount: _stockRankings.length,
      ),
    );
  }

  Widget _buildStockCard(StockRanking ranking) {
    final pctChg = _calculatePctChg(ranking.klineData);
    final isPositive = pctChg >= 0;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 排名、股票名称和黑名单按钮行
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _getRankColor(ranking.rank),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      '${ranking.rank}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ranking.stockInfo.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${ranking.stockInfo.symbol} | ${ranking.stockInfo.market}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // 价格
                Text(
                  '¥${ranking.klineData.close.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                // 黑名单按钮（小按钮）
                FutureBuilder<bool>(
                  future: BlacklistService.isInBlacklist(ranking.stockInfo.tsCode),
                  builder: (context, snapshot) {
                    final isInBlacklist = snapshot.data ?? false;
                    return GestureDetector(
                      onTap: () => _toggleBlacklist(ranking.stockInfo, isInBlacklist),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isInBlacklist ? Colors.green[100] : Colors.orange[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          isInBlacklist ? Icons.remove_circle : Icons.block,
                          size: 16,
                          color: isInBlacklist ? Colors.green[700] : Colors.orange[700],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 涨跌幅、成交量、成交额一行
            Row(
              children: [
                Expanded(
                  child: _buildCompactInfoItem(
                    '涨跌幅',
                    '${isPositive ? '+' : ''}${pctChg.toStringAsFixed(2)}%',
                    isPositive ? Colors.red[700]! : Colors.green[700]!,
                  ),
                ),
                Expanded(
                  child: _buildCompactInfoItem(
                    '成交量',
                    '${(ranking.klineData.vol / 10000).toStringAsFixed(0)}万手',
                    Colors.orange[700]!,
                  ),
                ),
                Expanded(
                  child: _buildCompactInfoItem(
                    '成交额',
                    '${ranking.amountInYi.toStringAsFixed(2)}亿元',
                    Colors.blue[700]!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildCompactInfoItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }


  Color _getRankColor(int rank) {
    if (rank <= 3) {
      return Colors.amber[700]!;
    } else if (rank <= 10) {
      return Colors.blue[700]!;
    } else {
      return Colors.grey[600]!;
    }
  }

  // 计算涨跌幅
  double _calculatePctChg(KlineData klineData) {
    if (klineData.preClose > 0) {
      return (klineData.close - klineData.preClose) / klineData.preClose * 100;
    }
    return 0.0;
  }


  // 切换黑名单状态
  Future<void> _toggleBlacklist(StockInfo stock, bool isInBlacklist) async {
    try {
      if (isInBlacklist) {
        await BlacklistService.removeFromBlacklist(stock.tsCode);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已从黑名单移除 ${stock.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        await BlacklistService.addToBlacklist(stock.tsCode);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已添加 ${stock.name} 到黑名单'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
      // 刷新列表
      setState(() {});
    } catch (e) {
      if (mounted) {
        _showErrorDialog('操作失败: $e');
      }
    }
  }



}
