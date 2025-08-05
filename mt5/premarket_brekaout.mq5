//+------------------------------------------------------------------+
//|                                                         PremarketBreakoutEA.mq5 |
//|                        Premarket Volume and Breakout Strategy              |
//+------------------------------------------------------------------+
#property strict

input double   RiskPerTrade    = 1.0;      // Risk per trade in %
input double   RR_Ratio        = 3.0;      // Reward:Risk ratio
input int      VolumeThreshold = 1000000;  // Minimum premarket volume
input int      Slippage        = 10;       // Max slippage
input double   Lots            = 0.1;      // Fixed lot size (if risk calc is off)
input bool     UseDynamicLots  = true;

datetime       premarketStart = D'1970.01.01 11:00'; // 04:00 EST (adjust to broker timezone)
datetime       premarketEnd   = D'1970.01.01 14:30'; // 09:30 EST
double         premarketHigh  = 0;
double         premarketLow   = 0;
double         measuredMove   = 0;
bool           tradeExecuted  = false;

//+------------------------------------------------------------------+
//| Get premarket volume                                            |
//+------------------------------------------------------------------+
double GetPremarketVolume()
{
   double totalVolume = 0;
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_M1, premarketStart, premarketEnd, rates) > 0)
   {
      for(int i=0; i<ArraySize(rates); i++)
         totalVolume += rates[i].tick_volume;
   }
   return totalVolume;
}

//+------------------------------------------------------------------+
//| Get highest historical daily volume                             |
//+------------------------------------------------------------------+
double GetHighestDailyVolume(int daysBack = 60)
{
   double maxVol = 0;
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_D1, 0, daysBack, rates) > 0)
   {
      for(int i=0; i<ArraySize(rates); i++)
         if(rates[i].tick_volume > maxVol)
            maxVol = rates[i].tick_volume;
   }
   return maxVol;
}

//+------------------------------------------------------------------+
//| Identify consolidation range                                     |
//+------------------------------------------------------------------+
bool IdentifyConsolidationRange()
{
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_M1, premarketStart, premarketEnd, rates) <= 0)
      return false;

   double highest = -DBL_MAX;
   double lowest = DBL_MAX;
   datetime lastTimestamp = 0;
   int rangeCount = 0;
   
   for(int i=0; i<ArraySize(rates); i++)
   {
      if(rates[i].high > highest) highest = rates[i].high;
      if(rates[i].low < lowest)  lowest  = rates[i].low;
   }

   if((highest - lowest) / lowest < 0.05) // tight range under 5% width
   {
      premarketHigh = highest;
      premarketLow  = lowest;
      measuredMove  = premarketHigh - premarketLow;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Entry logic: monitor breakout and enter trade                   |
//+------------------------------------------------------------------+
void CheckForBreakout()
{
   if(tradeExecuted) return;

   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(price > premarketHigh)
   {
      double sl = premarketLow;
      double tp = premarketHigh + measuredMove;
      double stopDistance = price - sl;
      double lotSize = UseDynamicLots ? CalculateLotSize(stopDistance) : Lots;

      tradeExecuted = true;
      trade.Buy(lotSize, _Symbol, price, sl, tp, "Premarket Breakout");
   }
}

//+------------------------------------------------------------------+
//| Calculate position size based on account risk                   |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * RiskPerTrade / 100.0;
   double tickValue, tickSize;
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE, tickValue);
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, tickSize);

   double lotSize = riskAmount / (stopDistance / tickSize * tickValue);
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Main Tick Function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!tradeExecuted && TimeCurrent() > premarketEnd && TimeCurrent() < premarketEnd + 3600)
   {
      double preVol = GetPremarketVolume();
      double maxDailyVol = GetHighestDailyVolume();
      
      if(preVol >= VolumeThreshold && preVol >= maxDailyVol)
      {
         if(IdentifyConsolidationRange())
            CheckForBreakout();
      }
   }
}
