class FavoriteGroup {
  final String id;
  String name;
  String? color; // 颜色代码，如 '#FF0000'
  bool isPinned; // 是否置顶
  int order; // 排序顺序
  List<String> stockCodes; // 股票代码列表

  FavoriteGroup({
    required this.id,
    required this.name,
    this.color,
    this.isPinned = false,
    this.order = 0,
    List<String>? stockCodes,
  }) : stockCodes = stockCodes ?? [];

  factory FavoriteGroup.fromJson(Map<String, dynamic> json) {
    return FavoriteGroup(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      color: json['color'],
      isPinned: json['is_pinned'] ?? false,
      order: json['order'] ?? 0,
      stockCodes: json['stock_codes'] != null
          ? List<String>.from(json['stock_codes'])
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'is_pinned': isPinned,
      'order': order,
      'stock_codes': stockCodes,
    };
  }

  FavoriteGroup copyWith({
    String? name,
    String? color,
    bool? isPinned,
    int? order,
    List<String>? stockCodes,
  }) {
    return FavoriteGroup(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      isPinned: isPinned ?? this.isPinned,
      order: order ?? this.order,
      stockCodes: stockCodes ?? this.stockCodes,
    );
  }
}

