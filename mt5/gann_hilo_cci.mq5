#include <Trade\Trade.mqh>
CTrade trade;

input int    CCI_Period     = 20;
input int    GannPeriod     = 13;
input double LotSize        = 0.1;
input double StopLoss       = 100;
input double TakeProfit     = 150;
input int    MagicNumber    = 777;

double cci_current, cci_previous;
double gann_current, gann_previous;

// Calculate Gann HiLo Activator (simple midpoint)
double GannHiLo(int shift)
{
   double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low  = iLow(_Symbol, PERIOD_CURRENT, shift);
   return (high + low) / 2.0;
}

// Bullish reversal pattern (Engulfing)
bool IsBullishReversal()
{
   double prevOpen  = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double prevClose = iClose(_Symbol, PERIOD_CURRENT, 1);
   double currOpen  = iOpen(_Symbol, PERIOD_CURRENT, 0);
   double currClose = iClose(_Symbol, PERIOD_CURRENT, 0);

   return (prevClose < prevOpen && currClose > currOpen && currClose > prevOpen && currOpen < prevClose);
}

// Bearish reversal pattern (Engulfing)
bool IsBearishReversal()
{
   double prevOpen  = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double prevClose = iClose(_Symbol, PERIOD_CURRENT, 1);
   double currOpen  = iOpen(_Symbol, PERIOD_CURRENT, 0);
   double currClose = iClose(_Symbol, PERIOD_CURRENT, 0);

   return (prevClose > prevOpen && currClose < currOpen && currClose < prevOpen && currOpen > prevClose);
}

//+------------------------------------------------------------------+
//| Expert Initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Gann HiLo + CCI Reversal EA initialized.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   cci_current = iCCI(_Symbol, PERIOD_CURRENT, CCI_Period, PRICE_TYPICAL, 0);
   cci_previous = iCCI(_Symbol, PERIOD_CURRENT, CCI_Period, PRICE_TYPICAL, 1);
   gann_current = GannHiLo(0);
   gann_previous = GannHiLo(1);

   double priceAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double priceBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl = StopLoss * _Point;
   double tp = TakeProfit * _Point;

   // Exit if any position already open
   if (PositionSelect(_Symbol)) return;

   // BUY Conditions
   if (iClose(_Symbol, PERIOD_CURRENT, 1) > gann_previous &&
       IsBullishReversal() &&
       cci_previous < -100 && cci_current > -100)
   {
      if (trade.Buy(LotSize, _Symbol, 0.0, 0.0, "GannCCI Buy"))
      {
         ulong ticket = PositionGetTicket(0);
         trade.PositionModify(ticket, priceAsk - sl, priceAsk + tp);
      }
   }

   // SELL Conditions
   if (iClose(_Symbol, PERIOD_CURRENT, 1) < gann_previous &&
       IsBearishReversal() &&
       cci_previous > 100 && cci_current < 100)
   {
      if (trade.Sell(LotSize, _Symbol, 0.0, 0.0, "GannCCI Sell"))
      {
         ulong ticket = PositionGetTicket(0);
         trade.PositionModify(ticket, priceBid + sl, priceBid - tp);
      }
   }
}
