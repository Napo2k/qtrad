//+------------------------------------------------------------------+
//|                                               HybridDayTrade.mq5 |
//|                    Strategy: 10-SMA + MACD crossover + Scaling   |
//|                      Author: ChatGPT for user                    |
//+------------------------------------------------------------------+
#property copyright "ChatGPT"
#property link      ""
#property version   "1.00"
#property strict

input int      InpSmaPeriod         = 10;             // SMA Period
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_M5;      // Trading timeframe (M5)
input double   InpFixedLot          = 0.1;            // Fixed lot size (if UseRisk = false)
input double   InpRiskPercent       = 1.0;            // Risk % per trade (if UseRisk = true)
input bool     UseRisk              = false;          // Use % risk position sizing (else fixed lot)
input int      Slippage             = 5;              // Max slippage in points
input int      MagicNumber          = 123456;         // Magic number for EA trades

// Take profit scaling percentages (as decimal, e.g. 0.01 = 1%)
input double   TP1_Percent          = 0.01;           // TP1 at 1%
input double   TP2_Percent          = 0.02;           // TP2 at 2%
input double   TP3_Percent          = 0.03;           // TP3 at 3%

input double   MinDistancePoints    = 10;             // Min distance in points for TP/SL to avoid bad orders

// Trailing runner stop mode (only one mode here - previous day high/low)
input bool     UsePrevDayStop       = true;           // Use previous day high/low as trailing stop for runner portion

// Maximum number of simultaneous trades per direction
input int      MaxTradesPerDirection = 5;

//--- Global variables
double smaBuffer[];
double macdMain[];
double macdSignal[];
double macdHist[];

datetime prevDayTime = 0;
double   prevDayHigh = 0;
double   prevDayLow  = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Set timer for 1 minute to update previous day levels regularly
   EventSetTimer(60);
   Print("Hybrid Day Trade EA initialized.");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| Timer event to update previous day high/low                     |
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdatePreviousDayLevels();
  }

//+------------------------------------------------------------------+
//| Calculate previous day high/low                                  |
//+------------------------------------------------------------------+
void UpdatePreviousDayLevels()
  {
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   datetime todayStart = StringToTime(StringFormat("%d.%02d.%02d 00:00", timeStruct.year, timeStruct.mon, timeStruct.day));

   // If already updated today, skip
   if(prevDayTime == todayStart)
      return;

   // Get previous day start and end times
   datetime prevDayStart = todayStart - 86400;
   datetime prevDayEnd   = todayStart - 1;

   int barsCount = CopyRates(_Symbol, PERIOD_D1, 0, 2, NULL);
   if(barsCount < 2)
     {
      Print("Not enough daily bars to get previous day data.");
      return;
     }

   MqlRates rates[2];
   if(CopyRates(_Symbol, PERIOD_D1, 1, 1, rates) != 1)
     {
      Print("Failed to get previous day rates.");
      return;
     }

   prevDayHigh = rates[0].high;
   prevDayLow  = rates[0].low;
   prevDayTime = todayStart;

   //Print("Prev day High: ", DoubleToString(prevDayHigh, _Digits), " Low: ", DoubleToString(prevDayLow, _Digits));
  }

//+------------------------------------------------------------------+
//| Calculate position size based on risk % or fixed lot            |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPrice)
  {
   if(!UseRisk)
     {
      // Use fixed lot
      return(InpFixedLot);
     }

   // Risk-based sizing (risk percent of account balance)
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0)
     {
      Print("Error getting tick value or size.");
      return(InpFixedLot);
     }

   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * InpRiskPercent / 100.0;

   double stopLossPoints = MathAbs(Ask - stopLossPrice) / _Point;

   if(stopLossPoints <= 0)
      stopLossPoints = MinDistancePoints;

   double lotSize = riskAmount / (stopLossPoints * tickValue / tickSize);

   // Normalize lot size to allowed step
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lotSize = MathMax(lotSize, minLot);
   lotSize = MathMin(lotSize, maxLot);

   int steps = (int)(lotSize / lotStep);
   lotSize = steps * lotStep;

   return (NormalizeDouble(lotSize, 2));
  }

//+------------------------------------------------------------------+
//| Check for MACD crossover: true if histogram crosses above zero  |
//| direction = 1 for bullish crossover, -1 for bearish             |
//+------------------------------------------------------------------+
bool IsMacdCrossover(int shift, int direction)
  {
   // direction 1 = bullish (cross from below zero to above zero)
   // direction -1 = bearish (cross from above zero to below zero)

   if(direction == 1)
     {
      return (macdHist[shift+1] < 0 && macdHist[shift] > 0);
     }
   else if(direction == -1)
     {
      return (macdHist[shift+1] > 0 && macdHist[shift] < 0);
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Check if a new position can be opened (max trades per direction) |
//+------------------------------------------------------------------+
bool CanOpenNewPosition(int direction)
  {
   // direction: 1 = buy, -1 = sell
   int total = 0;
   for(int i=0; i<PositionsTotal(); i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            int posType = (int)PositionGetInteger(POSITION_TYPE);
            if(direction == 1 && posType == POSITION_TYPE_BUY)
               total++;
            else if(direction == -1 && posType == POSITION_TYPE_SELL)
               total++;
           }
        }
     }
   return total < MaxTradesPerDirection;
  }

//+------------------------------------------------------------------+
//| Close part of position by percent                                |
//+------------------------------------------------------------------+
bool ClosePartial(ulong ticket, double percent)
  {
   if(percent <= 0 || percent > 1)
      return false;

   if(!PositionSelectByTicket(ticket))
      return false;

   double volume = PositionGetDouble(POSITION_VOLUME);
   double closeVolume = volume * percent;

   if(closeVolume < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      return false;

   // Normalize to step
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   closeVolume = MathFloor(closeVolume / volStep) * volStep;

   if(closeVolume < volStep)
      return false;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = _Symbol;
   request.volume = closeVolume;
   request.magic = MagicNumber;
   request.deviation = Slippage;

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
     {
      request.type = ORDER_TYPE_SELL;
     }
   else
     {
      request.type = ORDER_TYPE_BUY;
     }

   bool res = OrderSend(request,result);
   if(!res)
     {
      Print("Partial close failed: ",GetLastError());
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Open position helper function                                    |
//+------------------------------------------------------------------+
bool OpenPosition(int direction, double lotSize)
  {
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
     {
      Print("Lot size too small");
      return false;
     }

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.magic = MagicNumber;
   request.deviation = Slippage;

   if(direction == 1)
      request.type = ORDER_TYPE_BUY;
   else if(direction == -1)
      request.type = ORDER_TYPE_SELL;
   else
     {
      Print("Invalid trade direction");
      return false;
     }

   bool res = OrderSend(request,result);
   if(!res)
     {
      Print("OrderSend failed: ", GetLastError());
      return false;
     }
   if(result.retcode != TRADE_RETCODE_DONE)
     {
      Print("Trade not done, retcode: ", result.retcode);
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Manage existing positions: scale out, trailing stop runner      |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   double point = _Point;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      int posType = (int)PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
      double pnlPoints = 0;

      if(posType == POSITION_TYPE_BUY)
         pnlPoints = (currentPrice - openPrice) / point;
      else if(posType == POSITION_TYPE_SELL)
         pnlPoints = (openPrice - currentPrice) / point;

      // Scaling out logic at 1%, 2%, 3% moves

      double priceChangePercent = pnlPoints * point / openPrice;

      // Percent targets (positive decimal)
      double TP1 = TP1_Percent;
      double TP2 = TP2_Percent;
      double TP3 = TP3_Percent;

      // We check if partial closes already done by counting position volume?
      // For simplicity, track via static vars or comments - here we do simple implementation:
      // We'll close 25% once price crosses target levels, if enough volume is present

      double quarterVol = volume * 0.25;

      // Close first 25% at +1%
      if(priceChangePercent >= TP1)
        {
         // Try partial close if volume allows
         ClosePartial(ticket, 0.25);
        }
      // Close second 25% at +2%
      if(priceChangePercent >= TP2)
        {
         ClosePartial(ticket, 0.25);
        }
      // Close third 25% at +3%
      if(priceChangePercent >= TP3)
        {
         ClosePartial(ticket, 0.25);
        }

      // Remaining 25% runner: trailing stop at previous day high/low

      if(UsePrevDayStop)
        {
         double newSL = 0;
         if(posType == POSITION_TYPE_BUY)
            newSL = prevDayLow;
         else if(posType == POSITION_TYPE_SELL)
            newSL = prevDayHigh;

         // Modify stop loss if current SL is worse
         double currentSL = PositionGetDouble(POSITION_SL);

         bool needModify = false;
         if(posType == POSITION_TYPE_BUY && (currentSL < newSL || currentSL == 0))
           {
            needModify = true;
           }
         else if(posType == POSITION_TYPE_SELL && (currentSL > newSL || currentSL == 0))
           {
            needModify = true;
           }

         if(needModify && newSL > 0)
           {
            // Modify position SL
            MqlTradeRequest request;
            MqlTradeResult  result;
            ZeroMemory(request);
            ZeroMemory(result);

            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = _Symbol;
            request.sl = newSL;
            request.tp = PositionGetDouble(POSITION_TP);
            request.magic = MagicNumber;

            if(!OrderSend(request, result))
              {
               Print("Failed to modify SL: ", GetLastError());
              }
            else if(result.retcode != TRADE_RETCODE_DONE)
              {
               Print("Modify SL not done, retcode: ", result.retcode);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Main OnTick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   static datetime lastProcessedBarTime = 0;

   // Get the last closed candle time on selected timeframe
   MqlRates rates[];
   if(CopyRates(_Symbol, InpTimeframe, 1, 2, rates) != 2)
     {
      Print("Failed to get rates");
      return;
     }
   datetime lastBarTime = rates[1].time;

   // Process only once per bar close
   if(lastBarTime == lastProcessedBarTime)
      return;
   lastProcessedBarTime = lastBarTime;

   // Calculate SMA on timeframe
   if(CopyBuffer(_Symbol, InpTimeframe, 0, 0, 0) == 0) // Dummy check to ensure symbol and TF exist
     {
      Print("Invalid symbol/timeframe");
      return;
     }

   if(CopyBuffer(_Symbol, InpTimeframe, 0, 1, smaBuffer) != 1)
     {
      ArrayResize(smaBuffer, 1);
      smaBuffer[0] = iMA(_Symbol, InpTimeframe, InpSmaPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);
     }
   else
     {
      smaBuffer[0] = iMA(_Symbol, InpTimeframe, InpSmaPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);
     }

   // Calculate MACD buffers
   int macdHandle = iMACD(_Symbol, InpTimeframe, 12, 26, 9, PRICE_CLOSE);
   if(macdHandle == INVALID_HANDLE)
     {
      Print("Failed to create MACD handle");
      return;
     }

   ArrayResize(macdMain, 3);
   ArrayResize(macdSignal, 3);
   ArrayResize(macdHist, 3);

   if(CopyBuffer(macdHandle, 0, 0, 3, macdMain) <= 0 ||
      CopyBuffer(macdHandle, 1, 0, 3, macdSignal) <= 0 ||
      CopyBuffer(macdHandle, 2, 0, 3, macdHist) <= 0)
     {
      Print("Failed to copy MACD buffers");
      return;
     }

   // Release MACD handle
   IndicatorRelease(macdHandle);

   // Get candle close price of last closed bar on timeframe
   double closePrice = rates[1].close;

   double smaValue = iMA(_Symbol, InpTimeframe, InpSmaPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);

   // Entry logic:

   // Buy condition:
   bool buyCond = (closePrice > smaValue) && IsMacdCrossover(1, 1);

   // Sell condition:
   bool sellCond = (closePrice < smaValue) && IsMacdCrossover(1, -1);

   // Check and open new buy position
   if(buyCond && CanOpenNewPosition(1))
     {
      // Calculate stop loss for risk-based sizing (use previous day low or recent low as SL)
      double slPrice = prevDayLow > 0 ? prevDayLow : closePrice - (closePrice * 0.01);

      double lot = CalculateLotSize(slPrice);

      if(OpenPosition(1, lot))
         Print("Opened Buy @ ", DoubleToString(closePrice, _Digits));
     }

   // Check and open new sell position
   if(sellCond && CanOpenNewPosition(-1))
     {
      double slPrice = prevDayHigh > 0 ? prevDayHigh : closePrice + (closePrice * 0.01);

      double lot = CalculateLotSize(slPrice);

      if(OpenPosition(-1, lot))
         Print("Opened Sell @ ", DoubleToString(closePrice, _Digits));
     }

   // Manage open positions: scaling out and trailing stops
   ManagePositions();
  }
//+------------------------------------------------------------------+
