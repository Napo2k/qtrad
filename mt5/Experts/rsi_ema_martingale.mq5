//+------------------------------------------------------------------+
//|                    Custom Martingale EA for MT5                 |
//|         Features: RSI+EMA entry, dynamic martingale, TP, safety |
//+------------------------------------------------------------------+
#property strict

//--- Input Parameters
input double   InpInitialLot        = 0.1;       // Initial lot size
input double   InpLotMultiplier     = 2.0;       // Martingale lot multiplier
input double   InpInitialDistance   = 100;       // Initial distance in points
input double   InpDistanceMultiplier= 1.5;       // Distance multiplier
input int      InpMaxTrades         = 10;        // Max trades in a martingale sequence

// Indicator Settings
input int      InpRSIPeriod         = 14;        // RSI period
input double   InpRSIOverbought     = 70.0;      // RSI overbought threshold
input double   InpRSIOversold       = 30.0;      // RSI oversold threshold
input ENUM_TIMEFRAMES InpRSITimeframe = PERIOD_M5;

input int      InpEMAPeriod         = 50;        // EMA period
input ENUM_TIMEFRAMES InpEMATimeframe = PERIOD_M5;

// Take Profit Logic
input double   InpTakeProfitPips    = 50;        // TP in pips from average price
input double   InpPartialClosePct   = 0.5;       // % to close on partial TP (0.5 = 50%)

// Capital Protection
input double   InpMaxDrawdownPct    = 30;        // Max drawdown % to stop EA
input bool     InpEnableHedging     = true;      // Enable hedge after N trades
input int      InpHedgeTriggerCount = 5;         // Trigger hedging after this many trades

// Global Variables
double avgPrice = 0.0;
int tradesCount = 0;
double accountEquityAtStart;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   accountEquityAtStart = AccountInfoDouble(ACCOUNT_EQUITY);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Calculate EMA                                                    |
//+------------------------------------------------------------------+
double GetEMA()
  {
   return iMA(_Symbol, InpEMATimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
  }

//+------------------------------------------------------------------+
//| Calculate RSI                                                    |
//+------------------------------------------------------------------+
double GetRSI()
  {
   return iRSI(_Symbol, InpRSITimeframe, InpRSIPeriod, PRICE_CLOSE, 0);
  }

//+------------------------------------------------------------------+
//| Check capital protection                                         |
//+------------------------------------------------------------------+
bool CheckDrawdownExceeded()
  {
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = 100.0 * (accountEquityAtStart - currentEquity) / accountEquityAtStart;
   return drawdown > InpMaxDrawdownPct;
  }

//+------------------------------------------------------------------+
//| Count current Martingale trades                                  |
//+------------------------------------------------------------------+
int CountMartingaleTrades()
  {
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() == _Symbol && OrderMagicNumber() == 10001) count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Get current average entry price                                  |
//+------------------------------------------------------------------+
double GetAveragePrice()
  {
   double totalLots = 0.0, totalPrice = 0.0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() == _Symbol && OrderMagicNumber() == 10001)
        {
         double lot = OrderLots();
         totalLots += lot;
         totalPrice += lot * OrderOpenPrice();
        }
     }
   return (totalLots > 0) ? totalPrice / totalLots : 0.0;
  }

//+------------------------------------------------------------------+
//| Check if hedge is needed                                        |
//+------------------------------------------------------------------+
bool ShouldHedge()
  {
   return (InpEnableHedging && CountMartingaleTrades() >= InpHedgeTriggerCount);
  }

//+------------------------------------------------------------------+
//| Entry logic                                                      |
//+------------------------------------------------------------------+
void CheckEntry()
  {
   double rsi = GetRSI();
   double ema = GetEMA();
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(CountMartingaleTrades() > 0 || CheckDrawdownExceeded()) return;

   if(rsi < InpRSIOversold && price > ema)
     OpenTrade(ORDER_TYPE_BUY, InpInitialLot);

   if(rsi > InpRSIOverbought && price < ema)
     OpenTrade(ORDER_TYPE_SELL, InpInitialLot);
  }

//+------------------------------------------------------------------+
//| Open trade with given lot                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, double lot)
  {
   double sl = 0, tp = 0;
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.type     = type;
   request.volume   = lot;
   request.price    = price;
   request.magic    = 10001;
   request.sl       = 0;
   request.tp       = 0;
   request.deviation= 10;
   request.type_filling = ORDER_FILLING_IOC;

   OrderSend(request, result);
  }

//+------------------------------------------------------------------+
//| Martingale progression                                           |
//+------------------------------------------------------------------+
void ManageMartingale()
  {
   int count = CountMartingaleTrades();
   if(count == 0 || count >= InpMaxTrades || CheckDrawdownExceeded()) return;

   double lastEntryPrice = GetAveragePrice();
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double distance = InpInitialDistance * MathPow(InpDistanceMultiplier, count - 1) * _Point;

   ENUM_ORDER_TYPE type;
   bool shouldTrade = false;

   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) &&
         OrderSymbol() == _Symbol && OrderMagicNumber() == 10001)
        {
         if(OrderType() == ORDER_TYPE_BUY && currentPrice <= lastEntryPrice - distance)
           {
            type = ORDER_TYPE_BUY;
            shouldTrade = true;
           }
         else if(OrderType() == ORDER_TYPE_SELL && currentPrice >= lastEntryPrice + distance)
           {
            type = ORDER_TYPE_SELL;
            shouldTrade = true;
           }
         break;
        }
     }

   if(shouldTrade)
     {
      double lot = InpInitialLot * MathPow(InpLotMultiplier, count);
      OpenTrade(type, lot);
     }
  }

//+------------------------------------------------------------------+
//| Take profit logic                                                |
//+------------------------------------------------------------------+
void ManageTakeProfit()
  {
   int count = CountMartingaleTrades();
   if(count == 0) return;

   double avg = GetAveragePrice();
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tpDistance = InpTakeProfitPips * _Point;

   double totalLots = 0;
   ENUM_ORDER_TYPE type = (price > avg) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != 10001 || OrderSymbol() != _Symbol) continue;

      totalLots += OrderLots();
     }

   // Full or partial closure
   bool tpHit = false;
   if(type == ORDER_TYPE_BUY && price - avg >= tpDistance) tpHit = true;
   if(type == ORDER_TYPE_SELL && avg - price >= tpDistance) tpHit = true;

   if(tpHit)
     {
      double closeLots = totalLots * InpPartialClosePct;

      for(int i=OrdersTotal()-1; i>=0 && closeLots > 0; i--)
        {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderMagicNumber() != 10001 || OrderSymbol() != _Symbol) continue;

         double lot = OrderLots();
         double toClose = MathMin(closeLots, lot);
         ulong ticket = OrderTicket();

         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action   = TRADE_ACTION_DEAL;
         request.symbol   = _Symbol;
         request.position = ticket;
         request.volume   = toClose;
         request.price    = (OrderType() == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         request.type     = (OrderType() == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.deviation= 10;
         request.magic    = 10001;
         request.type_filling = ORDER_FILLING_IOC;

         OrderSend(request, result);

         closeLots -= toClose;
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckEntry();
   ManageMartingale();
   ManageTakeProfit();

   if(ShouldHedge())
     {
      // Simple hedge: open opposite trade with same total lot size
      double hedgeLots = 0;
      ENUM_ORDER_TYPE hedgeType;

      for(int i=OrdersTotal()-1; i>=0; i--)
        {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderMagicNumber() != 10001 || OrderSymbol() != _Symbol) continue;

         hedgeLots += OrderLots();
         hedgeType = (OrderType() == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        }

      if(hedgeLots > 0)
         OpenTrade(hedgeType, hedgeLots);
     }
  }
