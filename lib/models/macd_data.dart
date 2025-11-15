class MacdData {
  final String tsCode;
  final String tradeDate;
  final double dif; // DIF值
  final double dea; // DEA值
  final double macd; // MACD值（柱状图，M值）

  MacdData({
    required this.tsCode,
    required this.tradeDate,
    required this.dif,
    required this.dea,
    required this.macd,
  });

  factory MacdData.fromJson(Map<String, dynamic> json) {
    return MacdData(
      tsCode: json['ts_code'] ?? '',
      tradeDate: json['trade_date'] ?? '',
      dif: double.tryParse(json['dif']?.toString() ?? '0') ?? 0.0,
      dea: double.tryParse(json['dea']?.toString() ?? '0') ?? 0.0,
      macd: double.tryParse(json['macd']?.toString() ?? '0') ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ts_code': tsCode,
      'trade_date': tradeDate,
      'dif': dif,
      'dea': dea,
      'macd': macd,
    };
  }
}

