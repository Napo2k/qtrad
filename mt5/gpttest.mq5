//+------------------------------------------------------------------+
//|                                                   MA_ATR_EA.mq5 |
//+------------------------------------------------------------------+
#property strict

input int FastMAPeriod = 20;
input int SlowMAPeriod = 50;
input int ATRPeriod    = 14;
input double ATRMultiplierSL = 1.5;
input double ATRMultiplierTP = 2.0;
input double LotSize    = 0.1;
input int Slippage      = 5;
input ulong MagicNumber = 123456;

int fastMAHandle, slowMAHandle, atrHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   fastMAHandle = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowMAHandle = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle    = iATR(_Symbol, _Period, ATRPeriod);

   if (fastMAHandle == INVALID_HANDLE || slowMAHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastTime = 0;
   if (lastTime == iTime(_Symbol, _Period, 0))
      return;
   lastTime = iTime(_Symbol, _Period, 0);

   double maFast[2], maSlow[2], atr[1];
   if (CopyBuffer(fastMAHandle, 0, 0, 2, maFast) < 0 ||
       CopyBuffer(slowMAHandle, 0, 0, 2, maSlow) < 0 ||
       CopyBuffer(atrHandle, 0, 0, 1, atr) < 0)
   {
      Print("Failed to copy indicator data");
      return;
   }

   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
   {
      Print("Failed to get market tick");
      return;
   }

   if (PositionSelect(_Symbol)) return; // Skip if there's an open position

   // BUY
   if (maFast[1] < maSlow[1] && maFast[0] > maSlow[0])
   {
      double sl = NormalizeDouble(tick.bid - atr[0] * ATRMultiplierSL, _Digits);
      double tp = NormalizeDouble(tick.bid + atr[0] * ATRMultiplierTP, _Digits);
      tradeOrder(ORDER_TYPE_BUY, LotSize, _Symbol, tick.bid, Slippage, sl, tp);
   }

   // SELL
   else if (maFast[1] > maSlow[1] && maFast[0] < maSlow[0])
   {
      double sl = NormalizeDouble(tick.ask + atr[0] * ATRMultiplierSL, _Digits);
      double tp = NormalizeDouble(tick.ask - atr[0] * ATRMultiplierTP, _Digits);
      tradeOrder(ORDER_TYPE_SELL, LotSize, _Symbol, tick.ask, Slippage, sl, tp);
   }
}


//+------------------------------------------------------------------+
//| Order execution function                                         |
//+------------------------------------------------------------------+
void tradeOrder(ENUM_ORDER_TYPE type, double lots, string symbol, double price, int slippage, double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = symbol;
   request.volume   = lots;
   request.price    = price;
   request.sl       = sl;
   request.tp       = tp;
   request.magic    = MagicNumber;
   request.type     = type;
   request.deviation = slippage;
   request.type_filling = ORDER_FILLING_IOC;

   if (!OrderSend(request, result))
      Print("OrderSend failed: ", result.retcode);
}
