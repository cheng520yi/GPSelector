import 'package:flutter/material.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../models/favorite_group.dart';
import '../services/favorite_stock_service.dart';
import '../services/favorite_group_service.dart';
import '../services/stock_api_service.dart';
import '../services/stock_pool_service.dart';
import '../services/stock_pool_config_service.dart';
import 'stock_detail_screen.dart';
import 'stock_search_screen.dart';
import 'favorite_group_edit_screen.dart';
import 'stock_selector_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<FavoriteGroup> _groups = [];
  String _selectedGroupId = 'default';
  List<StockInfo> _stocks = [];
  Map<String, KlineData> _stockData = {}; // 股票代码 -> K线数据
  Map<String, KlineData> _indexData = {}; // 指数代码 -> K线数据
  bool _isLoading = false;
  String _marketStatus = '未开市'; // 开市、未开市、闭市
  String _sortType = 'marketCap'; // marketCap, pctChg, amount, price
  bool _sortAscending = false; // false为降序(箭头向上)，true为升序(箭头向下)

  // 三个固定指数
  static const List<Map<String, String>> _indices = [
    {'code': '000001.SH', 'name': '上证指数'},
    {'code': '399001.SZ', 'name': '深证成指'},
    {'code': '399006.SZ', 'name': '创业板指'},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _updateMarketStatus();
    // 每分钟更新一次市场状态
    _startMarketStatusTimer();
  }

  void _startMarketStatusTimer() {
    Future.delayed(const Duration(minutes: 1), () {
      if (mounted) {
        _updateMarketStatus();
        _startMarketStatusTimer();
      }
    });
  }

  void _updateMarketStatus() {
    final now = DateTime.now();
    final weekday = now.weekday;
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 100 + minute;

    String status;
    if (weekday >= 1 && weekday <= 5) {
      // 交易日
      if (currentTime >= 930 && currentTime <= 1130) {
        status = '开市';
      } else if (currentTime >= 1300 && currentTime <= 1500) {
        status = '开市';
      } else if (currentTime < 930) {
        status = '未开市';
      } else if (currentTime > 1500) {
        status = '闭市';
      } else {
        status = '午休';
      }
    } else {
      status = '未开市';
    }

    setState(() {
      _marketStatus = status;
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 加载分组
      final groups = await FavoriteGroupService.getAllGroups();
      setState(() {
        _groups = groups;
        // 只有在初始化时（_selectedGroupId为'default'）才设置默认选中第一个
        // 如果已经有选中的分组，检查该分组是否还存在，如果不存在才选择第一个
        if (_groups.isNotEmpty) {
          if (_selectedGroupId == 'default') {
            // 初始化时，选择第一个分组
            _selectedGroupId = _groups.first.id;
          } else {
            // 检查当前选中的分组是否还存在
            final currentGroupExists = _groups.any((g) => g.id == _selectedGroupId);
            if (!currentGroupExists) {
              // 如果当前选中的分组不存在了，选择第一个分组
              _selectedGroupId = _groups.first.id;
            }
            // 如果当前选中的分组存在，保持选中状态不变
          }
        }
      });

      // 加载指数数据
      await _loadIndexData();

      // 加载股票数据
      await _loadStockData();
    } catch (e) {
      print('加载数据失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadIndexData() async {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final currentTime = hour * 100 + minute;
    
    // 判断是否在交易时间（9:30-16:30）
    final isTradingTime = StockApiService.isTradingDay(now) && 
                          currentTime >= 930 && 
                          currentTime <= 1630;

    // 并行加载所有指数数据
    final futures = _indices.map((index) async {
      try {
        KlineData? data;
        
        if (isTradingTime) {
          // 交易时间（9:30-16:30）使用iFind接口
          try {
            final realTimeData = await StockApiService.getIFinDRealTimeData(
              tsCodes: [index['code']!],
            );
            if (realTimeData.containsKey(index['code']!)) {
              data = realTimeData[index['code']!];
            }
          } catch (e) {
            print('iFind接口获取${index['name']}失败: $e');
          }
        }
        
        // 如果不在交易时间或iFind获取失败，使用T-share接口获取最新交易日数据
        if (data == null) {
          // 对于指数，使用getKlineData方法（支持index_daily API）
          try {
            final klineDataList = await StockApiService.getKlineData(
              tsCode: index['code']!,
              kLineType: 'daily',
              days: 10, // 获取最近10天的数据，确保能找到最新交易日
              stockName: index['name'],
            );
            
            // 获取最新的交易日数据（列表已按日期排序，取最后一条）
            if (klineDataList.isNotEmpty) {
              data = klineDataList.last;
              print('✅ 获取${index['name']}最新交易日数据: ${data.tradeDate}, 收盘价: ${data.close}');
            } else {
              print('⚠️ ${index['name']}未找到历史数据');
            }
          } catch (e) {
            print('获取${index['name']}历史数据失败: $e');
            // 如果getKlineData失败，尝试使用getLatestTradingDayData作为备选
            try {
              data = await StockApiService.getLatestTradingDayData(
                tsCode: index['code']!,
              );
            } catch (e2) {
              print('getLatestTradingDayData也失败: $e2');
            }
          }
        }

        return MapEntry(index['code']!, data);
      } catch (e) {
        print('获取${index['name']}数据失败: $e');
        return MapEntry(index['code']!, null as KlineData?);
      }
    }).toList();

    // 等待所有数据加载完成
    final results = await Future.wait(futures);
    
    // 批量更新状态
    setState(() {
      for (final entry in results) {
        if (entry.value != null) {
          _indexData[entry.key] = entry.value!;
        }
      }
    });
  }

  Future<void> _loadStockData() async {
    // 获取当前分组中的股票代码
    final stockCodes = await FavoriteGroupService.getGroupStockCodes(_selectedGroupId);
    
    // 获取股票信息
    final allFavorites = await FavoriteStockService.getFavoriteStocks();
    final stocks = allFavorites.where((s) => stockCodes.contains(s.tsCode)).toList();

    if (stocks.isEmpty) {
      setState(() {
        _stocks = [];
        _stockData = {};
      });
      return;
    }

    // 并行获取股票数据
    final now = DateTime.now();
    final config = await StockPoolConfigService.getConfig();
    final currentTime = now.hour * 100 + now.minute;
    
    // 判断是否应该使用实时接口
    bool shouldUseRealTime = false;
    if (StockApiService.isTradingDay(now) && currentTime >= 930) {
      if (config.enableRealtimeInterface) {
        // 开关打开时，检查是否在配置的时间窗口内
        final endTime = config.realtimeEndTime ?? const TimeOfDay(hour: 24, minute: 0);
        final endTimeMinutes = endTime.hour * 100 + endTime.minute;
        if (currentTime <= endTimeMinutes) {
          shouldUseRealTime = true;
        }
      } else {
        // 开关关闭时，9:30-24:00都使用iFinD接口
        shouldUseRealTime = true;
      }
    }

    final Map<String, KlineData> stockDataMap = {};

    if (shouldUseRealTime && stocks.length <= 50) {
      // 如果股票数量较少，尝试批量获取实时数据
      try {
        final tsCodes = stocks.map((s) => s.tsCode).toList();
        final realTimeData = await StockApiService.getIFinDRealTimeData(
          tsCodes: tsCodes,
        );
        stockDataMap.addAll(realTimeData);
      } catch (e) {
        print('批量获取实时数据失败: $e');
      }
    }

    // 并行获取缺失的股票数据
    final futures = stocks.map((stock) async {
      if (stockDataMap.containsKey(stock.tsCode)) {
        return MapEntry(stock.tsCode, stockDataMap[stock.tsCode]!);
      }
      
      try {
        KlineData? data;
        if (shouldUseRealTime && !stockDataMap.containsKey(stock.tsCode)) {
          // 尝试获取实时数据
          try {
            final realTimeData = await StockApiService.getIFinDRealTimeData(
              tsCodes: [stock.tsCode],
            );
            if (realTimeData.containsKey(stock.tsCode)) {
              data = realTimeData[stock.tsCode];
            }
          } catch (e) {
            // 实时数据获取失败，继续使用历史数据
          }
        }

        // 如果实时数据获取失败，使用历史数据
        if (data == null) {
          data = await StockApiService.getLatestTradingDayData(
            tsCode: stock.tsCode,
          );
        }

        return MapEntry(stock.tsCode, data);
      } catch (e) {
        print('获取${stock.name}数据失败: $e');
        return MapEntry(stock.tsCode, null as KlineData?);
      }
    }).toList();

    // 等待所有数据加载完成
    final results = await Future.wait(futures);
    
    // 合并结果
    for (final entry in results) {
      if (entry.value != null) {
        stockDataMap[entry.key] = entry.value!;
      }
    }

    // 检查并补充缺失的总市值数据
    final stocksWithMarketValue = await _supplementMarketValueData(stocks);

    setState(() {
      _stocks = stocksWithMarketValue;
      _stockData = stockDataMap;
    });

    // 应用排序
    _applySort();
  }

  // 补充缺失的总市值数据
  Future<List<StockInfo>> _supplementMarketValueData(List<StockInfo> stocks) async {
    // 找出没有总市值的股票
    final stocksWithoutMarketValue = stocks.where((s) => s.totalMarketValue == null || s.totalMarketValue == 0).toList();
    
    if (stocksWithoutMarketValue.isEmpty) {
      return stocks;
    }

    try {
      final tsCodes = stocksWithoutMarketValue.map((s) => s.tsCode).toList();
      print('📊 发现 ${tsCodes.length} 只股票缺少总市值，开始补充...');
      
      // 使用StockPoolService获取总市值数据
      final marketValueMap = await StockPoolService.getBatchMarketValueDataSingleRequest(
        tsCodes: tsCodes,
        targetDate: null, // 获取最新数据
      );

      print('✅ 成功获取 ${marketValueMap.length} 只股票的总市值数据');

      // 创建新的StockInfo列表，更新总市值
      final updatedStocks = stocks.map((stock) {
        if (stock.totalMarketValue == null || stock.totalMarketValue == 0) {
          final marketValue = marketValueMap[stock.tsCode];
          if (marketValue != null && marketValue > 0) {
            // 创建新的StockInfo对象，包含总市值
            return StockInfo(
              tsCode: stock.tsCode,
              name: stock.name,
              symbol: stock.symbol,
              area: stock.area,
              industry: stock.industry,
              market: stock.market,
              listDate: stock.listDate,
              totalMarketValue: marketValue,
              circMarketValue: stock.circMarketValue,
            );
          }
        }
        return stock;
      }).toList();

      return updatedStocks;
    } catch (e) {
      print('❌ 补充总市值数据失败: $e');
      return stocks; // 失败时返回原始列表
    }
  }

  void _applySort() {
    _stocks.sort((a, b) {
      final dataA = _stockData[a.tsCode];
      final dataB = _stockData[b.tsCode];
      
      int comparison = 0;
      switch (_sortType) {
        case 'marketCap':
          final marketCapA = a.totalMarketValue ?? 0.0;
          final marketCapB = b.totalMarketValue ?? 0.0;
          comparison = marketCapA.compareTo(marketCapB);
          break;
        case 'pctChg':
          if (dataA == null && dataB == null) return 0;
          if (dataA == null) return 1;
          if (dataB == null) return -1;
          comparison = dataA.pctChg.compareTo(dataB.pctChg);
          break;
        case 'amount':
          if (dataA == null && dataB == null) return 0;
          if (dataA == null) return 1;
          if (dataB == null) return -1;
          comparison = dataA.amount.compareTo(dataB.amount);
          break;
        case 'price':
          if (dataA == null && dataB == null) return 0;
          if (dataA == null) return 1;
          if (dataB == null) return -1;
          comparison = dataA.close.compareTo(dataB.close);
          break;
      }

      return _sortAscending ? comparison : -comparison;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('股票'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getMarketStatusColor(),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _marketStatus,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.filter_list, size: 20),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const StockSelectorScreen(),
                  ),
                ).then((_) {
                  // 从筛选页面返回时，只刷新股票数据，不重新加载分组
                  _loadStockData();
                });
              },
              tooltip: '筛选',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const StockSearchScreen(),
                ),
              );
              // 从搜索页面返回时，只刷新股票数据，不重新加载分组
              _loadStockData();
            },
            tooltip: '添加股票',
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit_groups',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 20),
                    SizedBox(width: 8),
                    Text('分组管理'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'edit_groups') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const FavoriteGroupEditScreen(),
                  ),
                ).then((_) {
                  // 从分组管理页面返回时，只刷新股票数据，不重新加载分组，保持当前选中状态
                  _loadStockData();
                });
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            height: 48,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _groups.length,
              itemBuilder: (context, index) {
                final group = _groups[index];
                final isSelected = group.id == _selectedGroupId;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(group.name),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedGroupId = group.id;
                        });
                        _loadStockData();
                      }
                    },
                    selectedColor: Colors.red,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  // 指数显示区域
                  SliverToBoxAdapter(
                    child: _buildIndexSection(),
                  ),
                  // 排序栏
                  SliverToBoxAdapter(
                    child: _buildSortBar(),
                  ),
                  // 股票列表
                  _buildStockList(),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const StockSearchScreen(),
            ),
          );
          // 从搜索页面返回时，只刷新股票数据，不重新加载分组
          _loadStockData();
        },
        child: const Icon(Icons.add),
        tooltip: '添加股票',
      ),
    );
  }

  Widget _buildIndexSection() {
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
      child: Row(
        children: _indices.map((index) {
          final data = _indexData[index['code']!];
          return Expanded(
            child: _buildIndexItem(
              index['name']!,
              index['code']!,
              data,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildIndexItem(String name, String tsCode, KlineData? data) {
    final isRising = data != null && data.close >= data.preClose;
    final priceColor = isRising ? Colors.red : Colors.green;

    // 创建指数StockInfo对象
    final indexStockInfo = StockInfo(
      tsCode: tsCode,
      name: name,
      symbol: tsCode.split('.').first,
      area: tsCode.endsWith('.SH') ? '上海' : '深圳',
      industry: '指数',
      market: tsCode.endsWith('.SH') ? '上交所' : '深交所',
    );

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => StockDetailScreen(
              stockInfo: indexStockInfo,
              currentKlineData: data,
            ),
          ),
        ).then((_) {
          // 从指数详情页返回时，只刷新股票数据，不重新加载分组
          _loadStockData();
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            if (data != null) ...[
              // 指数值着重显示
              Text(
                data.close.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: priceColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // 涨跌幅作为主要显示，字体更大更突出
              Text(
                '${data.pctChg >= 0 ? "+" : ""}${data.pctChg.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: priceColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${data.change >= 0 ? "+" : ""}${data.change.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 11,
                  color: priceColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ] else
              const Text(
                '--',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getMarketStatusColor() {
    switch (_marketStatus) {
      case '开市':
        return Colors.green;
      case '闭市':
        return Colors.orange;
      case '午休':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildSortBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          // 左侧占位，与列表中的名称/代码区域对齐（flex: 2）
          Expanded(
            flex: 2,
            child: Row(
              children: [
                const Text(
                  '排序:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // 总市值按钮（改为"总值"）
          Expanded(
            flex: 1,
            child: _buildSortChip('marketCap', '总值'),
          ),
          const SizedBox(width: 4),
          // 涨幅按钮
          Expanded(
            flex: 1,
            child: _buildSortChip('pctChg', '涨幅'),
          ),
          const SizedBox(width: 4),
          // 成交额按钮（改为"成交"）
          Expanded(
            flex: 1,
            child: _buildSortChip('amount', '成交'),
          ),
          const SizedBox(width: 4),
          // 价格按钮
          Expanded(
            flex: 1,
            child: _buildSortChip('price', '价格'),
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String type, String label) {
    final isSelected = _sortType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_sortType == type) {
            // 同一个按钮，切换升降序
            _sortAscending = !_sortAscending;
          } else {
            // 切换排序字段时，默认降序（箭头向上）
            _sortType = type;
            _sortAscending = false;
          }
          _applySort();
        });
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[100] : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.blue[300]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue[700] : Colors.black,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            if (isSelected) ...[
              const SizedBox(width: 2),
              Icon(
                _sortAscending ? Icons.arrow_downward : Icons.arrow_upward,
                size: 14,
                color: Colors.blue[700],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStockList() {
    if (_stocks.isEmpty) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 200,
          child: Center(
            child: Text('暂无股票'),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final stock = _stocks[index];
          final data = _stockData[stock.tsCode];
          return _buildStockItem(stock, data);
        },
        childCount: _stocks.length,
      ),
    );
  }

  Widget _buildStockItem(StockInfo stock, KlineData? data) {
    final isRising = data != null && data.close >= data.preClose;
    final priceColor = isRising ? Colors.red : Colors.green;

    // 格式化总市值（亿元）
    String formatMarketCap(double? value) {
      if (value == null || value == 0) return '--';
      if (value >= 10000) {
        return '${(value / 10000).toStringAsFixed(2)}万亿';
      } else if (value >= 1) {
        return '${value.toStringAsFixed(2)}亿';
      } else {
        return '${(value * 10000).toStringAsFixed(0)}万';
      }
    }

    // 格式化成交额（亿元）
    String formatAmount(double? value) {
      if (value == null || value == 0) return '--';
      final amountInYi = value / 100000; // 千元转亿元
      if (amountInYi >= 100) {
        return '${amountInYi.toStringAsFixed(2)}亿';
      } else if (amountInYi >= 1) {
        return '${amountInYi.toStringAsFixed(2)}亿';
      } else {
        return '${(amountInYi * 10000).toStringAsFixed(0)}万';
      }
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => StockDetailScreen(
              stockInfo: stock,
              currentKlineData: data,
            ),
          ),
        ).then((_) {
          // 从详情页返回时，只刷新股票数据，不重新加载分组，保持当前选中状态
          _loadStockData();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 股票名称和代码
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stock.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    stock.tsCode,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // 数据列：按 总市值 -> 涨幅 -> 成交额 -> 价格 的顺序，和排序按钮对应
            if (data != null) ...[
              // 总市值
              Expanded(
                flex: 1,
                child: Text(
                  formatMarketCap(stock.totalMarketValue),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              // 涨跌幅
              Expanded(
                flex: 1,
                child: Text(
                  '${data.pctChg >= 0 ? "+" : ""}${data.pctChg.toStringAsFixed(2)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: priceColor,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              // 成交额
              Expanded(
                flex: 1,
                child: Text(
                  formatAmount(data.amount),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              // 价格
              Expanded(
                flex: 1,
                child: Text(
                  data.close.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: priceColor,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else
              const Expanded(
                child: Text(
                  '--',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
          ],
        ),
      ),
    );
  }
}


