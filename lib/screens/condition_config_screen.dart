import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/condition_combination_service.dart';

class ConditionConfigScreen extends StatefulWidget {
  final ConditionCombination? editingCombination;

  const ConditionConfigScreen({
    super.key,
    this.editingCombination,
  });

  @override
  State<ConditionConfigScreen> createState() => _ConditionConfigScreenState();
}

class _ConditionConfigScreenState extends State<ConditionConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountThresholdController = TextEditingController();
  final _pctChgMinController = TextEditingController();
  final _pctChgMaxController = TextEditingController();
  final _ma5DistanceController = TextEditingController();
  final _ma10DistanceController = TextEditingController();
  final _ma20DistanceController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  int _selectedConsecutiveDays = 3;
  bool _isLoading = false;

  // 预设选项
  final List<double> _amountThresholds = [5.0, 10.0, 20.0, 50.0, 100.0];
  final List<int> _consecutiveDaysOptions = [3, 5, 10, 20];

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _amountThresholdController.dispose();
    _pctChgMinController.dispose();
    _pctChgMaxController.dispose();
    _ma5DistanceController.dispose();
    _ma10DistanceController.dispose();
    _ma20DistanceController.dispose();
    super.dispose();
  }

  void _initializeForm() {
    if (widget.editingCombination != null) {
      final combination = widget.editingCombination!;
      _nameController.text = combination.name;
      _descriptionController.text = combination.description;
      _amountThresholdController.text = combination.amountThreshold.toStringAsFixed(1);
      _selectedDate = combination.selectedDate;
      _pctChgMinController.text = combination.pctChgMin.toStringAsFixed(1);
      _pctChgMaxController.text = combination.pctChgMax.toStringAsFixed(1);
      _ma5DistanceController.text = combination.ma5Distance.toStringAsFixed(1);
      _ma10DistanceController.text = combination.ma10Distance.toStringAsFixed(1);
      _ma20DistanceController.text = combination.ma20Distance.toStringAsFixed(1);
      _selectedConsecutiveDays = combination.consecutiveDays;
    } else {
      // 设置默认值
      _nameController.text = '';
      _descriptionController.text = '';
      _amountThresholdController.text = '5.0';
      _pctChgMinController.text = '-10.0';
      _pctChgMaxController.text = '10.0';
      _ma5DistanceController.text = '5.0';
      _ma10DistanceController.text = '5.0';
      _ma20DistanceController.text = '5.0';
    }
  }

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
    }
  }

  Future<void> _saveCombination() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final combination = widget.editingCombination != null
          ? widget.editingCombination!.copyWith(
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim(),
              amountThreshold: double.parse(_amountThresholdController.text),
              selectedDate: _selectedDate,
              pctChgMin: double.parse(_pctChgMinController.text),
              pctChgMax: double.parse(_pctChgMaxController.text),
              ma5Distance: double.parse(_ma5DistanceController.text),
              ma10Distance: double.parse(_ma10DistanceController.text),
              ma20Distance: double.parse(_ma20DistanceController.text),
              consecutiveDays: _selectedConsecutiveDays,
              updatedAt: DateTime.now(),
            )
          : ConditionCombinationService.createCombination(
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim(),
              amountThreshold: double.parse(_amountThresholdController.text),
              selectedDate: _selectedDate,
              pctChgMin: double.parse(_pctChgMinController.text),
              pctChgMax: double.parse(_pctChgMaxController.text),
              ma5Distance: double.parse(_ma5DistanceController.text),
              ma10Distance: double.parse(_ma10DistanceController.text),
              ma20Distance: double.parse(_ma20DistanceController.text),
              consecutiveDays: _selectedConsecutiveDays,
            );

      final success = await ConditionCombinationService.saveCombination(combination);
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.editingCombination != null 
                  ? '条件组合已更新' 
                  : '条件组合已保存'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true); // 返回true表示保存成功
        }
      } else {
        if (mounted) {
          _showErrorDialog('保存失败，请重试');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('保存失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editingCombination != null ? '编辑条件组合' : '新建条件组合'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (widget.editingCombination != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteCombination,
              tooltip: '删除条件组合',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 基本信息
              _buildSectionCard(
                title: '基本信息',
                icon: Icons.info,
                color: Colors.blue,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '条件组合名称 *',
                      hintText: '例如：短线强势股筛选',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入条件组合名称';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: '描述',
                      hintText: '可选：描述这个条件组合的用途',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 成交额筛选
              _buildSectionCard(
                title: '成交额筛选',
                icon: Icons.attach_money,
                color: Colors.green,
                children: [
                  TextFormField(
                    controller: _amountThresholdController,
                    decoration: const InputDecoration(
                      labelText: '最低成交额(亿元) *',
                      hintText: '例如：5.0',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入最低成交额';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) {
                        return '请输入有效的成交额';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 日期筛选
              _buildSectionCard(
                title: '日期筛选',
                icon: Icons.calendar_today,
                color: Colors.orange,
                children: [
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
                            '选择日期: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 涨跌幅筛选
              _buildSectionCard(
                title: '涨跌幅筛选',
                icon: Icons.trending_up,
                color: Colors.purple,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _pctChgMinController,
                          decoration: const InputDecoration(
                            labelText: '涨跌幅最小值(%) *',
                            hintText: '例如：-10.0',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入最小值';
                            }
                            final min = double.tryParse(value);
                            if (min == null) {
                              return '请输入有效数值';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _pctChgMaxController,
                          decoration: const InputDecoration(
                            labelText: '涨跌幅最大值(%) *',
                            hintText: '例如：10.0',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入最大值';
                            }
                            final max = double.tryParse(value);
                            if (max == null) {
                              return '请输入有效数值';
                            }
                            final min = double.tryParse(_pctChgMinController.text);
                            if (min != null && max < min) {
                              return '最大值不能小于最小值';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 均线距离筛选
              _buildSectionCard(
                title: '均线距离筛选(%)',
                icon: Icons.show_chart,
                color: Colors.teal,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _ma5DistanceController,
                          decoration: const InputDecoration(
                            labelText: '距离5日均线(%) *',
                            hintText: '例如：5.0',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入5日均线距离';
                            }
                            final distance = double.tryParse(value);
                            if (distance == null || distance < 0) {
                              return '请输入有效距离';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _ma10DistanceController,
                          decoration: const InputDecoration(
                            labelText: '距离10日均线(%) *',
                            hintText: '例如：5.0',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入10日均线距离';
                            }
                            final distance = double.tryParse(value);
                            if (distance == null || distance < 0) {
                              return '请输入有效距离';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _ma20DistanceController,
                          decoration: const InputDecoration(
                            labelText: '距离20日均线(%) *',
                            hintText: '例如：5.0',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入20日均线距离';
                            }
                            final distance = double.tryParse(value);
                            if (distance == null || distance < 0) {
                              return '请输入有效距离';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 连续天数筛选
              _buildSectionCard(
                title: '连续天数筛选',
                icon: Icons.trending_up,
                color: Colors.indigo,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedConsecutiveDays,
                          decoration: const InputDecoration(
                            labelText: '连续天数 *',
                            border: OutlineInputBorder(),
                          ),
                          items: _consecutiveDaysOptions.map((days) {
                            return DropdownMenuItem(
                              value: days,
                              child: Text('连续${days}天'),
                            );
                          }).toList(),
                          onChanged: (value) {
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
                              color: Colors.indigo[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 保存按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveCombination,
                  icon: _isLoading 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isLoading ? '保存中...' : '保存条件组合'),
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
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
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
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCombination() async {
    if (widget.editingCombination == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除条件组合"${widget.editingCombination!.name}"吗？此操作不可撤销。'),
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
      setState(() {
        _isLoading = true;
      });

      try {
        final success = await ConditionCombinationService.deleteCombination(
          widget.editingCombination!.id,
        );

        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('条件组合已删除'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop(true); // 返回true表示删除成功
          }
        } else {
          if (mounted) {
            _showErrorDialog('删除失败，请重试');
          }
        }
      } catch (e) {
        if (mounted) {
          _showErrorDialog('删除失败: $e');
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }
}
