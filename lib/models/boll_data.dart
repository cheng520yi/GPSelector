class BollData {
  final String tsCode;
  final String tradeDate;
  final double upper; // 上轨
  final double middle; // 中轨
  final double lower; // 下轨

  BollData({
    required this.tsCode,
    required this.tradeDate,
    required this.upper,
    required this.middle,
    required this.lower,
  });

  factory BollData.fromJson(Map<String, dynamic> json) {
    return BollData(
      tsCode: json['ts_code'] ?? '',
      tradeDate: json['trade_date'] ?? '',
      upper: double.tryParse(json['boll_upper']?.toString() ?? '0') ?? 0.0,
      middle: double.tryParse(json['boll_mid']?.toString() ?? '0') ?? 0.0,
      lower: double.tryParse(json['boll_lower']?.toString() ?? '0') ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ts_code': tsCode,
      'trade_date': tradeDate,
      'boll_upper': upper,
      'boll_mid': middle,
      'boll_lower': lower,
    };
  }
}

