import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/stock_info.dart';
import '../services/stock_pool_service.dart';
import '../services/stock_pool_config_service.dart';
import '../services/blacklist_service.dart';
import 'log_viewer_screen.dart';

class StockPoolConfigScreen extends StatefulWidget {
  const StockPoolConfigScreen({super.key});

  @override
  State<StockPoolConfigScreen> createState() => _StockPoolConfigScreenState();
}

class _StockPoolConfigScreenState extends State<StockPoolConfigScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StockPoolConfig _config = StockPoolConfig();
  bool _isLoading = false;
  bool _isUpdatingPool = false;
  bool _hasUnsavedChanges = false;
  
  // 股票池信息
  Map<String, dynamic> _poolInfo = {};
  
  // 更新进度相关
  String _updateProgressText = '';
  int _updateCurrentStep = 0;
  int _updateTotalSteps = 100;
  
  // 黑名单相关
  List<StockInfo> _blacklistStocks = [];
  List<StockInfo> _allStocks = [];
  bool _isLoadingStocks = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // 表单控制器
  final TextEditingController _minMarketValueController = TextEditingController();
  final TextEditingController _maxMarketValueController = TextEditingController();
  final TextEditingController _amountThresholdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadConfig();
    _loadPoolInfo();
    _loadBlacklistStocks();
    _loadAllStocks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _minMarketValueController.dispose();
    _maxMarketValueController.dispose();
    _amountThresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final config = await StockPoolConfigService.getConfig();
      print('🔧 加载配置: enableMarketValueFilter=${config.enableMarketValueFilter}, minMarketValue=${config.minMarketValue}, maxMarketValue=${config.maxMarketValue}');
      setState(() {
        _config = config;
        _updateControllers();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('加载配置失败: $e');
    }
  }

  void _updateControllers() {
    _minMarketValueController.text = _config.minMarketValue?.toString() ?? '';
    _maxMarketValueController.text = _config.maxMarketValue?.toString() ?? '';
    _amountThresholdController.text = _config.amountThreshold.toString();
  }

  void _updateConfigFromControllers() {
    final minMarketValue = _minMarketValueController.text.isNotEmpty 
        ? double.tryParse(_minMarketValueController.text) 
        : null;
    final maxMarketValue = _maxMarketValueController.text.isNotEmpty 
        ? double.tryParse(_maxMarketValueController.text) 
        : null;
    
    // 如果设置了总市值范围，自动启用总市值筛选
    final enableMarketValueFilter = _config.enableMarketValueFilter || 
        (minMarketValue != null || maxMarketValue != null);
    
    _config = _config.copyWith(
      enableMarketValueFilter: enableMarketValueFilter,
      minMarketValue: minMarketValue,
      maxMarketValue: maxMarketValue,
    );
  }

  Future<void> _saveConfig() async {
    try {
      // 从控制器获取值并更新配置
      final minMarketValue = _minMarketValueController.text.isNotEmpty 
          ? double.tryParse(_minMarketValueController.text) 
          : null;
      final maxMarketValue = _maxMarketValueController.text.isNotEmpty 
          ? double.tryParse(_maxMarketValueController.text) 
          : null;
      
      // 如果设置了总市值范围，自动启用总市值筛选
      final enableMarketValueFilter = _config.enableMarketValueFilter || 
          (minMarketValue != null || maxMarketValue != null);
      
      final updatedConfig = _config.copyWith(
        enableMarketValueFilter: enableMarketValueFilter,
        minMarketValue: minMarketValue,
        maxMarketValue: maxMarketValue,
        amountThreshold: double.tryParse(_amountThresholdController.text) ?? _config.amountThreshold,
        selectedDate: _config.selectedDate,
        autoUpdate: _config.autoUpdate,
        updateInterval: _config.updateInterval,
        enableRealtimeInterface: _config.enableRealtimeInterface,
      );
      
      print('💾 保存配置: enableMarketValueFilter=${updatedConfig.enableMarketValueFilter}, minMarketValue=${updatedConfig.minMarketValue}, maxMarketValue=${updatedConfig.maxMarketValue}');

      await StockPoolConfigService.saveConfig(updatedConfig);
      setState(() {
        _config = updatedConfig;
        _hasUnsavedChanges = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('配置已保存'),
            backgroundColor: Colors.green,
          ),
        );
        
        // 如果当前在更新页面，刷新显示
        if (_tabController.index == 1) {
          setState(() {
            // 触发更新页面重新构建以显示最新配置
          });
        }
      }
    } catch (e) {
      _showErrorDialog('保存配置失败: $e');
    }
  }

  Future<void> _loadPoolInfo() async {
    final localInfo = await StockPoolService.getLocalPoolInfo();
    print('📊 加载股票池信息: enableMarketValueFilter=${localInfo['enableMarketValueFilter']}, minMarketValue=${localInfo['minMarketValue']}, maxMarketValue=${localInfo['maxMarketValue']}');
    setState(() {
      final thresholdValue = localInfo['threshold'];
      if (thresholdValue is num) {
        localInfo['threshold'] = thresholdValue.toDouble();
      }
      _poolInfo = localInfo;
    });
  }

  Future<void> _loadBlacklistStocks() async {
    try {
      final blacklistStocks = await BlacklistService.getBlacklistStockInfo();
      setState(() {
        _blacklistStocks = blacklistStocks;
      });
    } catch (e) {
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
      _updateTotalSteps = 100;
    });

    try {
      // 使用当前配置进行股票池构建
      await StockPoolService.buildStockPool(
        forceRefresh: true,
        amountThreshold: _config.amountThreshold,
        minMarketValue: _config.minMarketValue,
        maxMarketValue: _config.maxMarketValue,
        targetDate: _config.selectedDate, // 使用选择的日期
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _updateCurrentStep = progress;
              if (progress <= 20) {
                _updateProgressText = '正在加载股票基础数据...';
              } else if (progress <= 25) {
                _updateProgressText = '正在准备获取K线数据...';
              } else if (progress <= 55) {
                _updateProgressText = '正在获取K线数据...';
              } else if (progress <= 60) {
                if (_config.enableMarketValueFilter) {
                  _updateProgressText = '正在准备获取总市值数据...';
                } else {
                  _updateProgressText = '正在筛选股票...';
                }
              } else if (progress <= 75) {
                if (_config.enableMarketValueFilter) {
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
      
      // 重新加载数据
      await _loadPoolInfo();
      await _loadAllStocks();
      
      if (mounted) {
        setState(() {
          _updateProgressText = '股票池更新完成！';
          _updateCurrentStep = 100;
        });
        
        // 构建详细的配置信息
        String configInfo = '成交额≥${_config.amountThreshold}亿元';
        if (_config.enableMarketValueFilter) {
          configInfo += '，总市值筛选已启用';
          if (_config.minMarketValue != null) {
            configInfo += '（最小${_config.minMarketValue}亿元';
          }
          if (_config.maxMarketValue != null) {
            configInfo += _config.minMarketValue != null ? '，最大${_config.maxMarketValue}亿元）' : '（最大${_config.maxMarketValue}亿元）';
          } else if (_config.minMarketValue != null) {
            configInfo += '）';
          }
        }
        configInfo += '，筛选日期：${DateFormat('yyyy-MM-dd').format(_config.selectedDate)}';
        
        String message = '股票池更新成功！\n使用配置：$configInfo';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        
        await Future.delayed(const Duration(seconds: 2));
        Navigator.of(context).pop(true); // 返回并传递更新标志
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

  Future<bool> _onWillPop() async {
    if (_hasUnsavedChanges) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('未保存的更改'),
          content: const Text('您有未保存的配置更改，是否要保存？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('不保存'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      
      if (result == true) {
        await _saveConfig();
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          await _onWillPop();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
          title: const Text('股票池配置'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
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
              icon: const Icon(Icons.save),
              onPressed: _hasUnsavedChanges ? _saveConfig : null,
              tooltip: '保存配置',
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case 'export':
                    await _exportConfig();
                    break;
                  case 'import':
                    await _importConfig();
                    break;
                  case 'reset':
                    await _resetConfig();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.download),
                    title: Text('导出配置'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    leading: Icon(Icons.upload),
                    title: Text('导入配置'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'reset',
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('重置配置'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.settings), text: '配置'),
              Tab(icon: Icon(Icons.update), text: '更新'),
              Tab(icon: Icon(Icons.block), text: '黑名单'),
            ],
          ),
        ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildConfigTab(),
                    _buildUpdateTab(),
                    _buildBlacklistTab(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildConfigTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 基础配置
          _buildConfigCard(
            title: '基础配置',
            icon: Icons.tune,
            color: Colors.blue,
            children: [
              // 成交额阈值
              TextFormField(
                controller: _amountThresholdController,
                decoration: const InputDecoration(
                  labelText: '成交额阈值（亿元）',
                  hintText: '例如：5.0',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  setState(() {
                    final parsed = double.tryParse(value);
                    if (parsed != null) {
                      _config = _config.copyWith(amountThreshold: parsed);
                    }
                    _hasUnsavedChanges = true;
                  });
                },
              ),
              const SizedBox(height: 16),
              
              // 日期选择
              InkWell(
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
                        '选择日期: ${DateFormat('yyyy-MM-dd').format(_config.selectedDate)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),

          // 接口配置
          _buildConfigCard(
            title: '接口配置',
            icon: Icons.api,
            color: Colors.purple,
            children: [
              SwitchListTile(
                title: const Text('启用首页筛选实时接口'),
                subtitle: const Text('仅影响首页从股票池筛选的操作'),
                value: _config.enableRealtimeInterface,
                onChanged: (value) async {
                  setState(() {
                    _config = _config.copyWith(enableRealtimeInterface: value);
                  });
                  try {
                    await StockPoolConfigService.setRealtimeInterfaceEnabled(value);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(value ? '已开启首页实时接口' : '已关闭首页实时接口'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('更新实时接口配置失败: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      setState(() {
                        _config = _config.copyWith(enableRealtimeInterface: !value);
                      });
                    }
                  }
                },
                activeColor: Colors.purple[400],
              ),
              const SizedBox(height: 8),
              ListTile(
                title: const Text('实时接口截止时间'),
                subtitle: Text(
                  _config.realtimeEndTime != null
                      ? '${_config.realtimeEndTime!.hour.toString().padLeft(2, '0')}:${_config.realtimeEndTime!.minute.toString().padLeft(2, '0')}'
                      : '未设置（默认24:00）',
                ),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final TimeOfDay? picked = await showTimePicker(
                    context: context,
                    initialTime: _config.realtimeEndTime ?? const TimeOfDay(hour: 16, minute: 30),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: ColorScheme.light(
                            primary: Colors.purple[400]!,
                            onPrimary: Colors.white,
                            surface: Colors.white,
                            onSurface: Colors.black,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    setState(() {
                      _config = _config.copyWith(realtimeEndTime: picked);
                    });
                    try {
                      await StockPoolConfigService.setRealtimeEndTime(picked);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已设置截止时间为 ${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('更新截止时间配置失败: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple[100]!),
                ),
                child: Text(
                  _config.enableRealtimeInterface
                      ? '开启后，当筛选日期为当天且在交易日 09:30 之后进行首页筛选时，将使用 iFinD 实时接口；股票池更新逻辑不受影响。\n\n如果设置了截止时间（如16:30），则在09:30-16:30之间使用iFinD接口，16:30后使用TuShare接口。如果未设置截止时间，则在09:30-24:00之间使用iFinD接口。'
                      : '开启后，当筛选日期为当天且在交易日 09:30 之后进行首页筛选时，将使用 iFinD 实时接口；股票池更新逻辑不受影响。',
                  style: TextStyle(
                    color: Colors.purple[700],
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 总市值筛选配置
          _buildConfigCard(
            title: '总市值筛选',
            icon: Icons.account_balance,
            color: Colors.orange,
            children: [
              SwitchListTile(
                title: const Text('启用总市值筛选'),
                subtitle: const Text('开启后将在股票池构建时应用总市值筛选'),
                value: _config.enableMarketValueFilter,
                onChanged: (value) {
                  setState(() {
                    _config = _config.copyWith(enableMarketValueFilter: value);
                    _hasUnsavedChanges = true;
                    if (!value) {
                      _minMarketValueController.clear();
                      _maxMarketValueController.clear();
                    }
                  });
                },
                activeColor: Colors.orange[600],
              ),
              if (_config.enableMarketValueFilter) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minMarketValueController,
                        decoration: const InputDecoration(
                          labelText: '最小总市值（亿元）',
                          hintText: '例如：100',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          setState(() => _hasUnsavedChanges = true);
                          _updateConfigFromControllers();
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text('至', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _maxMarketValueController,
                        decoration: const InputDecoration(
                          labelText: '最大总市值（亿元）',
                          hintText: '例如：1000',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          setState(() => _hasUnsavedChanges = true);
                          _updateConfigFromControllers();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          
          
          const SizedBox(height: 16),
          
          // 自动更新配置
          _buildConfigCard(
            title: '自动更新',
            icon: Icons.schedule,
            color: Colors.purple,
            children: [
              SwitchListTile(
                title: const Text('启用自动更新'),
                subtitle: const Text('定期自动更新股票池数据'),
                value: _config.autoUpdate,
                onChanged: (value) {
                  setState(() {
                    _config = _config.copyWith(autoUpdate: value);
                    _hasUnsavedChanges = true;
                  });
                },
                activeColor: Colors.purple[600],
              ),
              if (_config.autoUpdate) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _config.updateInterval,
                  decoration: const InputDecoration(
                    labelText: '更新间隔',
                    border: OutlineInputBorder(),
                  ),
                  items: [6, 12, 24, 48].map((hours) {
                    return DropdownMenuItem(
                      value: hours,
                      child: Text('每${hours}小时'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _config = _config.copyWith(updateInterval: value!);
                      _hasUnsavedChanges = true;
                    });
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 股票池信息卡片
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
                        '股票池信息',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('股票数量', '${_poolInfo['stockCount'] ?? 0}只'),
                  _buildInfoRow('最后更新', _poolInfo['lastUpdateTime'] != null 
                      ? DateFormat('yyyy-MM-dd HH:mm').format(_poolInfo['lastUpdateTime'])
                      : '从未更新'),
                  _buildInfoRow('数据状态', _poolInfo['isValid'] == true ? '有效' : '已过期'),
                  _buildInfoRow(
                    '成交额阈值',
                    '≥ ${((_poolInfo['threshold'] is num) ? (_poolInfo['threshold'] as num).toDouble() : 5.0).toStringAsFixed(2)}亿元',
                  ),
                  _buildInfoRow('筛选日期', _poolInfo['targetDate'] != null 
                      ? DateFormat('yyyy-MM-dd').format(_poolInfo['targetDate'])
                      : DateFormat('yyyy-MM-dd').format(_config.selectedDate)),
                  if (_poolInfo['enableMarketValueFilter'] == true) ...[
                    _buildInfoRow('总市值筛选', '已启用'),
                    if (_poolInfo['minMarketValue'] != null || _poolInfo['maxMarketValue'] != null)
                      _buildInfoRow('总市值范围', '${_poolInfo['minMarketValue'] ?? 0}亿 - ${_poolInfo['maxMarketValue'] ?? '∞'}亿元'),
                  ] else ...[
                    _buildInfoRow('总市值筛选', '未启用'),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 当前配置卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        '当前配置',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildConfigInfoRow('成交额阈值', '≥ ${_config.amountThreshold}亿元'),
                  _buildConfigInfoRow('筛选日期', DateFormat('yyyy-MM-dd').format(_config.selectedDate)),
                  if (_config.enableMarketValueFilter) ...[
                    _buildConfigInfoRow('总市值筛选', '已启用'),
                    if (_config.minMarketValue != null || _config.maxMarketValue != null)
                      _buildConfigInfoRow('总市值范围', '${_config.minMarketValue ?? 0}亿 - ${_config.maxMarketValue ?? '∞'}亿元'),
                  ] else ...[
                    _buildConfigInfoRow('总市值筛选', '未启用'),
                  ],
                  _buildConfigInfoRow('首页实时接口', _config.enableRealtimeInterface ? '已启用（仅影响首页筛选）' : '未启用'),
                  _buildConfigInfoRow('自动更新', _config.autoUpdate ? '已启用 (每${_config.updateInterval}小时)' : '未启用'),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 更新操作卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.update, color: Colors.green[700]),
                      const SizedBox(width: 8),
                      Text(
                        '更新操作',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
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
                            Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '更新说明',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• 将根据当前配置筛选股票池\n• 自动排除ST股票\n• 数据本地持久化保存\n• 建议每日更新一次',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
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
                        backgroundColor: Colors.green[600],
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
        
        // 股票列表
        Expanded(
          child: _buildStockList(),
        ),
      ],
    );
  }

  Widget _buildConfigCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
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
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.blue[700],
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockList() {
    final filteredStocks = _searchQuery.isEmpty 
        ? _blacklistStocks 
        : _blacklistStocks.where((stock) {
            return stock.name.contains(_searchQuery) || 
                   stock.symbol.contains(_searchQuery) ||
                   stock.tsCode.contains(_searchQuery);
          }).toList();

    if (_isLoadingStocks) {
      return const Center(child: CircularProgressIndicator());
    }

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
        return _buildStockCard(stock);
      },
    );
  }

  Widget _buildStockCard(StockInfo stock) {
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

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _config.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _config.selectedDate) {
      setState(() {
        _config = _config.copyWith(selectedDate: picked);
        _hasUnsavedChanges = true;
      });
    }
  }

  Future<void> _exportConfig() async {
    try {
      final configJson = await StockPoolConfigService.exportConfig();
      await Clipboard.setData(ClipboardData(text: configJson));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('配置已复制到剪贴板'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showErrorDialog('导出配置失败: $e');
    }
  }

  Future<void> _importConfig() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != null) {
        await StockPoolConfigService.importConfig(clipboardData!.text!);
        await _loadConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('配置导入成功'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        _showErrorDialog('剪贴板中没有配置数据');
      }
    } catch (e) {
      _showErrorDialog('导入配置失败: $e');
    }
  }

  Future<void> _resetConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认重置'),
        content: const Text('确定要重置所有配置为默认值吗？此操作不可撤销。'),
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
        await StockPoolConfigService.resetToDefault();
        await _loadConfig();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('配置已重置为默认值'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        _showErrorDialog('重置配置失败: $e');
      }
    }
  }
}
