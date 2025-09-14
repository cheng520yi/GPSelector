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
    );
  }

  // 获取成交额（亿元）
  double get amountInYi {
    return amount / 100000; // 千元转换为亿元
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
