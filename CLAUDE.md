# MT5 配对交易 EA (PairTrader)

## 项目概述

MT5 Expert Advisor，支持两个品种同时开仓（一多一空）组成配对，并对配对持仓进行盈亏监控和自动平仓。

## 目录结构

```
MQL5/Experts/XAUAndGC/XAUAndGC.mq5          # EA 主程序（入口 + 面板 + 事件处理）
MQL5/Include/XAUAndGC/PairTradeManager.mqh   # 配对管理（数据结构、交易执行、监控、持久化）
MQL5/Include/XAUAndGC/LicenseManager.mqh     # License 认证（启动验证 + 心跳 + 失效处理）
```

## 功能清单

### 已完成功能

- [x] 面板 UI（CAppDialog）：品种/方向/手数只读显示(Input参数)、止盈止损、一键开仓按钮
- [x] 开仓逻辑：同时对两个品种下市价单，用 Comment("PAIR_xxx") 关联配对
- [x] 开仓回滚：一笔失败时自动平掉已成功的另一笔
- [x] 多对同时持仓：支持同时持有多组配对
- [x] 盈亏监控：OnTimer 每秒遍历所有配对，计算合并浮动盈亏(USD)
- [x] 自动平仓：浮盈 >= 止盈阈值 或 浮亏 <= -止损阈值 时自动平掉整对
- [x] 手动平仓：面板上单对平仓按钮 + 全部平仓按钮
- [x] 持仓列表显示：面板实时显示每对的品种、方向、盈亏
- [x] 持久化：开仓/平仓后保存到 CSV 文件，EA 重启时恢复配对关系
- [x] 跨品种支持：自动 SymbolSelect 添加品种到市场报价
- [x] 历史交易记录：平仓后记录实际盈亏，面板显示最近5条，持久化到CSV
- [x] 基差监控：实时基差(A-B)、今日最高/最低/振幅、历史均值
- [x] 基差自动开仓：基差偏离均值超过阈值时自动开仓（Input参数控制开关/阈值/最大对数）
- [x] License认证：启动验证 + 定时心跳 + 服务器拒绝3次/网络断6次自动停止

## 设计要点

### 核心数据结构

```cpp
struct PairPosition {
   int       pairId;       // 自增ID
   string    symbolA;      // 品种A
   string    symbolB;      // 品种B
   ulong     ticketA;      // 品种A持仓单号
   ulong     ticketB;      // 品种B持仓单号
   ENUM_ORDER_TYPE dirA;   // 品种A方向 (BUY/SELL)
   ENUM_ORDER_TYPE dirB;   // 品种B方向 (BUY/SELL)
   double    lotsA;        // 品种A手数
   double    lotsB;        // 品种B手数
   datetime  openTime;     // 开仓时间
};
```

### 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 盈亏单位 | USD 金额 | 跨品种点值不同，金额更直观 |
| 配对关联 | Comment("PAIR_x") | Magic Number 留给 EA 识别自身订单 |
| 监控方式 | OnTimer(1秒) | OnTick 只响应当前图表品种 |
| 止盈止损 | 全局统一 Input 参数 | 所有配对共享同一组阈值 |
| 持久化 | CSV 文件 | 防止 EA 重启后丢失配对关系 |
| 面板框架 | CAppDialog | MQL5 标准库，开发快 |

### 注意事项

- EA 可挂载在任意品种图表上，交易品种由 Input 参数决定（面板只读显示）
- 跨品种下单前需先 `SymbolSelect(symbol, true)` 添加到市场报价
- 使用市价单避免限价单部分成交的问题
- 持久化文件路径: `MQL5/Files/PairTrader_data.csv`
- 历史记录文件: `MQL5/Files/PairTrader_history.csv`
- 基差自动开仓需设置 InpSpreadAutoOpen=true 启用，默认关闭
- 基差自动开仓逻辑：基差绝对值 >= 阈值时开仓（基差>=阈值→卖A买B，基差<=-阈值→买A卖B）
- 至少采样60次后才启动自动开仓判断，避免启动初期误判
- License验证：需在MT5「工具→选项→EA交易」中添加认证服务器URL
- License失效时自动平仓所有持仓并移除EA

## 开发环境

- 语言: MQL5
- 平台: MetaTrader 5
- 编译: MetaEditor 或 MT5 内置编译器
