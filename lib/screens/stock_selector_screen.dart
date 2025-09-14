import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/stock_ranking.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../services/stock_filter_service.dart';
import '../services/stock_pool_service.dart';
import '../services/ma_calculation_service.dart';
import '../services/test_api_service.dart';
import '../services/blacklist_service.dart';
import 'stock_pool_config_screen.dart';

class StockSelectorScreen extends StatefulWidget {
  const StockSelectorScreen({super.key});

  @override
  State<StockSelectorScreen> createState() => _StockSelectorScreenState();
}

class _StockSelectorScreenState extends State<StockSelectorScreen> {
  List<StockRanking> _stockRankings = [];
  bool _isLoading = false;
  double _selectedAmountThreshold = 5.0;
  DateTime _selectedDate = DateTime.now(); // 新增日期筛选
  double _selectedPctChgMin = -10.0; // 涨跌幅最小值
  double _selectedPctChgMax = 10.0;  // 涨跌幅最大值
  double _selectedMa5Distance = 5.0; // 距离5日均线距离
  double _selectedMa10Distance = 5.0; // 距离10日均线距离
  double _selectedMa20Distance = 5.0; // 距离20日均线距离
  int _selectedConsecutiveDays = 3; // 连续天数
  List<double> _amountThresholds = [5.0, 10.0, 20.0, 50.0, 100.0];
  List<int> _consecutiveDaysOptions = [3, 5, 10, 20]; // 连续天数选项
  Map<String, dynamic> _poolInfo = {};
  int _amountFilterCount = 0; // 符合成交额条件的股票数量
  String _currentProgressText = ''; // 当前进度提示文本
  int _currentStep = 0; // 当前步骤
  int _totalSteps = 6; // 总步骤数
  int _currentStockIndex = 0; // 当前处理的股票索引
  int _totalStocks = 0; // 总股票数
  final ScrollController _scrollController = ScrollController(); // 滚动控制器

  @override
  void initState() {
    super.initState();
    _updatePoolInfo();
    _calculateAmountFilterCount();
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

  Future<void> _loadStocks() async {
    // 收起键盘
    FocusScope.of(context).unfocus();
    
    print('🚀 开始筛选股票...');
    print('📊 筛选条件:');
    print('   - 成交额: ≥ ${_selectedAmountThreshold}亿元');
    print('   - 黑名单过滤: 移除黑名单中的股票');
    print('   - 日期: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
    print('   - 涨跌幅: ${_selectedPctChgMin}% ~ ${_selectedPctChgMax}%');
    print('   - 均线距离: 5日≤${_selectedMa5Distance}%, 10日≤${_selectedMa10Distance}%, 20日≤${_selectedMa20Distance}%');
    print('   - 连续天数: ${_selectedConsecutiveDays}天收盘价高于20日线');
    
    setState(() {
      _isLoading = true;
      _currentProgressText = '开始筛选...';
      _currentStep = 1;
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
        _currentStep = 0;
        _currentProgressText = '筛选完成！共找到 ${rankings.length} 只符合条件的股票';
      });
      
      _updatePoolInfo();
    } catch (e) {
      print('❌ 筛选过程出错: $e');
      setState(() {
        _isLoading = false;
        _currentProgressText = '';
        _currentStep = 0;
        _currentStockIndex = 0;
        _totalStocks = 0;
      });
      _showErrorDialog('加载股票数据失败: $e');
    }
  }

  Future<List<StockRanking>> _filterFromStockPool(List<StockInfo> stockPool, Map<String, KlineData> klineDataMap) async {
    print('🔍 开始筛选过程...');
    
    // 条件1：按成交额筛选（使用选择日期的数据）
    print('📊 条件1: 按成交额筛选 (≥ ${_selectedAmountThreshold}亿元)');
    print('📅 筛选日期: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
    List<StockRanking> condition1Results = [];
    
    // 获取选择日期的K线数据
    final List<String> tsCodes = stockPool.map((stock) => stock.tsCode).toList();
    print('📡 获取${DateFormat('yyyy-MM-dd').format(_selectedDate)}的K线数据，共${tsCodes.length}只股票');
    
    final selectedDateKlineData = await StockPoolService.getBatchDailyKlineData(
      tsCodes: tsCodes,
      targetDate: _selectedDate, // 使用选择日期
      batchSize: 20, // 每批20只股票
    );
    
    print('✅ 获取到${selectedDateKlineData.length}只股票的${DateFormat('yyyy-MM-dd').format(_selectedDate)}数据');
    
    for (StockInfo stock in stockPool) {
      final KlineData? klineData = selectedDateKlineData[stock.tsCode];
      
      if (klineData != null && klineData.amountInYi >= _selectedAmountThreshold) {
        print('   ✅ ${stock.name}: 成交额${klineData.amountInYi.toStringAsFixed(2)}亿元 (${klineData.tradeDate})');
        condition1Results.add(StockRanking(
          stockInfo: stock,
          klineData: klineData,
          amountInYi: klineData.amountInYi,
          rank: 0, // 临时排名，稍后会重新排序
        ));
      } else if (klineData != null) {
        print('   ❌ ${stock.name}: 成交额${klineData.amountInYi.toStringAsFixed(2)}亿元 < ${_selectedAmountThreshold}亿元 (${klineData.tradeDate})');
      } else {
        print('   ⚠️ ${stock.name}: 未找到${DateFormat('yyyy-MM-dd').format(_selectedDate)}的数据');
      }
    }
    print('✅ 条件1完成: ${condition1Results.length}只股票通过成交额筛选');
    
    // 更新成交额筛选数量提示和进度
    setState(() {
      _amountFilterCount = condition1Results.length;
      _currentStep = 2;
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
      _currentStep = 3;
      _currentProgressText = '黑名单过滤完成: ${blacklistFilteredResults.length}只股票通过黑名单过滤\n下一步: 条件2 - 涨跌幅筛选';
    });

    // 条件2：按涨跌幅筛选（从黑名单过滤后的结果中筛选）
    print('📈 条件2: 按涨跌幅筛选 (${_selectedPctChgMin}% ~ ${_selectedPctChgMax}%)');
    print('📅 筛选日期: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
    List<StockRanking> condition2Results = [];
    
    // 获取需要重新请求K线数据的股票代码
    final List<String> tsCodesForCondition2 = blacklistFilteredResults.map((r) => r.stockInfo.tsCode).toList();
    print('📡 需要获取${DateFormat('yyyy-MM-dd').format(_selectedDate)}K线数据的股票: ${tsCodesForCondition2.length}只');
    
    // 更新进度提示
    setState(() {
      _currentProgressText = '条件2进行中: 正在获取${tsCodesForCondition2.length}只股票的${DateFormat('yyyy-MM-dd').format(_selectedDate)}K线数据...';
    });
    
    // 批量获取指定日期的K线数据
    final Map<String, KlineData> condition2KlineData = 
        await StockPoolService.getBatchDailyKlineData(tsCodes: tsCodesForCondition2, targetDate: _selectedDate);
    print('✅ ${DateFormat('yyyy-MM-dd').format(_selectedDate)}K线数据获取完成');
    
    for (StockRanking ranking in blacklistFilteredResults) {
      final KlineData? selectedDateKline = condition2KlineData[ranking.stockInfo.tsCode];
      
      if (selectedDateKline != null) {
        // 计算涨跌幅：(close - pre_close) / pre_close * 100
        final double pctChg = selectedDateKline.preClose > 0 
            ? (selectedDateKline.close - selectedDateKline.preClose) / selectedDateKline.preClose * 100
            : 0.0;
        print('   ${ranking.stockInfo.name}: 涨跌幅 ${pctChg.toStringAsFixed(2)}% (${selectedDateKline.tradeDate})');
        
        if (pctChg >= _selectedPctChgMin && pctChg <= _selectedPctChgMax) {
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
        print('   ⚠️ ${ranking.stockInfo.name}: 未找到${DateFormat('yyyy-MM-dd').format(_selectedDate)}的K线数据');
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
      _currentStep = 4;
      _currentProgressText = '条件2完成: ${condition2Results.length}只股票通过涨跌幅筛选\n下一步: 条件3 - 均线距离筛选';
    });

    // 条件3：按均线距离筛选（从条件2的结果中筛选）
        print('📊 条件3: 按均线距离筛选 (5日≤${_selectedMa5Distance}%, 10日≤${_selectedMa10Distance}%, 20日≤${_selectedMa20Distance}%)');
    print('📅 基于选择日期: ${DateFormat('yyyy-MM-dd').format(_selectedDate)} 计算均线');
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
        await StockPoolService.getBatchHistoricalKlineData(tsCodes: tsCodesForMa, days: 60, targetDate: _selectedDate);
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
          _selectedMa5Distance,
          _selectedMa10Distance,
          _selectedMa20Distance,
        )) {
          condition3Results.add(ranking);
          print('✅ ${ranking.stockInfo.name} 通过均线距离筛选 (${DateFormat('yyyy-MM-dd').format(_selectedDate)}价格: ${currentPrice.toStringAsFixed(2)}, MA5: ${ma5.toStringAsFixed(2)}, MA10: ${ma10.toStringAsFixed(2)}, MA20: ${ma20.toStringAsFixed(2)})');
        } else {
          print('❌ ${ranking.stockInfo.name} 不满足均线距离条件 (${DateFormat('yyyy-MM-dd').format(_selectedDate)}价格: ${currentPrice.toStringAsFixed(2)}, MA5: ${ma5.toStringAsFixed(2)}, MA10: ${ma10.toStringAsFixed(2)}, MA20: ${ma20.toStringAsFixed(2)})');
        }
      } else {
        print('⚠️ ${ranking.stockInfo.name} 历史数据不足 (${historicalKlines.length}天 < 20天)');
      }
    }
    print('✅ 条件3完成: ${condition3Results.length}只股票通过均线距离筛选');
    
    // 更新进度提示
    setState(() {
      _currentStep = 5;
      _currentProgressText = '条件3完成: ${condition3Results.length}只股票通过均线距离筛选\n下一步: 条件4 - 连续天数筛选';
    });

    // 条件4：连续天数筛选（从条件3的结果中筛选）
    print('📈 条件4: 连续${_selectedConsecutiveDays}天收盘价高于20日线筛选');
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
        targetDate: _selectedDate
      );
      
      if (historicalKlines.length >= 20) {
        print('📊 ${ranking.stockInfo.name} 20日线计算: 基于${historicalKlines.length}个交易日数据');
        print('📅 选择日期: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
        print('📈 最近5个交易日数据:');
        for (int j = 0; j < math.min(5, historicalKlines.length); j++) {
          final kline = historicalKlines[j];
          print('   ${kline.tradeDate}: 收盘价=${kline.close.toStringAsFixed(2)}');
        }
        
        // 调试：显示数据排序情况
        print('🔍 ${ranking.stockInfo.name} 数据排序调试:');
        print('   总数据量: ${historicalKlines.length}天');
        print('   前5个日期: ${historicalKlines.take(5).map((k) => k.tradeDate).join(', ')}');
        print('   后5个日期: ${historicalKlines.reversed.take(5).map((k) => k.tradeDate).join(', ')}');
        
        // 找到选择日期在历史数据中的索引
        // historicalKlines是按时间正序排列的，最后一个是最近的日期
        int selectedDateIndex = -1;
        final selectedDateStr = DateFormat('yyyyMMdd').format(_selectedDate);
        for (int i = 0; i < historicalKlines.length; i++) {
          if (historicalKlines[i].tradeDate == selectedDateStr) {
            selectedDateIndex = i;
            break;
          }
        }
        
        if (selectedDateIndex == -1) {
          print('⚠️ ${ranking.stockInfo.name} 未找到选择日期 ${selectedDateStr} 的数据');
          print('   可用日期范围: ${historicalKlines.first.tradeDate} 到 ${historicalKlines.last.tradeDate}');
          continue;
        }
        
        print('🎯 ${ranking.stockInfo.name} 找到选择日期索引: ${selectedDateIndex}');
        print('   选择日期: ${selectedDateStr}');
        print('   该日期收盘价: ${historicalKlines[selectedDateIndex].close.toStringAsFixed(2)}');
        
        // 使用新的连续天数检查方法
        final meetsCondition = MaCalculationService.checkConsecutiveDaysAboveMA20(
          historicalKlines,
          _selectedConsecutiveDays,
          selectedDateIndex, // 从选择日期开始往前检查
        );
        
        if (meetsCondition) {
          condition4Results.add(ranking);
          print('✅ ${ranking.stockInfo.name} 连续${_selectedConsecutiveDays}天收盘价高于20日线 (基于${DateFormat('yyyy-MM-dd').format(_selectedDate)})');
        } else {
          print('❌ ${ranking.stockInfo.name} 不满足连续${_selectedConsecutiveDays}天收盘价高于20日线条件 (基于${DateFormat('yyyy-MM-dd').format(_selectedDate)})');
        }
      } else {
        print('⚠️ ${ranking.stockInfo.name} 历史数据不足 (${historicalKlines.length}天 < 20天)');
      }
    }
    print('✅ 条件4完成: ${condition4Results.length}只股票通过连续天数筛选');
    
    // 更新进度提示
    setState(() {
      _currentStep = 6;
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
                  await _calculateAmountFilterCount();
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
      padding: const EdgeInsets.all(16.0),
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
      child: Column(
        children: [
          // 条件1：成交额筛选
          _buildConditionCard(
            title: '条件1：成交额筛选',
            icon: Icons.attach_money,
            color: Colors.blue,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        value: _selectedAmountThreshold,
                        decoration: const InputDecoration(
                          labelText: '最低成交额',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: _amountThresholds.map((threshold) {
                          return DropdownMenuItem(
                            value: threshold,
                            child: Text('≥ ${threshold.toStringAsFixed(0)}亿元'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedAmountThreshold = value!;
                          });
                          // 成交额变化后只更新数量提示，不自动筛选
                          _calculateAmountFilterCount();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '股票池: ${_poolInfo['stockCount'] ?? 0}只',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 数量提示
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Text(
                    '符合条件: ${_amountFilterCount}只股票',
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 条件2：日期筛选
          _buildConditionCard(
            title: '条件2：日期筛选',
            icon: Icons.calendar_today,
            color: Colors.green,
            child: InkWell(
              onTap: _selectDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '选择日期: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 条件3：涨跌幅筛选
          _buildConditionCard(
            title: '条件3：涨跌幅筛选',
            icon: Icons.trending_up,
            color: Colors.orange,
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _selectedPctChgMin.toStringAsFixed(1),
                    decoration: const InputDecoration(
                      labelText: '涨跌幅最小值(%)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _selectedPctChgMin = double.tryParse(value) ?? -10.0;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: _selectedPctChgMax.toStringAsFixed(1),
                    decoration: const InputDecoration(
                      labelText: '涨跌幅最大值(%)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _selectedPctChgMax = double.tryParse(value) ?? 10.0;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 条件4：均线距离筛选
          _buildConditionCard(
            title: '条件4：均线距离筛选(%)',
            icon: Icons.show_chart,
            color: Colors.purple,
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _selectedMa5Distance.toStringAsFixed(1),
                    decoration: const InputDecoration(
                      labelText: '距离5日均线(%)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _selectedMa5Distance = double.tryParse(value) ?? 5.0;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: _selectedMa10Distance.toStringAsFixed(1),
                    decoration: const InputDecoration(
                      labelText: '距离10日均线(%)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _selectedMa10Distance = double.tryParse(value) ?? 5.0;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: _selectedMa20Distance.toStringAsFixed(1),
                    decoration: const InputDecoration(
                      labelText: '距离20日均线(%)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _selectedMa20Distance = double.tryParse(value) ?? 5.0;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 结果显示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              border: Border.all(color: Colors.green[200]!),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '筛选结果: ${_stockRankings.length} 只股票',
              style: TextStyle(
                color: Colors.green[700],
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          // 条件5：连续天数筛选
          _buildConditionCard(
            title: '条件5：连续天数筛选',
            icon: Icons.trending_up,
            color: Colors.purple,
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedConsecutiveDays,
                    decoration: const InputDecoration(
                      labelText: '连续天数',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _consecutiveDaysOptions.map((days) {
                      return DropdownMenuItem(
                        value: days,
                        child: Text('连续${days}天'),
                      );
                    }).toList(),
                    onChanged: _isLoading ? null : (value) {
                      setState(() {
                        _selectedConsecutiveDays = value!;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '收盘价高于20日线',
                      style: TextStyle(
                        color: Colors.purple[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 进度提示
          if (_currentProgressText.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
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
            // 排名和股票名称行
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isPositive ? Colors.red[50] : Colors.green[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${isPositive ? '+' : ''}${pctChg.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: isPositive ? Colors.red[700] : Colors.green[700],
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 成交额和成交量
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    '成交额',
                    '${ranking.amountInYi.toStringAsFixed(2)}亿元',
                    Colors.blue[700]!,
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    '成交量',
                    '${(ranking.klineData.vol / 10000).toStringAsFixed(0)}万手',
                    Colors.orange[700]!,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 添加到黑名单按钮
            SizedBox(
              width: double.infinity,
              child: FutureBuilder<bool>(
                future: BlacklistService.isInBlacklist(ranking.stockInfo.tsCode),
                builder: (context, snapshot) {
                  final isInBlacklist = snapshot.data ?? false;
                  return ElevatedButton.icon(
                    onPressed: () => _toggleBlacklist(ranking.stockInfo, isInBlacklist),
                    icon: Icon(isInBlacklist ? Icons.remove_circle : Icons.block),
                    label: Text(isInBlacklist ? '从黑名单移除' : '添加到黑名单'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isInBlacklist ? Colors.green[600] : Colors.orange[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, Color color) {
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
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildConditionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          // 内容区域
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
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

  // 检查是否需要更新缓存数据
  Future<bool> _checkIfNeedUpdateCache(Map<String, KlineData> klineDataMap) async {
    if (klineDataMap.isEmpty) {
      print('📊 缓存数据为空，需要更新');
      return true;
    }
    
    // 获取当前日期
    final now = DateTime.now();
    final todayStr = DateFormat('yyyyMMdd').format(now);
    
    // 检查缓存数据的日期
    int validDataCount = 0;
    int outdatedDataCount = 0;
    
    for (KlineData klineData in klineDataMap.values) {
      if (klineData.tradeDate == todayStr) {
        validDataCount++;
      } else {
        outdatedDataCount++;
      }
    }
    
    print('📊 缓存数据检查: 有效数据 $validDataCount 条，过期数据 $outdatedDataCount 条');
    
    // 如果有效数据少于总数的50%，则需要更新
    final totalCount = klineDataMap.length;
    final validRatio = validDataCount / totalCount;
    
    if (validRatio < 0.5) {
      print('📊 有效数据比例过低 (${(validRatio * 100).toStringAsFixed(1)}%)，需要更新缓存');
      return true;
    }
    
    print('📊 缓存数据有效，无需更新');
    return false;
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

  // 选择日期
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      print('📅 选择日期: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
    }
  }


  // 计算符合成交额条件的股票数量
  Future<void> _calculateAmountFilterCount() async {
    try {
      final localData = await StockPoolService.loadStockPoolFromLocal();
      List<StockInfo> stockPool = localData['stockPool'] as List<StockInfo>;
      Map<String, KlineData> klineDataMap = localData['klineData'] as Map<String, KlineData>;
      
      int count = 0;
      for (StockInfo stock in stockPool) {
        final KlineData? klineData = klineDataMap[stock.tsCode];
        if (klineData != null && klineData.amountInYi >= _selectedAmountThreshold) {
          count++;
        }
      }
      
      setState(() {
        _amountFilterCount = count;
      });
    } catch (e) {
      print('计算成交额筛选数量失败: $e');
    }
  }
}
