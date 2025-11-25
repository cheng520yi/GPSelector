import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import '../models/kline_data.dart';
import '../models/macd_data.dart';
import '../models/boll_data.dart';

class KlineChartWidget extends StatefulWidget {
  final List<KlineData> klineDataList;
  final List<MacdData> macdDataList; // MACD数据
  final List<BollData> bollDataList; // BOLL数据
  final int? displayDays; // 可选：要显示的天数，如果为null则显示所有数据
  final int subChartCount; // 副图数量，默认为1（成交量），支持4个副图
  final String chartType; // 图表类型：daily(日K), weekly(周K), monthly(月K)
  final Function(KlineData, Map<String, double?>)? onDataSelected; // 选中数据回调

  const KlineChartWidget({
    super.key,
    required this.klineDataList,
    this.macdDataList = const [],
    this.bollDataList = const [],
    this.displayDays,
    this.subChartCount = 1, // 默认1个副图（成交量）
    this.chartType = 'daily', // 默认日K
    this.onDataSelected,
  });

  @override
  State<KlineChartWidget> createState() => _KlineChartWidgetState();
}

class _KlineChartWidgetState extends State<KlineChartWidget> {
  int? _selectedIndex; // 选中的K线数据索引（在可见数据中的索引）
  Timer? _autoResetTimer; // 自动恢复定时器
  
  @override
  void didUpdateWidget(KlineChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果klineDataList发生变化，清除选中状态
    if (oldWidget.klineDataList != widget.klineDataList) {
      _selectedIndex = null;
      _autoResetTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _autoResetTimer?.cancel();
    super.dispose();
  }

  // 根据触摸位置找到对应的K线数据点
  int? _findDataIndexAtPosition(double x, Size size) {
    if (widget.klineDataList.isEmpty) return null;

    // 计算可见数据范围（与paint方法中的逻辑保持一致）
    final int startIndex;
    if (widget.displayDays != null) {
      final calculatedStartIndex = widget.klineDataList.length - widget.displayDays!;
      startIndex = math.max(19, calculatedStartIndex);
    } else {
      if (widget.klineDataList.length > 19) {
        startIndex = 19;
      } else {
        startIndex = 0;
      }
    }

    final visibleData = widget.klineDataList.sublist(startIndex);
    if (visibleData.isEmpty) return null;

    // 计算K线宽度和间距（与_drawCandles保持一致）
    final chartWidth = size.width;
    double dynamicCandleWidth = KlineChartPainter.candleWidth;
    double dynamicCandleSpacing = KlineChartPainter.candleSpacing;

    if (visibleData.length > 0) {
      final requiredWidth = visibleData.length * (KlineChartPainter.candleWidth + KlineChartPainter.candleSpacing);
      if (requiredWidth > chartWidth) {
        final scale = chartWidth / requiredWidth;
        dynamicCandleWidth = KlineChartPainter.candleWidth * scale;
        dynamicCandleSpacing = KlineChartPainter.candleSpacing * scale;
      } else {
        final availableWidthPerCandle = chartWidth / visibleData.length;
        final totalRatio = KlineChartPainter.candleWidth + KlineChartPainter.candleSpacing;
        dynamicCandleWidth = (KlineChartPainter.candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (KlineChartPainter.candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }

    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;

    // 找到最接近触摸位置的K线索引
    final index = (x / candleTotalWidth).round();
    if (index >= 0 && index < visibleData.length) {
      return index;
    }
    return null;
  }

  // 计算选中日期的均线值
  Map<String, double?> _calculateMovingAveragesForIndex(int index) {
    // 计算在完整数据列表中的索引
    final int startIndex;
    if (widget.displayDays != null) {
      final calculatedStartIndex = widget.klineDataList.length - widget.displayDays!;
      startIndex = math.max(19, calculatedStartIndex);
    } else {
      if (widget.klineDataList.length > 19) {
        startIndex = 19;
      } else {
        startIndex = 0;
      }
    }

    final absoluteIndex = startIndex + index;
    if (absoluteIndex < 0 || absoluteIndex >= widget.klineDataList.length) {
      return {'ma5': null, 'ma10': null, 'ma20': null, 'prevMa5': null, 'prevMa10': null, 'prevMa20': null};
    }

    // 计算MA5
    double? ma5;
    double? prevMa5;
    if (absoluteIndex >= 4) {
      final last5 = widget.klineDataList.sublist(absoluteIndex - 4, absoluteIndex + 1);
      ma5 = last5.map((e) => e.close).reduce((a, b) => a + b) / 5;
      
      if (absoluteIndex >= 5) {
        final prev5 = widget.klineDataList.sublist(absoluteIndex - 5, absoluteIndex);
        prevMa5 = prev5.map((e) => e.close).reduce((a, b) => a + b) / 5;
      }
    }

    // 计算MA10
    double? ma10;
    double? prevMa10;
    if (absoluteIndex >= 9) {
      final last10 = widget.klineDataList.sublist(absoluteIndex - 9, absoluteIndex + 1);
      ma10 = last10.map((e) => e.close).reduce((a, b) => a + b) / 10;
      
      if (absoluteIndex >= 10) {
        final prev10 = widget.klineDataList.sublist(absoluteIndex - 10, absoluteIndex);
        prevMa10 = prev10.map((e) => e.close).reduce((a, b) => a + b) / 10;
      }
    }

    // 计算MA20
    double? ma20;
    double? prevMa20;
    if (absoluteIndex >= 19) {
      final last20 = widget.klineDataList.sublist(absoluteIndex - 19, absoluteIndex + 1);
      ma20 = last20.map((e) => e.close).reduce((a, b) => a + b) / 20;
      
      if (absoluteIndex >= 20) {
        final prev20 = widget.klineDataList.sublist(absoluteIndex - 20, absoluteIndex);
        prevMa20 = prev20.map((e) => e.close).reduce((a, b) => a + b) / 20;
      }
    }

    return {'ma5': ma5, 'ma10': ma10, 'ma20': ma20, 'prevMa5': prevMa5, 'prevMa10': prevMa10, 'prevMa20': prevMa20};
  }

  void _handleTapDown(TapDownDetails details) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final index = _findDataIndexAtPosition(details.localPosition.dx, size);
    if (index != null) {
      // 计算在完整数据列表中的索引
      final int startIndex;
      if (widget.displayDays != null) {
        final calculatedStartIndex = widget.klineDataList.length - widget.displayDays!;
        startIndex = math.max(19, calculatedStartIndex);
      } else {
        if (widget.klineDataList.length > 19) {
          startIndex = 19;
        } else {
          startIndex = 0;
        }
      }

      final absoluteIndex = startIndex + index;
      if (absoluteIndex >= 0 && absoluteIndex < widget.klineDataList.length) {
        setState(() {
          _selectedIndex = index;
        });

        final selectedData = widget.klineDataList[absoluteIndex];
        final maValues = _calculateMovingAveragesForIndex(index);
        
        // 通知父组件
        if (widget.onDataSelected != null) {
          widget.onDataSelected!(selectedData, maValues);
        }

        // 取消之前的定时器
        _autoResetTimer?.cancel();
        // 5秒后自动恢复（无论是否是最新数据）
        _autoResetTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _selectedIndex = null;
            });
            // 恢复显示最新日期的数据
            if (widget.klineDataList.isNotEmpty && widget.onDataSelected != null) {
              final latestData = widget.klineDataList.last;
              final latestMaValues = _calculateLatestMovingAverages();
              widget.onDataSelected!(latestData, latestMaValues);
            }
          }
        });
      }
    }
  }

  // 计算最新交易日的均线值（用于恢复）
  Map<String, double?> _calculateLatestMovingAverages() {
    if (widget.klineDataList.length < 5) {
      return {'ma5': null, 'ma10': null, 'ma20': null, 'prevMa5': null, 'prevMa10': null, 'prevMa20': null};
    }

    // 计算在可见数据中的最后一个索引
    final int startIndex;
    if (widget.displayDays != null) {
      final calculatedStartIndex = widget.klineDataList.length - widget.displayDays!;
      startIndex = math.max(19, calculatedStartIndex);
    } else {
      if (widget.klineDataList.length > 19) {
        startIndex = 19;
      } else {
        startIndex = 0;
      }
    }

    final lastVisibleIndex = widget.klineDataList.length - 1 - startIndex;
    return _calculateMovingAveragesForIndex(lastVisibleIndex);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.klineDataList.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    return GestureDetector(
      onTapDown: _handleTapDown,
      onPanUpdate: (DragUpdateDetails details) {
        // 拖动时也更新选中
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null) return;
        final size = renderBox.size;
        final index = _findDataIndexAtPosition(details.localPosition.dx, size);
        if (index != null) {
          // 计算在完整数据列表中的索引
          final int startIndex;
          if (widget.displayDays != null) {
            final calculatedStartIndex = widget.klineDataList.length - widget.displayDays!;
            startIndex = math.max(19, calculatedStartIndex);
          } else {
            if (widget.klineDataList.length > 19) {
              startIndex = 19;
            } else {
              startIndex = 0;
            }
          }

          final absoluteIndex = startIndex + index;
          if (absoluteIndex >= 0 && absoluteIndex < widget.klineDataList.length) {
            setState(() {
              _selectedIndex = index;
            });

            final selectedData = widget.klineDataList[absoluteIndex];
            final maValues = _calculateMovingAveragesForIndex(index);
            
            // 通知父组件
            if (widget.onDataSelected != null) {
              widget.onDataSelected!(selectedData, maValues);
            }

            // 取消之前的定时器
            _autoResetTimer?.cancel();
            // 5秒后自动恢复（无论是否是最新数据）
            _autoResetTimer = Timer(const Duration(seconds: 5), () {
              if (mounted) {
                setState(() {
                  _selectedIndex = null;
                });
                // 恢复显示最新日期的数据
                if (widget.klineDataList.isNotEmpty && widget.onDataSelected != null) {
                  final latestData = widget.klineDataList.last;
                  final latestMaValues = _calculateLatestMovingAverages();
                  widget.onDataSelected!(latestData, latestMaValues);
                }
              }
            });
          }
        }
      },
      child: CustomPaint(
        painter: KlineChartPainter(
          klineDataList: widget.klineDataList,
          macdDataList: widget.macdDataList,
          bollDataList: widget.bollDataList,
          displayDays: widget.displayDays,
          subChartCount: widget.subChartCount,
          chartType: widget.chartType,
          selectedIndex: _selectedIndex, // 传递选中索引
        ),
      size: Size.infinite,
      ),
    );
  }
}

// 均线数据点
class _MaPoint {
  final int index;
  final double? ma5;
  final double? ma10;
  final double? ma20;

  _MaPoint({
    required this.index,
    this.ma5,
    this.ma10,
    this.ma20,
  });
}

class KlineChartPainter extends CustomPainter {
  final List<KlineData> klineDataList;
  final List<MacdData> macdDataList; // MACD数据
  final List<BollData> bollDataList; // BOLL数据
  final int? displayDays; // 可选：要显示的天数，如果为null则显示所有数据
  final int subChartCount; // 副图数量
  final String chartType; // 图表类型：daily(日K), weekly(周K), monthly(月K)
  final int? selectedIndex; // 选中的K线数据索引（在可见数据中的索引）
  static const double leftPadding = 0.0; // 左侧padding（设为0，让图表铺满宽度）
  static const double rightPadding = 0.0; // 右侧padding（设为0，让图表铺满宽度）
  static const double topPadding = 0.0; // 顶部padding（设为0，完全占满）
  static const double bottomPadding = 18.0; // 底部padding（用于日期标签，尽量紧凑）
  static const double priceLabelPadding = 2.0; // 价格标签距离左侧的间距（覆盖在图表上，偏左展示）
  static const double chartGap = 4.0; // K线图和成交量图之间的间隙（减小间隙）
  static const double candleWidth = 7.0; // 将原来的6.0 + 2.0合并，减少间隙
  static const double candleSpacing = 1.0; // 消除间隙，将间隙合并到K线宽度上
  static const double volumeChartHeight = 120.0; // 成交量图表高度
  // K线图占整个图表的高度比例（根据副图数量动态调整）
  static double _getKlineChartHeightRatio(int subChartCount) {
    switch (subChartCount) {
      case 1:
        return 0.7; // 1个副图时，K线图占70%
      case 2:
        return 0.55; // 2个副图时，K线图占55%
      case 3:
        return 0.45; // 3个副图时，K线图占45%
      case 4:
        return 0.4; // 4个副图时，K线图占40%
      default:
        return 0.7;
    }
  }

  KlineChartPainter({
    required this.klineDataList,
    this.macdDataList = const [],
    this.bollDataList = const [],
    this.displayDays,
    this.subChartCount = 1,
    this.chartType = 'daily',
    this.selectedIndex,
  });

  // 计算每个数据点的均线值
  List<_MaPoint> _calculateMaPoints(List<KlineData> data) {
    List<_MaPoint> maPoints = [];
    
    for (int i = 0; i < data.length; i++) {
      double? ma5, ma10, ma20;
      
      // 计算MA5 - 从第5个数据点开始有值
      if (i >= 4) {
        double sum = 0.0;
        for (int j = i - 4; j <= i; j++) {
          sum += data[j].close;
        }
        ma5 = sum / 5;
      }
      
      // 计算MA10 - 从第10个数据点开始有值
      if (i >= 9) {
        double sum = 0.0;
        for (int j = i - 9; j <= i; j++) {
          sum += data[j].close;
        }
        ma10 = sum / 10;
      }
      
      // 计算MA20 - 从第20个数据点开始有值
      if (i >= 19) {
        double sum = 0.0;
        for (int j = i - 19; j <= i; j++) {
          sum += data[j].close;
        }
        ma20 = sum / 20;
      }
      
      maPoints.add(_MaPoint(
        index: i,
        ma5: ma5,
        ma10: ma10,
        ma20: ma20,
      ));
    }
    
    return maPoints;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (klineDataList.isEmpty) return;

    // 为MACD和BOLL标签预留高度
    const labelAreaHeight = 25.0; // 标签区域高度
    
    // 计算需要标签区域的副图数量（MACD和BOLL）
    int labelAreaCount = 0;
    if (subChartCount >= 2 && macdDataList.isNotEmpty) labelAreaCount++;
    if (subChartCount >= 3 && bollDataList.isNotEmpty) labelAreaCount++;
    
    // 从可用高度中扣除标签区域的高度
    final klineRatio = _getKlineChartHeightRatio(subChartCount);
    final baseAvailableHeight = size.height - topPadding - bottomPadding - chartGap * subChartCount;
    final availableHeight = baseAvailableHeight - labelAreaCount * labelAreaHeight;
    final klineChartHeight = availableHeight * klineRatio;
    final subChartHeight = availableHeight * (1 - klineRatio) / subChartCount;

    // 计算均线点（基于所有数据，确保均线计算准确）
    final allMaPoints = _calculateMaPoints(klineDataList);
    
    // 确定要显示的数据范围
    // 关键：确保所有均线（MA5、MA10、MA20）从显示区域的第一个点开始有值
    // MA5从索引4开始有值，MA10从索引9开始有值，MA20从索引19开始有值
    // 所以startIndex必须 >= 19，这样所有均线才能从显示区域的第一个点开始有值
    
    final int startIndex;
    if (displayDays != null) {
      // 用户想显示最后N天的数据
      // 计算：如果要显示最后N个点，startIndex应该是 length - N
      // 但为了确保ma20从第一个点开始有值，startIndex必须 >= 19
      // 所以：startIndex = max(19, length - N)
      final calculatedStartIndex = klineDataList.length - displayDays!;
      startIndex = math.max(19, calculatedStartIndex);
    } else {
      // 没有指定displayDays，显示所有数据
      // 从索引19开始显示（确保均线从第一个点开始有值）
      if (klineDataList.length > 19) {
        startIndex = 19;
      } else {
        startIndex = 0;
      }
    }
    
    final visibleData = klineDataList.sublist(startIndex);
    final visibleMaPoints = allMaPoints.sublist(startIndex);
    
    // 计算价格范围（基于显示的数据和对应的均线）
    double maxPrice = visibleData.map((e) => math.max(e.high, e.close)).reduce(math.max);
    double minPrice = visibleData.map((e) => math.min(e.low, e.close)).reduce(math.min);
    
    // 检查均线是否超出价格范围
    for (var point in visibleMaPoints) {
      if (point.ma5 != null) {
        maxPrice = math.max(maxPrice, point.ma5!);
        minPrice = math.min(minPrice, point.ma5!);
      }
      if (point.ma10 != null) {
        maxPrice = math.max(maxPrice, point.ma10!);
        minPrice = math.min(minPrice, point.ma10!);
      }
      if (point.ma20 != null) {
        maxPrice = math.max(maxPrice, point.ma20!);
        minPrice = math.min(minPrice, point.ma20!);
      }
    }
    
    // 添加一些边距，使图表更美观
    final priceRange = maxPrice - minPrice;
    if (priceRange > 0) {
      maxPrice += priceRange * 0.1;
      minPrice -= priceRange * 0.1;
    } else {
      // 如果价格范围为零，添加一个小的偏移
      maxPrice += maxPrice * 0.01;
      minPrice -= minPrice * 0.01;
    }

    // 计算绘制区域（铺满整个屏幕宽度）
    final chartWidth = size.width;
    
    // 根据数据量动态调整K线宽度和间距，确保完全铺满屏幕宽度
    // 如果数据较少，增大宽度和间距使图表铺满；如果数据太多，缩小以适应
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    
    if (visibleData.length > 0) {
      if (visibleData.length == 1) {
        // 只有1个数据点，K线宽度铺满整个宽度
        dynamicCandleWidth = chartWidth;
        dynamicCandleSpacing = 0;
      } else {
        // 计算每个K线应该占用的宽度，使第一个和最后一个K线完全铺满
        final availableWidthPerCandle = chartWidth / visibleData.length;
        // 保持宽度和间距的比例，但调整它们使图表完全铺满
        final totalRatio = candleWidth + candleSpacing;
        dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }
    
    final dynamicCandleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;

    // 计算成交量范围
    double maxVolume = visibleData.map((e) => e.vol).reduce(math.max);
    if (maxVolume <= 0) maxVolume = 1.0;
    
    // 调试：打印成交量信息
    if (visibleData.isNotEmpty) {
      final lastData = visibleData.last;
      print('📊 成交量计算: 图表类型=$chartType, 可见数据量=${visibleData.length}, 最大成交量=$maxVolume');
      print('📊 最后一条数据: 日期=${lastData.tradeDate}, 成交量=${lastData.vol}, 占比=${(lastData.vol / maxVolume * 100).toStringAsFixed(2)}%');
      // 打印所有数据的成交量，用于调试
      if (visibleData.length <= 10) {
        print('📊 所有可见数据的成交量:');
        for (int i = 0; i < visibleData.length; i++) {
          print('  ${i + 1}. ${visibleData[i].tradeDate}: 成交量=${visibleData[i].vol}');
        }
      } else {
        print('📊 前5条和后5条数据的成交量:');
        for (int i = 0; i < 5; i++) {
          print('  ${i + 1}. ${visibleData[i].tradeDate}: 成交量=${visibleData[i].vol}');
        }
        print('  ...');
        for (int i = visibleData.length - 5; i < visibleData.length; i++) {
          print('  ${i + 1}. ${visibleData[i].tradeDate}: 成交量=${visibleData[i].vol}');
        }
      }
    }

    // 绘制K线图背景网格
    _drawKlineGrid(canvas, size, maxPrice, minPrice, klineChartHeight);

    // 绘制价格标签（Y轴刻度值）
    _drawPriceLabels(canvas, size, maxPrice, minPrice, klineChartHeight);

    // 先绘制K线（在均线下方）
    _drawCandles(canvas, size, visibleData, maxPrice, minPrice, chartWidth, klineChartHeight);

    // 再绘制均线（在K线上方，确保均线可见）
    _drawMaLines(canvas, size, visibleData, visibleMaPoints, maxPrice, minPrice, chartWidth, klineChartHeight);

    // 绘制副图（固定顺序：第1个=成交量，第2个=MACD，第3个=BOLL，第4个=成交量）
    double currentSubChartTop = topPadding + klineChartHeight + chartGap;
    print('🔍 开始绘制副图: subChartCount=$subChartCount, macdDataList.length=${macdDataList.length}, bollDataList.length=${bollDataList.length}');
    for (int i = 0; i < subChartCount; i++) {
      print('🔍 绘制第${i + 1}个副图: i=$i');
      // 判断是否需要标签区域（MACD或BOLL）
      final needsLabelArea = (i == 1 && macdDataList.isNotEmpty) || (i == 2 && bollDataList.isNotEmpty);
      // 图表高度保持不变（subChartHeight），标签区域在图表上方
      final chartTop = needsLabelArea ? currentSubChartTop + labelAreaHeight : currentSubChartTop;
      
      // 计算副图底部位置（用于绘制底部线条）
      final subChartBottom = needsLabelArea 
          ? chartTop + subChartHeight 
          : currentSubChartTop + subChartHeight;
      
      // 第1个副图（索引0）：成交量
      if (i == 0) {
        print('📊 绘制成交量图表（第1个副图）');
        _drawVolumeChart(canvas, size, visibleData, maxVolume, chartWidth, currentSubChartTop, subChartHeight);
        _drawVolumeLabels(canvas, size, maxVolume, currentSubChartTop, subChartHeight);
      }
      // 第2个副图（索引1）：MACD指标
      else if (i == 1) {
        if (macdDataList.isNotEmpty) {
        print('✅ 绘制MACD图表（第2个副图）');
        // 先绘制标签（在图表上方）
          _drawMacdLabels(canvas, size, visibleData, macdDataList, selectedIndex, currentSubChartTop, labelAreaHeight);
        // 再绘制图表（在标签下方，保持原来的高度）
        _drawMacdChart(canvas, size, visibleData, macdDataList, chartWidth, chartTop, subChartHeight);
        } else {
          print('⚠️ MACD数据为空，绘制成交量图表（第2个副图）');
          _drawVolumeChart(canvas, size, visibleData, maxVolume, chartWidth, currentSubChartTop, subChartHeight);
          _drawVolumeLabels(canvas, size, maxVolume, currentSubChartTop, subChartHeight);
        }
      }
      // 第3个副图（索引2）：BOLL指标
      else if (i == 2) {
        if (bollDataList.isNotEmpty) {
        print('✅ 绘制BOLL图表（第3个副图）');
        // 先绘制标签（在图表上方）
          _drawBollLabels(canvas, size, visibleData, bollDataList, selectedIndex, currentSubChartTop, labelAreaHeight);
        // 再绘制图表（在标签下方，保持原来的高度）
        _drawBollChart(canvas, size, visibleData, bollDataList, chartWidth, chartTop, subChartHeight);
      } else {
          print('⚠️ BOLL数据为空，绘制成交量图表（第3个副图）');
          _drawVolumeChart(canvas, size, visibleData, maxVolume, chartWidth, currentSubChartTop, subChartHeight);
          _drawVolumeLabels(canvas, size, maxVolume, currentSubChartTop, subChartHeight);
        }
      }
      // 第4个及以上副图（索引3及以上）：成交量
      else {
        print('📊 绘制成交量图表（第${i + 1}个副图）');
        _drawVolumeChart(canvas, size, visibleData, maxVolume, chartWidth, currentSubChartTop, subChartHeight);
        _drawVolumeLabels(canvas, size, maxVolume, currentSubChartTop, subChartHeight);
      }
      
      // 在每个副图底部绘制灰色水平线
      final bottomLinePaint = Paint()
        ..color = Colors.grey[300]!
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(0, subChartBottom),
        Offset(chartWidth, subChartBottom),
        bottomLinePaint,
      );
      
      // 更新下一个副图的顶部位置（如果有标签区域，需要加上标签高度）
      currentSubChartTop += subChartHeight + (needsLabelArea ? labelAreaHeight : 0) + chartGap;
    }

    // 绘制选中竖线（如果有选中）
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < visibleData.length) {
      _drawSelectedLine(canvas, size, visibleData, selectedIndex!, klineChartHeight, currentSubChartTop - chartGap);
    }

    // 绘制日期标签（在最后一个副图下方）
    final lastSubChartTop = topPadding + klineChartHeight + chartGap + subChartHeight * subChartCount + chartGap * (subChartCount - 1);
    _drawDateLabels(canvas, size, visibleData, lastSubChartTop);
  }

  void _drawKlineGrid(Canvas canvas, Size size, double maxPrice, double minPrice, double chartHeight) {
    final paint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 0.5;

    // 绘制水平网格线（价格线，铺满整个屏幕宽度）
    for (int i = 0; i <= 4; i++) {
      final y = topPadding + chartHeight * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }

    // 绘制垂直网格线（时间线，铺满整个屏幕宽度）
    for (int i = 0; i <= 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(
        Offset(x, topPadding),
        Offset(x, topPadding + chartHeight),
        paint,
      );
    }
  }

  void _drawPriceLabels(Canvas canvas, Size size, double maxPrice, double minPrice, double chartHeight) {
    final textStyle = TextStyle(
      color: Colors.grey[700],
      fontSize: 9, // 减小字体大小
    );
    final textPainter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );

    // 绘制价格标签（覆盖在图表上，在图表内部显示，展示在网格横线上，偏左展示）
    for (int i = 0; i <= 4; i++) {
      final price = maxPrice - (maxPrice - minPrice) * i / 4;
      textPainter.text = TextSpan(
        text: price.toStringAsFixed(2), // 去掉¥符号，更简洁
        style: textStyle,
      );
      textPainter.layout();
      // 价格标签覆盖在图表上，展示在网格横线上（向上微调），偏左展示（向左微调）
      final y = topPadding + chartHeight * i / 4;
      // 向上微调：减去一个小的偏移量，让标签稍微在网格线上方
      textPainter.paint(
        canvas,
        Offset(priceLabelPadding, y - textPainter.height / 2 - 4),
      );
    }
  }

  // 绘制选中竖线
  void _drawSelectedLine(Canvas canvas, Size size, List<KlineData> visibleData, int selectedIndex,
      double klineChartHeight, double subChartBottom) {
    if (selectedIndex < 0 || selectedIndex >= visibleData.length) return;

    final chartWidth = size.width;
    
    // 计算K线宽度和间距（与_drawCandles保持一致）
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    
    if (visibleData.length > 0) {
      if (visibleData.length == 1) {
        dynamicCandleWidth = chartWidth;
        dynamicCandleSpacing = 0;
      } else {
        final availableWidthPerCandle = chartWidth / visibleData.length;
        final totalRatio = candleWidth + candleSpacing;
        dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }
    
    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;
    final x = selectedIndex * candleTotalWidth + dynamicCandleWidth / 2;

    // 绘制竖线（从K线图顶部到所有副图底部）
    final linePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(x, topPadding),
      Offset(x, subChartBottom),
      linePaint,
    );
  }

  void _drawDateLabels(Canvas canvas, Size size, List<KlineData> visibleData, double volumeChartTop) {
    if (visibleData.isEmpty) return;

    final textStyle = TextStyle(
      color: Colors.grey[700],
      fontSize: 9, // 减小字体大小
    );
    final selectedTextStyle = TextStyle(
      color: Colors.blue,
      fontSize: 9,
      fontWeight: FontWeight.bold,
    );
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    // 绘制日期标签（底部，在图表最下方，铺满整个宽度）
    final chartWidth = size.width; // 图表区域宽度（铺满整个屏幕）
    
    // 动态计算K线宽度和间距（与_drawCandles保持一致）
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    
    if (visibleData.length > 0) {
      if (visibleData.length == 1) {
        dynamicCandleWidth = chartWidth;
        dynamicCandleSpacing = 0;
      } else {
        final availableWidthPerCandle = chartWidth / visibleData.length;
        final totalRatio = candleWidth + candleSpacing;
        dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }
    
    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;
    
    // 如果有选中，在底部显示选中日期
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < visibleData.length) {
      final selectedData = visibleData[selectedIndex!];
      String dateStr;
      
      // 根据图表类型格式化日期
      if (chartType == 'monthly') {
        dateStr = selectedData.tradeDate.substring(0, 6);
      } else {
        dateStr = '${selectedData.tradeDate.substring(4, 6)}-${selectedData.tradeDate.substring(6, 8)}';
      }
      
      textPainter.text = TextSpan(
        text: dateStr,
        style: selectedTextStyle,
      );
      textPainter.layout();
      final x = selectedIndex! * candleTotalWidth + dynamicCandleWidth / 2;
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, size.height - bottomPadding + 4),
      );
    } else {
      // 没有选中时，显示常规的5个日期标签
      final labelCount = 5;
    for (int i = 0; i < labelCount; i++) {
      final index = (visibleData.length - 1) * i ~/ (labelCount - 1);
      if (index < visibleData.length) {
        final date = visibleData[index].tradeDate;
          String dateStr;
          
          // 根据图表类型格式化日期
          if (chartType == 'monthly') {
            // 月K：显示为YYYYMM格式（如202511）
            dateStr = date.substring(0, 6); // 取前6位：YYYYMM
          } else {
            // 日K和周K：显示为MM-DD格式
            dateStr = '${date.substring(4, 6)}-${date.substring(6, 8)}';
          }
          
        textPainter.text = TextSpan(
          text: dateStr,
          style: textStyle,
        );
        textPainter.layout();
          final x = index * candleTotalWidth + dynamicCandleWidth / 2;
          
          // 计算标签的x位置
          double labelX;
          if (i == 0) {
            // 第一个标签：紧靠左边框
            labelX = 0;
          } else if (i == labelCount - 1) {
            // 最后一个标签：紧靠右边框
            labelX = size.width - textPainter.width;
          } else {
            // 中间标签：居中显示
            labelX = x - textPainter.width / 2;
          }
          
        textPainter.paint(
          canvas,
            Offset(labelX, size.height - bottomPadding + 4),
        );
        }
      }
    }
  }

  void _drawCandles(Canvas canvas, Size size, List<KlineData> visibleData, 
      double maxPrice, double minPrice, double chartWidth, double chartHeight) {
    // 动态计算K线宽度和间距，确保完全铺满屏幕宽度
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    
    if (visibleData.length > 0) {
      if (visibleData.length == 1) {
        // 只有1个数据点，K线宽度铺满整个宽度
        dynamicCandleWidth = chartWidth;
        dynamicCandleSpacing = 0;
      } else {
        // 计算每个K线应该占用的宽度，使第一个和最后一个K线完全铺满
        final availableWidthPerCandle = chartWidth / visibleData.length;
        final totalRatio = candleWidth + candleSpacing;
        dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }
    
    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;
    final priceRange = maxPrice - minPrice;

    for (int i = 0; i < visibleData.length; i++) {
      final data = visibleData[i];
      // 确保第一个K线从0开始，最后一个K线延伸到chartWidth
      final x = i * candleTotalWidth + dynamicCandleWidth / 2;
      
      // 计算价格对应的Y坐标
      final highY = topPadding + (maxPrice - data.high) / priceRange * chartHeight;
      final lowY = topPadding + (maxPrice - data.low) / priceRange * chartHeight;
      final openY = topPadding + (maxPrice - data.open) / priceRange * chartHeight;
      final closeY = topPadding + (maxPrice - data.close) / priceRange * chartHeight;

      // 判断涨跌
      final isRising = data.close >= data.open;
      final color = isRising ? Colors.red[800]! : Colors.green[700]!; // 使用更深的红色和绿色

      // 计算实体位置
      final bodyTop = math.min(openY, closeY);
      final bodyBottom = math.max(openY, closeY);
      final bodyHeight = math.max(bodyBottom - bodyTop, 1.0); // 至少1像素高

      // 绘制实体（矩形）
      // 绿柱：实心（填充绿色）
      // 红柱：空心（红色边框，白色内部）
      final bodyPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(
          x - dynamicCandleWidth / 2,
          bodyTop,
          dynamicCandleWidth,
          bodyHeight,
        ),
        bodyPaint,
      );

      // 如果是涨（红柱），绘制白色内部矩形实现空心效果
      // 使用fill模式而不是stroke，确保宽度与绿柱一致
      if (isRising) {
        final whitePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        
        // 计算白色矩形的尺寸，向内缩进1像素，实现边框效果
        final whiteRectWidth = math.max(dynamicCandleWidth - 2.0, 1.0);
        final whiteRectHeight = math.max(bodyHeight - 2.0, 1.0);
        final whiteRectLeft = x - dynamicCandleWidth / 2 + 1.0;
        final whiteRectTop = bodyTop + 1.0;
        
        canvas.drawRect(
          Rect.fromLTWH(
            whiteRectLeft,
            whiteRectTop,
            whiteRectWidth,
            whiteRectHeight,
          ),
          whitePaint,
        );
      }

      // 绘制上下影线 - 在实体之后绘制，确保影线与实体无缝连接
      final shadowPaint = Paint()
        ..color = color
        ..strokeWidth = 1.0;
      
      // 上影线：从最高价到实体顶部
      if (highY < bodyTop) {
        canvas.drawLine(
          Offset(x, highY),
          Offset(x, bodyTop),
          shadowPaint,
        );
      }
      
      // 下影线：从实体底部到最低价
      if (lowY > bodyBottom) {
        canvas.drawLine(
          Offset(x, bodyBottom),
          Offset(x, lowY),
          shadowPaint,
        );
      }
    }
  }

  // 绘制均线
  void _drawMaLines(Canvas canvas, Size size, List<KlineData> visibleData, 
      List<_MaPoint> visibleMaPoints, double maxPrice, double minPrice, 
      double chartWidth, double chartHeight) {
    if (visibleData.length != visibleMaPoints.length) return;

    final priceRange = maxPrice - minPrice;

    // 绘制MA5（黑色）
    _drawMaLine(canvas, visibleMaPoints, (point) => point.ma5, 
        Colors.black, maxPrice, minPrice, priceRange, chartHeight, chartWidth);

    // 绘制MA10（黄色）
    _drawMaLine(canvas, visibleMaPoints, (point) => point.ma10, 
        Colors.yellow, maxPrice, minPrice, priceRange, chartHeight, chartWidth);

    // 绘制MA20（紫色）
    _drawMaLine(canvas, visibleMaPoints, (point) => point.ma20, 
        Colors.purple, maxPrice, minPrice, priceRange, chartHeight, chartWidth);
  }

  void _drawMaLine(Canvas canvas, List<_MaPoint> maPoints, 
      double? Function(_MaPoint) getMaValue, Color color, 
      double maxPrice, double minPrice, double priceRange, 
      double chartHeight, double chartWidth) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.3 // 稍微细一点
      ..style = PaintingStyle.stroke;

    // 动态计算K线宽度和间距（与_drawCandles保持一致，确保完全铺满）
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    
    if (maPoints.length > 0) {
      if (maPoints.length == 1) {
        dynamicCandleWidth = chartWidth;
        dynamicCandleSpacing = 0;
      } else {
        final availableWidthPerCandle = chartWidth / maPoints.length;
        final totalRatio = candleWidth + candleSpacing;
        dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }
    
    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;

    // 收集所有有效的均线点
    List<Offset> validPoints = [];
    for (int i = 0; i < maPoints.length; i++) {
      final maValue = getMaValue(maPoints[i]);
      
      if (maValue != null) {
        final x = i * candleTotalWidth + dynamicCandleWidth / 2;
        final y = topPadding + (maxPrice - maValue) / priceRange * chartHeight;
        validPoints.add(Offset(x, y));
      }
    }

    // 使用贝塞尔曲线平滑连接点
    if (validPoints.isEmpty) return;
    
    final path = Path();
    
    if (validPoints.length == 1) {
      path.moveTo(validPoints[0].dx, validPoints[0].dy);
      path.lineTo(validPoints[0].dx, validPoints[0].dy);
    } else if (validPoints.length == 2) {
      // 只有两个点，直接连接
      path.moveTo(validPoints[0].dx, validPoints[0].dy);
      path.lineTo(validPoints[1].dx, validPoints[1].dy);
        } else {
      // 多个点，使用三次贝塞尔曲线平滑连接
      // 使用Catmull-Rom样条曲线的思想，计算控制点
      path.moveTo(validPoints[0].dx, validPoints[0].dy);
      
      for (int i = 1; i < validPoints.length; i++) {
        final prev = validPoints[i - 1];
        final curr = validPoints[i];
        
        if (i == 1) {
          // 第二个点：使用第一个点和第二个点的中点作为控制点
          final controlX = (prev.dx + curr.dx) / 2;
          final controlY = (prev.dy + curr.dy) / 2;
          path.quadraticBezierTo(controlX, controlY, curr.dx, curr.dy);
        } else if (i == validPoints.length - 1) {
          // 最后一个点：使用前一个点和最后一个点的中点作为控制点
          final controlX = (prev.dx + curr.dx) / 2;
          final controlY = (prev.dy + curr.dy) / 2;
          path.quadraticBezierTo(controlX, controlY, curr.dx, curr.dy);
        } else {
          // 中间的点：使用三次贝塞尔曲线，计算两个控制点
          // 控制点1：前一个点和当前点的1/3处
          // 控制点2：前一个点和当前点的2/3处
          // 这样可以创建更平滑的过渡
          final prevPrev = validPoints[i - 2];
          
          // 计算方向向量
          final dx1 = prev.dx - prevPrev.dx;
          final dy1 = prev.dy - prevPrev.dy;
          final dx2 = curr.dx - prev.dx;
          final dy2 = curr.dy - prev.dy;
          
          // 计算控制点：使用前一个点和当前点的中点，但根据方向调整
          final tension = 0.3; // 张力系数，控制曲线的平滑程度
          final controlX1 = prev.dx + dx1 * tension;
          final controlY1 = prev.dy + dy1 * tension;
          final controlX2 = curr.dx - dx2 * tension;
          final controlY2 = curr.dy - dy2 * tension;
          
          // 使用三次贝塞尔曲线
          path.cubicTo(controlX1, controlY1, controlX2, controlY2, curr.dx, curr.dy);
        }
      }
    }

    canvas.drawPath(path, linePaint);
  }

  // 绘制成交量图表
  void _drawVolumeChart(Canvas canvas, Size size, List<KlineData> visibleData,
      double maxVolume, double chartWidth, double volumeChartTop, double volumeChartHeight) {
    // 动态计算K线宽度和间距（与_drawCandles保持一致，确保完全铺满）
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    
    if (visibleData.length > 0) {
      if (visibleData.length == 1) {
        dynamicCandleWidth = chartWidth;
        dynamicCandleSpacing = 0;
      } else {
        final availableWidthPerCandle = chartWidth / visibleData.length;
        final totalRatio = candleWidth + candleSpacing;
        dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }
    
    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;

    // 绘制成交量柱状图
    for (int i = 0; i < visibleData.length; i++) {
      final data = visibleData[i];
      final x = i * candleTotalWidth + dynamicCandleWidth / 2;
      
      // 计算成交量高度
      final volumeHeight = (data.vol / maxVolume) * volumeChartHeight;
      final volumeY = volumeChartTop + volumeChartHeight - volumeHeight;
      
      // 调试：打印最后几条数据的绘制信息
      if (i >= visibleData.length - 3) {
        print('📊 绘制成交量柱: 索引=$i, 日期=${data.tradeDate}, 成交量=${data.vol}, 高度=$volumeHeight, maxVolume=$maxVolume');
      }

      // 判断涨跌（与K线颜色一致）
      final isRising = data.close >= data.open;
      final color = isRising ? Colors.red.withOpacity(0.6) : Colors.green[700]!.withOpacity(0.6); // 使用更深的绿色

      final volumePaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      // 绘制成交量柱
      canvas.drawRect(
        Rect.fromLTWH(
          x - dynamicCandleWidth / 2,
          volumeY,
          dynamicCandleWidth,
          volumeHeight,
        ),
        volumePaint,
      );
    }
  }

  // 绘制成交量标签
  void _drawVolumeLabels(Canvas canvas, Size size, double maxVolume, 
      double volumeChartTop, double volumeChartHeight) {
    final textStyle = TextStyle(
      color: Colors.grey[700],
      fontSize: 9, // 减小字体大小
    );
    final textPainter = TextPainter(
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    );

    // 绘制成交量标签（左侧，在成交量图表区域内，尽量紧凑）
    final volumeStr = '${(maxVolume / 10000).toStringAsFixed(0)}万手';
    textPainter.text = TextSpan(
      text: volumeStr,
      style: textStyle,
    );
    textPainter.layout();
    // 将标签放在成交量图表的上方，覆盖在图表上（图表内部）
    textPainter.paint(
      canvas,
      Offset(priceLabelPadding, volumeChartTop + 4),
    );
  }


  // 绘制MACD图表
  void _drawMacdChart(Canvas canvas, Size size, List<KlineData> visibleData,
      List<MacdData> macdDataList, double chartWidth, double macdChartTop, double macdChartHeight) {
    if (macdDataList.isEmpty || visibleData.isEmpty) {
      print('⚠️ MACD图表绘制跳过: macdDataList=${macdDataList.length}, visibleData=${visibleData.length}');
      return;
    }

    // 创建日期到MACD数据的映射（保持与K线数据的索引对应关系）
    Map<String, MacdData> macdMap = {};
    for (var macd in macdDataList) {
      macdMap[macd.tradeDate] = macd;
    }

    // 统计匹配情况
    int matchedCount = 0;
    int unmatchedCount = 0;
    for (var kline in visibleData) {
      final macd = macdMap[kline.tradeDate];
      if (macd != null) {
        matchedCount++;
      } else {
        unmatchedCount++;
        if (unmatchedCount <= 3) {
          print('⚠️ MACD数据缺失: K线日期=${kline.tradeDate}（该日期不绘制MACD）');
        }
      }
    }

    print('🔍 MACD数据匹配: ${visibleData.length}个K线数据中，匹配MACD:$matchedCount个, 缺失:$unmatchedCount个');
    if (matchedCount == 0) {
      print('⚠️ 没有匹配的MACD数据，跳过MACD图表绘制');
      return;
    }

    // 计算MACD值的范围（根据K线展示区间内的最高最低值，自适应DIF、DEA和M的值）
    // 关键策略：使用统一的纵向比例尺，使DIF、DEA和M值协调显示
    // 遍历visibleData，从macdMap中查找对应的MACD数据，保持索引对应关系
    
    // 计算所有MACD值（DIF、DEA、M）在可见区间内的最高和最低值
    double maxAllValues = double.negativeInfinity;
    double minAllValues = double.infinity;
    
    for (var kline in visibleData) {
      final macd = macdMap[kline.tradeDate];
      if (macd != null) {
        // 检查DIF值
        if (!macd.dif.isNaN && !macd.dif.isInfinite) {
          maxAllValues = math.max(maxAllValues, macd.dif);
          minAllValues = math.min(minAllValues, macd.dif);
        }
        // 检查DEA值
        if (!macd.dea.isNaN && !macd.dea.isInfinite) {
          maxAllValues = math.max(maxAllValues, macd.dea);
          minAllValues = math.min(minAllValues, macd.dea);
        }
        // 检查M值
        if (!macd.macd.isNaN && !macd.macd.isInfinite) {
          maxAllValues = math.max(maxAllValues, macd.macd);
          minAllValues = math.min(minAllValues, macd.macd);
        }
      }
    }
    
    // 如果所有值都是无效的，使用默认值
    if (maxAllValues == double.negativeInfinity || minAllValues == double.infinity) {
      maxAllValues = 1.0;
      minAllValues = -1.0;
    }
    
    print('🔍 MACD可见区间范围: 最小值=$minAllValues, 最大值=$maxAllValues');
    
    // 计算DIF和DEA的最大绝对值（用于趋势分析）
    List<double> difValues = [];
    List<double> deaValues = [];
    List<double> macdValues = [];
    for (var kline in visibleData) {
      final macd = macdMap[kline.tradeDate];
      if (macd != null) {
        if (!macd.dif.isNaN && !macd.dif.isInfinite) difValues.add(macd.dif.abs());
        if (!macd.dea.isNaN && !macd.dea.isInfinite) deaValues.add(macd.dea.abs());
        if (!macd.macd.isNaN && !macd.macd.isInfinite) macdValues.add(macd.macd);
      }
    }
    
    double maxDifAbs = difValues.isNotEmpty ? difValues.reduce(math.max) : 0.0;
    double maxDeaAbs = deaValues.isNotEmpty ? deaValues.reduce(math.max) : 0.0;
    double maxDifDeaAbs = math.max(maxDifAbs, maxDeaAbs);
    
    // 计算M值的最大绝对值和分布情况（用于趋势分析）
    double maxMacdValue = macdValues.isNotEmpty ? macdValues.map((e) => e.abs()).reduce(math.max) : 0.0;
    // 计算M值在正负两边的最大值
    double maxMacdPositive = 0.0;
    double maxMacdNegative = 0.0;
    for (var value in macdValues) {
      if (value > 0 && value > maxMacdPositive) {
        maxMacdPositive = value;
      }
      if (value < 0 && value.abs() > maxMacdNegative) {
        maxMacdNegative = value.abs();
      }
    }
    
    // 计算DIF和DEA的实际最大值和最小值（考虑正负，用于趋势分析）
    List<double> difDeaMax = [];
    List<double> difDeaMin = [];
    for (var kline in visibleData) {
      final macd = macdMap[kline.tradeDate];
      if (macd != null) {
        if (!macd.dif.isNaN && !macd.dif.isInfinite && !macd.dea.isNaN && !macd.dea.isInfinite) {
          difDeaMax.add(math.max(macd.dif, macd.dea));
          difDeaMin.add(math.min(macd.dif, macd.dea));
        }
      }
    }
    final actualMaxDifDea = difDeaMax.isNotEmpty ? difDeaMax.reduce(math.max) : 0.0;
    final actualMinDifDea = difDeaMin.isNotEmpty ? difDeaMin.reduce(math.min) : 0.0;
    
    // 分析MACD趋势（上涨、下跌、震荡）
    // 通过计算M值的平均值和斜率来判断趋势
    double macdSum = 0.0;
    int macdCount = 0;
    for (var value in macdValues) {
      macdSum += value;
      macdCount++;
    }
    final macdAverage = macdCount > 0 ? macdSum / macdCount : 0.0;
    
    // 计算趋势斜率（使用线性回归的简单方法：比较前半段和后半段的平均值）
    final midIndex = visibleData.length ~/ 2;
    double firstHalfSum = 0.0;
    double secondHalfSum = 0.0;
    int firstHalfCount = 0;
    int secondHalfCount = 0;
    
    for (int i = 0; i < visibleData.length; i++) {
      final macd = macdMap[visibleData[i].tradeDate];
      if (macd != null && !macd.macd.isNaN && !macd.macd.isInfinite) {
        if (i < midIndex) {
          firstHalfSum += macd.macd;
          firstHalfCount++;
        } else {
          secondHalfSum += macd.macd;
          secondHalfCount++;
        }
      }
    }
    
    final firstHalfAvg = firstHalfCount > 0 ? firstHalfSum / firstHalfCount : 0.0;
    final secondHalfAvg = secondHalfCount > 0 ? secondHalfSum / secondHalfCount : 0.0;
    final trendSlope = secondHalfAvg - firstHalfAvg;
    
    // 判断趋势类型
    String trendType = '震荡';
    double trendStrength = 0.0; // -1到1之间，-1表示强烈下跌，1表示强烈上涨，0表示震荡
    
    if (macdCount > 0) {
      // 如果平均值和斜率都为正，判断为上涨趋势
      // 如果平均值和斜率都为负，判断为下跌趋势
      // 否则为震荡趋势
      final avgSign = macdAverage > 0 ? 1 : -1;
      final slopeSign = trendSlope > 0 ? 1 : -1;
      
      if (avgSign == 1 && slopeSign == 1 && macdAverage.abs() > 0.01) {
        trendType = '上涨';
        trendStrength = math.min(1.0, (macdAverage.abs() + trendSlope.abs()) / (maxMacdValue * 2));
      } else if (avgSign == -1 && slopeSign == -1 && macdAverage.abs() > 0.01) {
        trendType = '下跌';
        trendStrength = -math.min(1.0, (macdAverage.abs() + trendSlope.abs()) / (maxMacdValue * 2));
      } else {
        trendType = '震荡';
        trendStrength = 0.0;
      }
    }
    
    print('🔍 MACD趋势分析: 类型=$trendType, 强度=${trendStrength.toStringAsFixed(2)}, 平均值=$macdAverage, 斜率=$trendSlope');
    
    // 分析M值的分布，根据趋势调整0轴位置
    // 计算M值在正负两边的最大绝对值
    final macdPositiveRange = maxMacdPositive;
    final macdNegativeRange = maxMacdNegative;
    
    // 计算DIF/DEA在正负两边的范围
    final difDeaPositiveRange = actualMaxDifDea > 0 ? actualMaxDifDea : 0.0;
    final difDeaNegativeRange = actualMinDifDea < 0 ? actualMinDifDea.abs() : 0.0;
    
    // 使用统一的最高最低值作为Y轴范围的基础
    // 确保包含所有DIF、DEA和M值
    double maxMacd = maxAllValues;
    double minMacd = minAllValues;
    
    // 根据趋势调整范围的不对称性，但保持统一的比例尺
    // 趋势强度影响范围调整（0.1到0.3的调整幅度）
    final trendAdjustment = trendStrength.abs() * 0.2; // 减小调整幅度，使图形更协调
    
    // 计算正负两边的范围
    final positiveRange = maxAllValues > 0 ? maxAllValues : 0.0;
    final negativeRange = minAllValues < 0 ? minAllValues.abs() : 0.0;
    
    if (trendType == '上涨') {
      // 上涨趋势：0轴偏下，增加上方范围
      maxMacd = positiveRange * (1.0 + trendAdjustment);
      minMacd = -negativeRange * (1.0 - trendAdjustment * 0.5);
      print('🔍 上涨趋势：上方范围扩大${(trendAdjustment * 100).toStringAsFixed(1)}%，0轴偏下');
    } else if (trendType == '下跌') {
      // 下跌趋势：0轴偏上，增加下方范围
      maxMacd = positiveRange * (1.0 - trendAdjustment * 0.5);
      minMacd = -negativeRange * (1.0 + trendAdjustment);
      print('🔍 下跌趋势：下方范围扩大${(trendAdjustment * 100).toStringAsFixed(1)}%，0轴偏上');
    } else {
      // 震荡趋势：0轴居中，保持对称
      final baseRange = math.max(positiveRange, negativeRange);
      maxMacd = baseRange;
      minMacd = -baseRange;
      print('🔍 震荡趋势：0轴居中，范围对称');
    }
    
    // 确保范围包含所有实际值
    if (maxMacd < maxAllValues) {
      maxMacd = maxAllValues;
    }
    if (minMacd > minAllValues) {
      minMacd = minAllValues;
    }
    
    // 添加极小的边距（0.5%），使图形更协调
    final dataRange = maxMacd - minMacd;
    if (dataRange > 0) {
      maxMacd = maxMacd + dataRange * 0.005; // 添加0.5%的上边距
      minMacd = minMacd - dataRange * 0.005; // 添加0.5%的下边距
    }
    
    // 最终检查：确保范围有效
    if (maxMacd == minMacd || (maxMacd - minMacd) == 0) {
      // 如果范围无效，使用对称范围
      final absMax = math.max(maxAllValues.abs(), minAllValues.abs());
      maxMacd = absMax * 1.01;
      minMacd = -absMax * 1.01;
    }
    
    if (maxMacd == minMacd || (maxMacd - minMacd) == 0) {
      maxMacd = 1.0;
      minMacd = -1.0;
    }

    // 验证0轴位置（根据趋势有不同的期望位置）
    var currentRange = maxMacd - minMacd;
    var zeroPosition = (0.0 - minMacd) / currentRange;
    var zeroPositionPercent = zeroPosition * 100;
    
    // 根据趋势设置期望的0轴位置
    double expectedZeroPosition = 50.0; // 默认居中
    String expectedDescription = '居中';
    if (trendType == '上涨') {
      expectedZeroPosition = 35.0; // 上涨趋势：0轴偏下（约35%位置）
      expectedDescription = '偏下（上涨趋势）';
    } else if (trendType == '下跌') {
      expectedZeroPosition = 65.0; // 下跌趋势：0轴偏上（约65%位置）
      expectedDescription = '偏上（下跌趋势）';
    } else {
      expectedZeroPosition = 50.0; // 震荡趋势：0轴居中
      expectedDescription = '居中（震荡趋势）';
    }
    
    print('🔍 MACD 0轴位置: ${zeroPositionPercent.toStringAsFixed(2)}% (期望${expectedZeroPosition.toStringAsFixed(0)}%，表示${expectedDescription})');
    
    // 如果不是震荡趋势且0轴位置偏差较大，进行微调
    if (trendType != '震荡' && (zeroPositionPercent - expectedZeroPosition).abs() > 5.0) {
      print('⚠️ 0轴位置偏差较大，进行微调');
      // 根据趋势调整范围
      if (trendType == '上涨') {
        // 上涨趋势：增加上方范围，减小下方范围
        final newUpper = maxMacd * 1.1;
        final newLower = minMacd.abs() * 0.9;
        maxMacd = newUpper;
        minMacd = -newLower;
      } else if (trendType == '下跌') {
        // 下跌趋势：增加下方范围，减小上方范围
        final newUpper = maxMacd * 0.9;
        final newLower = minMacd.abs() * 1.1;
        maxMacd = newUpper;
        minMacd = -newLower;
      }
      currentRange = maxMacd - minMacd;
      final adjustedZeroPosition = (0.0 - minMacd) / currentRange;
      print('🔍 调整后0轴位置: ${(adjustedZeroPosition * 100).toStringAsFixed(2)}%');
    }
    
    // 使用最终的范围
    final finalMacdRange = maxMacd - minMacd;
    
    print('🔍 MACD Y轴范围: min=$minMacd, max=$maxMacd, range=$finalMacdRange');

    // 不绘制MACD水平网格线（Y轴刻度线）
    // final gridPaint = Paint()
    //   ..color = Colors.grey[300]!
    //   ..strokeWidth = 0.5;
    // 
    // // 绘制0轴（根据实际Y轴范围动态计算0轴位置）
    // // 0轴的Y坐标 = 图表顶部 + (最大值 - 0值) / (最大值 - 最小值) * 图表高度
    // final zeroY = macdChartTop + (maxMacd - 0.0) / finalMacdRange * macdChartHeight;
    // canvas.drawLine(
    //   Offset(0, zeroY),
    //   Offset(chartWidth, zeroY),
    //   gridPaint,
    // );
    // 
    // // 绘制其他水平网格线
    // for (int i = 1; i <= 2; i++) {
    //   final y = macdChartTop + macdChartHeight * i / 4;
    //   canvas.drawLine(
    //     Offset(0, y),
    //     Offset(chartWidth, y),
    //     gridPaint,
    //   );
    // }

    // 动态计算K线宽度和间距（与_drawCandles保持一致）
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    
    if (visibleData.length > 0) {
      if (visibleData.length == 1) {
        dynamicCandleWidth = chartWidth;
        dynamicCandleSpacing = 0;
      } else {
        final availableWidthPerCandle = chartWidth / visibleData.length;
        final totalRatio = candleWidth + candleSpacing;
        dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }
    
    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;

    // 绘制MACD柱状图（M值）- 使用更窄的宽度
    // 遍历visibleData，保持与K线数据的索引对应关系
    final macdBarWidth = dynamicCandleWidth * 0.35; // 柱状图宽度为K线宽度的35%，使其更细
    for (int i = 0; i < visibleData.length; i++) {
      final kline = visibleData[i];
      final macd = macdMap[kline.tradeDate];
      
      // 如果没有MACD数据，跳过绘制，但保持索引对应关系
      if (macd == null) {
        continue;
      }
      
      final x = i * candleTotalWidth + dynamicCandleWidth / 2;
      
      // 计算MACD柱状图的高度和位置（使用与DIF线完全相同的计算方式）
      final macdValue = macd.macd;
      
      // 计算0轴在图表中的实际Y坐标位置（与DIF/DEA线使用完全相同的计算方式）
      // DIF/DEA线的Y坐标计算公式：y = chartTop + (maxMacd - value) / macdRange * chartHeight
      // 确保使用完全相同的参数：chartTop=macdChartTop, macdRange=finalMacdRange, chartHeight=macdChartHeight
      final zeroY = macdChartTop + (maxMacd - 0.0) / finalMacdRange * macdChartHeight;
      
      // 计算M值在Y轴上的位置（与DIF/DEA线使用完全相同的计算方式）
      // 使用完全相同的公式和参数，确保比例尺一致
      final mValueY = macdChartTop + (maxMacd - macdValue) / finalMacdRange * macdChartHeight;
      
      // 计算柱状图的高度和位置，确保与DIF线使用完全相同的比例尺
      // 在Canvas坐标系中，Y坐标从上往下递增
      // 对于正值（M值在0轴上方）：mValueY < zeroY（Y坐标更小，在图表上方）
      // 对于负值（M值在0轴下方）：mValueY > zeroY（Y坐标更大，在图表下方）
      double macdHeight;
      double barTopY;
      
      if (macdValue >= 0) {
        // 正值：M值在0轴上方，柱状图从0轴向上绘制到M值位置
        // mValueY < zeroY（Y坐标更小，在图表上方）
        barTopY = mValueY; // 柱状图顶部在M值的Y坐标位置（与DIF线位置一致）
        macdHeight = zeroY - mValueY; // 高度是从M值位置到0轴的距离
      } else {
        // 负值：M值在0轴下方，柱状图从0轴向下绘制到M值位置
        // mValueY > zeroY（Y坐标更大，在图表下方）
        barTopY = zeroY; // 柱状图顶部在0轴
        macdHeight = mValueY - zeroY; // 高度是从0轴到M值位置的距离
      }
      
      // 确保高度不为负
      macdHeight = math.max(0.0, macdHeight);
      
      // 添加详细的调试信息（仅对最后一个数据点），验证三个指标使用完全相同的比例尺
      if (i == visibleData.length - 1) {
        // 使用与_drawMacdLine完全相同的公式计算DIF和DEA的Y坐标
        final difY = macdChartTop + (maxMacd - macd.dif) / finalMacdRange * macdChartHeight;
        final deaY = macdChartTop + (maxMacd - macd.dea) / finalMacdRange * macdChartHeight;
        
        print('🔍 ========== MACD三个指标比例尺验证 ==========');
        print('🔍 参数验证: chartTop=$macdChartTop, maxMacd=$maxMacd, range=$finalMacdRange, height=$macdChartHeight');
        print('🔍 数值: DIF=${macd.dif}, DEA=${macd.dea}, M=${macd.macd}');
        print('🔍 Y坐标: DIF=$difY, DEA=$deaY, M=$mValueY, 0轴=$zeroY');
        print('🔍 公式验证:');
        print('🔍   DIF公式: $macdChartTop + ($maxMacd - ${macd.dif}) / $finalMacdRange * $macdChartHeight = $difY');
        print('🔍   DEA公式: $macdChartTop + ($maxMacd - ${macd.dea}) / $finalMacdRange * $macdChartHeight = $deaY');
        print('🔍   M值公式: $macdChartTop + ($maxMacd - $macdValue) / $finalMacdRange * $macdChartHeight = $mValueY');
        
        // 验证：如果DIF和M值相同，它们的Y坐标应该也相同
        if ((macd.dif - macd.macd).abs() < 0.001) {
          final yDiff = (difY - mValueY).abs();
          if (yDiff > 0.1) {
            print('⚠️ 警告: DIF和M值几乎相同(${macd.dif} vs ${macd.macd})，但Y坐标差=$yDiff');
          } else {
            print('✅ DIF和M值几乎相同时，Y坐标也几乎相同');
          }
        }
        print('🔍 ============================================');
      }
      
      final color = macdValue >= 0 ? Colors.red.withOpacity(0.6) : Colors.green[700]!.withOpacity(0.6); // 使用更深的绿色
      
      final macdPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      
      // 绘制柱状图
      // 对于正值：从mValueY（顶部）向下延伸到zeroY（底部）
      // 对于负值：从zeroY（顶部）向下延伸到mValueY（底部）
      // 使用Rect.fromLTWH时，Y坐标是矩形顶部，height是向下延伸的高度
        canvas.drawRect(
          Rect.fromLTWH(
          x - macdBarWidth / 2,
          barTopY,
          macdBarWidth,
            macdHeight,
          ),
          macdPaint,
        );
      }

    // 绘制DIF线（黑色）- 使用visibleData和macdMap，保持索引对应关系
    bool hasValidDif = false;
    for (var kline in visibleData) {
      final macd = macdMap[kline.tradeDate];
      if (macd != null && !macd.dif.isNaN && !macd.dif.isInfinite && macd.dif != 0.0) {
        hasValidDif = true;
        break;
      }
    }
    if (hasValidDif) {
      _drawMacdLine(canvas, visibleData, macdMap, (m) => m.dif, Colors.black, 
          minMacd, maxMacd, finalMacdRange, macdChartHeight, macdChartTop, chartWidth,
          strokeWidth: 1.0); // DIF线更细一些
    }
    
    // 绘制DEA线（黄色/橙色）- 使用visibleData和macdMap，保持索引对应关系
    bool hasValidDea = false;
    for (var kline in visibleData) {
      final macd = macdMap[kline.tradeDate];
      if (macd != null && !macd.dea.isNaN && !macd.dea.isInfinite && macd.dea != 0.0) {
        hasValidDea = true;
        break;
      }
    }
    if (hasValidDea) {
      _drawMacdLine(canvas, visibleData, macdMap, (m) => m.dea, Colors.orange, 
          minMacd, maxMacd, finalMacdRange, macdChartHeight, macdChartTop, chartWidth);
    }
  }

  // 绘制MACD线（DIF或DEA）
  // 使用visibleData和macdMap，保持与K线数据的索引对应关系
  void _drawMacdLine(Canvas canvas, List<KlineData> visibleData, Map<String, MacdData> macdMap,
      double Function(MacdData) getValue, Color color,
      double minMacd, double maxMacd, double macdRange,
      double chartHeight, double chartTop, double chartWidth,
      {double strokeWidth = 1.3}) { // 可选的线条宽度参数
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth // 使用传入的线条宽度
      ..style = PaintingStyle.stroke;

    // 动态计算K线宽度和间距（与visibleData长度对应）
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    
    if (visibleData.length > 0) {
      if (visibleData.length == 1) {
        dynamicCandleWidth = chartWidth;
        dynamicCandleSpacing = 0;
      } else {
        final availableWidthPerCandle = chartWidth / visibleData.length;
        final totalRatio = candleWidth + candleSpacing;
        dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }
    
    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;

    // 收集所有有效的点
    // 使用与M值柱状图完全相同的Y坐标计算公式：y = chartTop + (maxMacd - value) / macdRange * chartHeight
    // 遍历visibleData，保持索引对应关系
    List<Offset> validPoints = [];
    for (int i = 0; i < visibleData.length; i++) {
      final kline = visibleData[i];
      final macd = macdMap[kline.tradeDate];
      
      // 如果没有MACD数据，跳过（不绘制），但保持索引对应关系
      if (macd == null) {
        continue;
      }
      
      final value = getValue(macd);
      if (!value.isNaN && !value.isInfinite) {
        final x = i * candleTotalWidth + dynamicCandleWidth / 2;
        // 确保使用与M值柱状图完全相同的公式和参数
        final y = chartTop + (maxMacd - value) / macdRange * chartHeight;
        validPoints.add(Offset(x, y));
        
        // 对于最后一个数据点，添加调试信息验证Y坐标计算
        if (i == visibleData.length - 1) {
          print('🔍 _drawMacdLine Y坐标计算: value=$value, y=$y');
          print('🔍   公式: chartTop=$chartTop + (maxMacd=$maxMacd - value=$value) / macdRange=$macdRange * chartHeight=$chartHeight = $y');
        }
      }
    }

    print('🔍 MACD线条有效点数: ${validPoints.length}, K线数据长度: ${visibleData.length}');

    if (validPoints.length < 2) {
      print('⚠️ MACD线条点数不足，无法绘制');
      return;
    }

    // 使用更平滑的贝塞尔曲线连接点
    final path = Path();
    path.moveTo(validPoints[0].dx, validPoints[0].dy);

    for (int i = 1; i < validPoints.length; i++) {
      if (i == 1) {
        // 第二个点：使用二次贝塞尔曲线
        final controlPoint = Offset(
          (validPoints[i - 1].dx + validPoints[i].dx) / 2,
          (validPoints[i - 1].dy + validPoints[i].dy) / 2,
        );
        path.quadraticBezierTo(
          controlPoint.dx,
          controlPoint.dy,
          validPoints[i].dx,
          validPoints[i].dy,
        );
      } else if (i == validPoints.length - 1) {
        // 最后一个点：使用二次贝塞尔曲线
        final controlPoint = Offset(
          (validPoints[i - 1].dx + validPoints[i].dx) / 2,
          (validPoints[i - 1].dy + validPoints[i].dy) / 2,
        );
        path.quadraticBezierTo(
          controlPoint.dx,
          controlPoint.dy,
          validPoints[i].dx,
          validPoints[i].dy,
        );
      } else {
        // 中间点：使用三次贝塞尔曲线，计算更平滑的控制点
        final prevPoint = validPoints[i - 1];
        final currentPoint = validPoints[i];
        final nextPoint = validPoints[i + 1];
        
        // 计算方向向量
        final dx1 = currentPoint.dx - prevPoint.dx;
        final dy1 = currentPoint.dy - prevPoint.dy;
        final dx2 = nextPoint.dx - currentPoint.dx;
        final dy2 = nextPoint.dy - currentPoint.dy;
        
        // 使用张力系数控制曲线的平滑程度（与BOLL曲线保持一致）
        final tension = 0.3;
        final cp1 = Offset(
          prevPoint.dx + dx1 * tension,
          prevPoint.dy + dy1 * tension,
        );
        final cp2 = Offset(
          currentPoint.dx - dx2 * tension,
          currentPoint.dy - dy2 * tension,
        );
        
        path.cubicTo(
          cp1.dx, cp1.dy,
          cp2.dx, cp2.dy,
          currentPoint.dx, currentPoint.dy,
        );
      }
    }

    canvas.drawPath(path, linePaint);
  }

  // 绘制MACD标签（包含趋势箭头，支持选中日期联动）
  void _drawMacdLabels(Canvas canvas, Size size, List<KlineData> visibleData, List<MacdData> macdDataList,
      int? selectedIndex, double macdChartTop, double macdChartHeight) {
    if (macdDataList.isEmpty) return;

    // 计算MACD值的范围
    double maxMacd = macdDataList.map((e) => math.max(e.dif, math.max(e.dea, e.macd))).reduce(math.max);
    double minMacd = macdDataList.map((e) => math.min(e.dif, math.min(e.dea, e.macd))).reduce(math.min);
    
    // 确保范围包含0
    maxMacd = math.max(maxMacd.abs(), minMacd.abs());
    minMacd = -maxMacd;
    
    if (maxMacd == minMacd) {
      maxMacd = 1.0;
      minMacd = -1.0;
    }

    final textStyle = TextStyle(
      color: Colors.grey[700],
      fontSize: 9,
    );
    final textPainter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );

    // 不绘制MACD Y轴刻度值
    // for (int i = 0; i <= 4; i++) {
    //   final value = maxMacd - (maxMacd - minMacd) * i / 4;
    //   textPainter.text = TextSpan(
    //     text: value.toStringAsFixed(2),
    //     style: textStyle,
    //   );
    //   textPainter.layout();
    //   final y = macdChartTop + macdChartHeight * i / 4;
    //   textPainter.paint(
    //     canvas,
    //     Offset(priceLabelPadding, y - textPainter.height / 2 - 2),
    //   );
    // }

    // 绘制MACD指标名称和数值（在图表右上角，参考BOLL标签的样式）
    // 如果有选中，显示选中日期的数据；否则显示最新的数据
    MacdData? displayData;
    if (selectedIndex != null && selectedIndex >= 0 && selectedIndex < visibleData.length) {
      // 显示选中日期的MACD数据
      final selectedKline = visibleData[selectedIndex];
      displayData = macdDataList.firstWhere(
        (m) => m.tradeDate == selectedKline.tradeDate,
        orElse: () => macdDataList.last, // 如果找不到，使用最新的
      );
    } else {
      // 显示最新的MACD数据
      displayData = macdDataList.last;
    }
    
    if (displayData != null) {
      // 计算趋势箭头（与前一个值比较）
      String getTrend(double? current, double? prev) {
        if (current == null || prev == null) return '↓';
        return current >= prev ? '↑' : '↓';
      }
      
      // 查找当前数据在列表中的索引
      int currentIndex = macdDataList.indexOf(displayData);
      
      // 获取前一个MACD数据
      double? prevDif, prevDea, prevMacd;
      if (currentIndex > 0) {
        final prev = macdDataList[currentIndex - 1];
        prevDif = prev.dif;
        prevDea = prev.dea;
        prevMacd = prev.macd;
      }
      
      final difTrend = getTrend(displayData.dif, prevDif);
      final deaTrend = getTrend(displayData.dea, prevDea);
      final macdTrend = getTrend(displayData.macd, prevMacd);
      
      // 箭头颜色：上涨用红色，下跌用绿色
      final difTrendColor = difTrend == '↑' ? Colors.red[700]! : Colors.green[700]!;
      final deaTrendColor = deaTrend == '↑' ? Colors.red[700]! : Colors.green[700]!;
      final macdTrendColor = macdTrend == '↑' ? Colors.red[700]! : Colors.green[700]!;
      
      // 使用RichText分别设置文本和箭头的样式
      final baseTextStyle = TextStyle(
        color: Colors.grey[800],
        fontSize: 10,
        fontWeight: FontWeight.w500,
      );
      final arrowTextStyle = TextStyle(
        color: Colors.grey[800],
        fontSize: 14, // 箭头更大
        fontWeight: FontWeight.bold,
      );
      
      final labelPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(text: 'MACD ▼ DIF:', style: baseTextStyle),
            TextSpan(text: displayData.dif.toStringAsFixed(2), style: baseTextStyle),
            TextSpan(text: difTrend, style: arrowTextStyle.copyWith(color: difTrendColor)),
            TextSpan(text: ' DEA:', style: baseTextStyle),
            TextSpan(text: displayData.dea.toStringAsFixed(2), style: baseTextStyle),
            TextSpan(text: deaTrend, style: arrowTextStyle.copyWith(color: deaTrendColor)),
            TextSpan(text: ' M:', style: baseTextStyle),
            TextSpan(text: displayData.macd.toStringAsFixed(2), style: baseTextStyle),
            TextSpan(text: macdTrend, style: arrowTextStyle.copyWith(color: macdTrendColor)),
          ],
        ),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      );
      labelPainter.layout();
      
      // 计算标签位置（在标签区域内的右上角）
      const padding = 4.0;
      const backgroundPadding = 2.0;
      final labelX = size.width - labelPainter.width - padding;
      // 标签在标签区域内的垂直居中位置
      final labelY = macdChartTop + (macdChartHeight - labelPainter.height) / 2;
      
      // 先绘制白色背景矩形（接近透明）
      final backgroundRect = Rect.fromLTWH(
        labelX - backgroundPadding,
        labelY - backgroundPadding,
        labelPainter.width + backgroundPadding * 2,
        labelPainter.height + backgroundPadding * 2,
      );
      final backgroundPaint = Paint()
        ..color = Colors.white.withOpacity(0.15) // 接近透明的白色背景，15%不透明度
        ..style = PaintingStyle.fill;
      canvas.drawRect(backgroundRect, backgroundPaint);
      
      // 再绘制文本（在背景之上）
      labelPainter.paint(
        canvas,
        Offset(labelX, labelY),
      );
    }
  }

  // 绘制BOLL图表
  void _drawBollChart(Canvas canvas, Size size, List<KlineData> visibleData,
      List<BollData> bollDataList, double chartWidth, double bollChartTop, double bollChartHeight) {
    if (bollDataList.isEmpty || visibleData.isEmpty) {
      print('⚠️ BOLL图表绘制跳过: bollDataList=${bollDataList.length}, visibleData=${visibleData.length}');
      return;
    }

    // 创建日期到BOLL数据的映射
    final Map<String, BollData> bollMap = {};
    for (var boll in bollDataList) {
      bollMap[boll.tradeDate] = boll;
    }

    // 计算BOLL值的范围
    double maxBoll = bollDataList.map((e) => math.max(e.upper, math.max(e.middle, e.lower))).reduce(math.max);
    double minBoll = bollDataList.map((e) => math.min(e.upper, math.min(e.middle, e.lower))).reduce(math.min);
    
    if (maxBoll == minBoll) {
      maxBoll = minBoll + 1.0;
    }

    final bollRange = maxBoll - minBoll;
    if (bollRange == 0) return;

    // 计算K线宽度和间距
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    
    if (visibleData.length > 0) {
      if (visibleData.length == 1) {
        dynamicCandleWidth = chartWidth;
        dynamicCandleSpacing = 0;
      } else {
        final availableWidthPerCandle = chartWidth / visibleData.length;
        final totalRatio = candleWidth + candleSpacing;
        dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }

    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;

    // 计算价格范围（包含前复权价格和BOLL轨道）
    double maxPrice = maxBoll;
    double minPrice = minBoll;
    
    // 检查是否有前复权价格数据，如果有则包含在价格范围内
    for (var kline in visibleData) {
      if (kline.highQfq != null && kline.lowQfq != null) {
        maxPrice = math.max(maxPrice, kline.highQfq!);
        minPrice = math.min(minPrice, kline.lowQfq!);
      } else {
        // 如果没有前复权价格，使用普通价格
        maxPrice = math.max(maxPrice, kline.high);
        minPrice = math.min(minPrice, kline.low);
      }
    }
    
    // 添加边距
    final priceRange = maxPrice - minPrice;
    if (priceRange > 0) {
      maxPrice += priceRange * 0.05;
      minPrice -= priceRange * 0.05;
    }
    
    final finalPriceRange = maxPrice - minPrice;
    if (finalPriceRange == 0) return;

    // 不绘制BOLL水平网格线（Y轴刻度线）
    // final gridPaint = Paint()
    //   ..color = Colors.grey[300]!
    //   ..strokeWidth = 0.5;
    // for (int i = 0; i <= 4; i++) {
    //   final y = bollChartTop + bollChartHeight * i / 4;
    //   canvas.drawLine(
    //     Offset(0, y),
    //     Offset(chartWidth, y),
    //     gridPaint,
    //   );
    // }

    // 绘制K线（使用前复权价格，叠加在BOLL图表中）
    _drawCandlesInBollChart(canvas, size, visibleData, maxPrice, minPrice, finalPriceRange, 
        chartWidth, bollChartHeight, bollChartTop, candleTotalWidth, dynamicCandleWidth);

    // 绘制BOLL上轨、中轨、下轨（在K线之上）
    _drawBollLine(canvas, visibleData, bollMap, (boll) => boll.upper, Colors.red,
        minPrice, maxPrice, finalPriceRange, bollChartHeight, bollChartTop, chartWidth, candleTotalWidth, dynamicCandleWidth);
    _drawBollLine(canvas, visibleData, bollMap, (boll) => boll.middle, Colors.orange,
        minPrice, maxPrice, finalPriceRange, bollChartHeight, bollChartTop, chartWidth, candleTotalWidth, dynamicCandleWidth);
    _drawBollLine(canvas, visibleData, bollMap, (boll) => boll.lower, Colors.green,
        minPrice, maxPrice, finalPriceRange, bollChartHeight, bollChartTop, chartWidth, candleTotalWidth, dynamicCandleWidth);
  }

  // 在BOLL图表中绘制K线（使用前复权价格）
  void _drawCandlesInBollChart(Canvas canvas, Size size, List<KlineData> visibleData,
      double maxPrice, double minPrice, double priceRange, double chartWidth, 
      double chartHeight, double chartTop, double candleTotalWidth, double dynamicCandleWidth) {
    for (int i = 0; i < visibleData.length; i++) {
      final data = visibleData[i];
      
      // 优先使用前复权价格
      final open = data.openQfq ?? data.open;
      final high = data.highQfq ?? data.high;
      final low = data.lowQfq ?? data.low;
      final close = data.closeQfq ?? data.close;
      
      final x = i * candleTotalWidth + dynamicCandleWidth / 2;
      
      // 计算价格对应的Y坐标
      final highY = chartTop + (maxPrice - high) / priceRange * chartHeight;
      final lowY = chartTop + (maxPrice - low) / priceRange * chartHeight;
      final openY = chartTop + (maxPrice - open) / priceRange * chartHeight;
      final closeY = chartTop + (maxPrice - close) / priceRange * chartHeight;

      // 判断涨跌
      final isRising = close >= open;
      final color = isRising ? Colors.red[800]! : Colors.green[700]!;

      // 计算实体位置
      final bodyTop = math.min(openY, closeY);
      final bodyBottom = math.max(openY, closeY);
      final bodyHeight = math.max(bodyBottom - bodyTop, 1.0);

      // 绘制实体
      final bodyPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(
          x - dynamicCandleWidth / 2,
          bodyTop,
          dynamicCandleWidth,
          bodyHeight,
        ),
        bodyPaint,
      );

      // 如果是涨（红柱），绘制白色内部矩形实现空心效果
      if (isRising) {
        final whitePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        
        final whiteRectWidth = math.max(dynamicCandleWidth - 2.0, 1.0);
        final whiteRectHeight = math.max(bodyHeight - 2.0, 1.0);
        final whiteRectLeft = x - dynamicCandleWidth / 2 + 1.0;
        final whiteRectTop = bodyTop + 1.0;
        
        canvas.drawRect(
          Rect.fromLTWH(
            whiteRectLeft,
            whiteRectTop,
            whiteRectWidth,
            whiteRectHeight,
          ),
          whitePaint,
        );
      }

      // 绘制上下影线
      final shadowPaint = Paint()
        ..color = color
        ..strokeWidth = 1.0;
      
      if (highY < bodyTop) {
        canvas.drawLine(
          Offset(x, highY),
          Offset(x, bodyTop),
          shadowPaint,
        );
      }
      
      if (lowY > bodyBottom) {
        canvas.drawLine(
          Offset(x, bodyBottom),
          Offset(x, lowY),
          shadowPaint,
        );
      }
    }
  }

  // 绘制BOLL线（使用更平滑的算法）
  void _drawBollLine(Canvas canvas, List<KlineData> visibleData,
      Map<String, BollData> bollMap, double Function(BollData) getValue, Color color,
      double minBoll, double maxBoll, double bollRange,
      double chartHeight, double chartTop, double chartWidth,
      double candleTotalWidth, double dynamicCandleWidth) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // 收集所有有效的点
    List<Offset> validPoints = [];
    for (int i = 0; i < visibleData.length; i++) {
      final kline = visibleData[i];
      final boll = bollMap[kline.tradeDate];
      
      if (boll != null) {
        final value = getValue(boll);
        if (!value.isNaN && !value.isInfinite) {
        final x = i * candleTotalWidth + dynamicCandleWidth / 2;
        final y = chartTop + chartHeight - ((value - minBoll) / bollRange * chartHeight);
          validPoints.add(Offset(x, y));
        }
      }
    }

    if (validPoints.length < 2) return;

    // 使用更平滑的贝塞尔曲线连接
    final path = Path();
    path.moveTo(validPoints[0].dx, validPoints[0].dy);

    for (int i = 1; i < validPoints.length; i++) {
      if (i == 1) {
        // 第二个点：使用二次贝塞尔曲线
        final controlPoint = Offset(
          (validPoints[i - 1].dx + validPoints[i].dx) / 2,
          (validPoints[i - 1].dy + validPoints[i].dy) / 2,
        );
        path.quadraticBezierTo(
          controlPoint.dx,
          controlPoint.dy,
          validPoints[i].dx,
          validPoints[i].dy,
        );
      } else if (i == validPoints.length - 1) {
        // 最后一个点：使用二次贝塞尔曲线
        final controlPoint = Offset(
          (validPoints[i - 1].dx + validPoints[i].dx) / 2,
          (validPoints[i - 1].dy + validPoints[i].dy) / 2,
        );
        path.quadraticBezierTo(
          controlPoint.dx,
          controlPoint.dy,
          validPoints[i].dx,
          validPoints[i].dy,
        );
        } else {
        // 中间点：使用三次贝塞尔曲线，计算更平滑的控制点
        final prevPoint = validPoints[i - 1];
        final currentPoint = validPoints[i];
        final nextPoint = validPoints[i + 1];
        
        // 计算方向向量
        final dx1 = currentPoint.dx - prevPoint.dx;
        final dy1 = currentPoint.dy - prevPoint.dy;
        final dx2 = nextPoint.dx - currentPoint.dx;
        final dy2 = nextPoint.dy - currentPoint.dy;
        
        // 使用张力系数控制曲线的平滑程度
        final tension = 0.3;
              final cp1 = Offset(
          prevPoint.dx + dx1 * tension,
          prevPoint.dy + dy1 * tension,
              );
              final cp2 = Offset(
          currentPoint.dx - dx2 * tension,
          currentPoint.dy - dy2 * tension,
              );
              
              path.cubicTo(
                cp1.dx, cp1.dy,
                cp2.dx, cp2.dy,
          currentPoint.dx, currentPoint.dy,
              );
      }
    }

    canvas.drawPath(path, linePaint);
  }

  // 绘制BOLL标签（支持选中日期联动）
  void _drawBollLabels(Canvas canvas, Size size, List<KlineData> visibleData, List<BollData> bollDataList,
      int? selectedIndex, double bollChartTop, double bollChartHeight) {
    if (bollDataList.isEmpty) return;

    // 计算BOLL值的范围
    double maxBoll = bollDataList.map((e) => math.max(e.upper, math.max(e.middle, e.lower))).reduce(math.max);
    double minBoll = bollDataList.map((e) => math.min(e.upper, math.min(e.middle, e.lower))).reduce(math.min);
    
    if (maxBoll == minBoll) {
      maxBoll = minBoll + 1.0;
    }

    final textStyle = TextStyle(
      color: Colors.grey[700],
      fontSize: 9,
    );
    final textPainter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );

    // 不绘制BOLL Y轴刻度值
    // for (int i = 0; i <= 4; i++) {
    //   final value = maxBoll - (maxBoll - minBoll) * i / 4;
    //   textPainter.text = TextSpan(
    //     text: value.toStringAsFixed(2),
    //     style: textStyle,
    //   );
    //   textPainter.layout();
    //   final y = bollChartTop + bollChartHeight * i / 4;
    //   textPainter.paint(
    //     canvas,
    //     Offset(priceLabelPadding, y - textPainter.height / 2 - 2),
    //   );
    // }

    // 绘制BOLL指标名称和数值（在图表右上角）
    // 如果有选中，显示选中日期的数据；否则显示最新的数据
    BollData? displayData;
    if (selectedIndex != null && selectedIndex >= 0 && selectedIndex < visibleData.length) {
      // 显示选中日期的BOLL数据
      final selectedKline = visibleData[selectedIndex];
      displayData = bollDataList.firstWhere(
        (b) => b.tradeDate == selectedKline.tradeDate,
        orElse: () => bollDataList.last, // 如果找不到，使用最新的
      );
    } else {
      // 显示最新的BOLL数据
      displayData = bollDataList.last;
    }
    
    if (displayData != null) {
      // 计算趋势箭头（与前一个值比较）
      String getTrend(double? current, double? prev) {
        if (current == null || prev == null) return '↓';
        return current >= prev ? '↑' : '↓';
      }
      
      // 查找当前数据在列表中的索引
      int currentIndex = bollDataList.indexOf(displayData);
      
      // 获取前一个BOLL数据
      double? prevUpper, prevMiddle, prevLower;
      if (currentIndex > 0) {
        final prev = bollDataList[currentIndex - 1];
        prevUpper = prev.upper;
        prevMiddle = prev.middle;
        prevLower = prev.lower;
      }
      
      final upperTrend = getTrend(displayData.upper, prevUpper);
      final middleTrend = getTrend(displayData.middle, prevMiddle);
      final lowerTrend = getTrend(displayData.lower, prevLower);
      
      // 箭头颜色：上涨用红色，下跌用绿色
      final middleTrendColor = middleTrend == '↑' ? Colors.red[700]! : Colors.green[700]!;
      final upperTrendColor = upperTrend == '↑' ? Colors.red[700]! : Colors.green[700]!;
      final lowerTrendColor = lowerTrend == '↑' ? Colors.red[700]! : Colors.green[700]!;
      
      // 使用RichText分别设置文本和箭头的样式
      final baseTextStyle = TextStyle(
        color: Colors.grey[800],
        fontSize: 10,
        fontWeight: FontWeight.w500,
      );
      final arrowTextStyle = TextStyle(
        color: Colors.grey[800],
        fontSize: 14, // 箭头更大
        fontWeight: FontWeight.bold,
      );
      
      final labelPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(text: 'BOLL ▼ MID:', style: baseTextStyle),
            TextSpan(text: displayData.middle.toStringAsFixed(2), style: baseTextStyle),
            TextSpan(text: middleTrend, style: arrowTextStyle.copyWith(color: middleTrendColor)),
            TextSpan(text: ' UP:', style: baseTextStyle),
            TextSpan(text: displayData.upper.toStringAsFixed(2), style: baseTextStyle),
            TextSpan(text: upperTrend, style: arrowTextStyle.copyWith(color: upperTrendColor)),
            TextSpan(text: ' LOW:', style: baseTextStyle),
            TextSpan(text: displayData.lower.toStringAsFixed(2), style: baseTextStyle),
            TextSpan(text: lowerTrend, style: arrowTextStyle.copyWith(color: lowerTrendColor)),
          ],
        ),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      );
      labelPainter.layout();
      
      // 计算标签位置（在标签区域内的右上角）
      const padding = 4.0;
      const backgroundPadding = 2.0;
      final labelX = size.width - labelPainter.width - padding;
      // 标签在标签区域内的垂直居中位置
      final labelY = bollChartTop + (bollChartHeight - labelPainter.height) / 2;
      
      // 先绘制白色背景矩形（接近透明）
      final backgroundRect = Rect.fromLTWH(
        labelX - backgroundPadding,
        labelY - backgroundPadding,
        labelPainter.width + backgroundPadding * 2,
        labelPainter.height + backgroundPadding * 2,
      );
      final backgroundPaint = Paint()
        ..color = Colors.white.withOpacity(0.15) // 接近透明的白色背景，15%不透明度
        ..style = PaintingStyle.fill;
      canvas.drawRect(backgroundRect, backgroundPaint);
      
      // 再绘制文本（在背景之上）
      labelPainter.paint(
        canvas,
        Offset(labelX, labelY),
      );
    }
  }

  @override
  bool shouldRepaint(KlineChartPainter oldDelegate) {
    // 检查选中索引是否变化（影响竖线显示）
    if (oldDelegate.selectedIndex != selectedIndex) {
      return true;
    }
    // 比较数据长度和内容，确保数据变化时重新绘制
    if (oldDelegate.klineDataList.length != klineDataList.length) {
      return true;
    }
    if (oldDelegate.macdDataList.length != macdDataList.length) {
      return true;
    }
    if (oldDelegate.bollDataList.length != bollDataList.length) {
      return true;
    }
    // 比较第一个和最后一个数据点，确保数据范围变化时重新绘制
    if (klineDataList.isNotEmpty && oldDelegate.klineDataList.isNotEmpty) {
      final oldFirst = oldDelegate.klineDataList.first;
      final newFirst = klineDataList.first;
      final oldLast = oldDelegate.klineDataList.last;
      final newLast = klineDataList.last;
      
      if (oldFirst.tradeDate != newFirst.tradeDate ||
          oldLast.tradeDate != newLast.tradeDate ||
          oldFirst.close != newFirst.close ||
          oldLast.close != newLast.close) {
        return true;
      }
    }
    return false;
  }
}

