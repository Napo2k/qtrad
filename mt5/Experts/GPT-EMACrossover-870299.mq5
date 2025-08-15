// =============================================
// File 2: EMA_Trend_Crossover_Risk_Managed_EA.mq5
// Medium-term trend strategy: 50 EMA vs 200 EMA with ATR-based SL/TP + %risk sizing
// Fixed: removed use of undefined SYMBOL_VOLUME_DIGITS and replaced with computed lot digits
// =============================================
#property copyright   "Released for educational use"
#property version     "1.1"
#property strict

#include <Trade/Trade.mqh>
CTrade trade2;

// ---- Inputs ----
input int      InpFastEMA        = 50;        // Fast EMA period
input int      InpSlowEMA        = 200;       // Slow EMA period
input int      InpATRPeriod2     = 14;        // ATR period
input double   InpSL_ATR_Mult    = 2.5;       // Stop = ATR * Multiplier
input double   InpTP_ATR_Mult    = 4.0;       // TakeProfit = ATR * Multiplier (0 = disabled)
input double   InpRiskPct        = 1.0;       // % equity risk per trade
input bool     InpTrailATR       = true;      // Trail with ATR
input int      InpSlipPts        = 5;         // Max slippage (points)
input ulong    InpMagic2         = 870299;     // Magic number
input string   InpComment2       = "GPT-EMATrend";// Trade comment
input bool     InpOnePosOnly2    = true;      // Only one position open per symbol
input ENUM_TIMEFRAMES InpTF2     = PERIOD_H1; // Working timeframe

// ---- Globals ----
int hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE, hATR2 = INVALID_HANDLE;
double point2, tick_size2, tick_value2, lot_step2, min_lot2, max_lot2;

bool NewBar2(){ static datetime last=0; datetime t=iTime(_Symbol, InpTF2, 0); if(t!=last){ last=t; return true;} return false; }

bool GetSymbolInfo2(){
   point2      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   tick_size2  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   tick_value2 = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   lot_step2   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   min_lot2    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   max_lot2    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return(point2>0 && tick_size2>0 && tick_value2>0 && lot_step2>0);
}

double VPP2(){ return (tick_value2 * (point2 / tick_size2)); }

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


double NormLot2(double lots)
{
   double n = MathFloor(lots/lot_step2)*lot_step2;
   n = MathMax(min_lot2, MathMin(n, max_lot2));
   int vol_digits = GetVolumeDigits(lot_step2);
   return NormalizeDouble(n, vol_digits);
}

bool GetMA(int handle, int shift, double &val)
{
   double b[]; if(CopyBuffer(handle,0,shift,1,b)!=1) return false; val=b[0]; return true;
}

bool GetATR2(double &atr){ double b[]; if(CopyBuffer(hATR2,0,1,1,b)!=1) return false; atr=b[0]; return true; }

int OnInit()
{
   if(!GetSymbolInfo2()) return(INIT_FAILED);
   hFast = iMA(_Symbol, InpTF2, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, InpTF2, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hATR2 = iATR(_Symbol, InpTF2, InpATRPeriod2);
   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE || hATR2==INVALID_HANDLE) return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){}

void TrailATR2()
{
   if(!InpTrailATR) return;
   for(int i=0;i<PositionsTotal();i++){
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic2) continue;
      double atr; if(!GetATR2(atr)) return;
      long type = PositionGetInteger(POSITION_TYPE);
      double sl = PositionGetDouble(POSITION_SL);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double trail = InpSL_ATR_Mult * atr;
      if(type==POSITION_TYPE_BUY){
         double newSL = bid - trail;
         if(sl < newSL){ trade2.PositionModify(PositionGetString(POSITION_SYMBOL), newSL, PositionGetDouble(POSITION_TP)); }
      } else if(type==POSITION_TYPE_SELL){
         double newSL = ask + trail;
         if(sl == 0 || sl > newSL){ trade2.PositionModify(PositionGetString(POSITION_SYMBOL), newSL, PositionGetDouble(POSITION_TP)); }
      }
   }
}

void OnTick()
{
   if(!NewBar2()){ TrailATR2(); return; }

   if(InpOnePosOnly2 && PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC)==(long)InpMagic2){ TrailATR2(); return; }

   double fast0, fast1, slow0, slow1;
   if(!GetMA(hFast,0,fast0)) return;
   if(!GetMA(hFast,1,fast1)) return;
   if(!GetMA(hSlow,0,slow0)) return;
   if(!GetMA(hSlow,1,slow1)) return;

   double atr; if(!GetATR2(atr)) return;

   bool bullCross = (fast1 <= slow1 && fast0 > slow0);
   bool bearCross = (fast1 >= slow1 && fast0 < slow0);

   double sl_dist = InpSL_ATR_Mult * atr;
   double tp_dist = (InpTP_ATR_Mult>0? InpTP_ATR_Mult * atr : 0.0);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money = equity * (InpRiskPct/100.0);
   double risk_per_lot = (sl_dist/point2) * VPP2();
   double lots = NormLot2(risk_money / risk_per_lot);
   if(lots < min_lot2) return;

   trade2.SetExpertMagicNumber(InpMagic2);
   trade2.SetDeviationInPoints(InpSlipPts);
   trade2.SetAsyncMode(false);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(bullCross){
      double sl = ask - sl_dist;
      double tp = (tp_dist>0? ask + tp_dist : 0.0);
      trade2.Buy(lots, _Symbol, 0.0, sl, tp, InpComment2);
   }
   if(bearCross){
      double sl = bid + sl_dist;
      double tp = (tp_dist>0? bid - tp_dist : 0.0);
      trade2.Sell(lots, _Symbol, 0.0, sl, tp, InpComment2);
   }

   TrailATR2();
}
