//+------------------------------------------------------------------+
//| EMA Cross + RSI Strategy with Money Management (MT5)             |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

//--- Inputs
input ENUM_TIMEFRAMES Inp_Timeframe         = PERIOD_H1;
input int             Inp_EMA_Fast          = 50;
input int             Inp_EMA_Slow          = 200;
input int             Inp_RSI_Period        = 14;
input double          Inp_RSI_Filter        = 50.0;
input double          Inp_RiskPercent       = 1.5;
input double          Inp_RR                = 2.0;
input int             Inp_MaxTrades         = 1;
input int             Inp_SwingBars         = 30;
input double          Inp_SL_Buffer_Pips    = 10.0;
input double          Inp_Breakeven_Pips    = 20.0;
input double          Inp_PartialClosePct   = 50.0;
input double          Inp_TrailingStartPips = 30.0;
input double          Inp_TrailingStepPips  = 10.0;
input uint            Inp_MagicNumber       = 123456;

//--- Internal
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(Inp_MagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only act on new closed bar
   MqlRates rates[3];
   if(CopyRates(_Symbol, Inp_Timeframe, 0, 3, rates) < 2) return;
   if(rates[1].time == lastBarTime) return;
   lastBarTime = rates[1].time;

   // Get EMA/RSI values (shift 1 = last closed bar, shift 2 = prev bar)
   double emaFast_curr = iMA(_Symbol, Inp_Timeframe, Inp_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaFast_prev = iMA(_Symbol, Inp_Timeframe, Inp_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 2);
   double emaSlow_curr = iMA(_Symbol, Inp_Timeframe, Inp_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaSlow_prev = iMA(_Symbol, Inp_Timeframe, Inp_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 2);
   double rsi_curr     = iRSI(_Symbol, Inp_Timeframe, Inp_RSI_Period, PRICE_CLOSE, 1);

   // D1 trend filter
   double emaFast_D1 = iMA(_Symbol, PERIOD_D1, Inp_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaSlow_D1 = iMA(_Symbol, PERIOD_D1, Inp_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);

   // Limit open trades
   if(CountOpenPositions(_Symbol) >= Inp_MaxTrades) return;

   // Detect crosses
   bool bullishCross = (emaFast_prev <= emaSlow_prev) && (emaFast_curr > emaSlow_curr);
   bool bearishCross = (emaFast_prev >= emaSlow_prev) && (emaFast_curr < emaSlow_curr);

   // Buy condition
   if(bullishCross && rsi_curr > Inp_RSI_Filter && emaFast_D1 > emaSlow_D1)
      PlaceTrade(true);

   // Sell condition
   if(bearishCross && rsi_curr < Inp_RSI_Filter && emaFast_D1 < emaSlow_D1)
      PlaceTrade(false);

   // Manage open trades
   ManagePositions();
}

//+------------------------------------------------------------------+
//| Place trade                                                      |
//+------------------------------------------------------------------+
void PlaceTrade(bool isBuy)
{
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pipPoint = (digits == 3 || digits == 5) ? point * 10 : point;

   double price    = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Determine SL from swings
   double sl_price = 0;
   if(isBuy)
      sl_price = GetLowestLow(Inp_SwingBars) - Inp_SL_Buffer_Pips * pipPoint;
   else
      sl_price = GetHighestHigh(Inp_SwingBars) + Inp_SL_Buffer_Pips * pipPoint;

   // Validate SL
   if(isBuy && sl_price >= price) sl_price = price - (Inp_SL_Buffer_Pips + 5) * pipPoint;
   if(!isBuy && sl_price <= price) sl_price = price + (Inp_SL_Buffer_Pips + 5) * pipPoint;

   double sl_distance_pips = MathAbs(price - sl_price) / pipPoint;
   if(sl_distance_pips < 1) return;

   // Lot size calc
   double pipValuePerLot = EstimatePipValuePerLot(pipPoint);
   double risk_amount    = AccountInfoDouble(ACCOUNT_BALANCE) * (Inp_RiskPercent / 100.0);
   double lot            = risk_amount / (sl_distance_pips * pipValuePerLot);

   // Adjust lot
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(minLot, MathMin(maxLot, NormalizeDouble(MathFloor(lot / lotStep) * lotStep, (int)SymbolInfoInteger(_Symbol, SYMBOL_VOLUME_DIGITS))));
   if(lot < minLot) return;

   // TP calc
   double tp_price = 0;
   if(Inp_RR > 0)
   {
      double sl_dist = MathAbs(price - sl_price);
      tp_price = isBuy ? price + sl_dist * Inp_RR : price - sl_dist * Inp_RR;
   }

   // Place trade
   bool ok = isBuy ? trade.Buy(lot, _Symbol, 0, sl_price, tp_price, "EMA50/200+RSI Buy")
                   : trade.Sell(lot, _Symbol, 0, sl_price, tp_price, "EMA50/200+RSI Sell");

   if(!ok)
      Print("Trade failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Manage positions                                                 |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double pipPoint = (digits == 3 || digits == 5) ? point * 10 : point;

   if(!PositionSelect(_Symbol)) return;

   double volume      = PositionGetDouble(POSITION_VOLUME);
   double open_price  = PositionGetDouble(POSITION_PRICE_OPEN);
   double cur_sl      = PositionGetDouble(POSITION_SL);
   double cur_tp      = PositionGetDouble(POSITION_TP);
   long   posType     = PositionGetInteger(POSITION_TYPE);
   double current_price = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double profit_pips = (posType == POSITION_TYPE_BUY) ? (current_price - open_price) / pipPoint
                                                       : (open_price - current_price) / pipPoint;

   // Breakeven
   if(Inp_Breakeven_Pips > 0 && profit_pips >= Inp_Breakeven_Pips)
   {
      double new_sl = (posType == POSITION_TYPE_BUY) ? open_price + 2 * pipPoint
                                                     : open_price - 2 * pipPoint;
      if((posType == POSITION_TYPE_BUY && new_sl > cur_sl) ||
         (posType == POSITION_TYPE_SELL && (cur_sl == 0 || new_sl < cur_sl)))
      {
         trade.PositionModify(_Symbol, new_sl, cur_tp);
      }
   }

   // Partial close
   if(Inp_PartialClosePct > 0 && cur_tp != 0)
   {
      bool tpNear = (posType == POSITION_TYPE_BUY && current_price >= cur_tp - 1.5 * pipPoint) ||
                    (posType == POSITION_TYPE_SELL && current_price <= cur_tp + 1.5 * pipPoint);
      if(tpNear)
      {
         double closeVol = NormalizeDouble(volume * (Inp_PartialClosePct / 100.0), (int)SymbolInfoInteger(_Symbol, SYMBOL_VOLUME_DIGITS));
         if(closeVol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            trade.PositionClosePartial(_Symbol, closeVol);
      }
   }

   // Trailing stop
   if(Inp_TrailingStartPips > 0 && profit_pips >= Inp_TrailingStartPips)
   {
      double desired_sl = (posType == POSITION_TYPE_BUY) ? current_price - Inp_TrailingStepPips * pipPoint
                                                         : current_price + Inp_TrailingStepPips * pipPoint;
      if((posType == POSITION_TYPE_BUY && desired_sl > cur_sl) ||
         (posType == POSITION_TYPE_SELL && (cur_sl == 0 || desired_sl < cur_sl)))
      {
         trade.PositionModify(_Symbol, desired_sl, cur_tp);
      }
   }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int CountOpenPositions(string symbol)
{
   int count = 0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(PositionSelectByIndex(i) && PositionGetString(POSITION_SYMBOL) == symbol)
         count++;
   }
   return count;
}

double GetLowestLow(int bars)
{
   MqlRates r[];
   int copied = CopyRates(_Symbol, Inp_Timeframe, 1, bars, r);
   if(copied <= 0) return 0;
   double low = r[0].low;
   for(int i=1; i<copied; i++) if(r[i].low < low) low = r[i].low;
   return low;
}

double GetHighestHigh(int bars)
{
   MqlRates r[];
   int copied = CopyRates(_Symbol, Inp_Timeframe, 1, bars, r);
   if(copied <= 0) return 0;
   double high = r[0].high;
   for(int i=1; i<copied; i++) if(r[i].high > high) high = r[i].high;
   return high;
}

double EstimatePipValuePerLot(double pipPoint)
{
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size > 0)
      return (tick_value / tick_size) * pipPoint;
   return 10.0; // default for major pairs
}
