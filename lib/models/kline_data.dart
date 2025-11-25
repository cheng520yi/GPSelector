class KlineData {
  final String tsCode;
  final String tradeDate;
  final double open;
  final double high;
  final double low;
  final double close;
  final double preClose;
  final double change;
  final double pctChg;
  final double vol;
  final double amount; // 成交额（千元）
  
  // 前复权价格（用于BOLL图表叠加）
  final double? openQfq;
  final double? highQfq;
  final double? lowQfq;
  final double? closeQfq;

  KlineData({
    required this.tsCode,
    required this.tradeDate,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.preClose,
    required this.change,
    required this.pctChg,
    required this.vol,
    required this.amount,
    this.openQfq,
    this.highQfq,
    this.lowQfq,
    this.closeQfq,
  });

  factory KlineData.fromJson(Map<String, dynamic> json) {
    return KlineData(
      tsCode: json['ts_code'] ?? '',
      tradeDate: json['trade_date'] ?? '',
      open: double.tryParse(json['open']?.toString() ?? '0') ?? 0.0,
      high: double.tryParse(json['high']?.toString() ?? '0') ?? 0.0,
      low: double.tryParse(json['low']?.toString() ?? '0') ?? 0.0,
      close: double.tryParse(json['close']?.toString() ?? '0') ?? 0.0,
      preClose: double.tryParse(json['pre_close']?.toString() ?? '0') ?? 0.0,
      change: double.tryParse(json['change']?.toString() ?? '0') ?? 0.0,
      pctChg: double.tryParse(json['pct_chg']?.toString() ?? '0') ?? 0.0,
      vol: double.tryParse(json['vol']?.toString() ?? '0') ?? 0.0,
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      openQfq: json['open_qfq'] != null ? double.tryParse(json['open_qfq']?.toString() ?? '0') : null,
      highQfq: json['high_qfq'] != null ? double.tryParse(json['high_qfq']?.toString() ?? '0') : null,
      lowQfq: json['low_qfq'] != null ? double.tryParse(json['low_qfq']?.toString() ?? '0') : null,
      closeQfq: json['close_qfq'] != null ? double.tryParse(json['close_qfq']?.toString() ?? '0') : null,
    );
  }

  // 获取成交额（亿元）
  double get amountInYi {
    return amount / 100000; // 千元转换为亿元
  }

  // 计算涨跌额（实时数据需要）
  double get calculatedChange {
    if (preClose > 0) {
      return close - preClose;
    }
    return change;
  }

  // 计算涨跌幅（实时数据需要）
  double get calculatedPctChg {
    if (preClose > 0) {
      return ((close - preClose) / preClose) * 100;
    }
    return pctChg;
  }

  Map<String, dynamic> toJson() {
    return {
      'ts_code': tsCode,
      'trade_date': tradeDate,
      'open': open,
      'high': high,
      'low': low,
      'close': close,
      'pre_close': preClose,
      'change': change,
      'pct_chg': pctChg,
      'vol': vol,
      'amount': amount,
    };
  }
}
