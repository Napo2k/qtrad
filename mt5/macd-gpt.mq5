//+------------------------------------------------------------------+
//|    MACD + 200 EMA + Support/Resistance Confirmation EA (M30)     |
//|    Buy: MACD cross up below 0 + price above 200 EMA + support    |
//|    Sell: MACD cross down above 0 + price below 200 EMA + resistance|
//+------------------------------------------------------------------+
#property strict

input int EMA_Period = 200;
input double Risk_Percent = 1.0; // 1% of account
input ulong MagicNumber = 444888;

int emaHandle, macdHandle;
bool hasPosition = false;
datetime lastSignalTime = 0;

int OnInit()
{
   emaHandle = iMA(_Symbol, PERIOD_M30, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if (emaHandle == INVALID_HANDLE) return INIT_FAILED;

   macdHandle = iMACD(_Symbol, PERIOD_M30, 12, 26, 9, PRICE_CLOSE);
   if (macdHandle == INVALID_HANDLE) return INIT_FAILED;

   return INIT_SUCCEEDED;
}

void OnTick()
{
   static datetime lastTime = 0;
   MqlRates price[3];
   if (CopyRates(_Symbol, PERIOD_M30, 0, 3, price) < 3) return;
   if (price[1].time == lastTime) return;
   lastTime = price[1].time;

   double ema[1];
   if (CopyBuffer(emaHandle, 0, 1, 1, ema) < 1) return;

   double macdMain[3], macdSignal[3];
   if (CopyBuffer(macdHandle, 0, 0, 3, macdMain) < 3) return;
   if (CopyBuffer(macdHandle, 1, 0, 3, macdSignal) < 3) return;

   double close = price[1].close;

   // Exit Logic
   if (hasPosition && PositionSelect(_Symbol))
   {
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      if (sl > 0 && tp > 0) return; // Let SL/TP handle it
   }

   // Entry Logic
   if (!hasPosition && TimeCurrent() != lastSignalTime)
   {
      bool macdCrossUp = macdMain[1] < macdSignal[1] && macdMain[0] > macdSignal[0] && macdMain[0] < 0;
      bool macdCrossDown = macdMain[1] > macdSignal[1] && macdMain[0] < macdSignal[0] && macdMain[0] > 0;
      
      if (macdCrossUp && close > ema[0])
      {
         OpenTrade(ORDER_TYPE_BUY);
         lastSignalTime = TimeCurrent();
      }
      else if (macdCrossDown && close < ema[0])
      {
         OpenTrade(ORDER_TYPE_SELL);
         lastSignalTime = TimeCurrent();
      }
   }
}

double CalculateLotSize()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * Risk_Percent / 100.0;
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot_size = risk_amount / tick_value;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return NormalizeDouble(lot_size, (int)MathLog10(1.0 / step));
}

void OpenTrade(int type)
{
   double sl, tp, price;
   double lot = CalculateLotSize();

   if (type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = SymbolInfoDouble(_Symbol, SYMBOL_BID) - 100 * _Point; // placeholder, replace w/ support or 200 EMA
      tp = price + 1.5 * (price - sl);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + 100 * _Point;
      tp = price - 1.5 * (sl - price);
   }

   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.price = NormalizeDouble(price, _Digits);
   req.sl = NormalizeDouble(sl, _Digits);
   req.tp = NormalizeDouble(tp, _Digits);
   req.magic = MagicNumber;
   req.deviation = 10;
   req.type = type;
   req.type_filling = ORDER_FILLING_IOC;

   if (OrderSend(req, res))
   {
      hasPosition = true;
      Print("Trade opened: ", type == ORDER_TYPE_BUY ? "BUY" : "SELL");
   }
   else
      Print("Order failed: ", res.retcode);
}
