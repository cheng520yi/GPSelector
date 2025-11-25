class StockInfo {
  final String tsCode;
  final String name;
  final String symbol;
  final String area;
  final String industry;
  final String market;
  final String listDate;
  final double? totalMarketValue; // 总市值（亿元）
  final double? circMarketValue; // 流通市值（亿元）

  StockInfo({
    required this.tsCode,
    required this.name,
    this.symbol = '',
    this.area = '',
    this.industry = '',
    this.market = '',
    this.listDate = '',
    this.totalMarketValue,
    this.circMarketValue,
  });

  // 从新的JSON格式创建（键值对：股票代码：股票名称）
  factory StockInfo.fromMapEntry(MapEntry<String, dynamic> entry) {
    final tsCode = entry.key;
    final name = entry.value.toString();
    
    // 从股票代码中提取symbol
    final symbol = tsCode.split('.').first;
    
    return StockInfo(
      tsCode: tsCode,
      name: name,
      symbol: symbol,
      area: _getAreaFromCode(tsCode),
      industry: '未知',
      market: _getMarketFromCode(tsCode),
      listDate: '',
      totalMarketValue: null,
      circMarketValue: null,
    );
  }

  // 从旧的JSON格式创建
  factory StockInfo.fromJson(Map<String, dynamic> json) {
    return StockInfo(
      tsCode: json['ts_code'] ?? '',
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      area: json['area'] ?? '',
      industry: json['industry'] ?? '',
      market: json['market'] ?? '',
      listDate: json['list_date'] ?? '',
      totalMarketValue: json['total_market_value']?.toDouble(),
      circMarketValue: json['circ_market_value']?.toDouble(),
    );
  }

  // 根据股票代码判断地区
  static String _getAreaFromCode(String tsCode) {
    if (tsCode.endsWith('.SZ')) {
      return '深圳';
    } else if (tsCode.endsWith('.SH')) {
      return '上海';
    } else if (tsCode.endsWith('.BJ')) {
      return '北京';
    }
    return '未知';
  }

  // 根据股票代码判断市场
  static String _getMarketFromCode(String tsCode) {
    if (tsCode.endsWith('.SZ')) {
      return '深交所';
    } else if (tsCode.endsWith('.SH')) {
      return '上交所';
    } else if (tsCode.endsWith('.BJ')) {
      return '北交所';
    }
    return '未知';
  }

  Map<String, dynamic> toJson() {
    return {
      'ts_code': tsCode,
      'symbol': symbol,
      'name': name,
      'area': area,
      'industry': industry,
      'market': market,
      'list_date': listDate,
      'total_market_value': totalMarketValue,
      'circ_market_value': circMarketValue,
    };
  }
}
