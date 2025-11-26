import 'package:flutter/material.dart';
import '../models/stock_info.dart';
import '../models/kline_data.dart';
import '../models/favorite_group.dart';
import '../services/favorite_stock_service.dart';
import '../services/favorite_group_service.dart';
import '../services/stock_api_service.dart';
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
  String _sortType = 'price'; // price, pctChg, change
  bool _sortAscending = false; // false为降序，true为升序

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
        if (_groups.isNotEmpty && _selectedGroupId == 'default') {
          _selectedGroupId = _groups.first.id;
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
    final shouldUseRealTime = StockApiService.isTradingDay(now) &&
        StockApiService.isWithinRealTimeWindow();

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

    setState(() {
      _stocks = stocks;
      _stockData = stockDataMap;
    });

    // 应用排序
    _applySort();
  }

  void _applySort() {
    _stocks.sort((a, b) {
      final dataA = _stockData[a.tsCode];
      final dataB = _stockData[b.tsCode];
      
      if (dataA == null && dataB == null) return 0;
      if (dataA == null) return 1;
      if (dataB == null) return -1;

      int comparison = 0;
      switch (_sortType) {
        case 'price':
          comparison = dataA.close.compareTo(dataB.close);
          break;
        case 'pctChg':
          comparison = dataA.pctChg.compareTo(dataB.pctChg);
          break;
        case 'change':
          comparison = dataA.change.compareTo(dataB.change);
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
                );
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
              _loadData();
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
                  _loadData();
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
          _loadData();
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
        );
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          const Text(
            '排序:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 8),
          _buildSortChip('price', '最新'),
          const SizedBox(width: 8),
          _buildSortChip('pctChg', '涨幅'),
          const SizedBox(width: 8),
          _buildSortChip('change', '涨跌'),
          const Spacer(),
          IconButton(
            icon: Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _sortAscending = !_sortAscending;
              });
              _applySort();
            },
            tooltip: _sortAscending ? '升序' : '降序',
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String type, String label) {
    final isSelected = _sortType == type;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _sortType = type;
          });
          _applySort();
        }
      },
      selectedColor: Colors.blue[100],
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue[700] : Colors.black,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
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
          _loadData();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Row(
          children: [
            // 股票名称和代码
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stock.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stock.tsCode,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // 价格、涨幅、涨跌额
            if (data != null) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    data.close.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: priceColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${data.pctChg >= 0 ? "+" : ""}${data.pctChg.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 14,
                      color: priceColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${data.change >= 0 ? "+" : ""}${data.change.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: priceColor,
                    ),
                  ),
                ],
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
}

