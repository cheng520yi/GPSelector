import 'kline_data.dart';
import 'stock_info.dart';

class StockRanking {
  final StockInfo stockInfo;
  final KlineData klineData;
  final double amountInYi;
  final int rank;

  StockRanking({
    required this.stockInfo,
    required this.klineData,
    required this.amountInYi,
    required this.rank,
  });

  // 按成交额排序
  static List<StockRanking> sortByAmount(List<StockRanking> rankings) {
    rankings.sort((a, b) => b.amountInYi.compareTo(a.amountInYi));
    
    // 重新分配排名
    for (int i = 0; i < rankings.length; i++) {
      rankings[i] = StockRanking(
        stockInfo: rankings[i].stockInfo,
        klineData: rankings[i].klineData,
        amountInYi: rankings[i].amountInYi,
        rank: i + 1,
      );
    }
    
    return rankings;
  }
}
