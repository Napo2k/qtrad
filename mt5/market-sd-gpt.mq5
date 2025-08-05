//+------------------------------------------------------------------+
//| Supply & Demand with Market Structure - H1 Strategy EA           |
//+------------------------------------------------------------------+
#property strict

input double LotSize = 0.1;             // Configurable lot size
input double MinRRR = 2.5;              // Minimum Risk:Reward Ratio
input int LookbackBars = 100;           // Number of candles to evaluate

datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if (Period() != PERIOD_H1)
      return;

   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_H1, 0);
   if (currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   // Get price data
   MqlRates rates[];
   if (CopyRates(_Symbol, PERIOD_H1, 0, LookbackBars, rates) <= 0)
      return;

   ArraySetAsSeries(rates, true);

   double ask, bid;
   if (!SymbolInfoDouble(_Symbol, SYMBOL_ASK, ask) || !SymbolInfoDouble(_Symbol, SYMBOL_BID, bid))
      return;

   if (PositionsTotal() > 50) return;

   bool uptrend = IsUptrend(rates);
   bool downtrend = !uptrend;

   double zoneLow, zoneHigh;

   if (uptrend && FindDemandZone(rates, zoneLow, zoneHigh))
   {
      if (ask >= zoneLow && ask <= zoneHigh)
      {
         double sl = zoneLow - 2 * _Point;
         double tp = GetLastHigh(rates);
         double rr = (tp - ask) / (ask - sl);
         if (rr >= MinRRR)
            OpenTrade(ORDER_TYPE_BUY, ask, sl, tp);
      }
   }
   else if (downtrend && FindSupplyZone(rates, zoneLow, zoneHigh))
   {
      if (bid <= zoneHigh && bid >= zoneLow)
      {
         double sl = zoneHigh + 2 * _Point;
         double tp = GetLastLow(rates);
         double rr = (bid - tp) / (sl - bid);
         if (rr >= MinRRR)
            OpenTrade(ORDER_TYPE_SELL, bid, sl, tp);
      }
   }
}

//+------------------------------------------------------------------+
//| Determine if Uptrend based on Higher Lows/Highs                 |
//+------------------------------------------------------------------+
bool IsUptrend(MqlRates &rates[])
{
   for (int i = 20; i < ArraySize(rates) - 5; i++)
   {
      if (rates[i].low > rates[i + 5].low && rates[i].high > rates[i + 5].high)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Find Demand Zone                                                |
//+------------------------------------------------------------------+
bool FindDemandZone(MqlRates &rates[], double &zoneLow, double &zoneHigh)
{
   for (int i = 5; i < ArraySize(rates) - 5; i++)
   {
      if (rates[i].close < rates[i].open &&
          rates[i + 1].close < rates[i + 1].open &&
          rates[i - 1].close > rates[i - 1].open &&
          rates[i - 2].close > rates[i - 2].open)
      {
         zoneLow = rates[i].low;
         zoneHigh = rates[i].high;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Find Supply Zone                                                |
//+------------------------------------------------------------------+
bool FindSupplyZone(MqlRates &rates[], double &zoneLow, double &zoneHigh)
{
   for (int i = 5; i < ArraySize(rates) - 5; i++)
   {
      if (rates[i].close > rates[i].open &&
          rates[i + 1].close > rates[i + 1].open &&
          rates[i - 1].close < rates[i - 1].open &&
          rates[i - 2].close < rates[i - 2].open)
      {
         zoneLow = rates[i].low;
         zoneHigh = rates[i].high;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get Last Major Swing High                                       |
//+------------------------------------------------------------------+
double GetLastHigh(MqlRates &rates[])
{
   double highest = rates[1].high;
   for (int i = 2; i < ArraySize(rates); i++)
   {
      if (rates[i].high > highest)
         highest = rates[i].high;
   }
   return highest;
}

//+------------------------------------------------------------------+
//| Get Last Major Swing Low                                        |
//+------------------------------------------------------------------+
double GetLastLow(MqlRates &rates[])
{
   double lowest = rates[1].low;
   for (int i = 2; i < ArraySize(rates); i++)
   {
      if (rates[i].low < lowest)
         lowest = rates[i].low;
   }
   return lowest;
}

//+------------------------------------------------------------------+
//| Open Trade                                                      |
//+------------------------------------------------------------------+
void OpenTrade(int type, double entry, double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = type;
   request.price = entry;
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = 10;
   request.magic = 123456;
   request.type_filling = ORDER_FILLING_IOC;

   if (!OrderSend(request, result))
      Print("Trade failed: ", result.retcode);
   else
      Print("Trade executed: ", result.order);
}
