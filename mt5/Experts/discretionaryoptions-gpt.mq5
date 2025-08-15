//+------------------------------------------------------------------+
//|   Discretionary Options Strategy EA (Converted to MT5)          |
//|   Auto-trades support/resistance zones with confirmation        |
//+------------------------------------------------------------------+
#property strict

input double   Risk_Percent       = 5.0;     // Risk per trade (%)
input int      ATR_Period         = 14;      // ATR Period
input int      Swing_Bars         = 8;       // Number of bars for swing high/low detection
input double   Reward_Multiplier  = 2.5;     // Take profit multiplier (2.5x risk)
input int      Max_Candle_Hold    = 10;      // Exit after this many candles if TP not hit
input int      Slippage_Points    = 10;      // Slippage allowed
input ENUM_TIMEFRAMES Timeframe  = PERIOD_M15;

double atr;

int ticket = -1;
datetime last_trade_time = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   static datetime last_bar_time = 0;
   MqlRates price[];
   if(CopyRates(_Symbol, Timeframe, 0, Swing_Bars+5, price) <= 0) return;

   ArraySetAsSeries(price,true);
   if(price[0].time == last_bar_time) return;
   last_bar_time = price[0].time;

   if(PositionSelect(_Symbol)) return; // One trade at a time

   static int atr_handle = iATR(_Symbol, Timeframe, ATR_Period);
   double atr_values[];
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_values) <= 0) return;
   atr = atr_values[0];

   double recentHigh = price[1].high;
   double recentLow = price[1].low;

   for(int i = 2; i <= Swing_Bars; i++)
     {
      if(price[i].high > recentHigh) recentHigh = price[i].high;
      if(price[i].low < recentLow) recentLow = price[i].low;
     }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double lotSize = CalculateLotSize(Risk_Percent, atr);

   // Bullish Setup (Support touch + bullish close)
   if(bid <= recentLow + atr * 0.2 && price[1].close > price[2].close)
     {
      double sl = bid - atr;
      double tp = bid + (atr * Reward_Multiplier);
      OpenTrade(ORDER_TYPE_BUY, lotSize, sl, tp);
     }

   // Bearish Setup (Resistance touch + bearish close)
   if(ask >= recentHigh - atr * 0.2 && price[1].close < price[2].close)
     {
      double sl = ask + atr;
      double tp = ask - (atr * Reward_Multiplier);
      OpenTrade(ORDER_TYPE_SELL, lotSize, sl, tp);
     }
  }
//+------------------------------------------------------------------+
double CalculateLotSize(double risk_percent, double stop_loss_pips)
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * (risk_percent / 100.0);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double price_per_point = tick_value / tick_size;

   double lots = (risk_amount / (stop_loss_pips * price_per_point));
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathMax(min_lot, MathMin(max_lot, lots));
   lots = MathFloor(lots / lot_step) * lot_step;
   return NormalizeDouble(lots, 2);
  }
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, double lots, double sl, double tp)
  {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.symbol = _Symbol;
   request.volume = lots;
   request.type = type;
   request.action = TRADE_ACTION_DEAL;
   request.deviation = Slippage_Points;
   request.magic = 20250731;
   request.sl = sl;
   request.tp = tp;
   request.type_filling = ORDER_FILLING_FOK;
   request.price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                                              SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(!OrderSend(request, result))
     {
      Print("Trade failed: ", result.retcode);
     }
   else
     {
      Print("Trade opened: ", EnumToString(type), " at ", request.price, " | SL: ", sl, " | TP: ", tp);
     }
  }
//+------------------------------------------------------------------+
