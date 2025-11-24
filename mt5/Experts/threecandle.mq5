//+------------------------------------------------------------------+
//|                          Three Candle EMA ATR Strategy.mq5       |
//|      Buy only: 3-candle pattern + above EMA + ATR-based SL/TP   |
//+------------------------------------------------------------------+
#property strict

input int ATR_Period = 21;
input int EMA_Period = 40;
input double Risk_Percent = 1.0;
input ulong MagicNumber = 123456;

int emaHandle, atrHandle;

int OnInit()
{
   emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, ATR_Period);

   if (emaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnTick()
{
   static datetime lastBarTime = 0;
   MqlRates price[4];
   if (CopyRates(_Symbol, _Period, 0, 4, price) < 4) return;
   if (price[1].time == lastBarTime) return;
   lastBarTime = price[1].time;

   if (PositionSelect(_Symbol)) return; // one trade at a time

   if (!ThreeCandlePattern(price)) return;

   double ema[1];
   if (CopyBuffer(emaHandle, 0, 1, 1, ema) < 1) return;
   if (price[1].close <= ema[0]) return; // price not above EMA

   double atr[1];
   if (CopyBuffer(atrHandle, 0, 1, 1, atr) < 1) return;

   double sl_dist = atr[0] * 2.0;
   double tp_dist = sl_dist * 2.0;
   double lot = CalculateLotSize(sl_dist);

   double openPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = NormalizeDouble(openPrice - sl_dist, _Digits);
   double tp = NormalizeDouble(openPrice + tp_dist, _Digits);

   OpenBuyTrade(lot, openPrice, sl, tp);
}

bool ThreeCandlePattern(MqlRates &price[])
{
   return (
      price[2].high > price[1].high &&
      price[2].low  < price[1].low  &&
      price[0].close > price[1].high
   );
}

double CalculateLotSize(double sl_distance)
{
   double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * Risk_Percent / 100.0;
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot_size = risk_amount / (sl_distance / SymbolInfoDouble(_Symbol, SYMBOL_POINT) * tick_value);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return NormalizeDouble(lot_size, (int)MathLog10(1.0 / step));
}

void OpenBuyTrade(double lot, double price, double sl, double tp)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type   = ORDER_TYPE_BUY;
   req.price  = price;
   req.sl     = sl;
   req.tp     = tp;
   req.magic  = MagicNumber;
   req.deviation = 10;
   req.type_filling = ORDER_FILLING_IOC;

   if (!OrderSend(req, res))
      Print("OrderSend failed: ", res.retcode);
   else
      Print("Buy order placed. Order #: ", res.order);
}
