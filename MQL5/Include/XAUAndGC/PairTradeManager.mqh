//+------------------------------------------------------------------+
//|                                            PairTradeManager.mqh  |
//|                         配对交易管理模块                           |
//|         数据结构、交易执行、盈亏监控、持久化                         |
//+------------------------------------------------------------------+
#property copyright "PairTrader EA"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| 配对持仓结构体                                                     |
//+------------------------------------------------------------------+
struct PairPosition
{
   int               pairId;
   string            symbolA;
   string            symbolB;
   ulong             ticketA;
   ulong             ticketB;
   ENUM_ORDER_TYPE   dirA;
   ENUM_ORDER_TYPE   dirB;
   double            lotsA;
   double            lotsB;
   datetime          openTime;
};

//+------------------------------------------------------------------+
//| 平仓历史记录结构体                                                  |
//+------------------------------------------------------------------+
struct PairHistory
{
   int               pairId;
   string            symbolA;
   string            symbolB;
   ENUM_ORDER_TYPE   dirA;
   ENUM_ORDER_TYPE   dirB;
   double            lotsA;
   double            lotsB;
   datetime          openTime;
   datetime          closeTime;
   string            reason;       // "止盈" / "止损" / "手动"
   double            realProfit;   // 实际已实现盈亏
};

//+------------------------------------------------------------------+
//| 基差监控器                                                         |
//+------------------------------------------------------------------+
class CSpreadMonitor
{
private:
   string            m_symbolA;
   string            m_symbolB;
   double            m_dayHigh;
   double            m_dayLow;
   double            m_current;
   datetime          m_dayStart;       // 当日起始时间
   double            m_sumSpread;      // 历史累计基差（用于计算均值）
   int               m_sumCount;       // 历史采样次数
   double            m_histAvg;        // 历史均值

public:
                     CSpreadMonitor();
   void              Init(string symA, string symB);
   void              Update();         // OnTimer中调用
   double            Current()    { return m_current; }
   double            DayHigh()    { return m_dayHigh; }
   double            DayLow()     { return m_dayLow; }
   double            HistAvg()    { return (m_sumCount > 0) ? m_sumSpread / m_sumCount : 0.0; }
   int               SampleCount(){ return m_sumCount; }
   string            SymbolA()    { return m_symbolA; }
   string            SymbolB()    { return m_symbolB; }
};

//+------------------------------------------------------------------+
//| CSpreadMonitor 构造函数                                            |
//+------------------------------------------------------------------+
CSpreadMonitor::CSpreadMonitor()
{
   m_dayHigh   = -DBL_MAX;
   m_dayLow    = DBL_MAX;
   m_current   = 0.0;
   m_dayStart  = 0;
   m_sumSpread = 0.0;
   m_sumCount  = 0;
   m_histAvg   = 0.0;
}

//+------------------------------------------------------------------+
//| 初始化基差监控                                                      |
//+------------------------------------------------------------------+
void CSpreadMonitor::Init(string symA, string symB)
{
   m_symbolA  = symA;
   m_symbolB  = symB;
   m_dayStart = 0;
   m_dayHigh  = -DBL_MAX;
   m_dayLow   = DBL_MAX;
   m_current  = 0.0;
   m_sumSpread = 0.0;
   m_sumCount  = 0;

   // 添加品种到市场报价
   SymbolSelect(symA, true);
   SymbolSelect(symB, true);
}

//+------------------------------------------------------------------+
//| 更新基差（每次OnTimer调用）                                          |
//+------------------------------------------------------------------+
void CSpreadMonitor::Update()
{
   double bidA = SymbolInfoDouble(m_symbolA, SYMBOL_BID);
   double bidB = SymbolInfoDouble(m_symbolB, SYMBOL_BID);

   if(bidA <= 0 || bidB <= 0)
      return;

   m_current = bidA - bidB;

   // 检查是否跨天，重置日内高低
   MqlDateTime now;
   TimeCurrent(now);
   datetime today = StringToTime(IntegerToString(now.year) + "."
                  + IntegerToString(now.mon) + "."
                  + IntegerToString(now.day));

   if(today != m_dayStart)
   {
      m_dayStart = today;
      m_dayHigh  = m_current;
      m_dayLow   = m_current;
      Print("[SpreadMonitor] 新交易日，基差重置. 当前基差=", DoubleToString(m_current, 2));
   }

   if(m_current > m_dayHigh) m_dayHigh = m_current;
   if(m_current < m_dayLow)  m_dayLow  = m_current;

   // 累计采样（用于历史均值）
   m_sumSpread += m_current;
   m_sumCount++;
}

//+------------------------------------------------------------------+
//| 配对交易管理器                                                     |
//+------------------------------------------------------------------+
class CPairTradeManager
{
private:
   PairPosition      m_pairs[];
   PairHistory       m_history[];
   int               m_maxHistory;
   int               m_nextPairId;
   int               m_magicNumber;
   CTrade            m_trade;
   string            m_persistFile;
   string            m_historyFile;

   // 获取持仓浮盈
   double            GetPositionProfit(ulong ticket);
   // 查询已实现盈亏（通过历史成交）
   double            GetRealizedProfit(ulong posTicket);
   // 验证品种
   bool              ValidateSymbol(string symbol);
   // 平掉单笔持仓（同步）
   bool              ClosePosition(ulong ticket);
   // 异步发送平仓请求，返回request_id（0=失败或已不存在）
   ulong             ClosePositionAsync(ulong ticket);
   // 等待异步平仓完成
   bool              WaitAsyncClose(ulong ticket, int timeoutMs = 3000);
   // 生成 Comment 标记
   string            PairComment(int pairId);
   // 设置品种对应的成交模式
   void              SetFillType(string symbol);
   // 等待订单成交并返回持仓ticket
   ulong             WaitForPosition(string symbol, ulong orderTicket, string comment);

public:
                     CPairTradeManager();
                    ~CPairTradeManager();

   // 初始化
   void              Init(int magicNumber);

   // 开仓：创建一对持仓
   bool              OpenPair(string symbolA, ENUM_ORDER_TYPE dirA, double lotsA,
                              string symbolB, ENUM_ORDER_TYPE dirB, double lotsB,
                              string &errorMsg);

   // 平仓：平掉指定配对（reason: "止盈"/"止损"/"手动"）
   bool              ClosePair(int pairId, string &errorMsg, string reason = "手动");

   // 全部平仓
   void              CloseAllPairs();

   // 获取某对的浮动盈亏
   double            GetPairProfit(int index);

   // 获取所有配对的总浮动盈亏
   double            GetTotalProfit();

   // 盈亏监控：检查所有配对，返回被平仓的配对数
   int               MonitorPairs(double takeProfit, double stopLoss, double tpBuffer = 0.0);

   // 配对数量
   int               PairCount() { return ArraySize(m_pairs); }

   // 获取配对信息
   bool              GetPair(int index, PairPosition &pair);

   // 持久化
   void              SaveToFile();
   void              LoadFromFile();

   // 验证持仓是否仍存在（EA重启后清理无效配对）
   void              ValidatePairs();

   // 历史记录
   int               HistoryCount()  { return ArraySize(m_history); }
   bool              GetHistory(int index, PairHistory &hist);
   void              SaveHistoryToFile();
   void              LoadHistoryFromFile();
};

//+------------------------------------------------------------------+
//| 构造函数                                                          |
//+------------------------------------------------------------------+
CPairTradeManager::CPairTradeManager()
{
   m_nextPairId = 1;
   m_magicNumber = 0;
   m_maxHistory = 50;
   m_persistFile = "PairTrader_data.csv";
   m_historyFile = "PairTrader_history.csv";
}

//+------------------------------------------------------------------+
//| 析构函数                                                          |
//+------------------------------------------------------------------+
CPairTradeManager::~CPairTradeManager()
{
}

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
void CPairTradeManager::Init(int magicNumber)
{
   m_magicNumber = magicNumber;
   m_trade.SetExpertMagicNumber(magicNumber);
   LoadFromFile();
   LoadHistoryFromFile();
   ValidatePairs();
}

//+------------------------------------------------------------------+
//| 生成配对标记                                                       |
//+------------------------------------------------------------------+
string CPairTradeManager::PairComment(int pairId)
{
   return "PAIR_" + IntegerToString(pairId);
}

//+------------------------------------------------------------------+
//| 根据品种支持的模式设置成交类型                                        |
//+------------------------------------------------------------------+
void CPairTradeManager::SetFillType(string symbol)
{
   long fillMode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);

   if((fillMode & SYMBOL_FILLING_FOK) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillMode & SYMBOL_FILLING_IOC) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      m_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   Print("品种 ", symbol, " 成交模式: ", fillMode, " -> 使用: ",
         ((fillMode & SYMBOL_FILLING_FOK) != 0) ? "FOK" :
         ((fillMode & SYMBOL_FILLING_IOC) != 0) ? "IOC" : "RETURN");
}

//+------------------------------------------------------------------+
//| 等待订单成交，返回持仓ticket（0=超时失败）                             |
//+------------------------------------------------------------------+
ulong CPairTradeManager::WaitForPosition(string symbol, ulong orderTicket, string comment)
{
   // 最多等5秒
   for(int i = 0; i < 50; i++)
   {
      // 遍历所有持仓查找匹配的
      int total = PositionsTotal();
      for(int j = 0; j < total; j++)
      {
         ulong posTicket = PositionGetTicket(j);
         if(posTicket == 0)
            continue;

         string posSym = PositionGetString(POSITION_SYMBOL);
         string posComment = PositionGetString(POSITION_COMMENT);

         // 通过 comment 匹配（最可靠的方式）
         if(posSym == symbol && posComment == comment)
         {
            Print("找到持仓: symbol=", posSym, " ticket=", posTicket, " comment=", posComment);
            return posTicket;
         }
      }
      Sleep(100);
   }

   Print("等待持仓超时: symbol=", symbol, " order=", orderTicket);
   return 0;
}

//+------------------------------------------------------------------+
//| 验证品种是否可用（含等待报价就绪）                                    |
//+------------------------------------------------------------------+
bool CPairTradeManager::ValidateSymbol(string symbol)
{
   // 尝试添加到市场报价
   if(!SymbolSelect(symbol, true))
      return false;

   // 检查品种是否存在
   if(SymbolInfoInteger(symbol, SYMBOL_EXIST) == 0)
      return false;

   // 等待报价数据就绪（最多等3秒）
   for(int i = 0; i < 30; i++)
   {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(bid > 0 && ask > 0)
         return true;
      Sleep(100);
   }

   Print("警告: 品种 ", symbol, " 报价未就绪 (bid/ask=0)");
   return false;
}

//+------------------------------------------------------------------+
//| 获取持仓浮盈(USD)                                                  |
//+------------------------------------------------------------------+
double CPairTradeManager::GetPositionProfit(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return 0.0;

   double profit = PositionGetDouble(POSITION_PROFIT);
   double swap = PositionGetDouble(POSITION_SWAP);
   return profit + swap;
}

//+------------------------------------------------------------------+
//| 查询某持仓的已实现盈亏（从历史成交中获取）                              |
//+------------------------------------------------------------------+
double CPairTradeManager::GetRealizedProfit(ulong posTicket)
{
   if(!HistorySelectByPosition(posTicket))
      return 0.0;

   double total = 0.0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;

      long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
      {
         total += HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)
                + HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      }
   }
   return total;
}

//+------------------------------------------------------------------+
//| 平掉单笔持仓                                                      |
//+------------------------------------------------------------------+
bool CPairTradeManager::ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return true; // 持仓已不存在，视为成功

   string sym = PositionGetString(POSITION_SYMBOL);
   SetFillType(sym);
   return m_trade.PositionClose(ticket);
}

//+------------------------------------------------------------------+
//| 异步发送平仓请求                                                   |
//+------------------------------------------------------------------+
ulong CPairTradeManager::ClosePositionAsync(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return 0; // 已不存在，返回0表示无需等待

   string sym = PositionGetString(POSITION_SYMBOL);
   double volume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   SetFillType(sym);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.position  = ticket;
   request.symbol    = sym;
   request.volume    = volume;
   request.magic     = m_magicNumber;
   request.deviation = 20;

   // 平仓方向与持仓方向相反
   if(posType == POSITION_TYPE_BUY)
   {
      request.type  = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(sym, SYMBOL_BID);
   }
   else
   {
      request.type  = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(sym, SYMBOL_ASK);
   }

   // 使用与CTrade一致的成交模式
   long fillMode = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((fillMode & SYMBOL_FILLING_FOK) != 0)
      request.type_filling = ORDER_FILLING_FOK;
   else if((fillMode & SYMBOL_FILLING_IOC) != 0)
      request.type_filling = ORDER_FILLING_IOC;
   else
      request.type_filling = ORDER_FILLING_RETURN;

   if(!OrderSendAsync(request, result))
   {
      Print("异步平仓发送失败: ticket=", ticket, " error=", GetLastError());
      return 0;
   }

   if(result.retcode != TRADE_RETCODE_PLACED)
   {
      Print("异步平仓被拒: ticket=", ticket, " retcode=", result.retcode);
      return 0;
   }

   Print("异步平仓已发送: ticket=", ticket, " request_id=", result.request_id);
   return result.request_id;
}

//+------------------------------------------------------------------+
//| 等待异步平仓完成（检查持仓是否消失）                                   |
//+------------------------------------------------------------------+
bool CPairTradeManager::WaitAsyncClose(ulong ticket, int timeoutMs)
{
   int waited = 0;
   int step = 50; // 50ms检查一次
   while(waited < timeoutMs)
   {
      if(!PositionSelectByTicket(ticket))
         return true; // 持仓已消失，平仓成功
      Sleep(step);
      waited += step;
   }
   Print("等待异步平仓超时: ticket=", ticket);
   return false;
}

//+------------------------------------------------------------------+
//| 开仓：创建一对持仓                                                 |
//+------------------------------------------------------------------+
bool CPairTradeManager::OpenPair(string symbolA, ENUM_ORDER_TYPE dirA, double lotsA,
                                  string symbolB, ENUM_ORDER_TYPE dirB, double lotsB,
                                  string &errorMsg)
{
   // 验证品种
   if(!ValidateSymbol(symbolA))
   {
      errorMsg = "品种A无效: " + symbolA;
      return false;
   }
   if(!ValidateSymbol(symbolB))
   {
      errorMsg = "品种B无效: " + symbolB;
      return false;
   }

   // 验证手数
   double minLotA = SymbolInfoDouble(symbolA, SYMBOL_VOLUME_MIN);
   double maxLotA = SymbolInfoDouble(symbolA, SYMBOL_VOLUME_MAX);
   double stepA   = SymbolInfoDouble(symbolA, SYMBOL_VOLUME_STEP);
   if(lotsA < minLotA || lotsA > maxLotA)
   {
      errorMsg = symbolA + " 手数超出范围 [" + DoubleToString(minLotA, 2) + " - " + DoubleToString(maxLotA, 2) + "]";
      return false;
   }

   double minLotB = SymbolInfoDouble(symbolB, SYMBOL_VOLUME_MIN);
   double maxLotB = SymbolInfoDouble(symbolB, SYMBOL_VOLUME_MAX);
   double stepB   = SymbolInfoDouble(symbolB, SYMBOL_VOLUME_STEP);
   if(lotsB < minLotB || lotsB > maxLotB)
   {
      errorMsg = symbolB + " 手数超出范围 [" + DoubleToString(minLotB, 2) + " - " + DoubleToString(maxLotB, 2) + "]";
      return false;
   }

   // 规范化手数
   lotsA = MathFloor(lotsA / stepA) * stepA;
   lotsB = MathFloor(lotsB / stepB) * stepB;

   int pairId = m_nextPairId;
   string comment = PairComment(pairId);

   m_trade.SetExpertMagicNumber(m_magicNumber);

   // === 发送订单A ===
   SetFillType(symbolA);
   Print("开仓A: ", symbolA, " ", (dirA == ORDER_TYPE_BUY ? "BUY" : "SELL"), " ", lotsA);
   bool resultA = false;
   if(dirA == ORDER_TYPE_BUY)
      resultA = m_trade.Buy(lotsA, symbolA, 0, 0, 0, comment);
   else
      resultA = m_trade.Sell(lotsA, symbolA, 0, 0, 0, comment);

   uint retcodeA = m_trade.ResultRetcode();
   Print("订单A返回码: ", retcodeA, " ", m_trade.ResultRetcodeDescription());
   if(!resultA || (retcodeA != TRADE_RETCODE_DONE && retcodeA != TRADE_RETCODE_PLACED))
   {
      errorMsg = symbolA + " 下单失败: [" + IntegerToString(retcodeA) + "] " + m_trade.ResultRetcodeDescription();
      Print("订单A失败: ", errorMsg);
      return false;
   }

   ulong ticketA = m_trade.ResultOrder();

   // 等待订单成交、持仓出现
   ulong posTicketA = WaitForPosition(symbolA, ticketA, comment);
   if(posTicketA == 0)
   {
      errorMsg = symbolA + " 等待持仓超时";
      Print("订单A: ", errorMsg);
      return false;
   }
   Print("订单A成功: order=", ticketA, " position=", posTicketA);

   // === 发送订单B ===
   SetFillType(symbolB);
   Print("开仓B: ", symbolB, " ", (dirB == ORDER_TYPE_BUY ? "BUY" : "SELL"), " ", lotsB);
   bool resultB = false;
   if(dirB == ORDER_TYPE_BUY)
      resultB = m_trade.Buy(lotsB, symbolB, 0, 0, 0, comment);
   else
      resultB = m_trade.Sell(lotsB, symbolB, 0, 0, 0, comment);

   uint retcodeB = m_trade.ResultRetcode();
   Print("订单B返回码: ", retcodeB, " ", m_trade.ResultRetcodeDescription());
   if(!resultB || (retcodeB != TRADE_RETCODE_DONE && retcodeB != TRADE_RETCODE_PLACED))
   {
      // 订单B失败，回滚订单A
      errorMsg = symbolB + " 下单失败: [" + IntegerToString(retcodeB) + "] " + m_trade.ResultRetcodeDescription();
      Print("订单B失败: ", errorMsg, " -> 回滚订单A");

      SetFillType(symbolA);
      if(PositionSelectByTicket(posTicketA))
         m_trade.PositionClose(posTicketA);

      return false;
   }

   ulong ticketB = m_trade.ResultOrder();
   ulong posTicketB = WaitForPosition(symbolB, ticketB, comment);
   if(posTicketB == 0)
   {
      errorMsg = symbolB + " 等待持仓超时";
      Print("订单B: ", errorMsg, " -> 回滚订单A");

      SetFillType(symbolA);
      if(PositionSelectByTicket(posTicketA))
         m_trade.PositionClose(posTicketA);

      return false;
   }
   Print("订单B成功: order=", ticketB, " position=", posTicketB);

   // 创建配对记录
   PairPosition pair;
   pair.pairId   = pairId;
   pair.symbolA  = symbolA;
   pair.symbolB  = symbolB;
   pair.ticketA  = posTicketA;
   pair.ticketB  = posTicketB;
   pair.dirA     = dirA;
   pair.dirB     = dirB;
   pair.lotsA    = lotsA;
   pair.lotsB    = lotsB;
   pair.openTime = TimeCurrent();

   int size = ArraySize(m_pairs);
   ArrayResize(m_pairs, size + 1);
   m_pairs[size] = pair;

   m_nextPairId++;
   SaveToFile();

   return true;
}

//+------------------------------------------------------------------+
//| 平仓：平掉指定配对                                                 |
//+------------------------------------------------------------------+
bool CPairTradeManager::ClosePair(int pairId, string &errorMsg, string reason)
{
   for(int i = 0; i < ArraySize(m_pairs); i++)
   {
      if(m_pairs[i].pairId == pairId)
      {
         // 保存配对信息（平仓后会从数组移除）
         PairPosition closingPair = m_pairs[i];

         // 异步并行发送两笔平仓请求，最大限度减少腿间暴露时间
         ulong reqA = ClosePositionAsync(m_pairs[i].ticketA);
         ulong reqB = ClosePositionAsync(m_pairs[i].ticketB);

         // 等待两笔都完成
         bool closeA = (reqA == 0) ? !PositionSelectByTicket(m_pairs[i].ticketA)
                                   : WaitAsyncClose(m_pairs[i].ticketA);
         bool closeB = (reqB == 0) ? !PositionSelectByTicket(m_pairs[i].ticketB)
                                   : WaitAsyncClose(m_pairs[i].ticketB);

         if(!closeA || !closeB)
         {
            // 异步失败时回退到同步重试
            if(!closeA)
            {
               Print("异步平仓A失败，同步重试: ticket=", m_pairs[i].ticketA);
               closeA = ClosePosition(m_pairs[i].ticketA);
            }
            if(!closeB)
            {
               Print("异步平仓B失败，同步重试: ticket=", m_pairs[i].ticketB);
               closeB = ClosePosition(m_pairs[i].ticketB);
            }
         }

         if(!closeA || !closeB)
         {
            errorMsg = "部分平仓失败:";
            if(!closeA) errorMsg += " A(" + IntegerToString(m_pairs[i].ticketA) + ")";
            if(!closeB) errorMsg += " B(" + IntegerToString(m_pairs[i].ticketB) + ")";
            return false;
         }

         // 查询实际已实现盈亏并记录历史
         double realA = GetRealizedProfit(closingPair.ticketA);
         double realB = GetRealizedProfit(closingPair.ticketB);
         double realTotal = realA + realB;

         PairHistory hist;
         hist.pairId     = closingPair.pairId;
         hist.symbolA    = closingPair.symbolA;
         hist.symbolB    = closingPair.symbolB;
         hist.dirA       = closingPair.dirA;
         hist.dirB       = closingPair.dirB;
         hist.lotsA      = closingPair.lotsA;
         hist.lotsB      = closingPair.lotsB;
         hist.openTime   = closingPair.openTime;
         hist.closeTime  = TimeCurrent();
         hist.reason     = reason;
         hist.realProfit = realTotal;

         int hSize = ArraySize(m_history);
         ArrayResize(m_history, hSize + 1);
         m_history[hSize] = hist;

         // 超出上限时移除最早的记录
         if(ArraySize(m_history) > m_maxHistory)
         {
            for(int k = 0; k < ArraySize(m_history) - 1; k++)
               m_history[k] = m_history[k + 1];
            ArrayResize(m_history, ArraySize(m_history) - 1);
         }

         Print("配对 ", closingPair.pairId, " 平仓完成 [", reason, "] 实际盈亏: $",
               DoubleToString(realTotal, 2), " (A=$", DoubleToString(realA, 2),
               " B=$", DoubleToString(realB, 2), ")");

         // 从数组中移除
         for(int j = i; j < ArraySize(m_pairs) - 1; j++)
            m_pairs[j] = m_pairs[j + 1];
         ArrayResize(m_pairs, ArraySize(m_pairs) - 1);

         SaveToFile();
         SaveHistoryToFile();
         return true;
      }
   }

   errorMsg = "未找到配对 ID: " + IntegerToString(pairId);
   return false;
}

//+------------------------------------------------------------------+
//| 全部平仓                                                          |
//+------------------------------------------------------------------+
void CPairTradeManager::CloseAllPairs()
{
   string errorMsg;
   // 从后向前遍历，因为 ClosePair 会修改数组
   for(int i = ArraySize(m_pairs) - 1; i >= 0; i--)
   {
      ClosePair(m_pairs[i].pairId, errorMsg);
   }
}

//+------------------------------------------------------------------+
//| 获取某对的浮动盈亏                                                 |
//+------------------------------------------------------------------+
double CPairTradeManager::GetPairProfit(int index)
{
   if(index < 0 || index >= ArraySize(m_pairs))
      return 0.0;

   double profitA = GetPositionProfit(m_pairs[index].ticketA);
   double profitB = GetPositionProfit(m_pairs[index].ticketB);
   return profitA + profitB;
}

//+------------------------------------------------------------------+
//| 获取所有配对的总浮动盈亏                                            |
//+------------------------------------------------------------------+
double CPairTradeManager::GetTotalProfit()
{
   double total = 0.0;
   for(int i = 0; i < ArraySize(m_pairs); i++)
      total += GetPairProfit(i);
   return total;
}

//+------------------------------------------------------------------+
//| 盈亏监控                                                          |
//+------------------------------------------------------------------+
int CPairTradeManager::MonitorPairs(double takeProfit, double stopLoss, double tpBuffer)
{
   int closedCount = 0;
   string errorMsg;

   // 实际触发阈值 = 止盈 - 提前量，给滑点留余量
   double effectiveTP = takeProfit - tpBuffer;
   if(effectiveTP < 0) effectiveTP = 0;

   for(int i = ArraySize(m_pairs) - 1; i >= 0; i--)
   {
      double pairProfit = GetPairProfit(i);

      if(pairProfit >= effectiveTP)
      {
         Print("配对 ", m_pairs[i].pairId, " 触发止盈: ", DoubleToString(pairProfit, 2),
               " >= ", DoubleToString(effectiveTP, 2), " (TP=", DoubleToString(takeProfit, 2),
               " buffer=", DoubleToString(tpBuffer, 2), ")");
         if(ClosePair(m_pairs[i].pairId, errorMsg, "止盈"))
            closedCount++;
         else
            Print("止盈平仓失败: ", errorMsg);
      }
      else if(pairProfit <= -stopLoss)
      {
         Print("配对 ", m_pairs[i].pairId, " 触发止损: ", DoubleToString(pairProfit, 2), " <= -", DoubleToString(stopLoss, 2));
         if(ClosePair(m_pairs[i].pairId, errorMsg, "止损"))
            closedCount++;
         else
            Print("止损平仓失败: ", errorMsg);
      }
   }

   return closedCount;
}

//+------------------------------------------------------------------+
//| 获取配对信息                                                       |
//+------------------------------------------------------------------+
bool CPairTradeManager::GetPair(int index, PairPosition &pair)
{
   if(index < 0 || index >= ArraySize(m_pairs))
      return false;

   pair = m_pairs[index];
   return true;
}

//+------------------------------------------------------------------+
//| 保存到文件                                                         |
//+------------------------------------------------------------------+
void CPairTradeManager::SaveToFile()
{
   int handle = FileOpen(m_persistFile, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("持久化保存失败: ", GetLastError());
      return;
   }

   // 写入下一个 PairId
   FileWrite(handle, "NEXT_ID", IntegerToString(m_nextPairId));

   // 写入每对数据
   for(int i = 0; i < ArraySize(m_pairs); i++)
   {
      FileWrite(handle,
                IntegerToString(m_pairs[i].pairId),
                m_pairs[i].symbolA,
                m_pairs[i].symbolB,
                IntegerToString(m_pairs[i].ticketA),
                IntegerToString(m_pairs[i].ticketB),
                IntegerToString(m_pairs[i].dirA),
                IntegerToString(m_pairs[i].dirB),
                DoubleToString(m_pairs[i].lotsA, 2),
                DoubleToString(m_pairs[i].lotsB, 2),
                IntegerToString(m_pairs[i].openTime));
   }

   FileClose(handle);
}

//+------------------------------------------------------------------+
//| 从文件加载                                                         |
//+------------------------------------------------------------------+
void CPairTradeManager::LoadFromFile()
{
   if(!FileIsExist(m_persistFile))
      return;

   int handle = FileOpen(m_persistFile, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("持久化加载失败: ", GetLastError());
      return;
   }

   ArrayResize(m_pairs, 0);

   // 读取第一行: NEXT_ID
   if(!FileIsEnding(handle))
   {
      string tag = FileReadString(handle);
      if(tag == "NEXT_ID")
         m_nextPairId = (int)StringToInteger(FileReadString(handle));
   }

   // 读取配对数据
   while(!FileIsEnding(handle))
   {
      string pidStr = FileReadString(handle);
      if(pidStr == "" || pidStr == "NEXT_ID")
         break;

      PairPosition pair;
      pair.pairId   = (int)StringToInteger(pidStr);
      pair.symbolA  = FileReadString(handle);
      pair.symbolB  = FileReadString(handle);
      pair.ticketA  = (ulong)StringToInteger(FileReadString(handle));
      pair.ticketB  = (ulong)StringToInteger(FileReadString(handle));
      pair.dirA     = (ENUM_ORDER_TYPE)StringToInteger(FileReadString(handle));
      pair.dirB     = (ENUM_ORDER_TYPE)StringToInteger(FileReadString(handle));
      pair.lotsA    = StringToDouble(FileReadString(handle));
      pair.lotsB    = StringToDouble(FileReadString(handle));
      pair.openTime = (datetime)StringToInteger(FileReadString(handle));

      int size = ArraySize(m_pairs);
      ArrayResize(m_pairs, size + 1);
      m_pairs[size] = pair;
   }

   FileClose(handle);
   Print("从文件恢复 ", ArraySize(m_pairs), " 个配对");
}

//+------------------------------------------------------------------+
//| 验证持仓是否仍存在                                                  |
//+------------------------------------------------------------------+
void CPairTradeManager::ValidatePairs()
{
   for(int i = ArraySize(m_pairs) - 1; i >= 0; i--)
   {
      bool existA = PositionSelectByTicket(m_pairs[i].ticketA);
      bool existB = PositionSelectByTicket(m_pairs[i].ticketB);

      if(!existA && !existB)
      {
         // 两笔都不存在，移除配对
         Print("配对 ", m_pairs[i].pairId, " 双腿均已不存在，移除");
         for(int j = i; j < ArraySize(m_pairs) - 1; j++)
            m_pairs[j] = m_pairs[j + 1];
         ArrayResize(m_pairs, ArraySize(m_pairs) - 1);
      }
      else if(!existA || !existB)
      {
         // 单腿缺失，告警但保留（可能需要手动处理）
         Print("警告: 配对 ", m_pairs[i].pairId, " 单腿缺失! A=", existA, " B=", existB);
      }
   }

   SaveToFile();
}

//+------------------------------------------------------------------+
//| 获取历史记录                                                       |
//+------------------------------------------------------------------+
bool CPairTradeManager::GetHistory(int index, PairHistory &hist)
{
   if(index < 0 || index >= ArraySize(m_history))
      return false;

   hist = m_history[index];
   return true;
}

//+------------------------------------------------------------------+
//| 保存历史记录到文件                                                  |
//+------------------------------------------------------------------+
void CPairTradeManager::SaveHistoryToFile()
{
   int handle = FileOpen(m_historyFile, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("历史记录保存失败: ", GetLastError());
      return;
   }

   for(int i = 0; i < ArraySize(m_history); i++)
   {
      FileWrite(handle,
                IntegerToString(m_history[i].pairId),
                m_history[i].symbolA,
                m_history[i].symbolB,
                IntegerToString(m_history[i].dirA),
                IntegerToString(m_history[i].dirB),
                DoubleToString(m_history[i].lotsA, 2),
                DoubleToString(m_history[i].lotsB, 2),
                IntegerToString(m_history[i].openTime),
                IntegerToString(m_history[i].closeTime),
                m_history[i].reason,
                DoubleToString(m_history[i].realProfit, 2));
   }

   FileClose(handle);
}

//+------------------------------------------------------------------+
//| 从文件加载历史记录                                                  |
//+------------------------------------------------------------------+
void CPairTradeManager::LoadHistoryFromFile()
{
   if(!FileIsExist(m_historyFile))
      return;

   int handle = FileOpen(m_historyFile, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("历史记录加载失败: ", GetLastError());
      return;
   }

   ArrayResize(m_history, 0);

   while(!FileIsEnding(handle))
   {
      string pidStr = FileReadString(handle);
      if(pidStr == "")
         break;

      PairHistory hist;
      hist.pairId     = (int)StringToInteger(pidStr);
      hist.symbolA    = FileReadString(handle);
      hist.symbolB    = FileReadString(handle);
      hist.dirA       = (ENUM_ORDER_TYPE)StringToInteger(FileReadString(handle));
      hist.dirB       = (ENUM_ORDER_TYPE)StringToInteger(FileReadString(handle));
      hist.lotsA      = StringToDouble(FileReadString(handle));
      hist.lotsB      = StringToDouble(FileReadString(handle));
      hist.openTime   = (datetime)StringToInteger(FileReadString(handle));
      hist.closeTime  = (datetime)StringToInteger(FileReadString(handle));
      hist.reason     = FileReadString(handle);
      hist.realProfit = StringToDouble(FileReadString(handle));

      int size = ArraySize(m_history);
      ArrayResize(m_history, size + 1);
      m_history[size] = hist;
   }

   FileClose(handle);
   Print("从文件恢复 ", ArraySize(m_history), " 条历史记录");
}
