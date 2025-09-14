import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/condition_combination_service.dart';
import 'condition_config_screen.dart';

class ConditionManagementScreen extends StatefulWidget {
  const ConditionManagementScreen({super.key});

  @override
  State<ConditionManagementScreen> createState() => _ConditionManagementScreenState();
}

class _ConditionManagementScreenState extends State<ConditionManagementScreen> {
  List<ConditionCombination> _combinations = [];
  bool _isLoading = true;
  String? _defaultCombinationId;

  @override
  void initState() {
    super.initState();
    _loadCombinations();
  }

  Future<void> _loadCombinations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final combinations = await ConditionCombinationService.getAllCombinations();
      final defaultId = await ConditionCombinationService.getDefaultCombinationId();
      
      setState(() {
        _combinations = combinations;
        _defaultCombinationId = defaultId;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('加载条件组合失败: $e');
    }
  }

  Future<void> _createNewCombination() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ConditionConfigScreen(),
      ),
    );

    if (result == true) {
      await _loadCombinations();
      // 通知首页刷新
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }

  Future<void> _editCombination(ConditionCombination combination) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConditionConfigScreen(editingCombination: combination),
      ),
    );

    if (result == true) {
      await _loadCombinations();
      // 通知首页刷新
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }

  Future<void> _setAsDefault(ConditionCombination combination) async {
    try {
      final success = await ConditionCombinationService.setDefaultCombination(combination.id);
      if (success) {
        setState(() {
          _defaultCombinationId = combination.id;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已将"${combination.name}"设为默认条件组合'),
              backgroundColor: Colors.green,
            ),
          );
          // 通知首页刷新
          Navigator.of(context).pop(true);
        }
      } else {
        _showErrorDialog('设置默认条件组合失败');
      }
    } catch (e) {
      _showErrorDialog('设置默认条件组合失败: $e');
    }
  }

  Future<void> _deleteCombination(ConditionCombination combination) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除条件组合"${combination.name}"吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await ConditionCombinationService.deleteCombination(combination.id);
        if (success) {
          await _loadCombinations();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('条件组合已删除'),
                backgroundColor: Colors.green,
              ),
            );
            // 通知首页刷新
            Navigator.of(context).pop(true);
          }
        } else {
          _showErrorDialog('删除失败，请重试');
        }
      } catch (e) {
        _showErrorDialog('删除失败: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('条件组合管理'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createNewCombination,
            tooltip: '新建条件组合',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _combinations.isEmpty
              ? _buildEmptyState()
              : _buildCombinationsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_list_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '暂无保存的条件组合',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角的"+"按钮创建第一个条件组合',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createNewCombination,
            icon: const Icon(Icons.add),
            label: const Text('创建条件组合'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinationsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _combinations.length,
      itemBuilder: (context, index) {
        final combination = _combinations[index];
        final isDefault = combination.id == _defaultCombinationId;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    combination.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '默认',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (combination.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    combination.description,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  combination.shortDescription,
                  style: TextStyle(
                    color: Colors.blue[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '创建时间: ${DateFormat('yyyy-MM-dd HH:mm').format(combination.createdAt)}',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case 'edit':
                    await _editCombination(combination);
                    break;
                  case 'set_default':
                    await _setAsDefault(combination);
                    break;
                  case 'delete':
                    await _deleteCombination(combination);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 8),
                      Text('编辑'),
                    ],
                  ),
                ),
                if (!isDefault)
                  const PopupMenuItem(
                    value: 'set_default',
                    child: Row(
                      children: [
                        Icon(Icons.star, size: 20),
                        SizedBox(width: 8),
                        Text('设为默认'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('删除', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
            onTap: () => _editCombination(combination),
          ),
        );
      },
    );
  }
}
