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
//| 配对交易管理器                                                     |
//+------------------------------------------------------------------+
class CPairTradeManager
{
private:
   PairPosition      m_pairs[];
   int               m_nextPairId;
   int               m_magicNumber;
   CTrade            m_trade;
   string            m_persistFile;

   // 获取持仓浮盈
   double            GetPositionProfit(ulong ticket);
   // 验证品种
   bool              ValidateSymbol(string symbol);
   // 平掉单笔持仓
   bool              ClosePosition(ulong ticket);
   // 生成 Comment 标记
   string            PairComment(int pairId);

public:
                     CPairTradeManager();
                    ~CPairTradeManager();

   // 初始化
   void              Init(int magicNumber);

   // 开仓：创建一对持仓
   bool              OpenPair(string symbolA, ENUM_ORDER_TYPE dirA, double lotsA,
                              string symbolB, ENUM_ORDER_TYPE dirB, double lotsB,
                              string &errorMsg);

   // 平仓：平掉指定配对
   bool              ClosePair(int pairId, string &errorMsg);

   // 全部平仓
   void              CloseAllPairs();

   // 获取某对的浮动盈亏
   double            GetPairProfit(int index);

   // 获取所有配对的总浮动盈亏
   double            GetTotalProfit();

   // 盈亏监控：检查所有配对，返回被平仓的配对数
   int               MonitorPairs(double takeProfit, double stopLoss);

   // 配对数量
   int               PairCount() { return ArraySize(m_pairs); }

   // 获取配对信息
   bool              GetPair(int index, PairPosition &pair);

   // 持久化
   void              SaveToFile();
   void              LoadFromFile();

   // 验证持仓是否仍存在（EA重启后清理无效配对）
   void              ValidatePairs();
};

//+------------------------------------------------------------------+
//| 构造函数                                                          |
//+------------------------------------------------------------------+
CPairTradeManager::CPairTradeManager()
{
   m_nextPairId = 1;
   m_magicNumber = 0;
   m_persistFile = "PairTrader_data.csv";
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
//| 平掉单笔持仓                                                      |
//+------------------------------------------------------------------+
bool CPairTradeManager::ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return true; // 持仓已不存在，视为成功

   return m_trade.PositionClose(ticket);
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
   Print("开仓A: ", symbolA, " ", (dirA == ORDER_TYPE_BUY ? "BUY" : "SELL"), " ", lotsA);
   bool resultA = false;
   if(dirA == ORDER_TYPE_BUY)
      resultA = m_trade.Buy(lotsA, symbolA, 0, 0, 0, comment);
   else
      resultA = m_trade.Sell(lotsA, symbolA, 0, 0, 0, comment);

   uint retcodeA = m_trade.ResultRetcode();
   if(!resultA || retcodeA != TRADE_RETCODE_DONE)
   {
      errorMsg = symbolA + " 下单失败: [" + IntegerToString(retcodeA) + "] " + m_trade.ResultRetcodeDescription();
      Print("订单A失败: ", errorMsg);
      return false;
   }

   ulong ticketA = m_trade.ResultOrder();
   Print("订单A成功: ticket=", ticketA);

   // 等待持仓出现
   Sleep(200);

   // === 发送订单B ===
   Print("开仓B: ", symbolB, " ", (dirB == ORDER_TYPE_BUY ? "BUY" : "SELL"), " ", lotsB);
   bool resultB = false;
   if(dirB == ORDER_TYPE_BUY)
      resultB = m_trade.Buy(lotsB, symbolB, 0, 0, 0, comment);
   else
      resultB = m_trade.Sell(lotsB, symbolB, 0, 0, 0, comment);

   uint retcodeB = m_trade.ResultRetcode();
   if(!resultB || retcodeB != TRADE_RETCODE_DONE)
   {
      // 订单B失败，回滚订单A
      errorMsg = symbolB + " 下单失败: [" + IntegerToString(retcodeB) + "] " + m_trade.ResultRetcodeDescription();
      Print("订单B失败: ", errorMsg, " -> 回滚订单A");

      Sleep(200);
      if(PositionSelectByTicket(ticketA))
         m_trade.PositionClose(ticketA);

      return false;
   }

   ulong ticketB = m_trade.ResultOrder();
   Print("订单B成功: ticket=", ticketB);

   // 创建配对记录
   PairPosition pair;
   pair.pairId   = pairId;
   pair.symbolA  = symbolA;
   pair.symbolB  = symbolB;
   pair.ticketA  = ticketA;
   pair.ticketB  = ticketB;
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
bool CPairTradeManager::ClosePair(int pairId, string &errorMsg)
{
   for(int i = 0; i < ArraySize(m_pairs); i++)
   {
      if(m_pairs[i].pairId == pairId)
      {
         bool closeA = ClosePosition(m_pairs[i].ticketA);
         bool closeB = ClosePosition(m_pairs[i].ticketB);

         if(!closeA || !closeB)
         {
            errorMsg = "部分平仓失败:";
            if(!closeA) errorMsg += " A(" + IntegerToString(m_pairs[i].ticketA) + ")";
            if(!closeB) errorMsg += " B(" + IntegerToString(m_pairs[i].ticketB) + ")";
            return false;
         }

         // 从数组中移除
         for(int j = i; j < ArraySize(m_pairs) - 1; j++)
            m_pairs[j] = m_pairs[j + 1];
         ArrayResize(m_pairs, ArraySize(m_pairs) - 1);

         SaveToFile();
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
int CPairTradeManager::MonitorPairs(double takeProfit, double stopLoss)
{
   int closedCount = 0;
   string errorMsg;

   for(int i = ArraySize(m_pairs) - 1; i >= 0; i--)
   {
      double pairProfit = GetPairProfit(i);

      if(pairProfit >= takeProfit)
      {
         Print("配对 ", m_pairs[i].pairId, " 触发止盈: ", DoubleToString(pairProfit, 2), " >= ", DoubleToString(takeProfit, 2));
         if(ClosePair(m_pairs[i].pairId, errorMsg))
            closedCount++;
         else
            Print("止盈平仓失败: ", errorMsg);
      }
      else if(pairProfit <= -stopLoss)
      {
         Print("配对 ", m_pairs[i].pairId, " 触发止损: ", DoubleToString(pairProfit, 2), " <= -", DoubleToString(stopLoss, 2));
         if(ClosePair(m_pairs[i].pairId, errorMsg))
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
