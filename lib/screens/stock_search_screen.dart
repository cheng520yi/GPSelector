import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/stock_info.dart';
import '../services/stock_pool_service.dart';
import 'stock_detail_screen.dart';

class StockSearchScreen extends StatefulWidget {
  const StockSearchScreen({super.key});

  @override
  State<StockSearchScreen> createState() => _StockSearchScreenState();
}

class _StockSearchScreenState extends State<StockSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<StockInfo> _allStocks = [];
  List<StockInfo> _filteredStocks = [];
  List<String> _searchHistory = [];
  bool _isLoading = true;
  bool _isSearching = false;

  static const String _searchHistoryKey = 'stock_search_history';

  @override
  void initState() {
    super.initState();
    _loadAllStocks();
    _loadSearchHistory();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllStocks() async {
    try {
      // 从stock_data.json加载所有股票数据（包括指数），而不是从股票池加载
      final List<StockInfo> allStocks = await StockPoolService.loadStockData();
      setState(() {
        _allStocks = allStocks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载股票数据失败: $e')),
        );
      }
    }
  }

  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_searchHistoryKey);
      if (historyJson != null) {
        final List<dynamic> history = json.decode(historyJson);
        setState(() {
          _searchHistory = history.cast<String>();
        });
      }
    } catch (e) {
      print('加载搜索记录失败: $e');
    }
  }

  Future<void> _saveSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_searchHistoryKey, json.encode(_searchHistory));
    } catch (e) {
      print('保存搜索记录失败: $e');
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    setState(() {
      _isSearching = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredStocks = [];
      } else {
        _filteredStocks = _allStocks.where((stock) {
          return stock.name.contains(query) ||
              stock.tsCode.contains(query) ||
              stock.symbol.contains(query);
        }).toList();
      }
    });
  }

  void _onSearchSubmitted(String query) {
    if (query.trim().isEmpty) return;
    
    // 添加到搜索记录
    setState(() {
      _searchHistory.remove(query.trim());
      _searchHistory.insert(0, query.trim());
      if (_searchHistory.length > 20) {
        _searchHistory = _searchHistory.sublist(0, 20);
      }
    });
    _saveSearchHistory();
  }

  void _onHistoryItemTap(String query) {
    // 尝试从搜索记录中提取股票代码（格式：XXXXXX.XX）
    // 搜索记录格式可能是："股票名称 股票代码" 或单独的股票代码
    final trimmedQuery = query.trim();
    
    // 尝试匹配股票代码格式（如：300035.SZ, 600170.SH等）
    final codePattern = RegExp(r'(\d{6}\.[A-Z]{2})');
    final match = codePattern.firstMatch(trimmedQuery);
    
    if (match != null) {
      // 找到了股票代码，尝试查找对应的股票
      final tsCode = match.group(1)!;
      final stock = _allStocks.firstWhere(
        (s) => s.tsCode == tsCode,
        orElse: () => StockInfo(tsCode: '', name: ''),
      );
      
      if (stock.tsCode.isNotEmpty) {
        // 找到了股票，直接进入详情页面
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => StockDetailScreen(
              stockInfo: stock,
            ),
          ),
        );
        return;
      }
    }
    
    // 如果没有找到股票代码或找不到对应股票，尝试按名称或完整匹配
    // 先尝试精确匹配股票名称
    final exactMatch = _allStocks.firstWhere(
      (s) => s.name == trimmedQuery,
      orElse: () => StockInfo(tsCode: '', name: ''),
    );
    
    if (exactMatch.tsCode.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => StockDetailScreen(
            stockInfo: exactMatch,
          ),
        ),
      );
      return;
    }
    
    // 尝试匹配股票代码
    final codeMatch = _allStocks.firstWhere(
      (s) => s.tsCode == trimmedQuery,
      orElse: () => StockInfo(tsCode: '', name: ''),
    );
    
    if (codeMatch.tsCode.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => StockDetailScreen(
            stockInfo: codeMatch,
          ),
        ),
      );
      return;
    }
    
    // 如果都没找到，执行搜索
    _searchController.text = query;
    _onSearchChanged();
    _onSearchSubmitted(query);
  }

  void _deleteHistoryItem(String query) {
    setState(() {
      _searchHistory.remove(query);
    });
    _saveSearchHistory();
  }

  void _clearAllHistory() {
    setState(() {
      _searchHistory.clear();
    });
    _saveSearchHistory();
  }

  void _onStockTap(StockInfo stock) {
    // 添加到搜索记录
    final query = '${stock.name} ${stock.tsCode}';
    setState(() {
      _searchHistory.remove(query);
      _searchHistory.insert(0, query);
      if (_searchHistory.length > 20) {
        _searchHistory = _searchHistory.sublist(0, 20);
      }
    });
    _saveSearchHistory();

    // 导航到股票详情页面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StockDetailScreen(
          stockInfo: stock,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索股票'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // 搜索框
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '股票/功能/资讯/用户',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged();
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: _onSearchSubmitted,
                    autofocus: true,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    _onSearchSubmitted(_searchController.text);
                  },
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          // 内容区域
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _isSearching
                    ? _buildSearchResults()
                    : _buildSearchHistory(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_filteredStocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '未找到相关股票',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredStocks.length,
      itemBuilder: (context, index) {
        final stock = _filteredStocks[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              stock.symbol.isNotEmpty ? stock.symbol[0] : stock.name[0],
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          title: Text(stock.name),
          subtitle: Text('${stock.tsCode} ${stock.industry.isNotEmpty ? "· ${stock.industry}" : ""}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _onStockTap(stock),
        );
      },
    );
  }

  Widget _buildSearchHistory() {
    if (_searchHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '暂无搜索记录',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 搜索记录标题和清空按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '最近搜索',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: _clearAllHistory,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('清空'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        // 搜索记录列表（标签形式）
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _searchHistory.map<Widget>((query) {
                return InputChip(
                  label: Text(query),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => _deleteHistoryItem(query),
                  onPressed: () => _onHistoryItemTap(query),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

