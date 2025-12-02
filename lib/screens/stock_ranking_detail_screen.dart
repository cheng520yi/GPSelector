import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/stock_ranking.dart';
import '../services/stock_ranking_service.dart';
import '../services/ranking_config_service.dart';
import '../services/condition_combination_service.dart';
import '../services/stock_pool_config_service.dart';
import '../services/stock_api_service.dart';
import 'stock_detail_screen.dart';

class StockRankingDetailScreen extends StatefulWidget {
  final List<StockRanking> stockRankings;
  final ConditionCombination combination;

  const StockRankingDetailScreen({
    super.key,
    required this.stockRankings,
    required this.combination,
  });

  @override
  State<StockRankingDetailScreen> createState() => _StockRankingDetailScreenState();
}

class _StockRankingDetailScreenState extends State<StockRankingDetailScreen> {
  List<RankedStock> _rankedStocks = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _calculateRankings();
  }

  Future<void> _calculateRankings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 检查是否应该使用实时接口
      final config = await StockPoolConfigService.getConfig();
      final now = DateTime.now();
      final currentTime = now.hour * 100 + now.minute;
      bool useRealtimeInterface = false;
      
      // 如果启用了实时接口配置，且在交易时间内，使用实时接口
      if (config.enableRealtimeInterface && StockApiService.isTradingDay(now) && currentTime >= 930) {
        final endTime = config.realtimeEndTime ?? const TimeOfDay(hour: 16, minute: 30);
        final endTimeMinutes = endTime.hour * 100 + endTime.minute;
        if (currentTime <= endTimeMinutes) {
          useRealtimeInterface = true;
        }
      }

      final rankedStocks = await StockRankingService.calculateRankings(
        widget.stockRankings,
        widget.combination.selectedDate,
        useRealtimeInterface: useRealtimeInterface,
      );

      setState(() {
        _rankedStocks = rankedStocks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '计算排名失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('股票排名详情'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const RankingConfigScreen(),
                ),
              );
              if (result == true) {
                // 重新计算排名
                _calculateRankings();
              }
            },
            tooltip: '评分规则设置',
          ),
        ],
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
                        onPressed: _calculateRankings,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _rankedStocks.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无排名数据',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        // 统计信息
                        SliverToBoxAdapter(
                          child: _buildStatisticsCard(),
                        ),
                        // 排名列表
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return _buildRankedStockCard(_rankedStocks[index]);
                            },
                            childCount: _rankedStocks.length,
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildStatisticsCard() {
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
          Row(
            children: [
              Icon(Icons.analytics, color: Colors.blue[600]),
              const SizedBox(width: 8),
              const Text(
                '排名统计',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem('总股票数', '${_rankedStocks.length}'),
              ),
              Expanded(
                child: _buildStatItem('筛选日期', DateFormat('yyyy-MM-dd').format(widget.combination.selectedDate)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildRankedStockCard(RankedStock rankedStock) {
    final ranking = rankedStock.stockRanking;
    final pctChg = ranking.klineData.preClose > 0
        ? ((ranking.klineData.close - ranking.klineData.preClose) / ranking.klineData.preClose * 100)
        : ranking.klineData.pctChg;
    final isPositive = pctChg >= 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => StockDetailScreen(
                stockInfo: ranking.stockInfo,
                currentKlineData: ranking.klineData,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 排名和股票信息
              Row(
                children: [
                  // 排名
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getRankColor(rankedStock.rank),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        '${rankedStock.rank}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 股票信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ranking.stockInfo.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${ranking.stockInfo.symbol} | ${ranking.stockInfo.market}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 价格和涨跌幅
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '¥${ranking.klineData.close.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${isPositive ? '+' : ''}${pctChg.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: isPositive ? Colors.red[700] : Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 评分信息
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    // 总分
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '总分: ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${rankedStock.totalScore}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                        const Text(
                          ' / 10',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 详细评分
                    Row(
                      children: [
                        Expanded(
                          child: _buildScoreItem(
                            '市值',
                            rankedStock.marketValue.toStringAsFixed(2) + '亿',
                            rankedStock.marketValueScore,
                            5,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey[300],
                        ),
                        Expanded(
                          child: _buildScoreItem(
                            'BOLL偏离',
                            rankedStock.bollDeviation != null
                                ? '${rankedStock.bollDeviation!.toStringAsFixed(2)}%'
                                : '-',
                            rankedStock.bollDeviationScore,
                            5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreItem(String label, String value, int score, int maxScore) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$score/$maxScore 分',
          style: TextStyle(
            fontSize: 12,
            color: Colors.blue[700],
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _getRankColor(int rank) {
    if (rank <= 3) {
      return Colors.red[700]!;
    } else if (rank <= 10) {
      return Colors.orange[700]!;
    } else {
      return Colors.blue[700]!;
    }
  }
}

/// 评分规则配置页面
class RankingConfigScreen extends StatefulWidget {
  const RankingConfigScreen({super.key});

  @override
  State<RankingConfigScreen> createState() => _RankingConfigScreenState();
}

class _RankingConfigScreenState extends State<RankingConfigScreen> {
  RankingConfig _config = RankingConfigService.getDefaultConfig();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
    });
    final config = await RankingConfigService.getConfig();
    setState(() {
      _config = config;
      _isLoading = false;
    });
  }

  Future<void> _saveConfig() async {
    setState(() {
      _isLoading = true;
    });
    final success = await RankingConfigService.saveConfig(_config);
    setState(() {
      _isLoading = false;
    });
    
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存成功'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('评分规则设置'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 市值评分规则
                  _buildMarketValueSection(),
                  const SizedBox(height: 24),
                  // BOLL偏离评分规则
                  _buildBollDeviationSection(),
                  const SizedBox(height: 24),
                  // 保存按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveConfig,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue[600],
                      ),
                      child: const Text(
                        '保存',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMarketValueSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '市值评分规则',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ..._config.marketValueRanges.asMap().entries.map((entry) {
              final index = entry.key;
              final range = entry.value;
              return _buildMarketValueRangeItem(index, range);
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketValueRangeItem(int index, MarketValueRange range) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: range.min == 0 ? '0' : range.min.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '最小市值（亿）',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                final min = double.tryParse(value) ?? 0;
                final newRanges = List<MarketValueRange>.from(_config.marketValueRanges);
                newRanges[index] = MarketValueRange(
                  min: min,
                  max: range.max,
                  score: range.score,
                );
                setState(() {
                  _config = _config.copyWith(marketValueRanges: newRanges);
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          const Text('至'),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: range.max == double.infinity ? '无上限' : range.max.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '最大市值（亿）',
                border: const OutlineInputBorder(),
                suffixText: range.max == double.infinity ? '无上限' : null,
              ),
              onChanged: (value) {
                double max = double.infinity;
                if (value.trim().isNotEmpty && value != '无上限') {
                  max = double.tryParse(value) ?? double.infinity;
                }
                final newRanges = List<MarketValueRange>.from(_config.marketValueRanges);
                newRanges[index] = MarketValueRange(
                  min: range.min,
                  max: max,
                  score: range.score,
                );
                setState(() {
                  _config = _config.copyWith(marketValueRanges: newRanges);
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: range.score.toString(),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '分数',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                final score = int.tryParse(value) ?? 0;
                final newRanges = List<MarketValueRange>.from(_config.marketValueRanges);
                newRanges[index] = MarketValueRange(
                  min: range.min,
                  max: range.max,
                  score: score,
                );
                setState(() {
                  _config = _config.copyWith(marketValueRanges: newRanges);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBollDeviationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BOLL偏离评分规则',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ..._config.bollDeviationRanges.asMap().entries.map((entry) {
              final index = entry.key;
              final range = entry.value;
              return _buildDeviationRangeItem(index, range);
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviationRangeItem(int index, DeviationRange range) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: range.min == 0 ? '0' : range.min.toStringAsFixed(1),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '最小偏离（%）',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                final min = double.tryParse(value) ?? 0;
                final newRanges = List<DeviationRange>.from(_config.bollDeviationRanges);
                newRanges[index] = DeviationRange(
                  min: min,
                  max: range.max,
                  score: range.score,
                );
                setState(() {
                  _config = _config.copyWith(bollDeviationRanges: newRanges);
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          const Text('至'),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: range.max == double.infinity ? '无上限' : range.max.toStringAsFixed(1),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '最大偏离（%）',
                border: const OutlineInputBorder(),
                suffixText: range.max == double.infinity ? '无上限' : null,
              ),
              onChanged: (value) {
                double max = double.infinity;
                if (value.trim().isNotEmpty && value != '无上限') {
                  max = double.tryParse(value) ?? double.infinity;
                }
                final newRanges = List<DeviationRange>.from(_config.bollDeviationRanges);
                newRanges[index] = DeviationRange(
                  min: range.min,
                  max: max,
                  score: range.score,
                );
                setState(() {
                  _config = _config.copyWith(bollDeviationRanges: newRanges);
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: range.score.toString(),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '分数',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                final score = int.tryParse(value) ?? 0;
                final newRanges = List<DeviationRange>.from(_config.bollDeviationRanges);
                newRanges[index] = DeviationRange(
                  min: range.min,
                  max: range.max,
                  score: score,
                );
                setState(() {
                  _config = _config.copyWith(bollDeviationRanges: newRanges);
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

