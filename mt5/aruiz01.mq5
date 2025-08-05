//+------------------------------------------------------------------+
//|                                          MultiTF_BuySellStrategy.mq5 |
//|              Strategy: D1 Decel, H1 Confluence, M5 Breakout (Buy & Sell) |
//+------------------------------------------------------------------+
#property strict

input int ATR_Period = 14;
input double SL_ATR_Multiplier = 1.5;
input double TP_ATR_Multiplier = 2.0;
input double Risk_Percent = 5.0;
input ulong MagicNumber = 100001;

// Indicator handles
int ema50_H1, ema50_M5, atr_M5;

int OnInit()
{
   ema50_H1 = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   ema50_M5 = iMA(_Symbol, PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
   atr_M5   = iATR(_Symbol, PERIOD_M5, ATR_Period);

   if (ema50_H1 == INVALID_HANDLE || ema50_M5 == INVALID_HANDLE || atr_M5 == INVALID_HANDLE)
   {
      Print("Indicator handle creation failed");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnTick()
{
   static datetime lastCheck = 0;
   if (TimeCurrent() - lastCheck < 60) return;
   lastCheck = TimeCurrent();

   if (PositionSelect(_Symbol)) return;

   double atr[1];
   if (CopyBuffer(atr_M5, 0, 0, 1, atr) <= 0) return;

   double sl_dist = atr[0] * SL_ATR_Multiplier;
   double tp_dist = atr[0] * TP_ATR_Multiplier;
   double lot = CalculateLotSize(sl_dist);

   // Debug prints for condition checks
   PrintFormat("CheckD1 Buy: %s, CheckH1 Buy: %s, CheckM5 Buy: %s",
      BoolToString(CheckD1Deceleration(true)),
      BoolToString(CheckH1Confluence(true)),
      BoolToString(CheckM5Breakout(true))
   );
   PrintFormat("CheckD1 Sell: %s, CheckH1 Sell: %s, CheckM5 Sell: %s",
      BoolToString(CheckD1Deceleration(false)),
      BoolToString(CheckH1Confluence(false)),
      BoolToString(CheckM5Breakout(false))
   );

   if (CheckD1Deceleration(true) && CheckH1Confluence(true) && CheckM5Breakout(true))
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = NormalizeDouble(price - sl_dist, _Digits);
      double tp = NormalizeDouble(price + tp_dist, _Digits);
      OpenTrade(ORDER_TYPE_BUY, lot, price, sl, tp);
   }
   else if (CheckD1Deceleration(false) && CheckH1Confluence(false) && CheckM5Breakout(false))
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = NormalizeDouble(price + sl_dist, _Digits);
      double tp = NormalizeDouble(price - tp_dist, _Digits);
      OpenTrade(ORDER_TYPE_SELL, lot, price, sl, tp);
   }
}

bool CheckD1Deceleration(bool isBuy)
{
   MqlRates d1[4];
   if (CopyRates(_Symbol, PERIOD_D1, 0, 4, d1) < 4) return false;
   double r1 = d1[1].high - d1[1].low;
   double r2 = d1[2].high - d1[2].low;
   double r3 = d1[3].high - d1[3].low;
   return (r1 < r2 && r2 < r3);
}

bool CheckH1Confluence(bool isBuy)
{
   MqlRates h1[9];
   if (CopyRates(_Symbol, PERIOD_H1, 0, 9, h1) < 9) return false;

   double high = h1[1].high;
   double low = h1[1].low;
   for (int i = 2; i <= 8; i++)
   {
      if (h1[i].high > high) high = h1[i].high;
      if (h1[i].low < low) low = h1[i].low;
   }
   double fib_0618 = isBuy ? high - (high - low) * 0.618 : low + (high - low) * 0.618;

   double ema[1];
   if (CopyBuffer(ema50_H1, 0, 0, 1, ema) <= 0) return false;

   double price = SymbolInfoDouble(_Symbol, isBuy ? SYMBOL_BID : SYMBOL_ASK);
   
   double buffer = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;  // relaxed tolerance
   
   return (MathAbs(price - ema[0]) < buffer && MathAbs(price - fib_0618) < buffer);
}

bool CheckM5Breakout(bool isBuy)
{
   MqlRates m5[2];
   if (CopyRates(_Symbol, PERIOD_M5, 0, 2, m5) < 2) return false;
   double ema[1];
   if (CopyBuffer(ema50_M5, 0, 0, 1, ema) <= 0) return false;

   if (isBuy)
      return (m5[0].close > ema[0] && m5[0].close > m5[0].open);
   else
      return (m5[0].close < ema[0] && m5[0].close < m5[0].open);
}

double CalculateLotSize(double sl_distance)
{
   double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * Risk_Percent / 100.0;
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot_size = risk_amount / (sl_distance / SymbolInfoDouble(_Symbol, SYMBOL_POINT) * tick_value);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return NormalizeDouble(lot_size, (int)MathLog10(1.0 / step));
}

void OpenTrade(ENUM_ORDER_TYPE type, double lot, double price, double sl, double tp)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type   = type;
   req.price  = price;
   req.sl     = sl;
   req.tp     = tp;
   req.magic  = MagicNumber;
   req.deviation = 10;
   req.type_filling = ORDER_FILLING_IOC;

   if (!OrderSend(req, res))
      Print((type == ORDER_TYPE_BUY ? "Buy" : "Sell"), " failed: ", res.retcode);
   else
      Print((type == ORDER_TYPE_BUY ? "Buy" : "Sell"), " order placed: ", res.order);
}

// Helper to print bool as string
string BoolToString(bool b)
{
   return b ? "true" : "false";
}
