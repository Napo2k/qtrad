//+------------------------------------------------------------------+
//|             Aggressive XAUUSD Bot for MetaTrader 5              |
//|                   Strategy: Momentum Breakout                   |
//|       Features: Scalping, Trailing Stop, ATR-based SL/TP       |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
#include <MovingAverages.mqh>
CTrade trade;

//--- Input Parameters
input double   RiskPerTrade      = 1.5;         // Risk per trade (% of balance)
input int      MaxDailyLoss      = 6;           // Max daily loss (%) before shutdown
input int      MaxTradesPerDay   = 30;          // Max trades per day
input double   ATRMultiplierSL   = 0.75;        // ATR multiplier for stop loss
input double   ATRMultiplierTP   = 1.5;         // ATR multiplier for take profit
input double   ATRTrailTrigger   = 1.0;         // Profit level to start trailing (ATR)
input double   ATRTrailStep      = 0.5;         // Trailing stop distance (ATR)
input int      Slippage          = 10;          // Slippage in points
input ENUM_TIMEFRAMES ATR_TF     = PERIOD_M1;

//--- Globals
datetime       lastTradeTime = 0;
int            tradesToday = 0;
double         startOfDayBalance = 0;

//--- Indicator Handles
int handleEMA20, handleEMA50;
int handleMACD;
int handleATR;
int handleRSI;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   handleEMA20 = iMA(_Symbol, PERIOD_M1, 20, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA50 = iMA(_Symbol, PERIOD_M1, 50, 0, MODE_EMA, PRICE_CLOSE);
   handleMACD  = iMACD(_Symbol, PERIOD_M5, 12, 26, 9, PRICE_CLOSE);
   handleATR   = iATR(_Symbol, ATR_TF, 14);
   handleRSI   = iRSI(_Symbol, PERIOD_M1, 14, PRICE_CLOSE);
   startOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!SessionOK()) return;
   if(tradesToday >= MaxTradesPerDay) return;
   if(DailyLossExceeded()) return;

   double ema20 = iMAOnArray(NULL, 0, 20, 0, MODE_EMA, 0);
   double ema50 = iMAOnArray(NULL, 0, 50, 0, MODE_EMA, 0);
   double macd[], signal[];
   double rsi;
   double atr;

   if(CopyBuffer(handleMACD, 0, 0, 1, macd) < 1) return;
   if(CopyBuffer(handleRSI, 0, 0, 1, &rsi) < 1) return;
   if(CopyBuffer(handleATR, 0, 0, 1, &atr) < 1) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(ema20 > ema50 && macd[0] > 0 && rsi < 80 && BreakoutCondition(true, atr))
   {
      double lotSize = CalculateLotSize(atr, RiskPerTrade);
      if(trade.Buy(lotSize, _Symbol, ask, 0, 0, "AggressiveBuy"))
      {
         SetSLTP(true, atr);
         tradesToday++;
         lastTradeTime = TimeCurrent();
      }
   }
   else if(ema20 < ema50 && macd[0] < 0 && rsi > 20 && BreakoutCondition(false, atr))
   {
      double lotSize = CalculateLotSize(atr, RiskPerTrade);
      if(trade.Sell(lotSize, _Symbol, bid, 0, 0, "AggressiveSell"))
      {
         SetSLTP(false, atr);
         tradesToday++;
         lastTradeTime = TimeCurrent();
      }
   }
   ManageTrailingStops(atr);
}

//+------------------------------------------------------------------+
//| Risk-Based Lot Size Calculation                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double atr, double riskPercent)
{
   double stopPoints = atr * ATRMultiplierSL / _Point;
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * riskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lot = NormalizeDouble(riskMoney / (stopPoints * tickValue), 2);
   return MathMax(lot, lotStep);
}

//+------------------------------------------------------------------+
//| Set SL and TP using ATR                                          |
//+------------------------------------------------------------------+
void SetSLTP(bool isBuy, double atr)
{
   double sl, tp;
   if(isBuy)
   {
      sl = SymbolInfoDouble(_Symbol, SYMBOL_BID) - atr * ATRMultiplierSL;
      tp = SymbolInfoDouble(_Symbol, SYMBOL_BID) + atr * ATRMultiplierTP;
   }
   else
   {
      sl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + atr * ATRMultiplierSL;
      tp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - atr * ATRMultiplierTP;
   }
   trade.PositionModify(_Symbol, sl, tp);
}

//+------------------------------------------------------------------+
//| Check if breakout conditions met                                 |
//+------------------------------------------------------------------+
bool BreakoutCondition(bool isBuy, double atr)
{
   double lastFractal = iFractals(_Symbol, PERIOD_M1, MODE_UPPER);
   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(isBuy)
      return (price > lastFractal + 0.2 * atr);
   else
      return (price < lastFractal - 0.2 * atr);
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop                                             |
//+------------------------------------------------------------------+
void ManageTrailingStops(double atr)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double current = PositionGetDouble(POSITION_PRICE_CURRENT);
         bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double trailLevel = ATRTrailStep * atr;
         double trigger = ATRTrailTrigger * atr;

         if(isBuy && current > entry + trigger)
            trade.PositionModify(ticket, current - trailLevel, PositionGetDouble(POSITION_TP));
         else if(!isBuy && current < entry - trigger)
            trade.PositionModify(ticket, current + trailLevel, PositionGetDouble(POSITION_TP));
      }
   }
}

//+------------------------------------------------------------------+
//| Daily Loss Checker                                               |
//+------------------------------------------------------------------+
bool DailyLossExceeded()
{
   double pnl = AccountInfoDouble(ACCOUNT_BALANCE) - startOfDayBalance;
   return (pnl < -startOfDayBalance * MaxDailyLoss / 100.0);
}

//+------------------------------------------------------------------+
//| Session Filter: London & NY hours                                |
//+------------------------------------------------------------------+
bool SessionOK()
{
   datetime t = TimeCurrent();
   int hour = TimeHour(t);
   return (hour >= 8 && hour <= 19); // London to NY overlap
}
