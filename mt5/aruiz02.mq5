//+------------------------------------------------------------------+
//|                   Trend Pullback with Stochastic EA               |
//+------------------------------------------------------------------+
#property strict

input int EMA_Trend_Period = 200;
input int EMA_Pullback_Period = 20;
input int EMA_Exit_Period = 20;
input int Stoch_K = 5;
input int Stoch_D = 3;
input int Stoch_Slowing = 3;
input double Risk_Percent = 1.0;
input double Partial_Exit_RR = 1.5;
input ulong MagicNumber = 789012;

int emaTrendHandle, emaPullbackHandle, emaExitHandle, stochHandle;
bool partialExitDone = false;

int OnInit()
{
   emaTrendHandle = iMA(_Symbol, _Period, EMA_Trend_Period, 0, MODE_EMA, PRICE_CLOSE);
   emaPullbackHandle = iMA(_Symbol, _Period, EMA_Pullback_Period, 0, MODE_EMA, PRICE_CLOSE);
   emaExitHandle = iMA(_Symbol, _Period, EMA_Exit_Period, 0, MODE_EMA, PRICE_CLOSE);
   stochHandle = iStochastic(_Symbol, _Period, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);

   if (emaTrendHandle == INVALID_HANDLE || emaPullbackHandle == INVALID_HANDLE || emaExitHandle == INVALID_HANDLE || stochHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnTick()
{
   static datetime lastBarTime = 0;
   MqlRates price[3];
   if (CopyRates(_Symbol, _Period, 0, 3, price) < 3) return;
   if (price[1].time == lastBarTime) return;
   lastBarTime = price[1].time;

   double emaTrend[1], emaPullback[1], emaExit[1], k[1], d[1];
   if (CopyBuffer(emaTrendHandle, 0, 1, 1, emaTrend) < 1 ||
       CopyBuffer(emaPullbackHandle, 0, 1, 1, emaPullback) < 1 ||
       CopyBuffer(emaExitHandle, 0, 1, 1, emaExit) < 1 ||
       CopyBuffer(stochHandle, 0, 1, 1, k) < 1 ||
       CopyBuffer(stochHandle, 1, 1, 1, d) < 1) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- Manage open positions for exit conditions
   ManageOpenPositions(emaExit[0]);

   if (PositionSelect(_Symbol)) return;

   //--- Trend direction
   bool uptrend = price[1].close > emaTrend[0];
   bool downtrend = price[1].close < emaTrend[0];

   //--- Pullback conditions
   bool pullbackUp = uptrend && price[1].close < emaPullback[0];
   bool pullbackDown = downtrend && price[1].close > emaPullback[0];

   //--- Stochastic confirmation
   bool confirmBuy = pullbackUp && k[0] < 20 && d[0] < 20;
   bool confirmSell = pullbackDown && k[0] > 80 && d[0] > 80;

   //--- Execute Buy
   if (confirmBuy)
   {
      double sl = price[1].low;
      double tp = ask + 3 * (ask - sl);
      double lot = CalculateLotSize(ask - sl);
      partialExitDone = false;
      OpenTrade(ORDER_TYPE_BUY, lot, ask, sl, tp);
   }
   //--- Execute Sell
   if (confirmSell)
   {
      double sl = price[1].high;
      double tp = bid - 3 * (sl - bid);
      double lot = CalculateLotSize(sl - bid);
      partialExitDone = false;
      OpenTrade(ORDER_TYPE_SELL, lot, bid, sl, tp);
   }
}

double CalculateLotSize(double sl_distance)
{
   double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * Risk_Percent / 100.0;
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot_size = risk_amount / (sl_distance / SymbolInfoDouble(_Symbol, SYMBOL_POINT) * tick_value);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return NormalizeDouble(lot_size, (int)MathLog10(1.0 / step));
}

void OpenTrade(int orderType, double lot, double price, double sl, double tp)
{
   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = orderType;
   req.price = price;
   req.sl = NormalizeDouble(sl, _Digits);
   req.tp = NormalizeDouble(tp, _Digits);
   req.magic = MagicNumber;
   req.deviation = 10;
   req.type_filling = ORDER_FILLING_IOC;

   if (!OrderSend(req, res))
      Print("OrderSend failed: ", res.retcode);
   else
      Print((orderType == ORDER_TYPE_BUY ? "Buy" : "Sell"), " order placed. Order #: ", res.order);
}

void ManageOpenPositions(double emaExit)
{
   if (!PositionSelect(_Symbol)) return;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = SymbolInfoDouble(_Symbol, PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);
   double sl = PositionGetDouble(POSITION_SL);
   double lot = PositionGetDouble(POSITION_VOLUME);

   double rr = MathAbs(currentPrice - openPrice) / MathAbs(openPrice - sl);

   //--- Partial Exit
   if (!partialExitDone && rr >= Partial_Exit_RR)
   {
      double halfLot = NormalizeDouble(lot / 2.0, 2);
      if (halfLot >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      {
         MqlTradeRequest req;
         MqlTradeResult res;
         ZeroMemory(req);
         ZeroMemory(res);
         req.action = TRADE_ACTION_DEAL;
         req.symbol = _Symbol;
         req.volume = halfLot;
         req.position = PositionGetInteger(POSITION_IDENTIFIER);
         req.magic = MagicNumber;
         req.deviation = 10;
         req.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
         req.price = currentPrice;
         req.type_filling = ORDER_FILLING_IOC;
         if (OrderSend(req, res))
         {
            Print("Partial exit executed");
            partialExitDone = true;
         }
      }
   }

   //--- Full Exit on EMA break
   if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && currentPrice < emaExit) ||
       (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && currentPrice > emaExit))
   {
      MqlTradeRequest req;
      MqlTradeResult res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action = TRADE_ACTION_DEAL;
      req.symbol = _Symbol;
      req.volume = lot;
      req.position = PositionGetInteger(POSITION_IDENTIFIER);
      req.magic = MagicNumber;
      req.deviation = 10;
      req.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      req.price = currentPrice;
      req.type_filling = ORDER_FILLING_IOC;
      if (OrderSend(req, res))
         Print("Full exit on EMA break executed");
   }
}
