import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import '../models/kline_data.dart';
import '../models/macd_data.dart';

class KlineChartWidget extends StatefulWidget {
  final List<KlineData> klineDataList;
  final List<MacdData> macdDataList; // MACD数据
  final int? displayDays; // 可选：要显示的天数，如果为null则显示所有数据
  final int subChartCount; // 副图数量，默认为1（成交量），支持4个副图
  final String chartType; // 图表类型：daily(日K), weekly(周K), monthly(月K)
  final Function(KlineData, Map<String, double?>)? onDataSelected; // 选中数据回调

  const KlineChartWidget({
    super.key,
    required this.klineDataList,
    this.macdDataList = const [],
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

    // 根据副图数量计算K线图和成交量图的高度
    final klineRatio = _getKlineChartHeightRatio(subChartCount);
    final availableHeight = size.height - topPadding - bottomPadding - chartGap * subChartCount;
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

    // 绘制价格标签
    _drawPriceLabels(canvas, size, maxPrice, minPrice, klineChartHeight);

    // 先绘制K线（在均线下方）
    _drawCandles(canvas, size, visibleData, maxPrice, minPrice, chartWidth, klineChartHeight);

    // 再绘制均线（在K线上方，确保均线可见）
    _drawMaLines(canvas, size, visibleData, visibleMaPoints, maxPrice, minPrice, chartWidth, klineChartHeight);

    // 绘制副图（固定顺序：第1个=成交量，第2个=MACD，第3、4个=成交量）
    double currentSubChartTop = topPadding + klineChartHeight + chartGap;
    print('🔍 开始绘制副图: subChartCount=$subChartCount, macdDataList.length=${macdDataList.length}');
    for (int i = 0; i < subChartCount; i++) {
      print('🔍 绘制第${i + 1}个副图: i=$i');
      if (i == 1 && macdDataList.isNotEmpty) {
        // 第二个副图（索引1）显示MACD指标
        print('✅ 绘制MACD图表（第2个副图）');
        _drawMacdChart(canvas, size, visibleData, macdDataList, chartWidth, currentSubChartTop, subChartHeight);
        _drawMacdLabels(canvas, size, macdDataList, currentSubChartTop, subChartHeight);
      } else {
        // 第1、3、4个副图显示成交量
        print('📊 绘制成交量图表（第${i + 1}个副图）');
        _drawVolumeChart(canvas, size, visibleData, maxVolume, chartWidth, currentSubChartTop, subChartHeight);
        _drawVolumeLabels(canvas, size, maxVolume, currentSubChartTop, subChartHeight);
      }
      currentSubChartTop += subChartHeight + chartGap;
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

    // 创建日期到MACD数据的映射
    Map<String, MacdData> macdMap = {};
    for (var macd in macdDataList) {
      macdMap[macd.tradeDate] = macd;
    }

    // 获取可见数据对应的MACD数据
    List<MacdData> visibleMacdData = [];
    int matchedCount = 0;
    int unmatchedCount = 0;
    for (var kline in visibleData) {
      final macd = macdMap[kline.tradeDate];
      if (macd != null) {
        visibleMacdData.add(macd);
        matchedCount++;
      } else {
        unmatchedCount++;
        if (unmatchedCount <= 3) {
          print('⚠️ 日期不匹配: K线日期=${kline.tradeDate}, MACD数据日期=${macdMap.keys.take(3).toList()}');
        }
      }
    }

    print('🔍 MACD可见数据: ${visibleMacdData.length}/${visibleData.length} (匹配:$matchedCount, 不匹配:$unmatchedCount)');
    if (visibleMacdData.isNotEmpty) {
      print('🔍 MACD数据示例: 日期=${visibleMacdData.first.tradeDate}, DIF=${visibleMacdData.first.dif}, DEA=${visibleMacdData.first.dea}, MACD=${visibleMacdData.first.macd}');
    }

    if (visibleMacdData.isEmpty) {
      print('⚠️ MACD可见数据为空');
      return;
    }

    // 计算MACD值的范围
    double maxMacd = visibleMacdData.map((e) => math.max(e.dif, math.max(e.dea, e.macd))).reduce(math.max);
    double minMacd = visibleMacdData.map((e) => math.min(e.dif, math.min(e.dea, e.macd))).reduce(math.min);
    
    // 确保范围包含0
    maxMacd = math.max(maxMacd.abs(), minMacd.abs());
    minMacd = -maxMacd;
    
    if (maxMacd == minMacd) {
      maxMacd = 1.0;
      minMacd = -1.0;
    }

    final macdRange = maxMacd - minMacd;
    
    print('🔍 MACD范围: min=$minMacd, max=$maxMacd, range=$macdRange');

    // 绘制MACD网格线（0轴和水平线）
    final gridPaint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 0.5;
    
    // 绘制0轴（中间线）
    final zeroY = macdChartTop + macdChartHeight / 2;
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(chartWidth, zeroY),
      gridPaint,
    );
    
    // 绘制其他水平网格线
    for (int i = 1; i <= 2; i++) {
      final y = macdChartTop + macdChartHeight * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(chartWidth, y),
        gridPaint,
      );
    }

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

    // 绘制MACD柱状图（M值）
    for (int i = 0; i < visibleMacdData.length; i++) {
      final macd = visibleMacdData[i];
      final x = i * candleTotalWidth + dynamicCandleWidth / 2;
      
      // 计算MACD柱状图的高度和位置
      final macdValue = macd.macd;
      final macdHeight = (macdValue.abs() / macdRange) * macdChartHeight * 0.5; // 柱状图占一半高度
      final zeroY = macdChartTop + macdChartHeight / 2; // 0值在中间
      
      final color = macdValue >= 0 ? Colors.red.withOpacity(0.6) : Colors.green[700]!.withOpacity(0.6); // 使用更深的绿色
      
      final macdPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      
      if (macdValue >= 0) {
        // 正值，向上绘制
        canvas.drawRect(
          Rect.fromLTWH(
            x - dynamicCandleWidth / 2,
            zeroY - macdHeight,
            dynamicCandleWidth,
            macdHeight,
          ),
          macdPaint,
        );
      } else {
        // 负值，向下绘制
        canvas.drawRect(
          Rect.fromLTWH(
            x - dynamicCandleWidth / 2,
            zeroY,
            dynamicCandleWidth,
            macdHeight,
          ),
          macdPaint,
        );
      }
    }

    // 绘制DIF线（黑色）- 检查是否有非零的有效数据
    bool hasValidDif = visibleMacdData.any((m) => !m.dif.isNaN && !m.dif.isInfinite && m.dif != 0.0);
    if (hasValidDif) {
      print('🔍 开始绘制DIF线，有效数据点: ${visibleMacdData.where((m) => !m.dif.isNaN && !m.dif.isInfinite && m.dif != 0.0).length}');
      _drawMacdLine(canvas, visibleMacdData, (m) => m.dif, Colors.black, 
          minMacd, maxMacd, macdRange, macdChartHeight, macdChartTop, chartWidth);
    } else {
      print('⚠️ 没有有效的DIF数据（所有值都是0、NaN或Infinite）');
      // 打印DIF值范围以便调试
      if (visibleMacdData.isNotEmpty) {
        final difValues = visibleMacdData.map((m) => m.dif).where((v) => !v.isNaN && !v.isInfinite).toList();
        if (difValues.isNotEmpty) {
          print('🔍 DIF值范围: min=${difValues.reduce((a, b) => a < b ? a : b)}, max=${difValues.reduce((a, b) => a > b ? a : b)}');
        }
      }
    }
    
    // 绘制DEA线（黄色/橙色）- 检查是否有非零的有效数据
    bool hasValidDea = visibleMacdData.any((m) => !m.dea.isNaN && !m.dea.isInfinite && m.dea != 0.0);
    if (hasValidDea) {
      print('🔍 开始绘制DEA线，有效数据点: ${visibleMacdData.where((m) => !m.dea.isNaN && !m.dea.isInfinite && m.dea != 0.0).length}');
      _drawMacdLine(canvas, visibleMacdData, (m) => m.dea, Colors.orange, 
          minMacd, maxMacd, macdRange, macdChartHeight, macdChartTop, chartWidth);
    } else {
      print('⚠️ 没有有效的DEA数据（所有值都是0、NaN或Infinite）');
      // 打印DEA值范围以便调试
      if (visibleMacdData.isNotEmpty) {
        final deaValues = visibleMacdData.map((m) => m.dea).where((v) => !v.isNaN && !v.isInfinite).toList();
        if (deaValues.isNotEmpty) {
          print('🔍 DEA值范围: min=${deaValues.reduce((a, b) => a < b ? a : b)}, max=${deaValues.reduce((a, b) => a > b ? a : b)}');
        }
      }
    }
  }

  // 绘制MACD线（DIF或DEA）
  void _drawMacdLine(Canvas canvas, List<MacdData> macdDataList,
      double Function(MacdData) getValue, Color color,
      double minMacd, double maxMacd, double macdRange,
      double chartHeight, double chartTop, double chartWidth) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.3 // 稍微细一点
      ..style = PaintingStyle.stroke;

    // 动态计算K线宽度和间距
    double dynamicCandleWidth = candleWidth;
    double dynamicCandleSpacing = candleSpacing;
    
    if (macdDataList.length > 0) {
      if (macdDataList.length == 1) {
        dynamicCandleWidth = chartWidth;
        dynamicCandleSpacing = 0;
      } else {
        final availableWidthPerCandle = chartWidth / macdDataList.length;
        final totalRatio = candleWidth + candleSpacing;
        dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }
    
    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;

    // 收集所有有效的点
    List<Offset> validPoints = [];
    for (int i = 0; i < macdDataList.length; i++) {
      final value = getValue(macdDataList[i]);
      if (!value.isNaN && !value.isInfinite) {
        final x = i * candleTotalWidth + dynamicCandleWidth / 2;
        final y = chartTop + (maxMacd - value) / macdRange * chartHeight;
        validPoints.add(Offset(x, y));
      }
    }

    print('🔍 MACD线条有效点数: ${validPoints.length}, 数据长度: ${macdDataList.length}');

    if (validPoints.length < 2) {
      print('⚠️ MACD线条点数不足，无法绘制');
      return;
    }

    // 使用平滑曲线连接点
    final path = Path();
    path.moveTo(validPoints[0].dx, validPoints[0].dy);

    for (int i = 1; i < validPoints.length; i++) {
      if (i == 1) {
        // 第一个点，使用二次贝塞尔曲线
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
        // 最后一个点，使用二次贝塞尔曲线
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
        // 中间点，使用三次贝塞尔曲线
        final prevPoint = validPoints[i - 1];
        final currentPoint = validPoints[i];
        final nextPoint = validPoints[i + 1];
        
        final cp1 = Offset(
          (prevPoint.dx + currentPoint.dx) / 2,
          (prevPoint.dy + currentPoint.dy) / 2,
        );
        final cp2 = Offset(
          (currentPoint.dx + nextPoint.dx) / 2,
          (currentPoint.dy + nextPoint.dy) / 2,
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

  // 绘制MACD标签
  void _drawMacdLabels(Canvas canvas, Size size, List<MacdData> macdDataList,
      double macdChartTop, double macdChartHeight) {
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

    // 绘制MACD标签（覆盖在图表上，在图表内部显示）
    for (int i = 0; i <= 4; i++) {
      final value = maxMacd - (maxMacd - minMacd) * i / 4;
      textPainter.text = TextSpan(
        text: value.toStringAsFixed(2),
        style: textStyle,
      );
      textPainter.layout();
      final y = macdChartTop + macdChartHeight * i / 4;
      textPainter.paint(
        canvas,
        Offset(priceLabelPadding, y - textPainter.height / 2 - 2),
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

