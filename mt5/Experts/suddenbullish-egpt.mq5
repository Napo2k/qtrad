//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property version   "1.01"
#property strict

// Input parameters for customization
input double       LotSize          = 0.1;         // Lot size
input double       StopLossPoints   = 300;         // Stop-loss in points
input double       TakeProfitPoints = 600;         // Take-profit in points
input ENUM_TIMEFRAMES Timeframe     = PERIOD_M30;  // Timeframe (e.g., 30 minutes)
input int          ShortEMAPeriod   = 70;          // Short EMA period
input int          LongEMAPeriod    = 160;         // Long EMA period

double EMA_Short_prev, EMA_Long_prev;            // EMA values (previous candle)
//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Print initialization message
   Print("Expert Advisor initialized successfully.");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("Expert Advisor deinitialized.");
  }

//+------------------------------------------------------------------+
//| Expert logic: OnTick                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Check if the symbol has a position open
   bool hasPosition = PositionSelect(Symbol());

   // Get EMA values for the current and previous candle
   double EMA_Short    = iMA(Symbol(), Timeframe, ShortEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
   double EMA_Long     = iMA(Symbol(), Timeframe, LongEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);

   EMA_Short_prev      = iMA(Symbol(), Timeframe, ShortEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
   EMA_Long_prev       = iMA(Symbol(), Timeframe, LongEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);

   // Check for buy signal (short EMA crosses above long EMA)
   if (!hasPosition && EMA_Short_prev <= EMA_Long_prev && EMA_Short > EMA_Long)
     {
      // Calculate stop-loss and take-profit levels
      double stopLossPrice = NormalizeDouble(Bid - StopLossPoints * _Point, _Digits);
      double takeProfitPrice = NormalizeDouble(Bid + TakeProfitPoints * _Point, _Digits);

      // Send buy order
      if (OrderSend(Symbol(), OP_BUY, LotSize, NormalizeDouble(Ask, _Digits), 3, stopLossPrice, takeProfitPrice, "Bullish Breakout Buy", 0, 0, clrBlue) > 0)
         Print("Buy order placed successfully.");
      else
         Print("Failed to place buy order. Error: ", GetLastError());
     }

   // Check for exit signal (short EMA crosses below long EMA)
   if (hasPosition && EMA_Short_prev >= EMA_Long_prev && EMA_Short < EMA_Long)
     {
      // Close position
      ulong ticket = PositionGetInteger(POSITION_TICKET); // Get the ticket of the open position
      if (OrderClose(ticket, PositionGetDouble(POSITION_VOLUME), NormalizeDouble(Bid, _Digits), 3, clrRed))
         Print("Position closed successfully.");
      else
         Print("Failed to close position. Error: ", GetLastError());
     }
  }