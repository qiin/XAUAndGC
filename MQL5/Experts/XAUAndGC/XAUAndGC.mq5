//+------------------------------------------------------------------+
//|                                                  XAUAndGC.mq5    |
//|                         配对交易 EA                               |
//|   两个品种同时开仓(一多一空)，配对盈亏监控，自动止盈止损              |
//+------------------------------------------------------------------+
#property copyright "PairTrader EA"
#property version   "1.00"
#property strict

#include <Controls\Dialog.mqh>
#include <Controls\Button.mqh>
#include <Controls\Edit.mqh>
#include <Controls\Label.mqh>
#include <Controls\ComboBox.mqh>
#include <XAUAndGC\PairTradeManager.mqh>

//+------------------------------------------------------------------+
//| Input 参数                                                        |
//+------------------------------------------------------------------+
input double   InpTakeProfit    = 500.0;   // 止盈金额(USD)
input double   InpStopLoss     = 300.0;   // 止损金额(USD)
input int      InpMagicNumber  = 20240101; // Magic Number
input int      InpTimerSec     = 1;        // 监控间隔(秒)
input string   InpDefaultSymA  = "XAUUSD"; // 默认品种A
input string   InpDefaultSymB  = "GC";     // 默认品种B
input double   InpDefaultLotsA = 0.1;      // 默认手数A
input double   InpDefaultLotsB = 0.1;      // 默认手数B

//+------------------------------------------------------------------+
//| 面板尺寸常量                                                       |
//+------------------------------------------------------------------+
#define PANEL_WIDTH    420
#define PANEL_HEIGHT   500
#define ROW_HEIGHT     25
#define LABEL_X        10
#define INPUT_X        100
#define INPUT_WIDTH    120
#define BTN_WIDTH      80

//+------------------------------------------------------------------+
//| 主面板类                                                          |
//+------------------------------------------------------------------+
class CPairTraderPanel : public CAppDialog
{
private:
   // 品种A控件
   CLabel            m_lblSymA;
   CEdit             m_edtSymA;
   CComboBox         m_cmbDirA;
   CEdit             m_edtLotsA;

   // 品种B控件
   CLabel            m_lblSymB;
   CEdit             m_edtSymB;
   CComboBox         m_cmbDirB;
   CEdit             m_edtLotsB;

   // 止盈止损显示
   CLabel            m_lblTP;
   CLabel            m_lblTPVal;
   CLabel            m_lblSL;
   CLabel            m_lblSLVal;

   // 按钮
   CButton           m_btnOpen;
   CButton           m_btnCloseAll;

   // 持仓信息区域
   CLabel            m_lblPairHeader;
   CLabel            m_lblPairInfo[10];    // 最多显示10对
   CButton           m_btnClose[10];       // 每对的平仓按钮
   CLabel            m_lblTotalProfit;

   // 状态
   CLabel            m_lblStatus;

   int               m_displayCount;

public:
   bool              CreatePanel(long chart, string name, int subwin, int x, int y);
   void              UpdateDisplay();
   void              SetStatus(string msg);

   // 获取面板输入值
   string            GetSymbolA()   { return m_edtSymA.Text(); }
   string            GetSymbolB()   { return m_edtSymB.Text(); }
   double            GetLotsA()     { return StringToDouble(m_edtLotsA.Text()); }
   double            GetLotsB()     { return StringToDouble(m_edtLotsB.Text()); }
   ENUM_ORDER_TYPE   GetDirA()      { return (m_cmbDirA.Value() == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL; }
   ENUM_ORDER_TYPE   GetDirB()      { return (m_cmbDirB.Value() == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL; }

   // 事件映射
   virtual bool      OnEvent(const int id, const long &lparam, const double &dparam, const string &sparam);
};

//+------------------------------------------------------------------+
//| 全局变量                                                          |
//+------------------------------------------------------------------+
CPairTradeManager  g_manager;
CPairTraderPanel   g_panel;

//+------------------------------------------------------------------+
//| 事件处理映射                                                       |
//+------------------------------------------------------------------+
EVENT_MAP_BEGIN(CPairTraderPanel)
   ON_EVENT(ON_CLICK, m_btnOpen, OnClickOpen)
   ON_EVENT(ON_CLICK, m_btnCloseAll, OnClickCloseAll)
   ON_EVENT(ON_CLICK, m_btnClose[0], OnClickClose0)
   ON_EVENT(ON_CLICK, m_btnClose[1], OnClickClose1)
   ON_EVENT(ON_CLICK, m_btnClose[2], OnClickClose2)
   ON_EVENT(ON_CLICK, m_btnClose[3], OnClickClose3)
   ON_EVENT(ON_CLICK, m_btnClose[4], OnClickClose4)
   ON_EVENT(ON_CLICK, m_btnClose[5], OnClickClose5)
   ON_EVENT(ON_CLICK, m_btnClose[6], OnClickClose6)
   ON_EVENT(ON_CLICK, m_btnClose[7], OnClickClose7)
   ON_EVENT(ON_CLICK, m_btnClose[8], OnClickClose8)
   ON_EVENT(ON_CLICK, m_btnClose[9], OnClickClose9)
EVENT_MAP_END(CAppDialog)

//+------------------------------------------------------------------+
//| 按钮回调：开仓                                                     |
//+------------------------------------------------------------------+
void OnClickOpen(void)
{
   string errorMsg;
   bool result = g_manager.OpenPair(
      g_panel.GetSymbolA(), g_panel.GetDirA(), g_panel.GetLotsA(),
      g_panel.GetSymbolB(), g_panel.GetDirB(), g_panel.GetLotsB(),
      errorMsg
   );

   if(result)
      g_panel.SetStatus("开仓成功");
   else
      g_panel.SetStatus("开仓失败: " + errorMsg);

   g_panel.UpdateDisplay();
}

//+------------------------------------------------------------------+
//| 按钮回调：全部平仓                                                  |
//+------------------------------------------------------------------+
void OnClickCloseAll(void)
{
   g_manager.CloseAllPairs();
   g_panel.SetStatus("已全部平仓");
   g_panel.UpdateDisplay();
}

//+------------------------------------------------------------------+
//| 按钮回调：单对平仓（0-9）                                          |
//+------------------------------------------------------------------+
void ClosePairByIndex(int index)
{
   PairPosition pair;
   if(g_manager.GetPair(index, pair))
   {
      string errorMsg;
      if(g_manager.ClosePair(pair.pairId, errorMsg))
         g_panel.SetStatus("配对 " + IntegerToString(pair.pairId) + " 已平仓");
      else
         g_panel.SetStatus("平仓失败: " + errorMsg);
   }
   g_panel.UpdateDisplay();
}

void OnClickClose0(void) { ClosePairByIndex(0); }
void OnClickClose1(void) { ClosePairByIndex(1); }
void OnClickClose2(void) { ClosePairByIndex(2); }
void OnClickClose3(void) { ClosePairByIndex(3); }
void OnClickClose4(void) { ClosePairByIndex(4); }
void OnClickClose5(void) { ClosePairByIndex(5); }
void OnClickClose6(void) { ClosePairByIndex(6); }
void OnClickClose7(void) { ClosePairByIndex(7); }
void OnClickClose8(void) { ClosePairByIndex(8); }
void OnClickClose9(void) { ClosePairByIndex(9); }

//+------------------------------------------------------------------+
//| 创建面板                                                          |
//+------------------------------------------------------------------+
bool CPairTraderPanel::CreatePanel(long chart, string name, int subwin, int x, int y)
{
   if(!Create(chart, name, subwin, x, y, x + PANEL_WIDTH, y + PANEL_HEIGHT))
      return false;

   int row = 10;

   // === 品种A行 ===
   m_lblSymA.Create(m_chart_id, "lblSymA", m_subwin, LABEL_X, row, LABEL_X + 80, row + ROW_HEIGHT);
   m_lblSymA.Text("品种A:");
   Add(m_lblSymA);

   m_edtSymA.Create(m_chart_id, "edtSymA", m_subwin, INPUT_X, row, INPUT_X + INPUT_WIDTH, row + ROW_HEIGHT);
   m_edtSymA.Text(InpDefaultSymA);
   Add(m_edtSymA);

   m_cmbDirA.Create(m_chart_id, "cmbDirA", m_subwin, INPUT_X + INPUT_WIDTH + 5, row, INPUT_X + INPUT_WIDTH + 75, row + ROW_HEIGHT);
   m_cmbDirA.ItemAdd("Buy", 0);
   m_cmbDirA.ItemAdd("Sell", 1);
   m_cmbDirA.SelectByValue(0);
   Add(m_cmbDirA);

   m_edtLotsA.Create(m_chart_id, "edtLotsA", m_subwin, INPUT_X + INPUT_WIDTH + 80, row, INPUT_X + INPUT_WIDTH + 145, row + ROW_HEIGHT);
   m_edtLotsA.Text(DoubleToString(InpDefaultLotsA, 2));
   Add(m_edtLotsA);

   row += ROW_HEIGHT + 5;

   // === 品种B行 ===
   m_lblSymB.Create(m_chart_id, "lblSymB", m_subwin, LABEL_X, row, LABEL_X + 80, row + ROW_HEIGHT);
   m_lblSymB.Text("品种B:");
   Add(m_lblSymB);

   m_edtSymB.Create(m_chart_id, "edtSymB", m_subwin, INPUT_X, row, INPUT_X + INPUT_WIDTH, row + ROW_HEIGHT);
   m_edtSymB.Text(InpDefaultSymB);
   Add(m_edtSymB);

   m_cmbDirB.Create(m_chart_id, "cmbDirB", m_subwin, INPUT_X + INPUT_WIDTH + 5, row, INPUT_X + INPUT_WIDTH + 75, row + ROW_HEIGHT);
   m_cmbDirB.ItemAdd("Buy", 0);
   m_cmbDirB.ItemAdd("Sell", 1);
   m_cmbDirB.SelectByValue(1);
   Add(m_cmbDirB);

   m_edtLotsB.Create(m_chart_id, "edtLotsB", m_subwin, INPUT_X + INPUT_WIDTH + 80, row, INPUT_X + INPUT_WIDTH + 145, row + ROW_HEIGHT);
   m_edtLotsB.Text(DoubleToString(InpDefaultLotsB, 2));
   Add(m_edtLotsB);

   row += ROW_HEIGHT + 10;

   // === 止盈止损行 ===
   m_lblTP.Create(m_chart_id, "lblTP", m_subwin, LABEL_X, row, LABEL_X + 80, row + ROW_HEIGHT);
   m_lblTP.Text("止盈(USD):");
   Add(m_lblTP);

   m_lblTPVal.Create(m_chart_id, "lblTPVal", m_subwin, INPUT_X, row, INPUT_X + 80, row + ROW_HEIGHT);
   m_lblTPVal.Text(DoubleToString(InpTakeProfit, 2));
   Add(m_lblTPVal);

   m_lblSL.Create(m_chart_id, "lblSL", m_subwin, INPUT_X + 90, row, INPUT_X + 170, row + ROW_HEIGHT);
   m_lblSL.Text("止损(USD):");
   Add(m_lblSL);

   m_lblSLVal.Create(m_chart_id, "lblSLVal", m_subwin, INPUT_X + 180, row, INPUT_X + 260, row + ROW_HEIGHT);
   m_lblSLVal.Text(DoubleToString(InpStopLoss, 2));
   Add(m_lblSLVal);

   row += ROW_HEIGHT + 10;

   // === 开仓按钮 ===
   m_btnOpen.Create(m_chart_id, "btnOpen", m_subwin, LABEL_X, row, PANEL_WIDTH - 30, row + 35);
   m_btnOpen.Text("一键开仓");
   m_btnOpen.ColorBackground(clrDodgerBlue);
   m_btnOpen.Color(clrWhite);
   Add(m_btnOpen);

   row += 45;

   // === 分隔线 - 持仓区域标题 ===
   m_lblPairHeader.Create(m_chart_id, "lblPairHdr", m_subwin, LABEL_X, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
   m_lblPairHeader.Text("─── 当前持仓 ───");
   Add(m_lblPairHeader);

   row += ROW_HEIGHT + 5;

   // === 持仓对信息 (最多10对) ===
   m_displayCount = 0;
   Print("[CreatePanel] Pair controls start at row=", row, " chart_id=", m_chart_id, " subwin=", m_subwin);
   for(int i = 0; i < 10; i++)
   {
      string idxStr = IntegerToString(i);

      bool lblOk = m_lblPairInfo[i].Create(m_chart_id, "lblPair" + idxStr, m_subwin,
                              LABEL_X, row, PANEL_WIDTH - 80, row + ROW_HEIGHT);
      m_lblPairInfo[i].Text(" ");
      Add(m_lblPairInfo[i]);

      bool btnOk = m_btnClose[i].Create(m_chart_id, "btnClose" + idxStr, m_subwin,
                           PANEL_WIDTH - 75, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
      m_btnClose[i].Text(" ");
      m_btnClose[i].ColorBackground(clrNONE);
      m_btnClose[i].Color(clrNONE);
      Add(m_btnClose[i]);

      if(i == 0)
         Print("[CreatePanel] Pair[0] lblOk=", lblOk, " btnOk=", btnOk,
               " lblName=", m_lblPairInfo[i].Name(), " btnName=", m_btnClose[i].Name(),
               " row=", row);

      row += ROW_HEIGHT + 2;
   }

   // === 总盈亏 ===
   m_lblTotalProfit.Create(m_chart_id, "lblTotal", m_subwin, LABEL_X, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
   m_lblTotalProfit.Text("总盈亏: $0.00");
   Add(m_lblTotalProfit);

   row += ROW_HEIGHT + 10;

   // === 全部平仓按钮 ===
   m_btnCloseAll.Create(m_chart_id, "btnCloseAll", m_subwin, LABEL_X, row, PANEL_WIDTH - 30, row + 30);
   m_btnCloseAll.Text("全部平仓");
   m_btnCloseAll.ColorBackground(clrFireBrick);
   m_btnCloseAll.Color(clrWhite);
   Add(m_btnCloseAll);

   row += 40;

   // === 状态栏 ===
   m_lblStatus.Create(m_chart_id, "lblStatus", m_subwin, LABEL_X, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
   m_lblStatus.Text("就绪");
   m_lblStatus.Color(clrGray);
   Add(m_lblStatus);

   return true;
}

//+------------------------------------------------------------------+
//| 更新持仓显示                                                       |
//+------------------------------------------------------------------+
void CPairTraderPanel::UpdateDisplay()
{
   int count = g_manager.PairCount();

   // DEBUG: 每10秒输出一次日志，避免刷屏
   static datetime lastLog = 0;
   bool doLog = (TimeCurrent() - lastLog >= 10);
   if(doLog)
   {
      lastLog = TimeCurrent();
      Print("[UpdateDisplay] PairCount=", count, " m_chart_id=", m_chart_id, " m_subwin=", m_subwin);
   }

   for(int i = 0; i < 10; i++)
   {
      if(i < count)
      {
         PairPosition pair;
         g_manager.GetPair(i, pair);
         double profit = g_manager.GetPairProfit(i);

         string dirStrA = (pair.dirA == ORDER_TYPE_BUY) ? "B" : "S";
         string dirStrB = (pair.dirB == ORDER_TYPE_BUY) ? "B" : "S";
         string profitStr = (profit >= 0) ? "+" + DoubleToString(profit, 2) : DoubleToString(profit, 2);

         string info = "#" + IntegerToString(pair.pairId) + " "
                     + pair.symbolA + " " + dirStrA + " " + DoubleToString(pair.lotsA, 2)
                     + " / "
                     + pair.symbolB + " " + dirStrB + " " + DoubleToString(pair.lotsB, 2)
                     + "  $" + profitStr;

         if(doLog)
         {
            Print("[UpdateDisplay] Pair[", i, "] info=", info);
            // 检查控件对象名称和位置
            long lblX = ObjectGetInteger(m_chart_id, m_lblPairInfo[i].Name(), OBJPROP_XDISTANCE);
            long lblY = ObjectGetInteger(m_chart_id, m_lblPairInfo[i].Name(), OBJPROP_YDISTANCE);
            long lblVis = ObjectGetInteger(m_chart_id, m_lblPairInfo[i].Name(), OBJPROP_TIMEFRAMES);
            Print("[UpdateDisplay] Label name=", m_lblPairInfo[i].Name(),
                  " x=", lblX, " y=", lblY, " visible_flags=", lblVis);
            long btnX = ObjectGetInteger(m_chart_id, m_btnClose[i].Name(), OBJPROP_XDISTANCE);
            long btnY = ObjectGetInteger(m_chart_id, m_btnClose[i].Name(), OBJPROP_YDISTANCE);
            long btnVis = ObjectGetInteger(m_chart_id, m_btnClose[i].Name(), OBJPROP_TIMEFRAMES);
            Print("[UpdateDisplay] Button name=", m_btnClose[i].Name(),
                  " x=", btnX, " y=", btnY, " visible_flags=", btnVis);
         }

         m_lblPairInfo[i].Text(info);
         m_lblPairInfo[i].Color(profit >= 0 ? clrGreen : clrRed);

         m_btnClose[i].Text("平仓");
         m_btnClose[i].ColorBackground(clrTomato);
         m_btnClose[i].Color(clrWhite);
      }
      else
      {
         m_lblPairInfo[i].Text(" ");
         m_btnClose[i].Text(" ");
         m_btnClose[i].ColorBackground(clrNONE);
         m_btnClose[i].Color(clrNONE);
      }
   }

   // 总盈亏
   double total = g_manager.GetTotalProfit();
   if(count > 0)
   {
      string totalStr = (total >= 0) ? "+" + DoubleToString(total, 2) : DoubleToString(total, 2);
      m_lblTotalProfit.Text("总盈亏: $" + totalStr);
      m_lblTotalProfit.Color(total >= 0 ? clrGreen : clrRed);
   }
   else
   {
      m_lblTotalProfit.Text("无持仓");
      m_lblTotalProfit.Color(clrGray);
   }

   if(doLog)
   {
      Print("[UpdateDisplay] TotalProfit=", total, " displayCount=", count);
      // 列出面板内所有图表对象，检查有多少
      int totalObjs = ObjectsTotal(m_chart_id, m_subwin);
      Print("[UpdateDisplay] Chart objects in subwin ", m_subwin, ": ", totalObjs);
   }

   m_displayCount = count;
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| 设置状态文字                                                       |
//+------------------------------------------------------------------+
void CPairTraderPanel::SetStatus(string msg)
{
   m_lblStatus.Text(msg);
}

//+------------------------------------------------------------------+
//| EA 初始化                                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // 初始化交易管理器
   g_manager.Init(InpMagicNumber);

   // 创建面板
   if(!g_panel.CreatePanel(0, "PairTrader", 0, 20, 20))
   {
      Print("面板创建失败!");
      return INIT_FAILED;
   }

   g_panel.Run();

   Print("[OnInit] Panel created. PairCount after Init=", g_manager.PairCount());
   g_panel.UpdateDisplay();

   // 启动定时器
   EventSetTimer(InpTimerSec);

   Print("PairTrader EA 初始化完成. TP=", InpTakeProfit, " SL=", InpStopLoss);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EA 卸载                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_panel.Destroy(reason);
   Print("PairTrader EA 已卸载");
}

//+------------------------------------------------------------------+
//| 定时器事件：盈亏监控                                                |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 监控盈亏，自动平仓
   int closed = g_manager.MonitorPairs(InpTakeProfit, InpStopLoss);

   if(closed > 0)
      g_panel.SetStatus(IntegerToString(closed) + " 对触发自动平仓");

   // 刷新面板
   g_panel.UpdateDisplay();
}

//+------------------------------------------------------------------+
//| 图表事件：面板交互                                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   g_panel.ChartEvent(id, lparam, dparam, sparam);
}

//+------------------------------------------------------------------+
//| OnTick - 不使用，跨品种监控依赖 OnTimer                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 留空：跨品种场景下 OnTick 只响应当前图表品种
   // 所有监控逻辑在 OnTimer 中执行
}
