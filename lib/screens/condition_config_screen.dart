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

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  // 必填项
  double _amountThreshold = 20.0;

  // 可选项
  bool _enablePctChg = false;
  int _pctChgMin = -10; // -10 到 10
  int _pctChgMax = 10; // -10 到 10

  bool _enableMaDistance = false;
  MaDistanceConfig _ma5Config = MaDistanceConfig(enabled: false, distance: 5.0);
  MaDistanceConfig _ma10Config = MaDistanceConfig(enabled: false, distance: 5.0);
  MaDistanceConfig _ma20Config = MaDistanceConfig(enabled: false, distance: 5.0);

  bool _enableConsecutiveDays = false;
  ConsecutiveDaysConfig _consecutiveDaysConfig = ConsecutiveDaysConfig(
    enabled: false,
    days: 10,
    maType: 'ma20',
  );

  // 均线连续增长天数配置
  MaGrowthDaysConfigSet _maGrowthDaysConfig = MaGrowthDaysConfigSet(
    ma5Config: MaGrowthDaysConfig(enabled: false, days: 5),
    ma10Config: MaGrowthDaysConfig(enabled: false, days: 5),
    ma20Config: MaGrowthDaysConfig(enabled: false, days: 5),
  );

  // 成交额范围配置
  AmountRangeConfig _amountRangeConfig = AmountRangeConfig(
    enabled: false,
    minAmount: 0.0,
    maxAmount: 1000.0,
  );

  // 预设选项
  final List<double> _amountThresholds = [5.0, 10.0, 20.0, 50.0, 100.0];
  final List<int> _consecutiveDaysOptions = [3, 5, 10, 20];
  final List<int> _maGrowthDaysOptions = [1, 2, 3, 5, 10]; // 均线连续增长天数选项
  final List<String> _maTypes = ['ma5', 'ma10', 'ma20'];

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
    super.dispose();
  }

  void _initializeForm() {
    if (widget.editingCombination != null) {
      final combination = widget.editingCombination!;
      _nameController.text = combination.name;
      _descriptionController.text = combination.description;
      _amountThresholdController.text = combination.amountThreshold.toString();
      _selectedDate = combination.selectedDate;
      _amountThreshold = combination.amountThreshold;

      _enablePctChg = combination.enablePctChg;
      _pctChgMin = combination.pctChgMin;
      _pctChgMax = combination.pctChgMax;

      _enableMaDistance = combination.enableMaDistance;
      _ma5Config = combination.ma5Config;
      _ma10Config = combination.ma10Config;
      _ma20Config = combination.ma20Config;

      _enableConsecutiveDays = combination.enableConsecutiveDays;
      _consecutiveDaysConfig = combination.consecutiveDaysConfig;
      
      _maGrowthDaysConfig = combination.maGrowthDaysConfig;
      
      _amountRangeConfig = combination.amountRangeConfig;
    } else {
      _amountThresholdController.text = _amountThreshold.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editingCombination != null ? '编辑条件组合' : '新建条件组合'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _saveCombination,
              icon: const Icon(Icons.save, color: Colors.white),
              label: Text(
                widget.editingCombination != null ? '更新' : '保存',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
              _buildBasicInfoSection(),
              const SizedBox(height: 24),
              _buildRequiredConditionsSection(),
              const SizedBox(height: 24),
              _buildOptionalConditionsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[600]),
                const SizedBox(width: 8),
                Text(
                  '基本信息',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '条件组合名称 *',
                hintText: '请输入条件组合名称',
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
                hintText: '请输入条件组合描述（可选）',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequiredConditionsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.red[600]),
                const SizedBox(width: 8),
                Text(
                  '必填条件',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[600],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Text(
                    '必填',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // 成交额条件组
            _buildConditionGroup(
              title: '成交额条件',
              icon: Icons.attach_money,
              iconColor: Colors.blue,
              children: [
                _buildAmountThresholdField(),
              ],
            ),
            
            const SizedBox(height: 20),
            _buildDivider(),
            const SizedBox(height: 20),
            
            // 日期条件组
            _buildConditionGroup(
              title: '筛选日期',
              icon: Icons.calendar_today,
              iconColor: Colors.orange,
              children: [
                _buildDateField(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionalConditionsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Colors.orange[600]),
                const SizedBox(width: 8),
                Text(
                  '可选条件',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[600],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Text(
                    '可选',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // 价格相关条件组
            _buildConditionGroup(
              title: '价格条件',
              icon: Icons.trending_up,
              iconColor: Colors.blue,
              children: [
                _buildPctChgSection(),
              ],
            ),
            
            const SizedBox(height: 20),
            _buildDivider(),
            const SizedBox(height: 20),
            
            // 均线相关条件组
            _buildConditionGroup(
              title: '均线条件',
              icon: Icons.show_chart,
              iconColor: Colors.purple,
              children: [
                _buildMaDistanceSection(),
                const SizedBox(height: 16),
                _buildMaGrowthDaysSection(),
              ],
            ),
            
            const SizedBox(height: 20),
            _buildDivider(),
            const SizedBox(height: 20),
            
            // 时间相关条件组
            _buildConditionGroup(
              title: '时间条件',
              icon: Icons.access_time,
              iconColor: Colors.green,
              children: [
                _buildConsecutiveDaysSection(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionGroup({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.grey[300],
    );
  }

  Widget _buildAmountThresholdField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '成交额筛选',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _amountRangeConfig.enabled ? '范围模式' : '阈值模式',
                    style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: _amountRangeConfig.enabled,
                    onChanged: (value) {
                      setState(() {
                        _amountRangeConfig = AmountRangeConfig(
                          enabled: value,
                          minAmount: _amountRangeConfig.minAmount,
                          maxAmount: _amountRangeConfig.maxAmount,
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        if (!_amountRangeConfig.enabled) ...[
          // 阈值模式
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _amountThresholdController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: '请输入成交额阈值',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.blue[400]!),
                    ),
                    suffixText: '亿元',
                    suffixStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                    labelText: '最小成交额',
                    labelStyle: TextStyle(color: Colors.grey[700], fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入成交额阈值';
                    }
                    final amount = double.tryParse(value);
                    if (amount == null || amount <= 0) {
                      return '请输入有效的成交额阈值';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    final amount = double.tryParse(value);
                    if (amount != null) {
                      setState(() {
                        _amountThreshold = amount;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _amountThresholds.map((threshold) {
                    return FilterChip(
                      label: Text(
                        '${threshold.toStringAsFixed(0)}亿',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _amountThreshold == threshold ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      selected: _amountThreshold == threshold,
                      selectedColor: Colors.blue[100],
                      checkmarkColor: Colors.blue[700],
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _amountThreshold = threshold;
                            _amountThresholdController.text = threshold.toString();
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ] else ...[
          // 范围模式
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _amountRangeConfig.minAmount.toString(),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: '最小值',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.blue[400]!),
                          ),
                          suffixText: '亿',
                          suffixStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                          labelText: '最小成交额',
                          labelStyle: TextStyle(color: Colors.grey[700], fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入最小成交额';
                          }
                          final amount = double.tryParse(value);
                          if (amount == null || amount < 0) {
                            return '请输入有效的最小成交额';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          final amount = double.tryParse(value);
                          if (amount != null) {
                            setState(() {
                              _amountRangeConfig = AmountRangeConfig(
                                enabled: _amountRangeConfig.enabled,
                                minAmount: amount,
                                maxAmount: _amountRangeConfig.maxAmount,
                              );
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        '至',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: _amountRangeConfig.maxAmount >= 1000 ? '' : _amountRangeConfig.maxAmount.toString(),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: '最大值（空=无限制）',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.blue[400]!),
                          ),
                          suffixText: '亿',
                          suffixStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                          labelText: '最大成交额',
                          labelStyle: TextStyle(color: Colors.grey[700], fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            final amount = double.tryParse(value);
                            if (amount == null || amount <= _amountRangeConfig.minAmount) {
                              return '最大值必须大于最小值';
                            }
                          }
                          return null;
                        },
                        onChanged: (value) {
                          double maxAmount = 1000.0; // 默认无上限
                          if (value.trim().isNotEmpty) {
                            maxAmount = double.tryParse(value) ?? 1000.0;
                          }
                          setState(() {
                            _amountRangeConfig = AmountRangeConfig(
                              enabled: _amountRangeConfig.enabled,
                              minAmount: _amountRangeConfig.minAmount,
                              maxAmount: maxAmount,
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '提示：最大值留空表示无上限',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _selectDate,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey[200]!),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.calendar_today, color: Colors.orange[700], size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '筛选日期',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('yyyy-MM-dd').format(_selectedDate),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Icon(Icons.arrow_drop_down, color: Colors.orange[700], size: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPctChgSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: _enablePctChg,
              onChanged: (value) {
                setState(() {
                  _enablePctChg = value ?? false;
                });
              },
            ),
            const Text(
              '涨跌幅筛选',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        if (_enablePctChg) ...[
          const SizedBox(height: 12),
          const Text('涨跌幅范围:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey)),
          const SizedBox(height: 8),
          // 使用更紧凑的布局
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                // 最小值行
                Row(
                  children: [
                    const Text('最小值:', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _pctChgMin > -10 ? () {
                        setState(() {
                          _pctChgMin--;
                          if (_pctChgMin >= _pctChgMax) {
                            _pctChgMax = _pctChgMin + 1;
                          }
                        });
                      } : null,
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                    Container(
                      width: 50,
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey[400]!),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_pctChgMin > 0 ? '+' : ''}$_pctChgMin%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: _pctChgMin < _pctChgMax - 1 ? () {
                        setState(() {
                          _pctChgMin++;
                        });
                      } : null,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 最大值行
                Row(
                  children: [
                    const Text('最大值:', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _pctChgMax > _pctChgMin + 1 ? () {
                        setState(() {
                          _pctChgMax--;
                        });
                      } : null,
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                    Container(
                      width: 50,
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey[400]!),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_pctChgMax > 0 ? '+' : ''}$_pctChgMax%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: _pctChgMax < 10 ? () {
                        setState(() {
                          _pctChgMax++;
                        });
                      } : null,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMaDistanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: _enableMaDistance,
              onChanged: (value) {
                setState(() {
                  _enableMaDistance = value ?? false;
                });
              },
            ),
            const Text(
              '均线偏离筛选',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        if (_enableMaDistance) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                _buildMaDistanceRow('MA5', _ma5Config, (config) {
                  setState(() {
                    _ma5Config = config;
                  });
                }),
                const SizedBox(height: 6),
                Divider(height: 1, color: Colors.grey[200]),
                const SizedBox(height: 6),
                _buildMaDistanceRow('MA10', _ma10Config, (config) {
                  setState(() {
                    _ma10Config = config;
                  });
                }),
                const SizedBox(height: 6),
                Divider(height: 1, color: Colors.grey[200]),
                const SizedBox(height: 6),
                _buildMaDistanceRow('MA20', _ma20Config, (config) {
                  setState(() {
                    _ma20Config = config;
                  });
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMaDistanceRow(String maName, MaDistanceConfig config, Function(MaDistanceConfig) onChanged) {
    return Row(
      children: [
        Checkbox(
          value: config.enabled,
          onChanged: (value) {
            onChanged(MaDistanceConfig(
              enabled: value ?? false,
              distance: config.distance,
            ));
          },
        ),
        SizedBox(
          width: 50,
          child: Text(
            maName,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        const Text('偏离: ', style: TextStyle(fontSize: 13, color: Colors.grey)),
        SizedBox(
          width: 70,
          child: TextFormField(
            initialValue: config.distance.toString(),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.blue[400]!),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              suffixText: '%',
              suffixStyle: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            onChanged: (value) {
              final distance = double.tryParse(value);
              if (distance != null) {
                onChanged(MaDistanceConfig(
                  enabled: config.enabled,
                  distance: distance,
                ));
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildConsecutiveDaysSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: _enableConsecutiveDays,
              onChanged: (value) {
                setState(() {
                  _enableConsecutiveDays = value ?? false;
                });
              },
            ),
            const Text(
              '连续天数筛选',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        if (_enableConsecutiveDays) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('连续', style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        border: Border.all(color: Colors.green[300]!),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<int>(
                        value: _consecutiveDaysConfig.days,
                        items: _consecutiveDaysOptions.map((days) {
                          return DropdownMenuItem(
                            value: days,
                            child: Text(
                              '$days',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _consecutiveDaysConfig = ConsecutiveDaysConfig(
                                enabled: _consecutiveDaysConfig.enabled,
                                days: value,
                                maType: _consecutiveDaysConfig.maType,
                              );
                            });
                          }
                        },
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        icon: Icon(Icons.arrow_drop_down, color: Colors.green[700], size: 20),
                        dropdownColor: Colors.white,
                      ),
                    ),
                    const Text('天收盘价高于', style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        border: Border.all(color: Colors.green[300]!),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<String>(
                        value: _consecutiveDaysConfig.maType,
                        items: _maTypes.map((maType) {
                          String displayName = maType == 'ma5' ? 'MA5' : 
                                              maType == 'ma10' ? 'MA10' : 'MA20';
                          return DropdownMenuItem(
                            value: maType,
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _consecutiveDaysConfig = ConsecutiveDaysConfig(
                                enabled: _consecutiveDaysConfig.enabled,
                                days: _consecutiveDaysConfig.days,
                                maType: value,
                              );
                            });
                          }
                        },
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        icon: Icon(Icons.arrow_drop_down, color: Colors.green[700], size: 20),
                        dropdownColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMaGrowthDaysSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: _maGrowthDaysConfig.hasAnyEnabled,
              onChanged: (value) {
                setState(() {
                  final enabled = value ?? false;
                  _maGrowthDaysConfig = _maGrowthDaysConfig.copyWith(
                    ma5Config: _maGrowthDaysConfig.ma5Config.copyWith(enabled: enabled),
                    ma10Config: _maGrowthDaysConfig.ma10Config.copyWith(enabled: enabled),
                    ma20Config: _maGrowthDaysConfig.ma20Config.copyWith(enabled: enabled),
                  );
                });
              },
            ),
            const Text(
              '均线连续增长天数筛选',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        if (_maGrowthDaysConfig.hasAnyEnabled) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                // MA5配置
                _buildMaGrowthDaysItem(
                  'MA5',
                  _maGrowthDaysConfig.ma5Config,
                  (config) {
                    setState(() {
                      _maGrowthDaysConfig = _maGrowthDaysConfig.copyWith(ma5Config: config);
                    });
                  },
                ),
                const SizedBox(height: 6),
                Divider(height: 1, color: Colors.grey[200]),
                const SizedBox(height: 6),
                // MA10配置
                _buildMaGrowthDaysItem(
                  'MA10',
                  _maGrowthDaysConfig.ma10Config,
                  (config) {
                    setState(() {
                      _maGrowthDaysConfig = _maGrowthDaysConfig.copyWith(ma10Config: config);
                    });
                  },
                ),
                const SizedBox(height: 6),
                Divider(height: 1, color: Colors.grey[200]),
                const SizedBox(height: 6),
                // MA20配置
                _buildMaGrowthDaysItem(
                  'MA20',
                  _maGrowthDaysConfig.ma20Config,
                  (config) {
                    setState(() {
                      _maGrowthDaysConfig = _maGrowthDaysConfig.copyWith(ma20Config: config);
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMaGrowthDaysItem(
    String maName,
    MaGrowthDaysConfig config,
    Function(MaGrowthDaysConfig) onConfigChanged,
  ) {
    return Row(
      children: [
        Checkbox(
          value: config.enabled,
          onChanged: (value) {
            onConfigChanged(config.copyWith(enabled: value ?? false));
          },
        ),
        SizedBox(
          width: 50,
          child: Text(
            maName,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              const Text('连续增长 ', style: TextStyle(fontSize: 13, color: Colors.black87)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: config.enabled ? Colors.purple[50] : Colors.grey[100],
                  border: Border.all(
                    color: config.enabled ? Colors.purple[300]! : Colors.grey[300]!,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButton<int>(
                  value: _maGrowthDaysOptions.contains(config.days) ? config.days : 5,
                  items: _maGrowthDaysOptions.map((days) {
                    return DropdownMenuItem(
                      value: days,
                      child: Text(
                        '$days',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: config.enabled
                      ? (value) {
                          if (value != null) {
                            onConfigChanged(config.copyWith(days: value));
                          }
                        }
                      : null,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: config.enabled ? Colors.black87 : Colors.grey[600],
                  ),
                  icon: Icon(
                    Icons.arrow_drop_down,
                    color: config.enabled ? Colors.purple[700] : Colors.grey[600],
                  ),
                  dropdownColor: Colors.white,
                ),
              ),
              const Text(' 天', style: TextStyle(fontSize: 13, color: Colors.black87)),
            ],
          ),
        ),
      ],
    );
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
              amountThreshold: _amountThreshold,
              selectedDate: _selectedDate,
              amountRangeConfig: _amountRangeConfig,
              enablePctChg: _enablePctChg,
              pctChgMin: _pctChgMin,
              pctChgMax: _pctChgMax,
              enableMaDistance: _enableMaDistance,
              ma5Config: _ma5Config,
              ma10Config: _ma10Config,
              ma20Config: _ma20Config,
              enableConsecutiveDays: _enableConsecutiveDays,
              consecutiveDaysConfig: _consecutiveDaysConfig,
              maGrowthDaysConfig: _maGrowthDaysConfig,
              updatedAt: DateTime.now(),
            )
          : ConditionCombinationService.createCombination(
              name: _nameController.text.trim(),
              description: _descriptionController.text.trim(),
              amountThreshold: _amountThreshold,
              selectedDate: _selectedDate,
              amountRangeConfig: _amountRangeConfig,
              enablePctChg: _enablePctChg,
              pctChgMin: _pctChgMin,
              pctChgMax: _pctChgMax,
              enableMaDistance: _enableMaDistance,
              ma5Config: _ma5Config,
              ma10Config: _ma10Config,
              ma20Config: _ma20Config,
              enableConsecutiveDays: _enableConsecutiveDays,
              consecutiveDaysConfig: _consecutiveDaysConfig,
              maGrowthDaysConfig: _maGrowthDaysConfig,
            );

      final success = await ConditionCombinationService.saveCombination(combination);
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.editingCombination != null 
                  ? '条件组合更新成功' 
                  : '条件组合保存成功'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('保存失败，请重试'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
