//+------------------------------------------------------------------+
//|           Two MA Crossover EA - Multi-trade + Trailing + Risk    |
//+------------------------------------------------------------------+
#property strict

//--- Inputs
input ENUM_MA_METHOD   InpFastMAType   = MODE_EMA;
input int              InpFastMAPeriod = 10;
input ENUM_MA_METHOD   InpSlowMAType   = MODE_SMA;
input int              InpSlowMAPeriod = 30;
input ENUM_TIMEFRAMES  InpTimeframe    = PERIOD_CURRENT;

input double           InpRiskPercent  = 1.0;     // Risk % per trade
input double           InpStopLoss     = 100;     // Stop Loss in points
input double           InpTakeProfit   = 100;     // Take Profit in points
input int              InpSlippage     = 5;       // Slippage
input ulong            InpMagicNumber  = 999999;
input double           InpTrailingStop = 50;      // Trailing Stop in points (0=off)

//--- Globals
datetime last_bar_time = 0;
int fastMAHandle, slowMAHandle;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   fastMAHandle = iMA(_Symbol, InpTimeframe, InpFastMAPeriod, 0, InpFastMAType, PRICE_CLOSE);
   slowMAHandle = iMA(_Symbol, InpTimeframe, InpSlowMAPeriod, 0, InpSlowMAType, PRICE_CLOSE);

   if (fastMAHandle == INVALID_HANDLE || slowMAHandle == INVALID_HANDLE)
   {
      Print("Failed to create MA handles. Error: ", GetLastError());
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (fastMAHandle != INVALID_HANDLE) IndicatorRelease(fastMAHandle);
   if (slowMAHandle != INVALID_HANDLE) IndicatorRelease(slowMAHandle);
}

//+------------------------------------------------------------------+
//| Tick                                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Trailing stop logic
   if (InpTrailingStop > 0)
      ManageTrailingStops();

   // Run only on new candle
   datetime times[2];
   if (CopyTime(_Symbol, InpTimeframe, 0, 2, times) != 2) return;
   if (times[0] == last_bar_time) return;
   last_bar_time = times[0];

   double fastMA[2], slowMA[2];
   if (CopyBuffer(fastMAHandle, 0, 0, 2, fastMA) != 2 ||
       CopyBuffer(slowMAHandle, 0, 0, 2, slowMA) != 2)
      return;

   bool crossedUp   = (fastMA[1] < slowMA[1] && fastMA[0] > slowMA[0]);
   bool crossedDown = (fastMA[1] > slowMA[1] && fastMA[0] < slowMA[0]);

   if (crossedUp)   OpenTrade(ORDER_TYPE_BUY);
   if (crossedDown) OpenTrade(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Calculate lot size by risk                                       |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double sl_points = InpStopLoss;
   double oneLotSL = (sl_points / tickSize) * tickValue;

   double lotSize = NormalizeDouble(riskAmount / oneLotSL, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathMax(lotSize, minLot);
   lotSize = MathMin(lotSize, maxLot);
   lotSize = MathFloor(lotSize / step) * step;

   return lotSize;
}

//+------------------------------------------------------------------+
//| Open a trade                                                     |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
{
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request); ZeroMemory(result);

   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl = (InpStopLoss > 0)
               ? NormalizeDouble(price + (type == ORDER_TYPE_BUY ? -1 : 1) * InpStopLoss * _Point, _Digits)
               : 0;
   double tp = (InpTakeProfit > 0)
               ? NormalizeDouble(price + (type == ORDER_TYPE_BUY ? 1 : -1) * InpTakeProfit * _Point, _Digits)
               : 0;

   request.action   = TRADE_ACTION_DEAL;
   request.type     = type;
   request.symbol   = _Symbol;
   request.price    = price;
   request.sl       = sl;
   request.tp       = tp;
   request.volume   = CalculateLotSize();
   request.magic    = InpMagicNumber;
   request.deviation= InpSlippage;
   request.type_filling = ORDER_FILLING_IOC;

   if (!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE)
      Print("OrderSend failed. Code=", result.retcode, " Msg=", result.comment);
   else
      Print("Order opened: ", EnumToString(type), " @ ", price, " | SL=", sl, " TP=", tp);
}

//+------------------------------------------------------------------+
//| Manage Trailing Stops                                            |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!PositionGetTicket(i)) continue;

      if (PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if (symbol != _Symbol) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double price = (type == POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(symbol, SYMBOL_BID)
                     : SymbolInfoDouble(symbol, SYMBOL_ASK);
      double stopLoss = PositionGetDouble(POSITION_SL);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double trailDist = InpTrailingStop * _Point;

      double newSL = (type == POSITION_TYPE_BUY)
                     ? price - trailDist
                     : price + trailDist;

      if ((type == POSITION_TYPE_BUY && (stopLoss == 0 || newSL > stopLoss)) ||
          (type == POSITION_TYPE_SELL && (stopLoss == 0 || newSL < stopLoss)))
      {
         MqlTradeRequest request;
         MqlTradeResult  result;
         ZeroMemory(request); ZeroMemory(result);

         request.action     = TRADE_ACTION_SLTP;
         request.symbol     = symbol;
         request.position   = PositionGetInteger(POSITION_TICKET);
         request.sl         = NormalizeDouble(newSL, _Digits);
         request.tp         = PositionGetDouble(POSITION_TP);
         request.magic      = InpMagicNumber;

         if (!OrderSend(request, result))
            Print("Trailing SL update failed. ", result.retcode);
      }
   }
}
