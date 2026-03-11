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
#include <XAUAndGC\LicenseManager.mqh>

//+------------------------------------------------------------------+
//| Input 参数                                                        |
//+------------------------------------------------------------------+
input double   InpTakeProfit    = 500.0;   // 止盈金额(USD)
input double   InpStopLoss     = 300.0;   // 止损金额(USD)
input double   InpTPBuffer     = 5.0;     // 止盈提前触发量(USD)
input int      InpMagicNumber  = 20240101; // Magic Number
input int      InpTimerMs      = 500;      // 监控间隔(毫秒)
input string   InpDefaultSymA  = "XAUUSD"; // 品种A
input string   InpDefaultSymB  = "GC";     // 品种B
input double   InpDefaultLotsA = 0.1;      // 手数A
input double   InpDefaultLotsB = 0.1;      // 手数B

//--- 基差自动开仓参数
input bool     InpSpreadAutoOpen   = false;  // 启用基差自动开仓
input double   InpSpreadThreshold  = 5.0;    // 基差开仓阈值(绝对值)
input int      InpSpreadMaxPairs   = 3;      // 基差开仓最大同时持仓对数

//--- License 认证参数
input string   InpAuthServer      = "https://auth.1pay.dev";  // 认证服务器地址
input string   InpLicenseKey      = "";                         // License Key
input int      InpHeartbeatMin    = 5;                          // 心跳间隔(分钟)

//+------------------------------------------------------------------+
//| 面板尺寸常量                                                       |
//+------------------------------------------------------------------+
#define PANEL_WIDTH    420
#define PANEL_HEIGHT   750
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
   // 品种名（只读）
   CLabel            m_lblSymA;
   CLabel            m_lblSymAVal;
   // 方向和手数（可编辑）
   CComboBox         m_cmbDirA;
   CEdit             m_edtLotsA;

   CLabel            m_lblSymB;
   CLabel            m_lblSymBVal;
   CComboBox         m_cmbDirB;
   CEdit             m_edtLotsB;

   // 止盈止损显示
   CLabel            m_lblTP;
   CLabel            m_lblTPVal;
   CLabel            m_lblSL;
   CLabel            m_lblSLVal;

   // 基差监控区域
   CLabel            m_lblSpreadHeader;
   CLabel            m_lblSpreadCurrent;
   CLabel            m_lblSpreadDayHL;
   CLabel            m_lblSpreadAvg;
   CLabel            m_lblSpreadAuto;

   // 按钮
   CButton           m_btnOpen;
   CButton           m_btnCloseAll;

   // 持仓信息区域
   CLabel            m_lblPairHeader;
   CLabel            m_lblPairInfo[10];    // 最多显示10对
   CButton           m_btnClose[10];       // 每对的平仓按钮
   CLabel            m_lblTotalProfit;

   // 历史记录区域
   CLabel            m_lblHistHeader;
   CLabel            m_lblHistInfo[5];     // 最近5条平仓记录

   // 状态
   CLabel            m_lblStatus;

   int               m_displayCount;

public:
   bool              CreatePanel(long chart, string name, int subwin, int x, int y);
   void              UpdateDisplay();
   void              SetStatus(string msg);

   // 获取面板可编辑值
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
CSpreadMonitor     g_spread;
CLicenseManager    g_license;

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
   if(!g_license.IsAuthorized())
   {
      g_panel.SetStatus("License未验证，无法开仓");
      return;
   }

   string errorMsg;
   // 品种由Input参数决定（只读），方向和手数从面板读取
   bool result = g_manager.OpenPair(
      InpDefaultSymA, g_panel.GetDirA(), g_panel.GetLotsA(),
      InpDefaultSymB, g_panel.GetDirB(), g_panel.GetLotsB(),
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

   // === 品种A行：品种只读，方向和手数可编辑 ===
   m_lblSymA.Create(m_chart_id, "lblSymA", m_subwin, LABEL_X, row, LABEL_X + 80, row + ROW_HEIGHT);
   m_lblSymA.Text("品种A:");
   Add(m_lblSymA);

   m_lblSymAVal.Create(m_chart_id, "lblSymAVal", m_subwin, INPUT_X, row, INPUT_X + INPUT_WIDTH, row + ROW_HEIGHT);
   m_lblSymAVal.Text(InpDefaultSymA);
   m_lblSymAVal.Color(clrDodgerBlue);
   Add(m_lblSymAVal);

   m_cmbDirA.Create(m_chart_id, "cmbDirA", m_subwin, INPUT_X + INPUT_WIDTH + 5, row, INPUT_X + INPUT_WIDTH + 75, row + ROW_HEIGHT);
   m_cmbDirA.ItemAdd("Buy", 0);
   m_cmbDirA.ItemAdd("Sell", 1);
   m_cmbDirA.SelectByValue(0);
   Add(m_cmbDirA);

   m_edtLotsA.Create(m_chart_id, "edtLotsA", m_subwin, INPUT_X + INPUT_WIDTH + 80, row, INPUT_X + INPUT_WIDTH + 145, row + ROW_HEIGHT);
   m_edtLotsA.Text(DoubleToString(InpDefaultLotsA, 2));
   Add(m_edtLotsA);

   row += ROW_HEIGHT + 5;

   // === 品种B行：品种只读，方向和手数可编辑 ===
   m_lblSymB.Create(m_chart_id, "lblSymB", m_subwin, LABEL_X, row, LABEL_X + 80, row + ROW_HEIGHT);
   m_lblSymB.Text("品种B:");
   Add(m_lblSymB);

   m_lblSymBVal.Create(m_chart_id, "lblSymBVal", m_subwin, INPUT_X, row, INPUT_X + INPUT_WIDTH, row + ROW_HEIGHT);
   m_lblSymBVal.Text(InpDefaultSymB);
   m_lblSymBVal.Color(clrDodgerBlue);
   Add(m_lblSymBVal);

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

   // === 基差监控区域 ===
   m_lblSpreadHeader.Create(m_chart_id, "lblSpreadHdr", m_subwin, LABEL_X, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
   m_lblSpreadHeader.Text("─── 基差监控 (" + InpDefaultSymA + " - " + InpDefaultSymB + ") ───");
   Add(m_lblSpreadHeader);

   row += ROW_HEIGHT + 3;

   m_lblSpreadCurrent.Create(m_chart_id, "lblSpreadCur", m_subwin, LABEL_X, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
   m_lblSpreadCurrent.Text("实时基差: --");
   m_lblSpreadCurrent.Color(clrWhite);
   Add(m_lblSpreadCurrent);

   row += ROW_HEIGHT + 2;

   m_lblSpreadDayHL.Create(m_chart_id, "lblSpreadHL", m_subwin, LABEL_X, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
   m_lblSpreadDayHL.Text("今日: 高 -- / 低 --");
   Add(m_lblSpreadDayHL);

   row += ROW_HEIGHT + 2;

   m_lblSpreadAvg.Create(m_chart_id, "lblSpreadAvg", m_subwin, LABEL_X, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
   m_lblSpreadAvg.Text("均值: -- (采样: 0)");
   Add(m_lblSpreadAvg);

   row += ROW_HEIGHT + 2;

   m_lblSpreadAuto.Create(m_chart_id, "lblSpreadAuto", m_subwin, LABEL_X, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
   if(InpSpreadAutoOpen)
      m_lblSpreadAuto.Text("自动开仓: ON  阈值=" + DoubleToString(InpSpreadThreshold, 2) + "  上限=" + IntegerToString(InpSpreadMaxPairs) + "对");
   else
      m_lblSpreadAuto.Text("自动开仓: OFF");
   m_lblSpreadAuto.Color(InpSpreadAutoOpen ? clrLimeGreen : clrGray);
   Add(m_lblSpreadAuto);

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
   for(int i = 0; i < 10; i++)
   {
      string idxStr = IntegerToString(i);

      m_lblPairInfo[i].Create(m_chart_id, "lblPair" + idxStr, m_subwin,
                              LABEL_X, row, PANEL_WIDTH - 80, row + ROW_HEIGHT);
      m_lblPairInfo[i].Text(" ");
      Add(m_lblPairInfo[i]);

      m_btnClose[i].Create(m_chart_id, "btnClose" + idxStr, m_subwin,
                           PANEL_WIDTH - 75, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
      m_btnClose[i].Text(" ");
      m_btnClose[i].ColorBackground(clrNONE);
      m_btnClose[i].Color(clrNONE);
      Add(m_btnClose[i]);

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

   // === 分隔线 - 最近平仓标题 ===
   m_lblHistHeader.Create(m_chart_id, "lblHistHdr", m_subwin, LABEL_X, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
   m_lblHistHeader.Text("─── 最近平仓 ───");
   Add(m_lblHistHeader);

   row += ROW_HEIGHT + 5;

   // === 最近平仓记录 (最多5条) ===
   for(int h = 0; h < 5; h++)
   {
      string hIdxStr = IntegerToString(h);
      m_lblHistInfo[h].Create(m_chart_id, "lblHist" + hIdxStr, m_subwin,
                              LABEL_X, row, PANEL_WIDTH - 30, row + ROW_HEIGHT);
      m_lblHistInfo[h].Text(" ");
      m_lblHistInfo[h].Color(clrGray);
      Add(m_lblHistInfo[h]);

      row += ROW_HEIGHT + 2;
   }

   row += 5;

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
      Print("[UpdateDisplay] PairCount=", count);
   }

   // 基差监控区域更新
   double spread = g_spread.Current();
   double dayH   = g_spread.DayHigh();
   double dayL   = g_spread.DayLow();
   double avg    = g_spread.HistAvg();
   int    samples = g_spread.SampleCount();

   if(samples > 0)
   {
      m_lblSpreadCurrent.Text("实时基差: " + DoubleToString(spread, 2));
      m_lblSpreadCurrent.Color(spread >= 0 ? clrLimeGreen : clrOrangeRed);

      m_lblSpreadDayHL.Text("今日: 高 " + DoubleToString(dayH, 2)
                          + " / 低 " + DoubleToString(dayL, 2)
                          + " / 幅 " + DoubleToString(dayH - dayL, 2));

      m_lblSpreadAvg.Text("均值: " + DoubleToString(avg, 2) + " (采样: " + IntegerToString(samples) + ")");
   }

   // 持仓列表
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

   // 历史记录（最近5条，倒序显示：最新的在最上面）
   int histCount = g_manager.HistoryCount();
   for(int h = 0; h < 5; h++)
   {
      int histIdx = histCount - 1 - h;
      if(histIdx >= 0)
      {
         PairHistory hist;
         g_manager.GetHistory(histIdx, hist);

         string dirA = (hist.dirA == ORDER_TYPE_BUY) ? "B" : "S";
         string dirB = (hist.dirB == ORDER_TYPE_BUY) ? "B" : "S";
         string profStr = (hist.realProfit >= 0) ? "+" + DoubleToString(hist.realProfit, 2)
                                                  : DoubleToString(hist.realProfit, 2);

         MqlDateTime dt;
         TimeToStruct(hist.closeTime, dt);
         string timeStr = StringFormat("%02d:%02d", dt.hour, dt.min);

         string histText = "#" + IntegerToString(hist.pairId) + " "
                         + hist.symbolA + " " + dirA + " / "
                         + hist.symbolB + " " + dirB + "  "
                         + hist.reason + " $" + profStr + "  " + timeStr;

         m_lblHistInfo[h].Text(histText);
         m_lblHistInfo[h].Color(hist.realProfit >= 0 ? clrGreen : clrRed);
      }
      else
      {
         m_lblHistInfo[h].Text(" ");
         m_lblHistInfo[h].Color(clrGray);
      }
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
   // === License 验证（最先执行） ===
   g_license.Init(InpAuthServer, InpLicenseKey, InpHeartbeatMin);

   if(!g_license.Authenticate())
   {
      Print("[License] 验证失败，EA 将在 10 秒后自动移除");
      Comment("License 验证失败: " + g_license.GetStatus()
            + "\n请检查 License Key 是否正确"
            + "\n服务器: " + InpAuthServer);
      EventSetTimer(10); // 延迟移除，给用户看错误信息
      return INIT_SUCCEEDED;
   }

   // === 初始化交易管理器 ===
   g_manager.Init(InpMagicNumber);

   // 初始化基差监控
   g_spread.Init(InpDefaultSymA, InpDefaultSymB);

   // 创建面板
   if(!g_panel.CreatePanel(0, "PairTrader", 0, 20, 20))
   {
      Print("面板创建失败!");
      return INIT_FAILED;
   }

   g_panel.Run();

   // 禁止图表前景模式，防止K线绘制遮挡面板
   ChartSetInteger(0, CHART_FOREGROUND, false);

   Print("[OnInit] Panel created. PairCount after Init=", g_manager.PairCount());
   g_panel.UpdateDisplay();

   // 启动毫秒级定时器
   EventSetMillisecondTimer(InpTimerMs);

   Print("PairTrader EA 初始化完成. TP=", InpTakeProfit, " SL=", InpStopLoss,
         " Timer=", InpTimerMs, "ms SpreadAuto=", InpSpreadAutoOpen,
         " SpreadThreshold=", InpSpreadThreshold,
         " License=", g_license.GetStatus());
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
//| 基差自动开仓逻辑                                                   |
//+------------------------------------------------------------------+
void CheckSpreadAutoOpen()
{
   if(!InpSpreadAutoOpen)
      return;

   // 达到最大持仓对数则不开
   if(g_manager.PairCount() >= InpSpreadMaxPairs)
      return;

   double spread = g_spread.Current();
   int    samples = g_spread.SampleCount();

   // 至少采样60次后才开始判断（避免启动初期误判）
   if(samples < 60)
      return;

   string errorMsg;

   // 基差 >= 阈值: 基差偏高，做空基差（卖A买B，期待基差缩小）
   if(spread >= InpSpreadThreshold)
   {
      Print("[SpreadAuto] 基差偏高触发: spread=", DoubleToString(spread, 2),
            " >= 阈值=", DoubleToString(InpSpreadThreshold, 2));

      bool ok = g_manager.OpenPair(
         InpDefaultSymA, ORDER_TYPE_SELL, InpDefaultLotsA,
         InpDefaultSymB, ORDER_TYPE_BUY, InpDefaultLotsB,
         errorMsg
      );

      if(ok)
         g_panel.SetStatus("基差自动开仓(卖A买B)");
      else
         Print("[SpreadAuto] 开仓失败: ", errorMsg);
   }
   // 基差 <= -阈值: 基差偏低（反向），做多基差（买A卖B）
   else if(spread <= -InpSpreadThreshold)
   {
      Print("[SpreadAuto] 基差偏低触发: spread=", DoubleToString(spread, 2),
            " <= -阈值=", DoubleToString(-InpSpreadThreshold, 2));

      bool ok = g_manager.OpenPair(
         InpDefaultSymA, ORDER_TYPE_BUY, InpDefaultLotsA,
         InpDefaultSymB, ORDER_TYPE_SELL, InpDefaultLotsB,
         errorMsg
      );

      if(ok)
         g_panel.SetStatus("基差自动开仓(买A卖B)");
      else
         Print("[SpreadAuto] 开仓失败: ", errorMsg);
   }
}

//+------------------------------------------------------------------+
//| 定时器事件：盈亏监控 + 基差监控                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   // === License 未通过 → 延迟移除 ===
   if(!g_license.IsAuthorized())
   {
      ExpertRemove();
      return;
   }

   // === License 心跳（内部自动控制频率） ===
   if(!g_license.Heartbeat())
   {
      // License 失效，平掉所有持仓后停止
      Print("[License] License 已失效，正在平仓并停止...");
      g_manager.CloseAllPairs();
      g_panel.SetStatus("License失效: " + g_license.GetStatus());
      g_panel.UpdateDisplay();
      ExpertRemove();
      return;
   }

   // === 正常业务逻辑 ===
   // 更新基差
   g_spread.Update();

   // 监控盈亏，自动平仓
   int closed = g_manager.MonitorPairs(InpTakeProfit, InpStopLoss, InpTPBuffer);

   if(closed > 0)
      g_panel.SetStatus(IntegerToString(closed) + " 对触发自动平仓");

   // 基差自动开仓检查
   CheckSpreadAutoOpen();

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
   // 图表属性变化（新K线/缩放/滚动）时，确保面板前景显示
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      // 禁止图表前景显示，避免遮挡面板控件
      ChartSetInteger(0, CHART_FOREGROUND, false);
   }

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
