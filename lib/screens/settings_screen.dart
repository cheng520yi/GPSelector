import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/stock_info.dart';
import '../services/stock_pool_service.dart';
import '../services/blacklist_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isUpdatingPool = false;
  List<StockInfo> _blacklistStocks = [];
  List<StockInfo> _allStocks = [];
  bool _isLoadingBlacklist = false;
  bool _isLoadingStocks = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  
  // 总市值筛选相关
  final TextEditingController _minMarketValueController = TextEditingController();
  final TextEditingController _maxMarketValueController = TextEditingController();
  bool _enableMarketValueFilter = false;
  
  // 股票池更新进度相关
  String _updateProgressText = '';
  int _updateCurrentStep = 0;
  int _updateTotalSteps = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBlacklistStocks();
    _loadAllStocks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _minMarketValueController.dispose();
    _maxMarketValueController.dispose();
    super.dispose();
  }

  Future<void> _loadBlacklistStocks() async {
    setState(() {
      _isLoadingBlacklist = true;
    });
    
    try {
      final blacklistStocks = await BlacklistService.getBlacklistStockInfo();
      setState(() {
        _blacklistStocks = blacklistStocks;
        _isLoadingBlacklist = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingBlacklist = false;
      });
      _showErrorDialog('加载黑名单失败: $e');
    }
  }

  Future<void> _loadAllStocks() async {
    setState(() {
      _isLoadingStocks = true;
    });
    
    try {
      final localData = await StockPoolService.loadStockPoolFromLocal();
      final List<StockInfo> stockPool = localData['stockPool'] as List<StockInfo>;
      setState(() {
        _allStocks = stockPool;
        _isLoadingStocks = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingStocks = false;
      });
      _showErrorDialog('加载股票池失败: $e');
    }
  }

  Future<void> _updateStockPool() async {
    setState(() {
      _isUpdatingPool = true;
      _updateProgressText = '开始更新股票池...';
      _updateCurrentStep = 0;
      _updateTotalSteps = 100; // 使用百分比
    });

    try {
      // 解析总市值筛选条件
      double? minMarketValue;
      double? maxMarketValue;
      
      if (_enableMarketValueFilter) {
        if (_minMarketValueController.text.isNotEmpty) {
          minMarketValue = double.tryParse(_minMarketValueController.text);
        }
        if (_maxMarketValueController.text.isNotEmpty) {
          maxMarketValue = double.tryParse(_maxMarketValueController.text);
        }
      }
      
      // 实际执行股票池构建，使用真实的进度回调
      await StockPoolService.buildStockPool(
        forceRefresh: true,
        minMarketValue: minMarketValue,
        maxMarketValue: maxMarketValue,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _updateCurrentStep = progress;
              // 根据进度更新文本
              if (progress <= 20) {
                _updateProgressText = '正在加载股票基础数据...';
              } else if (progress <= 25) {
                _updateProgressText = '正在准备获取K线数据...';
              } else if (progress <= 55) {
                _updateProgressText = '正在获取K线数据...';
              } else if (progress <= 60) {
                if (_enableMarketValueFilter) {
                  _updateProgressText = '正在准备获取总市值数据...';
                } else {
                  _updateProgressText = '正在筛选股票...';
                }
              } else if (progress <= 75) {
                if (_enableMarketValueFilter) {
                  _updateProgressText = '正在获取总市值数据...';
                } else {
                  _updateProgressText = '正在筛选股票...';
                }
              } else if (progress <= 85) {
                _updateProgressText = '正在筛选股票...';
              } else if (progress <= 90) {
                _updateProgressText = '正在更新缓存...';
              } else if (progress <= 95) {
                _updateProgressText = '正在保存数据...';
              } else {
                _updateProgressText = '正在完成更新...';
              }
            });
          }
        },
      );
      
      // 重新加载股票池数据
      setState(() {
        _updateProgressText = '正在重新加载股票池数据...';
        _updateCurrentStep = 95;
      });
      
      await _loadAllStocks(); // 重新加载股票池数据
      
      if (mounted) {
        setState(() {
          _updateProgressText = '股票池更新完成！';
          _updateCurrentStep = 100;
        });
        
        String message = '股票池更新成功！';
        if (_enableMarketValueFilter) {
          message += '（已应用总市值筛选）';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );
        
        // 延迟一下再返回首页，让用户看到完成状态
        await Future.delayed(const Duration(seconds: 1));
        
        // 通知首页刷新股票池信息
        Navigator.of(context).pop(true); // 返回首页并传递更新标志
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _updateProgressText = '更新失败: $e';
        });
        _showErrorDialog('更新股票池失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingPool = false;
        });
      }
    }
  }

  Future<void> _addToBlacklist(StockInfo stock) async {
    try {
      final success = await BlacklistService.addToBlacklist(stock.tsCode);
      if (success) {
        await _loadBlacklistStocks();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已添加 ${stock.name} 到黑名单'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      _showErrorDialog('添加到黑名单失败: $e');
    }
  }

  Future<void> _removeFromBlacklist(StockInfo stock) async {
    try {
      final success = await BlacklistService.removeFromBlacklist(stock.tsCode);
      if (success) {
        await _loadBlacklistStocks();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已从黑名单移除 ${stock.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      _showErrorDialog('从黑名单移除失败: $e');
    }
  }

  Future<void> _clearBlacklist() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有黑名单吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await BlacklistService.clearBlacklist();
        await _loadBlacklistStocks();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已清空黑名单'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        _showErrorDialog('清空黑名单失败: $e');
      }
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

  List<StockInfo> get _filteredStocks {
    if (_searchQuery.isEmpty) return _allStocks;
    return _allStocks.where((stock) {
      return stock.name.contains(_searchQuery) || 
             stock.symbol.contains(_searchQuery) ||
             stock.tsCode.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.update), text: '更新缓存'),
            Tab(icon: Icon(Icons.tune), text: '股票池配置'),
            Tab(icon: Icon(Icons.block), text: '黑名单管理'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUpdateCacheTab(),
          _buildPoolConfigTab(),
          _buildBlacklistTab(),
        ],
      ),
    );
  }

  Widget _buildUpdateCacheTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        '股票池说明',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '• 股票池包含成交额≥5亿元的股票\n• 自动排除ST股票\n• 数据本地持久化保存\n• 建议每日更新一次',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isUpdatingPool ? null : _updateStockPool,
                      icon: _isUpdatingPool 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.update),
                      label: Text(_isUpdatingPool ? '更新中...' : '更新股票池'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  // 进度显示
                  if (_isUpdatingPool) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '更新进度',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _updateProgressText,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue[700],
                            ),
                          ),
                          if (_updateTotalSteps > 0) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _updateCurrentStep / _updateTotalSteps,
                              backgroundColor: Colors.blue[100],
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_updateCurrentStep}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoolConfigTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Text(
                        '总市值筛选配置',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '设置总市值筛选条件，只保留指定市值范围内的股票。\n单位：亿元',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('启用总市值筛选'),
                    subtitle: const Text('开启后将在股票池构建时应用总市值筛选'),
                    value: _enableMarketValueFilter,
                    onChanged: (value) {
                      setState(() {
                        _enableMarketValueFilter = value;
                        if (!value) {
                          _minMarketValueController.clear();
                          _maxMarketValueController.clear();
                        }
                      });
                    },
                    activeColor: Colors.orange[600],
                  ),
                  if (_enableMarketValueFilter) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minMarketValueController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '最小总市值（亿元）',
                              hintText: '例如：100',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text('至', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _maxMarketValueController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '最大总市值（亿元）',
                              hintText: '例如：1000',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '提示：留空表示不限制该方向。例如：只填最小值100，表示总市值≥100亿元的股票。',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlacklistTab() {
    return Column(
      children: [
        // 搜索栏
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索股票名称、代码或ts_code',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        
        // 黑名单统计
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.block, color: Colors.orange[700], size: 20),
              const SizedBox(width: 8),
              Text(
                '黑名单: ${_blacklistStocks.length}只股票',
                style: TextStyle(
                  color: Colors.orange[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_blacklistStocks.isNotEmpty)
                TextButton(
                  onPressed: _clearBlacklist,
                  child: Text(
                    '清空',
                    style: TextStyle(color: Colors.orange[700]),
                  ),
                ),
            ],
          ),
        ),
        
        const SizedBox(height: 8),
        
        // 标签页
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTabButton(
                  '黑名单股票',
                  _blacklistStocks.length,
                  _tabController.index == 0,
                  () => _tabController.animateTo(0),
                ),
              ),
              Expanded(
                child: _buildTabButton(
                  '全部股票',
                  _allStocks.length,
                  _tabController.index == 1,
                  () => _tabController.animateTo(1),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 8),
        
        // 股票列表
        Expanded(
          child: _tabController.index == 0
              ? _buildBlacklistStocks()
              : _buildAllStocks(),
        ),
      ],
    );
  }

  Widget _buildTabButton(String title, int count, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue[600] : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlacklistStocks() {
    if (_isLoadingBlacklist) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_blacklistStocks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '黑名单为空',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _blacklistStocks.length,
      itemBuilder: (context, index) {
        final stock = _blacklistStocks[index];
        return _buildBlacklistStockCard(stock);
      },
    );
  }

  Widget _buildAllStocks() {
    if (_isLoadingStocks) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredStocks = _filteredStocks;

    if (filteredStocks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '没有找到匹配的股票',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredStocks.length,
      itemBuilder: (context, index) {
        final stock = filteredStocks[index];
        return _buildAllStockCard(stock);
      },
    );
  }

  Widget _buildBlacklistStockCard(StockInfo stock) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange[100],
          child: Icon(Icons.block, color: Colors.orange[700]),
        ),
        title: Text(stock.name),
        subtitle: Text('${stock.symbol} | ${stock.market}'),
        trailing: IconButton(
          icon: const Icon(Icons.remove_circle, color: Colors.red),
          onPressed: () => _removeFromBlacklist(stock),
          tooltip: '从黑名单移除',
        ),
      ),
    );
  }

  Widget _buildAllStockCard(StockInfo stock) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue[100],
          child: Text(
            stock.name.substring(0, 1),
            style: TextStyle(
              color: Colors.blue[700],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(stock.name),
        subtitle: Text('${stock.symbol} | ${stock.market}'),
        trailing: FutureBuilder<bool>(
          future: BlacklistService.isInBlacklist(stock.tsCode),
          builder: (context, snapshot) {
            final isInBlacklist = snapshot.data ?? false;
            return IconButton(
              icon: Icon(
                isInBlacklist ? Icons.block : Icons.add_circle,
                color: isInBlacklist ? Colors.orange : Colors.green,
              ),
              onPressed: isInBlacklist
                  ? () => _removeFromBlacklist(stock)
                  : () => _addToBlacklist(stock),
              tooltip: isInBlacklist ? '从黑名单移除' : '添加到黑名单',
            );
          },
        ),
      ),
    );
  }
}
