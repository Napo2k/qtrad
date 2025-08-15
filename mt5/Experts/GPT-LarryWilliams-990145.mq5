//+------------------------------------------------------------------+
//|                                                LarryWilliams EA  |
//|                                   Implements Larry Williams'     |
//|               "first days of the month" long-only daily strategy |
//|                                     Ready for MT5 backtesting    |
//+------------------------------------------------------------------+
#property copyright   "Public domain"
#property version     "1.0"
#property strict

#include <Trade/Trade.mqh>

//--- Inputs
input string           InpSymbol            = "";             // Symbol (blank = current)
input ENUM_TIMEFRAMES  InpTF                = PERIOD_D1;      // Working timeframe
input double           InpLots              = 0.10;           // Lot size
input int              InpMagic             = 990145;       // Magic number

//--- Strategy timing rules
input bool             InpNoFridays         = true;           // Disallow Friday entries
input int              InpMaxDayOfMonth     = 12;             // Only trade within first N calendar days
input bool             InpOneTradePerMonth  = true;           // Only 1 trade per month

//--- Entry filter (Williams %R)
input int              InpWPR_Period        = 14;             // Williams %R period
input double           InpWPR_Threshold     = -20.0;          // W%R must be BELOW this value to enter (e.g., -20)

//--- Exit rule: minimum holding period (in completed bars on InpTF)
//    Set to 12 to reproduce the "Optimization 2" variant from the brief.
input int              InpMinHoldBars       = 1;              // Minimum holding bars before profit exit can trigger

//--- Risk management (choose either fixed % or ATR-based)
input bool             InpUseATRStops       = false;          // Use ATR-based SL/TP instead of fixed % SL
input int              InpATR_Period        = 14;             // ATR period (if ATR mode enabled)
input double           InpSL_ATR_Mult       = 2.0;            // SL = Entry - SLmult * ATR
input double           InpTP_ATR_Mult       = 2.0;            // TP = Entry + TPmult * ATR (0 = no TP)

input double           InpFixedSL_Pct       = 2.5;            // Fixed SL % below entry (for non-ATR mode)

//--- Misc
input bool             InpPrintDebug        = true;           // Verbose log output

//====================================================================
// Internal state
//====================================================================
CTrade   trade;
string   Symb;
int      wpr_handle = INVALID_HANDLE;
int      atr_handle = INVALID_HANDLE;
MqlTick  last_tick;

// Track last processed bar time (on InpTF) to ensure once-per-bar logic
static datetime last_bar_time = 0;

// Track the last month we opened a trade (yyyymm) to enforce 1 trade/month
static int last_trade_yyyymm = 0;

// Track entry info for the currently managed position
static datetime pos_entry_bar_time = 0;  // Open bar time on InpTF when trade was placed

//====================================================================
// Helpers
//====================================================================
int YyyymmFromTime(datetime t)
{
   MqlDateTime s; TimeToStruct(t, s);
   return s.year*100 + s.mon;
}

bool IsFriday(datetime t)
{
   MqlDateTime s; TimeToStruct(t, s);
   return (s.day_of_week == 5); // 0=Sun .. 5=Fri .. 6=Sat
}

int DayOfMonth(datetime t)
{
   MqlDateTime s; TimeToStruct(t, s);
   return s.day;
}

bool GetRates(int bars_needed, MqlRates &r0, MqlRates &r1, MqlRates &r2)
{
   // Fetch latest bars on the working timeframe
   MqlRates rates[];
   if(CopyRates(Symb, InpTF, 0, MathMax(bars_needed, 3), rates) < 3)
      return false;
   ArraySetAsSeries(rates, true);
   r0 = rates[0]; // current forming bar
   r1 = rates[1]; // just closed bar
   r2 = rates[2];
   return true;
}

bool GetIndicatorValues(double &wpr1, double &atr1)
{
   // Read values from the last completed bar (index 1)
   double wpr_buff[]; ArraySetAsSeries(wpr_buff, true);
   if(CopyBuffer(wpr_handle, 0, 0, 3, wpr_buff) < 3)
      return false;
   wpr1 = wpr_buff[1];

   if(InpUseATRStops)
   {
      double atr_buff[]; ArraySetAsSeries(atr_buff, true);
      if(CopyBuffer(atr_handle, 0, 0, 3, atr_buff) < 3)
         return false;
      atr1 = atr_buff[1];
   }
   else
   {
      atr1 = 0.0;
   }
   return true;
}

bool HasOpenPosition()
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == Symb)
            return true;
      }
   }
   return false;
}

bool SelectOurPosition()
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == Symb)
            return true;
      }
   }
   return false;
}

int BarsSince(datetime bar_time)
{
   // Returns number of COMPLETED bars since bar_time on InpTF
   MqlRates r0, r1, r2;
   if(!GetRates(3, r0, r1, r2))
      return 0;
   // Count how many closes have occurred since bar_time
   int count = 0;
   MqlRates rates[];
   int copied = CopyRates(Symb, InpTF, bar_time, TimeCurrent(), rates);
   if(copied <= 0) return 0;
   ArraySetAsSeries(rates, true);
   // Exclude the bar that starts exactly at bar_time (entry bar), so number of completed bars after it
   for(int i=0; i<copied; ++i)
   {
      if(rates[i].time > bar_time)
         count++;
   }
   // We want completed bars, and r0 is forming; ensure we don't count the current forming bar
   if(r0.time > bar_time)
      count = MathMax(0, count-1);
   return count;
}

void DebugPrint(string msg)
{
   if(InpPrintDebug) Print("[LW EA] ", msg);
}

//====================================================================
// Lifecycle
//====================================================================
int OnInit()
{
   Symb = (InpSymbol == "" ? _Symbol : InpSymbol);
   trade.SetExpertMagicNumber(InpMagic);

   // Create Williams %R handle
   wpr_handle = iWPR(Symb, InpTF, InpWPR_Period);
   if(wpr_handle == INVALID_HANDLE)
   {
      Print("Failed to create iWPR handle. Error ", GetLastError());
      return INIT_FAILED;
   }

   // Create ATR handle if needed
   if(InpUseATRStops)
   {
      atr_handle = iATR(Symb, InpTF, InpATR_Period);
      if(atr_handle == INVALID_HANDLE)
      {
         Print("Failed to create iATR handle. Error ", GetLastError());
         return INIT_FAILED;
      }
   }

   // Prime last_bar_time
   MqlRates r0, r1, r2;
   if(GetRates(3, r0, r1, r2))
      last_bar_time = r0.time;

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   if(!SymbolInfoTick(Symb, last_tick)) return;

   // Ensure we have enough history
   MqlRates r0, r1, r2;
   if(!GetRates(3, r0, r1, r2)) return;

   // New bar check on working timeframe
   bool new_bar = (r0.time != last_bar_time);
   if(new_bar)
   {
      // Process exits first at the open of a new bar
      ManageExitOnNewBar(r0, r1, r2);

      // Then evaluate entries using the just-closed bar (r1)
      EvaluateEntryOnNewBar(r0, r1, r2);

      last_bar_time = r0.time;
   }
}

//====================================================================
// Entry Logic
//====================================================================
void EvaluateEntryOnNewBar(const MqlRates &r0, const MqlRates &r1, const MqlRates &r2)
{
   // Only one position at a time for this symbol/magic
   if(HasOpenPosition())
   {
      DebugPrint("Position already open. Skipping new entry.");
      return;
   }

   // Enforce one-trade-per-month if enabled
   if(InpOneTradePerMonth && last_trade_yyyymm != 0)
   {
      int current_yyyymm = YyyymmFromTime(r1.time);
      if(current_yyyymm == last_trade_yyyymm)
      {
         DebugPrint("Already traded this month. Skipping entry.");
         return;
      }
   }

   // Timing filters are based on the signal candle (r1)
   if(InpNoFridays && IsFriday(r1.time))
   {
      DebugPrint("Signal candle is Friday. Skipping entry.");
      return;
   }
   if(DayOfMonth(r1.time) > InpMaxDayOfMonth)
   {
      DebugPrint("Signal after allowed day-of-month window. Skipping entry.");
      return;
   }

   // Indicator filters (use values from r1 / index 1)
   double wpr1, atr1; if(!GetIndicatorValues(wpr1, atr1)) return;

   // Rule: Enter when a daily candle CLOSES above previous day's CLOSE
   bool close_above_prev_close = (r1.close > r2.close);
   bool wpr_ok = (wpr1 < InpWPR_Threshold); // BELOW threshold (e.g., -30 < -20 is true)

   if(!(close_above_prev_close && wpr_ok))
   {
      DebugPrint("Entry conditions not met. close>prevClose=" + (string)close_above_prev_close + ", WPR=" + DoubleToString(wpr1,2));
      return;
   }

   // Compute SL/TP
   double sl = 0.0, tp = 0.0;
   double entry_price = r0.open; // enter at current bar open

   if(InpUseATRStops)
   {
      double atr = atr1;
      if(atr <= 0) { DebugPrint("ATR invalid. Skipping entry."); return; }
      sl = entry_price - InpSL_ATR_Mult * atr;
      if(InpTP_ATR_Mult > 0)
         tp = entry_price + InpTP_ATR_Mult * atr;
   }
   else
   {
      double sl_pct = MathMax(0.0, InpFixedSL_Pct) / 100.0;
      sl = entry_price * (1.0 - sl_pct);
      tp = 0.0; // no fixed TP in base mode (profit exit handled by candle rule)
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.Buy(InpLots, Symb, entry_price, sl, tp, "LW FirstDays Entry");
   if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      last_trade_yyyymm   = YyyymmFromTime(r1.time);
      pos_entry_bar_time  = r0.time; // the bar we entered on
      DebugPrint("BUY opened @" + DoubleToString(entry_price, _Digits) + " SL=" + DoubleToString(sl, _Digits) + (tp>0? " TP="+DoubleToString(tp,_Digits):""));
   }
   else
   {
      DebugPrint("Order failed. Retcode=" + IntegerToString((int)trade.ResultRetcode()) + " Desc=" + trade.ResultRetcodeDescription());
   }
}

//====================================================================
// Exit Logic
//====================================================================
void ManageExitOnNewBar(const MqlRates &r0, const MqlRates &r1, const MqlRates &r2)
{
   if(!SelectOurPosition())
      return;

   // Enforce minimum holding period before profit exit rule can trigger
   int held_bars = BarsSince(pos_entry_bar_time);
   bool min_hold_ok = (held_bars >= InpMinHoldBars);

   // Profit-taking rule: close on the NEXT DAY'S OPEN after a positive-closing candle
   // That means: if the last completed candle (r1) closed positive (close > open),
   // and we've held at least InpMinHoldBars, then we close now (at r0 open).
   bool positive_candle = (r1.close > r1.open);

   if(min_hold_ok && positive_candle)
   {
      double close_price = r0.open;
      if(!trade.PositionClose(Symb, close_price))
      {
         DebugPrint("PositionClose failed. Retcode=" + IntegerToString((int)trade.ResultRetcode()) + " Desc=" + trade.ResultRetcodeDescription());
      }
      else
      {
         DebugPrint("Position closed by rule at open @" + DoubleToString(close_price, _Digits));
      }
      return;
   }

   // No additional exit logic here (SL/TP handled by server if placed)
}

//====================================================================
// Notes for Backtesting & Optimization
// -------------------------------------------------------------------
// - Base Strategy (original):
//     * InpUseATRStops = false
//     * InpFixedSL_Pct = 2.5
//     * InpMinHoldBars = 1
// - Optimization 1 (ATR SL/TP, best demonstrated on Natural Gas):
//     * InpUseATRStops = true
//     * Tune InpATR_Period, InpSL_ATR_Mult, InpTP_ATR_Mult
// - Optimization 2 (Holding period adjustment, e.g., Nasdaq 100):
//     * InpMinHoldBars = 12
//
// - Ensure your data feed has D1 bars for the chosen symbol (Symb) and that
//   the symbol supports long-only trading if you keep the strategy as-is.
// - You can run the EA on any chart/timeframe; it internally uses InpTF
//   (default D1) via CopyRates() for signal generation and exits.
// - Entry/exit are evaluated once per new bar on InpTF.
// - This EA is LONG-ONLY by design, per the original rules.
// - One-trade-per-month is tracked using the signal candle month (r1).
// - Friday filter and first-N-days filter are also based on the signal candle (r1).
// - For portfolio tests, attach multiple instances with different symbols and magics.
//+------------------------------------------------------------------+
