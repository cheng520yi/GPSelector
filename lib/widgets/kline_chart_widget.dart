import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/kline_data.dart';

class KlineChartWidget extends StatelessWidget {
  final List<KlineData> klineDataList;
  final int? displayDays; // 可选：要显示的天数，如果为null则显示所有数据
  final int subChartCount; // 副图数量，默认为1（成交量），支持4个副图

  const KlineChartWidget({
    super.key,
    required this.klineDataList,
    this.displayDays,
    this.subChartCount = 1, // 默认1个副图（成交量）
  });

  @override
  Widget build(BuildContext context) {
    if (klineDataList.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    return CustomPaint(
      painter: KlineChartPainter(
        klineDataList: klineDataList,
        displayDays: displayDays,
        subChartCount: subChartCount,
      ),
      size: Size.infinite,
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
  final int? displayDays; // 可选：要显示的天数，如果为null则显示所有数据
  final int subChartCount; // 副图数量
  static const double leftPadding = 0.0; // 左侧padding（设为0，让图表铺满宽度）
  static const double rightPadding = 0.0; // 右侧padding（设为0，让图表铺满宽度）
  static const double topPadding = 0.0; // 顶部padding（设为0，完全占满）
  static const double bottomPadding = 18.0; // 底部padding（用于日期标签，尽量紧凑）
  static const double priceLabelPadding = 2.0; // 价格标签距离左侧的间距（覆盖在图表上，偏左展示）
  static const double chartGap = 4.0; // K线图和成交量图之间的间隙（减小间隙）
  static const double candleWidth = 6.0;
  static const double candleSpacing = 2.0;
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
    this.displayDays,
    this.subChartCount = 1,
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

    // 绘制K线图背景网格
    _drawKlineGrid(canvas, size, maxPrice, minPrice, klineChartHeight);

    // 绘制价格标签
    _drawPriceLabels(canvas, size, maxPrice, minPrice, klineChartHeight);

    // 先绘制均线（在K线下方）
    _drawMaLines(canvas, size, visibleData, visibleMaPoints, maxPrice, minPrice, chartWidth, klineChartHeight);

    // 再绘制K线（在均线上方）
    _drawCandles(canvas, size, visibleData, maxPrice, minPrice, chartWidth, klineChartHeight);

    // 绘制副图（成交量图表，支持多个）
    double currentSubChartTop = topPadding + klineChartHeight + chartGap;
    for (int i = 0; i < subChartCount; i++) {
      _drawVolumeChart(canvas, size, visibleData, maxVolume, chartWidth, currentSubChartTop, subChartHeight);
      _drawVolumeLabels(canvas, size, maxVolume, currentSubChartTop, subChartHeight);
      currentSubChartTop += subChartHeight + chartGap;
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

  void _drawDateLabels(Canvas canvas, Size size, List<KlineData> visibleData, double volumeChartTop) {
    if (visibleData.isEmpty) return;

    final textStyle = TextStyle(
      color: Colors.grey[700],
      fontSize: 9, // 减小字体大小
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
      final requiredWidth = visibleData.length * (candleWidth + candleSpacing);
      if (requiredWidth > chartWidth) {
        final scale = chartWidth / requiredWidth;
        dynamicCandleWidth = candleWidth * scale;
        dynamicCandleSpacing = candleSpacing * scale;
      } else {
        // 数据较少，增大宽度和间距使图表铺满
        final availableWidthPerCandle = chartWidth / visibleData.length;
        final totalRatio = candleWidth + candleSpacing;
        dynamicCandleWidth = (candleWidth / totalRatio) * availableWidthPerCandle;
        dynamicCandleSpacing = (candleSpacing / totalRatio) * availableWidthPerCandle;
      }
    }
    
    final candleTotalWidth = dynamicCandleWidth + dynamicCandleSpacing;
    final labelCount = 5; // 显示5个日期标签

    for (int i = 0; i < labelCount; i++) {
      final index = (visibleData.length - 1) * i ~/ (labelCount - 1);
      if (index < visibleData.length) {
        final date = visibleData[index].tradeDate;
        final dateStr = '${date.substring(4, 6)}-${date.substring(6, 8)}';
        textPainter.text = TextSpan(
          text: dateStr,
          style: textStyle,
        );
        textPainter.layout();
        final x = index * candleTotalWidth + dynamicCandleWidth / 2;
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, size.height - bottomPadding + 4),
        );
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
      final color = isRising ? Colors.red : Colors.green;

      // 绘制上下影线
      final shadowPaint = Paint()
        ..color = color
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(x, highY),
        Offset(x, lowY),
        shadowPaint,
      );

      // 绘制实体（矩形）
      final bodyTop = math.min(openY, closeY);
      final bodyBottom = math.max(openY, closeY);
      final bodyHeight = math.max(bodyBottom - bodyTop, 1.0); // 至少1像素高

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

      // 如果是跌，绘制空心（白色边框）
      if (!isRising) {
        final borderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawRect(
          Rect.fromLTWH(
            x - dynamicCandleWidth / 2,
            bodyTop,
            dynamicCandleWidth,
            bodyHeight,
          ),
          borderPaint,
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
      ..strokeWidth = 1.5
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

      // 判断涨跌（与K线颜色一致）
      final isRising = data.close >= data.open;
      final color = isRising ? Colors.red.withOpacity(0.6) : Colors.green.withOpacity(0.6);

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


  @override
  bool shouldRepaint(KlineChartPainter oldDelegate) {
    // 比较数据长度和内容，确保数据变化时重新绘制
    if (oldDelegate.klineDataList.length != klineDataList.length) {
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

