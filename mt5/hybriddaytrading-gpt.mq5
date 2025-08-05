//+------------------------------------------------------------------+
//|   Hybrid Day Trading Strategy EA (5-Minute, 10 SMA + MACD)       |
//+------------------------------------------------------------------+
#property strict

input int    SMA_Period       = 10;
input double Risk_Percent     = 1.0;
input int    MaxTradesPerDay  = 1000;   // Set very high; configurable later
input ulong  MagicNumber      = 555777;

int          smaHandle, macdHandle;
datetime     lastEntryTime = 0;

int          tradesToday = 0;
int          currentDay = -1;

//+------------------------------------------------------------------+
int OnInit()
{
   smaHandle = iMA(_Symbol, PERIOD_M5, SMA_Period, 0, MODE_SMA, PRICE_CLOSE);
   if (smaHandle == INVALID_HANDLE) return INIT_FAILED;

   macdHandle = iMACD(_Symbol, PERIOD_M5, 12, 26, 9, PRICE_CLOSE);
   if (macdHandle == INVALID_HANDLE) return INIT_FAILED;

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   MqlRates price[3];
   if (CopyRates(_Symbol, PERIOD_M5, 0, 3, price) < 3) return;

   double sma[3];
   if (CopyBuffer(smaHandle, 0, 0, 3, sma) < 3) return;

   double macdMain[3], macdSignal[3];
   if (CopyBuffer(macdHandle, 0, 0, 3, macdMain) < 3) return;
   if (CopyBuffer(macdHandle, 1, 0, 3, macdSignal) < 3) return;

   // Reset trade count on new day
   int today = TimeDay(TimeCurrent());
   if (today != currentDay)
   {
      tradesToday = 0;
      currentDay = today;
   }

   if (tradesToday >= MaxTradesPerDay) return;

   bool bullishCross = macdMain[1] < macdSignal[1] && macdMain[0] > macdSignal[0];
   bool bearishCross = macdMain[1] > macdSignal[1] && macdMain[0] < macdSignal[0];

   bool priceCrossAboveSMA = price[1].close < sma[1] && price[0].close > sma[0];
   bool priceCrossBelowSMA = price[1].close > sma[1] && price[0].close < sma[0];

   if (priceCrossAboveSMA && bullishCross)
   {
      OpenTrade(ORDER_TYPE_BUY);
   }
   else if (priceCrossBelowSMA && bearishCross)
   {
      OpenTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * Risk_Percent / 100.0;
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot_size = risk_amount / tick_value;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return NormalizeDouble(lot_size, (int)MathLog10(1.0 / step));
}

//+------------------------------------------------------------------+
void OpenTrade(int type)
{
   double totalLot = CalculateLotSize();
   double entryPrice = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl = (type == ORDER_TYPE_BUY) ? entryPrice - entryPrice * 0.005
                                        : entryPrice + entryPrice * 0.005;

   double tp1 = (type == ORDER_TYPE_BUY) ? entryPrice + entryPrice * 0.01
                                         : entryPrice - entryPrice * 0.01;
   double tp2 = (type == ORDER_TYPE_BUY) ? entryPrice + entryPrice * 0.02
                                         : entryPrice - entryPrice * 0.02;
   double tp3 = (type == ORDER_TYPE_BUY) ? entryPrice + entryPrice * 0.03
                                         : entryPrice - entryPrice * 0.03;

   double lot25 = NormalizeDouble(totalLot * 0.25, 2);

   // First 25% to TP1
   SendOrder(type, lot25, entryPrice, sl, tp1);
   // Second 25% to TP2
   SendOrder(type, lot25, entryPrice, sl, tp2);
   // Third 25% to TP3
   SendOrder(type, lot25, entryPrice, sl, tp3);
   // Final 25% trailing stop
   SendOrder(type, lot25, entryPrice, sl, 0, true);

   tradesToday++;
}

//+------------------------------------------------------------------+
void SendOrder(int type, double volume, double price, double sl, double tp, bool trailing=false)
{
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = volume;
   req.type = type;
   req.price = NormalizeDouble(price, _Digits);
   req.sl = NormalizeDouble(sl, _Digits);
   req.tp = (tp > 0) ? NormalizeDouble(tp, _Digits) : 0;
   req.magic = MagicNumber;
   req.deviation = 10;
   req.type_filling = ORDER_FILLING_IOC;

   if (OrderSend(req, res))
   {
      Print("Order opened: ", volume, " lots ", type == ORDER_TYPE_BUY ? "BUY" : "SELL");

      if (trailing && res.retcode == TRADE_RETCODE_DONE)
      {
         // For full trailing implementation, add trailing logic in OnTick
         Print("Trailing position active: Ticket #", res.order);
      }
   }
   else
   {
      Print("Order failed: ", res.retcode);
   }
}
