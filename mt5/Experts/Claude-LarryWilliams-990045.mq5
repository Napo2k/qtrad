//+------------------------------------------------------------------+
//|                                    Larry Williams Strategy.mq5 |
//|                                                    Expert Advisor |
//|                    Larry Williams' First Days of Month Strategy |
//+------------------------------------------------------------------+
#property copyright "Claude - Larry Williams"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Input parameters
input group "=== Strategy Selection ==="
enum ENUM_STRATEGY_TYPE
{
   ORIGINAL_STRATEGY = 0,     // Original Strategy (2.5% Stop Loss)
   ATR_OPTIMIZATION = 1,      // ATR Optimization 
   HOLDING_OPTIMIZATION = 2   // Holding Period Optimization
};

input ENUM_STRATEGY_TYPE StrategyType = ORIGINAL_STRATEGY; // Strategy Type

input group "=== Original Strategy Parameters ==="
input double StopLossPercent = 2.5;           // Stop Loss Percentage (Original)
input int MaxDayOfMonth = 12;                 // Maximum Day of Month to Trade
input bool AvoidFridays = true;               // Avoid Friday Entries

input group "=== Williams %R Parameters ==="
input int WilliamsR_Period = 14;              // Williams %R Period
input double WilliamsR_Threshold = -20.0;     // Williams %R Threshold

input group "=== ATR Optimization Parameters ==="
input int ATR_Period = 14;                    // ATR Period
input double ATR_StopLoss_Multiplier = 2.0;   // ATR Stop Loss Multiplier
input double ATR_TakeProfit_Multiplier = 3.0; // ATR Take Profit Multiplier

input group "=== Holding Period Optimization ==="
input int MinHoldingPeriod = 12;              // Minimum Holding Period (candles)

input group "=== Risk Management ==="
input double LotSize = 0.1;                   // Lot Size
input int MagicNumber = 990145;                 // Magic Number

input group "=== Trading Hours ==="
input int StartHour = 0;                      // Start Trading Hour
input int EndHour = 23;                       // End Trading Hour

//--- Global variables
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

int williamsRHandle;
int atrHandle;

double williamsRBuffer[];
double atrBuffer[];

bool tradeThisMonth = false;
int lastTradeMonth = -1;
int positionOpenCandles = 0;
datetime positionOpenTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Initialize trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   //--- Initialize indicators
   williamsRHandle = iWPR(Symbol(), PERIOD_CURRENT, WilliamsR_Period);
   atrHandle = iATR(Symbol(), PERIOD_CURRENT, ATR_Period);
   
   if(williamsRHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return INIT_FAILED;
   }
   
   //--- Set array as series
   ArraySetAsSeries(williamsRBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   
   Print("Larry Williams Strategy EA initialized successfully");
   Print("Strategy Type: ", EnumToString(StrategyType));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if(williamsRHandle != INVALID_HANDLE)
      IndicatorRelease(williamsRHandle);
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(Symbol(), PERIOD_CURRENT, 0);
   
   if(currentBarTime <= lastBarTime)
      return;
   lastBarTime = currentBarTime;
   
   //--- Update indicator buffers
   if(!UpdateIndicators())
      return;
   
   //--- Check trading conditions
   CheckTradingConditions();
   
   //--- Manage existing positions
   ManagePositions();
}

//+------------------------------------------------------------------+
//| Update indicator buffers                                         |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   if(CopyBuffer(williamsRHandle, 0, 0, 3, williamsRBuffer) < 3)
      return false;
   
   if(CopyBuffer(atrHandle, 0, 0, 3, atrBuffer) < 3)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check trading conditions                                         |
//+------------------------------------------------------------------+
void CheckTradingConditions()
{
   //--- Check if already have position
   if(PositionsTotal() > 0)
   {
      UpdatePositionInfo();
      return;
   }
   
   //--- Check month trading eligibility
   if(!CanTradeThisMonth())
      return;
   
   //--- Check day of month
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(dt.day > MaxDayOfMonth)
      return;
   
   //--- Check if Friday (avoid if enabled)
   if(AvoidFridays && dt.day_of_week == 5) // Friday = 5
      return;
   
   //--- Check trading hours
   if(dt.hour < StartHour || dt.hour > EndHour)
      return;
   
   //--- Check entry conditions
   if(CheckEntryConditions())
   {
      OpenPosition();
   }
}

//+------------------------------------------------------------------+
//| Check if can trade this month                                    |
//+------------------------------------------------------------------+
bool CanTradeThisMonth()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(lastTradeMonth != dt.mon)
   {
      tradeThisMonth = false;
      lastTradeMonth = dt.mon;
   }
   
   return !tradeThisMonth;
}

//+------------------------------------------------------------------+
//| Check entry conditions                                           |
//+------------------------------------------------------------------+
bool CheckEntryConditions()
{
   double currentClose = iClose(Symbol(), PERIOD_CURRENT, 1);
   double previousClose = iClose(Symbol(), PERIOD_CURRENT, 2);
   double currentWilliamsR = williamsRBuffer[1];
   
   //--- Entry condition: Close above previous close
   if(currentClose <= previousClose)
      return false;
   
   //--- Williams %R condition: Must be below threshold (not overbought)
   if(currentWilliamsR >= WilliamsR_Threshold)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
void OpenPosition()
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double stopLoss = 0;
   double takeProfit = 0;
   
   //--- Calculate stop loss and take profit based on strategy type
   CalculateStopLossAndTakeProfit(price, stopLoss, takeProfit);
   
   //--- Open position
   if(trade.Buy(LotSize, Symbol(), price, stopLoss, takeProfit, "Larry Williams Strategy"))
   {
      tradeThisMonth = true;
      positionOpenTime = TimeCurrent();
      positionOpenCandles = 0;
      
      Print("Position opened: ", Symbol(), " at ", price, 
            " SL: ", stopLoss, " TP: ", takeProfit);
   }
   else
   {
      Print("Failed to open position. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss and Take Profit                             |
//+------------------------------------------------------------------+
void CalculateStopLossAndTakeProfit(double price, double &stopLoss, double &takeProfit)
{
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   
   switch(StrategyType)
   {
      case ORIGINAL_STRATEGY:
         stopLoss = NormalizeDouble(price * (1 - StopLossPercent / 100.0), digits);
         takeProfit = 0; // No fixed take profit in original strategy
         break;
         
      case ATR_OPTIMIZATION:
         {
            double atr = atrBuffer[1];
            stopLoss = NormalizeDouble(price - (atr * ATR_StopLoss_Multiplier), digits);
            takeProfit = NormalizeDouble(price + (atr * ATR_TakeProfit_Multiplier), digits);
         }
         break;
         
      case HOLDING_OPTIMIZATION:
         stopLoss = NormalizeDouble(price * (1 - StopLossPercent / 100.0), digits);
         takeProfit = 0; // Will be managed manually based on holding period
         break;
   }
}

//+------------------------------------------------------------------+
//| Update position information                                      |
//+------------------------------------------------------------------+
void UpdatePositionInfo()
{
   if(PositionsTotal() > 0)
   {
      positionOpenCandles++;
   }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(PositionsTotal() == 0)
      return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == Symbol() && positionInfo.Magic() == MagicNumber)
         {
            CheckExitConditions();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check exit conditions                                            |
//+------------------------------------------------------------------+
void CheckExitConditions()
{
   bool shouldClose = false;
   string reason = "";
   
   switch(StrategyType)
   {
      case ORIGINAL_STRATEGY:
         if(CheckOriginalExitConditions())
         {
            shouldClose = true;
            reason = "Original strategy exit condition";
         }
         break;
         
      case ATR_OPTIMIZATION:
         // ATR optimization relies on stop loss and take profit levels
         // No additional exit logic needed
         break;
         
      case HOLDING_OPTIMIZATION:
         if(CheckHoldingOptimizationExit())
         {
            shouldClose = true;
            reason = "Holding period optimization exit";
         }
         break;
   }
   
   if(shouldClose)
   {
      ClosePosition(reason);
   }
}

//+------------------------------------------------------------------+
//| Check original strategy exit conditions                         |
//+------------------------------------------------------------------+
bool CheckOriginalExitConditions()
{
   //--- Must be open for at least 1 day
   if(positionOpenCandles < 1)
      return false;
   
   //--- Check if previous candle closed positive
   double previousOpen = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double previousClose = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if(previousClose > previousOpen)
   {
      //--- Close on next day's opening (current price)
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check holding optimization exit conditions                      |
//+------------------------------------------------------------------+
bool CheckHoldingOptimizationExit()
{
   //--- Must hold for minimum period
   if(positionOpenCandles < MinHoldingPeriod)
      return false;
   
   //--- Check if previous candle closed positive
   double previousOpen = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double previousClose = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if(previousClose > previousOpen)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == Symbol() && positionInfo.Magic() == MagicNumber)
         {
            double price = (positionInfo.PositionType() == POSITION_TYPE_BUY) ? 
                          SymbolInfoDouble(Symbol(), SYMBOL_BID) : 
                          SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            
            if(trade.PositionClose(positionInfo.Ticket()))
            {
               Print("Position closed: ", reason, " at price: ", price);
               positionOpenCandles = 0;
               positionOpenTime = 0;
            }
            else
            {
               Print("Failed to close position. Error: ", GetLastError());
            }
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get string representation of strategy type                       |
//+------------------------------------------------------------------+
string EnumToString(ENUM_STRATEGY_TYPE strategyType)
{
   switch(strategyType)
   {
      case ORIGINAL_STRATEGY: return "Original Strategy";
      case ATR_OPTIMIZATION: return "ATR Optimization";
      case HOLDING_OPTIMIZATION: return "Holding Period Optimization";
      default: return "Unknown Strategy";
   }
}