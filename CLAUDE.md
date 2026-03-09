# MT5 配对交易 EA (PairTrader)

## 项目概述

MT5 Expert Advisor，支持两个品种同时开仓（一多一空）组成配对，并对配对持仓进行盈亏监控和自动平仓。

## 目录结构

```
Experts/PairTrader.mq5      # EA 主程序（入口 + 面板 + 事件处理）
Include/PairTradeManager.mqh # 配对管理（数据结构、交易执行、监控、持久化）
```

## 功能清单

### 已完成功能

- [x] 面板 UI（CAppDialog）：品种/方向/手数输入、止盈止损设置、一键开仓按钮
- [x] 开仓逻辑：同时对两个品种下市价单，用 Comment("PAIR_xxx") 关联配对
- [x] 开仓回滚：一笔失败时自动平掉已成功的另一笔
- [x] 多对同时持仓：支持同时持有多组配对
- [x] 盈亏监控：OnTimer 每秒遍历所有配对，计算合并浮动盈亏(USD)
- [x] 自动平仓：浮盈 >= 止盈阈值 或 浮亏 <= -止损阈值 时自动平掉整对
- [x] 手动平仓：面板上单对平仓按钮 + 全部平仓按钮
- [x] 持仓列表显示：面板实时显示每对的品种、方向、盈亏
- [x] 持久化：开仓/平仓后保存到 CSV 文件，EA 重启时恢复配对关系
- [x] 跨品种支持：自动 SymbolSelect 添加品种到市场报价

### 待开发功能

- [ ] 品种下拉选择器（当前为文本输入）
- [ ] 历史交易记录面板

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

- EA 可挂载在任意品种图表上，交易品种由面板输入决定
- 跨品种下单前需先 `SymbolSelect(symbol, true)` 添加到市场报价
- 使用市价单避免限价单部分成交的问题
- 持久化文件路径: `MQL5/Files/PairTrader_data.csv`

## 开发环境

- 语言: MQL5
- 平台: MetaTrader 5
- 编译: MetaEditor 或 MT5 内置编译器
