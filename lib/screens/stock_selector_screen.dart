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
import 'stock_pool_config_screen.dart';
import 'condition_management_screen.dart';

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
    print('   - 涨跌幅: ${_selectedCombination!.pctChgMin}% ~ ${_selectedCombination!.pctChgMax}%');
    print('   - 均线距离: 5日≤${_selectedCombination!.ma5Distance}%, 10日≤${_selectedCombination!.ma10Distance}%, 20日≤${_selectedCombination!.ma20Distance}%');
    print('   - 连续天数: ${_selectedCombination!.consecutiveDays}天收盘价高于20日线');
    
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
      // 从本地加载股票池和K线数据
      print('📁 从本地加载股票池数据...');
      final localData = await StockPoolService.loadStockPoolFromLocal();
      List<StockInfo> stockPool = localData['stockPool'] as List<StockInfo>;
      Map<String, KlineData> klineDataMap = localData['klineData'] as Map<String, KlineData>;
      
      print('📈 本地股票池: ${stockPool.length}只股票');
      
      // 如果本地没有股票池，则构建新的
      if (stockPool.isEmpty) {
        print('⚠️ 本地股票池为空，开始构建新股票池...');
        stockPool = await StockPoolService.buildStockPool();
        // 重新加载本地数据
        final newLocalData = await StockPoolService.loadStockPoolFromLocal();
        klineDataMap = newLocalData['klineData'] as Map<String, KlineData>;
        print('✅ 新股票池构建完成: ${stockPool.length}只股票');
      } else {
        print('📁 使用本地股票池: ${stockPool.length}只股票');
        // 检查是否需要更新K线数据
        print('🔄 检查K线数据是否需要更新...');
        final updatedKlineData = await StockPoolService.updateKlineDataIfNeeded(stockPool);
        if (updatedKlineData.isNotEmpty) {
          print('📊 更新K线数据: ${updatedKlineData.length}只股票');
          klineDataMap = updatedKlineData;
          // 保存更新后的K线数据
          await StockPoolService.saveStockPoolToLocal(stockPool, klineDataMap);
        } else {
          print('✅ K线数据仍然有效，无需更新');
        }
      }

      // 从股票池中筛选符合条件的数据
      print('🔍 开始应用筛选条件...');
      List<StockRanking> rankings = await _filterFromStockPool(stockPool, klineDataMap);

      print('🎯 筛选完成! 找到 ${rankings.length} 只符合条件的股票');
      if (rankings.isNotEmpty) {
        print('📋 前5只股票:');
        for (int i = 0; i < math.min(5, rankings.length); i++) {
          final ranking = rankings[i];
          final pctChg = _calculatePctChg(ranking.klineData);
          print('   ${i + 1}. ${ranking.stockInfo.name} (${ranking.stockInfo.symbol}) - 成交额: ${ranking.amountInYi.toStringAsFixed(2)}亿元, 涨跌幅: ${pctChg.toStringAsFixed(2)}%');
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

  Future<List<StockRanking>> _filterFromStockPool(List<StockInfo> stockPool, Map<String, KlineData> klineDataMap) async {
    print('🔍 开始筛选过程...');
    
    // 条件1：按成交额筛选（使用选择日期的数据）
    print('📊 条件1: 按成交额筛选 (≥ ${_selectedCombination!.amountThreshold}亿元)');
    print('📅 筛选日期: ${DateFormat('yyyy-MM-dd').format(_selectedCombination!.selectedDate)}');
    List<StockRanking> condition1Results = [];
    
    // 获取选择日期的K线数据
    final List<String> tsCodes = stockPool.map((stock) => stock.tsCode).toList();
    print('📡 获取${DateFormat('yyyy-MM-dd').format(_selectedCombination!.selectedDate)}的K线数据，共${tsCodes.length}只股票');
    
    final selectedDateKlineData = await StockPoolService.getBatchDailyKlineData(
      tsCodes: tsCodes,
      targetDate: _selectedCombination!.selectedDate, // 使用选择日期
    );
    
    print('✅ 获取到${selectedDateKlineData.length}只股票的${DateFormat('yyyy-MM-dd').format(_selectedCombination!.selectedDate)}数据');
    
    for (StockInfo stock in stockPool) {
      final KlineData? klineData = selectedDateKlineData[stock.tsCode];
      
      if (klineData != null && klineData.amountInYi >= _selectedCombination!.amountThreshold) {
        print('   ✅ ${stock.name}: 成交额${klineData.amountInYi.toStringAsFixed(2)}亿元 (${klineData.tradeDate})');
        condition1Results.add(StockRanking(
          stockInfo: stock,
          klineData: klineData,
          amountInYi: klineData.amountInYi,
          rank: 0, // 临时排名，稍后会重新排序
        ));
      } else if (klineData != null) {
        print('   ❌ ${stock.name}: 成交额${klineData.amountInYi.toStringAsFixed(2)}亿元 < ${_selectedCombination!.amountThreshold}亿元 (${klineData.tradeDate})');
      } else {
        print('   ⚠️ ${stock.name}: 未找到${DateFormat('yyyy-MM-dd').format(_selectedCombination!.selectedDate)}的数据');
      }
    }
    print('✅ 条件1完成: ${condition1Results.length}只股票通过成交额筛选');
    
    // 更新进度
    setState(() {
      _currentProgressText = '条件1完成: ${condition1Results.length}只股票通过成交额筛选\n下一步: 黑名单过滤';
    });

    // 黑名单过滤：从条件1的结果中移除黑名单股票
    print('🚫 黑名单过滤: 移除黑名单中的股票');
    List<StockRanking> blacklistFilteredResults = [];
    final blacklist = await BlacklistService.getBlacklist();
    
    for (StockRanking ranking in condition1Results) {
      if (!blacklist.contains(ranking.stockInfo.tsCode)) {
        blacklistFilteredResults.add(ranking);
      } else {
        print('   🚫 ${ranking.stockInfo.name} 在黑名单中，已移除');
      }
    }
    
    print('✅ 黑名单过滤完成: ${blacklistFilteredResults.length}只股票通过黑名单过滤');
    
    // 更新进度提示
    setState(() {
      _currentProgressText = '黑名单过滤完成: ${blacklistFilteredResults.length}只股票通过黑名单过滤\n下一步: 条件2 - 涨跌幅筛选';
    });

    // 条件2：按涨跌幅筛选（从黑名单过滤后的结果中筛选）
    print('📈 条件2: 按涨跌幅筛选 (${_selectedCombination!.pctChgMin}% ~ ${_selectedCombination!.pctChgMax}%)');
    print('📅 筛选日期: ${DateFormat('yyyy-MM-dd').format(_selectedCombination!.selectedDate)}');
    List<StockRanking> condition2Results = [];
    
    // 获取需要重新请求K线数据的股票代码
    final List<String> tsCodesForCondition2 = blacklistFilteredResults.map((r) => r.stockInfo.tsCode).toList();
    print('📡 需要获取${DateFormat('yyyy-MM-dd').format(_selectedCombination!.selectedDate)}K线数据的股票: ${tsCodesForCondition2.length}只');
    
    // 更新进度提示
    setState(() {
      _currentProgressText = '条件2进行中: 正在获取${tsCodesForCondition2.length}只股票的${DateFormat('yyyy-MM-dd').format(_selectedCombination!.selectedDate)}K线数据...';
    });
    
    // 批量获取指定日期的K线数据
    final Map<String, KlineData> condition2KlineData = 
        await StockPoolService.getBatchDailyKlineData(tsCodes: tsCodesForCondition2, targetDate: _selectedCombination!.selectedDate);
    print('✅ ${DateFormat('yyyy-MM-dd').format(_selectedCombination!.selectedDate)}K线数据获取完成');
    
    for (StockRanking ranking in blacklistFilteredResults) {
      final KlineData? selectedDateKline = condition2KlineData[ranking.stockInfo.tsCode];
      
      if (selectedDateKline != null) {
        // 计算涨跌幅：(close - pre_close) / pre_close * 100
        final double pctChg = selectedDateKline.preClose > 0 
            ? (selectedDateKline.close - selectedDateKline.preClose) / selectedDateKline.preClose * 100
            : 0.0;
        print('   ${ranking.stockInfo.name}: 涨跌幅 ${pctChg.toStringAsFixed(2)}% (${selectedDateKline.tradeDate})');
        
        if (pctChg >= _selectedCombination!.pctChgMin && pctChg <= _selectedCombination!.pctChgMax) {
          // 更新ranking的K线数据为选择日期的数据
          final updatedRanking = StockRanking(
            stockInfo: ranking.stockInfo,
            klineData: selectedDateKline,
            amountInYi: selectedDateKline.amountInYi,
            rank: ranking.rank,
          );
          condition2Results.add(updatedRanking);
        }
      } else {
        print('   ⚠️ ${ranking.stockInfo.name}: 未找到${DateFormat('yyyy-MM-dd').format(_selectedCombination!.selectedDate)}的K线数据');
      }
    }
    print('✅ 条件2完成: ${condition2Results.length}只股票通过涨跌幅筛选');
    print('📋 条件2通过的股票列表:');
    for (int i = 0; i < condition2Results.length; i++) {
      final ranking = condition2Results[i];
      final pctChg = _calculatePctChg(ranking.klineData);
      print('   ${i + 1}. ${ranking.stockInfo.name} (${ranking.stockInfo.symbol}) - 涨跌幅: ${pctChg.toStringAsFixed(2)}%');
    }
    
    // 更新进度提示
    setState(() {
      _currentProgressText = '条件2完成: ${condition2Results.length}只股票通过涨跌幅筛选\n下一步: 条件3 - 均线距离筛选';
    });

    // 条件3：按均线距离筛选（从条件2的结果中筛选）
        print('📊 条件3: 按均线距离筛选 (5日≤${_selectedCombination!.ma5Distance}%, 10日≤${_selectedCombination!.ma10Distance}%, 20日≤${_selectedCombination!.ma20Distance}%)');
    print('📅 基于选择日期: ${DateFormat('yyyy-MM-dd').format(_selectedCombination!.selectedDate)} 计算均线');
    List<StockRanking> condition3Results = [];
    
    // 获取需要计算均线的股票代码
    final List<String> tsCodesForMa = condition2Results.map((r) => r.stockInfo.tsCode).toList();
    print('📡 需要获取历史K线数据的股票: ${tsCodesForMa.length}只');
    
    // 更新进度提示
    setState(() {
      _currentProgressText = '条件3进行中: 正在获取${tsCodesForMa.length}只股票的历史K线数据...';
    });
    
    // 批量获取历史K线数据（基于选择日期）
    print('🔄 开始批量获取历史K线数据...');
    final Map<String, List<KlineData>> historicalData = 
        await StockPoolService.getBatchHistoricalKlineData(tsCodes: tsCodesForMa, days: 60, targetDate: _selectedCombination!.selectedDate);
    print('✅ 历史K线数据获取完成');
    
    for (int i = 0; i < condition2Results.length; i++) {
      final ranking = condition2Results[i];
      _currentStockIndex = i + 1;
      
      // 更新进度提示
      setState(() {
        _currentProgressText = '条件3进行中: 处理第${_currentStockIndex}/${condition2Results.length}只股票\n正在计算${ranking.stockInfo.name}的均线距离...';
      });
      
      final List<KlineData> historicalKlines = historicalData[ranking.stockInfo.tsCode] ?? [];
      
      if (historicalKlines.length >= 20) { // 确保有足够的数据计算20日均线
        // 计算均线
        final double ma5 = MaCalculationService.calculateMA5(historicalKlines);
        final double ma10 = MaCalculationService.calculateMA10(historicalKlines);
        final double ma20 = MaCalculationService.calculateMA20(historicalKlines);
        
        // 使用选择日期的收盘价作为当前价格
        final currentPrice = ranking.klineData.close;
        
        // 检查均线距离条件
        if (MaCalculationService.checkMaDistanceCondition(
          currentPrice,
          ma5,
          ma10,
          ma20,
          _selectedCombination!.ma5Distance,
          _selectedCombination!.ma10Distance,
          _selectedCombination!.ma20Distance,
          ranking.stockInfo.name, // 传入股票名称
        )) {
          condition3Results.add(ranking);
        }
      } else {
        print('⚠️ ${ranking.stockInfo.name} 历史数据不足 (${historicalKlines.length}天 < 20天)');
      }
    }
    print('✅ 条件3完成: ${condition3Results.length}只股票通过均线距离筛选');
    
    // 更新进度提示
    setState(() {
      _currentProgressText = '条件3完成: ${condition3Results.length}只股票通过均线距离筛选\n下一步: 条件4 - 连续天数筛选';
    });

    // 条件4：连续天数筛选（从条件3的结果中筛选）
    print('📈 条件4: 连续${_selectedCombination!.consecutiveDays}天收盘价高于20日线筛选');
    List<StockRanking> condition4Results = [];
    _totalStocks = condition3Results.length;
    
    for (int i = 0; i < condition3Results.length; i++) {
      final ranking = condition3Results[i];
      _currentStockIndex = i + 1;
      
      // 更新进度提示
      setState(() {
        _currentProgressText = '条件5进行中: 处理第${_currentStockIndex}/${_totalStocks}只股票\n正在检查${ranking.stockInfo.name}的连续天数条件...';
      });
      // 获取历史K线数据用于计算20日均线（基于选择日期）
      final historicalKlines = await StockPoolService.getHistoricalKlineData(
        tsCode: ranking.stockInfo.tsCode, 
        days: 60, // 获取60天数据确保有足够交易日数据计算20日均线
        targetDate: _selectedCombination!.selectedDate
      );
      
      if (historicalKlines.length >= 20) {
        // 找到选择日期在历史数据中的索引
        int selectedDateIndex = -1;
        final selectedDateStr = DateFormat('yyyyMMdd').format(_selectedCombination!.selectedDate);
        for (int i = 0; i < historicalKlines.length; i++) {
          if (historicalKlines[i].tradeDate == selectedDateStr) {
            selectedDateIndex = i;
            break;
          }
        }
        
        if (selectedDateIndex == -1) {
          print('⚠️ ${ranking.stockInfo.name} 未找到选择日期数据');
          continue;
        }
        
        // 使用新的连续天数检查方法
        final meetsCondition = MaCalculationService.checkConsecutiveDaysAboveMA20(
          historicalKlines,
          _selectedCombination!.consecutiveDays,
          selectedDateIndex, // 从选择日期开始往前检查
        );
        
        if (meetsCondition) {
          condition4Results.add(ranking);
          print('✅ ${ranking.stockInfo.name} 连续${_selectedCombination!.consecutiveDays}天收盘价高于20日线');
        } else {
          print('❌ ${ranking.stockInfo.name} 不满足连续${_selectedCombination!.consecutiveDays}天收盘价高于20日线条件');
        }
      } else {
        print('⚠️ ${ranking.stockInfo.name} 历史数据不足');
      }
    }
    print('✅ 条件4完成: ${condition4Results.length}只股票通过连续天数筛选');
    
    // 更新进度提示
    setState(() {
      _currentProgressText = '条件4完成: ${condition4Results.length}只股票通过连续天数筛选\n下一步: 按成交额排序';
    });

    // 按成交额排序
    print('🔄 按成交额排序...');
    final sortedResults = StockRanking.sortByAmount(condition4Results);
    print('✅ 排序完成，最终结果: ${sortedResults.length}只股票');
    
    return sortedResults;
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
          _buildConditionRow('📈 涨跌幅', '${combination.pctChgMin}% ~ ${combination.pctChgMax}%'),
          _buildConditionRow('📊 5日线距离', '≤ ${combination.ma5Distance}%'),
          _buildConditionRow('📊 10日线距离', '≤ ${combination.ma10Distance}%'),
          _buildConditionRow('📊 20日线距离', '≤ ${combination.ma20Distance}%'),
          _buildConditionRow('⏰ 连续天数', '${combination.consecutiveDays}天收盘价高于20日线'),
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
