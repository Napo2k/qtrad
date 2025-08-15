//+------------------------------------------------------------------+
//|                                              EMA BREAKOUT SYSTEM|
//|                                        Created by: DJ Napo       |
//|                                        Magic Number: 07230910    |
//+------------------------------------------------------------------+
#property strict

//--- input parameters
input int    EMA_Period            = 50;          // EMA Period
input double PendingOffsetPips     = 5;           // Offset in pips for pending orders
input double SL_Trailing_Pips      = 10;          // Trailing stop offset in pips
input double StopToBreakevenPips   = 15;          // Move SL to BE after this profit (pips)
input bool   UseTrailingStop       = true;        // Enable trailing stop
input bool   UseBreakeven          = true;        // Enable break-even
input double LotSize               = 0.1;         // Default fixed lot size
input bool   UseRiskPercent        = false;       // Use % balance for risk
input double RiskPercent           = 1.0;         // Risk % per trade if enabled
input int    MaxSimultaneousTrades = 3;           // Max number of simultaneous trades
input int    Slippage              = 3;           // Max slippage
input int    MagicNumber           = 07230910;    // EA Magic Number
input ENUM_TIMEFRAMES Timeframe   = PERIOD_CURRENT; // EMA calculation timeframe

//--- global variables
datetime lastTradeTime = 0;
int handleEMA;

//+------------------------------------------------------------------+
//| Calculate lot size based on risk %                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPips)
{
   if(!UseRiskPercent)
      return LotSize;

   double riskAmount = AccountBalance() * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   double lot = NormalizeDouble((riskAmount / (stopLossPips * (tickValue / tickSize))) / contractSize, 2);
   return MathMax(lot, 0.01); // Prevent 0.00 lot
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   handleEMA = iMA(_Symbol, Timeframe, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(handleEMA == INVALID_HANDLE)
   {
      Print("Failed to create EMA handle");
      return(INIT_FAILED);
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMA != INVALID_HANDLE)
      IndicatorRelease(handleEMA);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(TimeCurrent() == lastTradeTime)
      return;

   if(PositionsTotalByMagic(MagicNumber) >= MaxSimultaneousTrades)
      return;

   if(!IsNewBar())
      return;

   double ema[2];
   if(CopyBuffer(handleEMA, 0, 0, 2, ema) < 2)
      return;

   double high0 = iHigh(_Symbol, Timeframe, 0);
   double low0  = iLow(_Symbol, Timeframe, 0);
   double close0= iClose(_Symbol, Timeframe, 0);
   double open0 = iOpen(_Symbol, Timeframe, 0);

   double offset = PendingOffsetPips * _Point;
   double sl_offset = SL_Trailing_Pips * _Point;

   CancelPendingOrders();

   //--- Buy Setup
   if(close0 > ema[0] && open0 < ema[0])
   {
      double entry = high0 + offset;
      double sl = low0;
      double lot = CalculateLotSize((entry - sl) / _Point);

      PlacePendingOrder(ORDER_TYPE_BUY_STOP, entry, sl, lot, "Buy Breakout");
   }

   //--- Sell Setup
   if(close0 < ema[0] && open0 > ema[0])
   {
      double entry = low0 - offset;
      double sl = high0;
      double lot = CalculateLotSize((sl - entry) / _Point);

      PlacePendingOrder(ORDER_TYPE_SELL_STOP, entry, sl, lot, "Sell Breakout");
   }

   lastTradeTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Cancel all EA-managed pending orders                             |
//+------------------------------------------------------------------+
void CancelPendingOrders()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(OrderGetTicket(i) && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
      {
         if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP ||
            OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
         {
            ulong ticket = OrderGetTicket(i);
            if(!OrderDelete(ticket))
               Print("Failed to delete pending order: ", ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Place a pending order                                            |
//+------------------------------------------------------------------+
void PlacePendingOrder(ENUM_ORDER_TYPE type, double price, double sl, double lot, string comment)
{
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_PENDING;
   request.symbol   = _Symbol;
   request.volume   = lot;
   request.type     = type;
   request.price    = NormalizeDouble(price, _Digits);
   request.sl       = NormalizeDouble(sl, _Digits);
   request.tp       = 0.0;
   request.magic    = MagicNumber;
   request.comment  = comment;
   request.deviation= Slippage;

   if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE)
      Print("OrderSend error: ", result.retcode);
}

//+------------------------------------------------------------------+
//| Check if new candle formed                                       |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, Timeframe, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Count positions by magic number                                  |
//+------------------------------------------------------------------+
int PositionsTotalByMagic(int magic)
{
   int count = 0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == magic)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Expert OnTrade function - for managing trailing stop & BE        |
//+------------------------------------------------------------------+
void OnTrade()
{
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double currentPrice = SymbolInfoDouble(_Symbol, POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);
      double profitPips = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                          ? (currentPrice - openPrice) / _Point
                          : (openPrice - currentPrice) / _Point;

      //--- Move SL to BE
      if(UseBreakeven && profitPips > StopToBreakevenPips)
      {
         double bePrice = openPrice;
         ModifySL(ticket, bePrice);
      }

      //--- Trailing Stop
      if(UseTrailingStop)
      {
         double trailingSL;
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            trailingSL = iLow(_Symbol, Timeframe, 1) - SL_Trailing_Pips * _Point;
         else
            trailingSL = iHigh(_Symbol, Timeframe, 1) + SL_Trailing_Pips * _Point;

         trailingSL = NormalizeDouble(trailingSL, _Digits);

         if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && trailingSL > sl) ||
            (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && trailingSL < sl))
         {
            ModifySL(ticket, trailingSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify Stop Loss                                                 |
//+------------------------------------------------------------------+
void ModifySL(ulong ticket, double newSL)
{
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   if(!PositionSelectByTicket(ticket))
      return;

   request.action   = TRADE_ACTION_SLTP;
   request.symbol   = _Symbol;
   request.position = ticket;
   request.sl       = newSL;
   request.tp       = PositionGetDouble(POSITION_TP);
   request.magic    = MagicNumber;

   if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE)
      Print("SL modify failed: ", result.retcode);
}
//+------------------------------------------------------------------+
