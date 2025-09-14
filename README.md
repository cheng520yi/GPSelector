# 股票筛选器 (GPSelector)

一个基于Flutter开发的股票筛选应用，用于按照成交额等条件筛选符合要求的股票。

## 功能特性

- 📊 从本地JSON文件加载股票基础数据
- 🔍 通过Tushare API获取实时K线数据
- 💰 按成交额筛选（默认≥5亿元）
- 📈 按成交额排名显示股票
- 🏭 支持按行业筛选
- 🌍 支持按地区筛选
- 📱 现代化的Material Design界面

## 技术栈

- **Flutter**: 跨平台移动应用框架
- **HTTP**: 网络请求
- **Intl**: 日期格式化
- **Tushare API**: 股票数据接口

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── models/                      # 数据模型
│   ├── stock_info.dart         # 股票基础信息模型
│   ├── kline_data.dart         # K线数据模型
│   └── stock_ranking.dart      # 股票排名模型
├── services/                    # 服务层
│   ├── stock_api_service.dart  # API服务
│   └── stock_filter_service.dart # 筛选服务
└── screens/                     # 界面
    └── stock_selector_screen.dart # 主界面
assets/
└── stock_data.json             # 股票基础数据
```

## 安装和运行

1. 确保已安装Flutter SDK
2. 克隆项目到本地
3. 在项目根目录运行：
   ```bash
   flutter pub get
   flutter run
   ```

## 配置说明

### API配置
- API地址: `http://api.tushare.pro`
- Token: 已在代码中配置
- 默认获取60天的日K线数据

### 筛选条件
- 最低成交额: 5亿元
- 数据来源: 最新交易日
- 排序方式: 按成交额降序

## 使用说明

1. 启动应用后，会自动加载股票数据
2. 使用顶部的行业和地区筛选器进行筛选
3. 点击刷新按钮重新加载数据
4. 股票按成交额排名显示，前3名用金色标识

## 注意事项

- 需要网络连接才能获取实时数据
- API请求有频率限制，请勿频繁刷新
- 成交额数据单位为亿元
- 涨跌幅用红绿色区分涨跌

## 许可证

MIT License
