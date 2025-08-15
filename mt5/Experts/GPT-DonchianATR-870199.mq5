// =============================================
// File 1: Donchian_ATR_Risk_Managed_EA.mq5
// Robust trend-following breakout (Turtle-style) with ATR stops and %risk sizing
// Fixed: removed use of undefined SYMBOL_VOLUME_DIGITS and replaced with computed lot digits
// =============================================
#property copyright   "Released for educational use"
#property version     "1.1"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// ---- Inputs ----
input int      InpDonchianEntry   = 55;      // Donchian Entry Period (breakout)
input int      InpDonchianExit    = 20;      // Donchian Exit Period (stop-out channel)
input int      InpATRPeriod       = 14;      // ATR period
input double   InpATRMultSL       = 2.0;     // SL = ATR * Multiplier
input double   InpATRMultTP       = 4.0;     // TP = ATR * Multiplier (0 = disabled)
input double   InpRiskPercent     = 1.0;     // % of equity risked per trade
input bool     InpUseTrailingATR  = true;    // Trail with ATR stop
input int      InpSlippagePoints  = 5;       // Max slippage (points)
input ulong    InpMagic           = 870199;  // Magic number
input string   InpComment         = "GPT-DonchianATR"; // Trade comment

// Execution options
input bool     InpOneTradePerDir  = true;    // Allow only one position per direction
input bool     InpOnlyOnePos      = true;    // Allow only one position total per symbol

// Timeframe (indicator calc)
input ENUM_TIMEFRAMES InpTF       = PERIOD_H1; // Working timeframe

// ---- Globals ----
int            atr_handle = INVALID_HANDLE;
double         point, tick_size, tick_value, lot_step, min_lot, max_lot;

// ---- Helpers ----
bool NewBar()
{
   static datetime last_bar = 0;
   datetime t = iTime(_Symbol, InpTF, 0);
   if(t != last_bar){ last_bar = t; return true; }
   return false;
}

bool GetSymbolInfo()
{
   point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   lot_step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   min_lot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   max_lot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return(point>0 && tick_size>0 && tick_value>0 && lot_step>0);
}

int GetVolumeDigits(double step)
{
   // Compute number of decimal places for the volume step (e.g. 0.01 -> 2)
   if(step <= 0) return(0);
   string s = DoubleToString(step, 10);
   int pos = StringFind(s, ".");
   if(pos < 0) return(0);
   // trim trailing zeros
   while(StringLen(s) > 0 && StringSubstr(s, StringLen(s)-1, 1) == "0")
      s = StringSubstr(s, 0, StringLen(s)-1);
   int digits = StringLen(s) - pos - 1;
   return(MathMax(0, digits));
}

double ValuePerPointPerLot()
{
   // Convert tick value/size to value per point for 1.0 lot
   return (tick_value * (point / tick_size));
}

double NormalizeLot(double lots)
{
   double n = MathFloor(lots/lot_step)*lot_step;
   n = MathMax(min_lot, MathMin(n, max_lot));
   int vol_digits = GetVolumeDigits(lot_step);
   return NormalizeDouble(n, vol_digits);
}

int CountOpenByDir(int dir)
{
   // dir: 1=BUY, -1=SELL
   int cnt = 0;
   for(int i=0;i<PositionsTotal();i++){
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!= (long)InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if((dir==1 && type==POSITION_TYPE_BUY) || (dir==-1 && type==POSITION_TYPE_SELL)) cnt++;
   }
   return cnt;
}

int CountOpenAll()
{
   int cnt = 0;
   for(int i=0;i<PositionsTotal();i++){
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!= (long)InpMagic) continue;
      cnt++;
   }
   return cnt;
}

bool GetATR(double &atr)
{
   double buf[];
   if(CopyBuffer(atr_handle,0,1,1,buf)!=1) return false; // shift 1 = last closed bar
   atr = buf[0];
   return true;
}

void Donchian(int period, double &highest, double &lowest)
{
   // Calculate over last 'period' closed bars (shift from 1)
   MqlRates rates[];
   int need = period+1;
   int copied = CopyRates(_Symbol, InpTF, 1, need, rates);
   highest = -DBL_MAX; lowest = DBL_MAX;
   if(copied<period) return;
   for(int i=0;i<period;i++){
      highest = MathMax(highest, rates[i].high);
      lowest  = MathMin(lowest,  rates[i].low);
   }
}

bool PlaceOrder(int dir, double sl_price, double tp_price, double lots)
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetAsyncMode(false);
   string cmt = InpComment;
   bool ok=false;
   if(dir>0){ ok = trade.Buy(lots, _Symbol, 0.0, sl_price, tp_price, cmt); }
   else { ok = trade.Sell(lots, _Symbol, 0.0, sl_price, tp_price, cmt); }
   return ok;
}

void ManageTrailingATR()
{
   if(!InpUseTrailingATR) return;
   double atr; if(!GetATR(atr)) return;
   double trail = InpATRMultSL * atr; // price units
   // iterate positions and modify SL per position
   for(int i=0;i<PositionsTotal();i++){
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic) continue;
      long type   = PositionGetInteger(POSITION_TYPE);
      double sl    = PositionGetDouble(POSITION_SL);
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(type==POSITION_TYPE_BUY){
         double newSL = bid - trail; // trail below price
         if(sl < newSL){ trade.PositionModify(PositionGetString(POSITION_SYMBOL), newSL, PositionGetDouble(POSITION_TP)); }
      } else if(type==POSITION_TYPE_SELL){
         double newSL = ask + trail; // trail above price
         if(sl == 0 || sl > newSL){ trade.PositionModify(PositionGetString(POSITION_SYMBOL), newSL, PositionGetDouble(POSITION_TP)); }
      }
   }
}

void ExitOnDonchian()
{
   double hi, lo; Donchian(InpDonchianExit, hi, lo);
   // close positions that break exit channel
   for(int i=0;i<PositionsTotal();i++){
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      double close1 = iClose(_Symbol, InpTF, 1);
      if(type==POSITION_TYPE_BUY && close1 < lo){ trade.PositionClose(PositionGetString(POSITION_SYMBOL)); }
      if(type==POSITION_TYPE_SELL && close1 > hi){ trade.PositionClose(PositionGetString(POSITION_SYMBOL)); }
   }
}

int OnInit()
{
   if(!GetSymbolInfo()) return(INIT_FAILED);
   atr_handle = iATR(_Symbol, InpTF, InpATRPeriod);
   if(atr_handle==INVALID_HANDLE) return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   if(!NewBar()) { ManageTrailingATR(); return; }

   if(InpOnlyOnePos && CountOpenAll()>0) { ManageTrailingATR(); ExitOnDonchian(); return; }

   double atr; if(!GetATR(atr)) return;
   double value_per_point = ValuePerPointPerLot();

   // Compute Donchian breakout levels
   double hiE, loE; Donchian(InpDonchianEntry, hiE, loE);
   double close1 = iClose(_Symbol, InpTF, 1);

   // Determine signals
   bool longSignal  = (close1 > hiE);
   bool shortSignal = (close1 < loE);

   // Calculate stop/TP distances in price units
   double sl_dist = InpATRMultSL * atr;
   double tp_dist = (InpATRMultTP>0 ? InpATRMultTP * atr : 0.0);

   // Position sizing by %risk
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money = equity * (InpRiskPercent/100.0);
   double dist_points = sl_dist/point;
   if(dist_points <= 0) return;
   double risk_per_lot = dist_points * value_per_point; // money risked per 1 lot
   double lots = risk_money / risk_per_lot;
   lots = NormalizeLot(lots);
   if(lots < min_lot) return;

   // Enforce position limits per direction
   if(longSignal && InpOneTradePerDir && CountOpenByDir(1)>0) longSignal=false;
   if(shortSignal && InpOneTradePerDir && CountOpenByDir(-1)>0) shortSignal=false;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(longSignal){
      double sl = ask - sl_dist;
      double tp = (tp_dist>0? ask + tp_dist : 0.0);
      PlaceOrder(+1, sl, tp, lots);
   }
   if(shortSignal){
      double sl = bid + sl_dist;
      double tp = (tp_dist>0? bid - tp_dist : 0.0);
      PlaceOrder(-1, sl, tp, lots);
   }

   ExitOnDonchian();
   ManageTrailingATR();
}


