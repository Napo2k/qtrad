//+------------------------------------------------------------------+
//|                                    Bollinger Bands Strategy EA   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Trading Time Settings ==="
input int    InpStartHour    = 9;     // Trading start hour (0-23)
input int    InpStartMinute  = 0;     // Trading start minute (0-59)
input int    InpEndHour      = 17;    // Trading end hour (0-23)
input int    InpEndMinute    = 0;     // Trading end minute (0-59)

input group "=== Indicator Settings ==="
input int    InpBBPeriod     = 8;     // Bollinger Bands period
input double InpBBDeviation  = 2.0;   // Bollinger Bands deviation
input int    InpSMAPeriod    = 10;    // Simple Moving Average period
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT; // Timeframe for analysis

input group "=== Exit Settings ==="
input int    InpFallbackCandles = 7;  // Fallback exit after N candles

input group "=== Risk Management ==="
input double InpLotSize      = 0.1;   // Lot size
input int    InpMagicNumber  = 123456; // Magic number for this EA

//--- Global variables
CTrade trade;
int bbHandle;
int smaHandle;
double bbUpper[], bbMiddle[], bbLower[];
double smaValues[];
datetime lastBarTime;
datetime entryTime;
int entryBarCount;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set trade parameters
    trade.SetExpertMagicNumber(InpMagicNumber);
    
    // Initialize indicators
    bbHandle = iBands(_Symbol, InpTimeframe, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
    smaHandle = iMA(_Symbol, InpTimeframe, InpSMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
    
    if(bbHandle == INVALID_HANDLE || smaHandle == INVALID_HANDLE)
    {
        Print("Error creating indicators");
        return INIT_FAILED;
    }
    
    // Initialize arrays
    ArraySetAsSeries(bbUpper, true);
    ArraySetAsSeries(bbMiddle, true);
    ArraySetAsSeries(bbLower, true);
    ArraySetAsSeries(smaValues, true);
    
    lastBarTime = 0;
    entryTime = 0;
    entryBarCount = 0;
    
    Print("Bollinger Bands Strategy EA initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    IndicatorRelease(bbHandle);
    IndicatorRelease(smaHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if new bar formed
    datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);
    if(currentBarTime == lastBarTime)
        return;
    
    lastBarTime = currentBarTime;
    
    // Update indicator values
    if(!UpdateIndicatorValues())
        return;
    
    // Check trading time window
    if(!IsWithinTradingHours())
        return;
    
    // Get current candle data
    double open = iOpen(_Symbol, InpTimeframe, 0);
    double high = iHigh(_Symbol, InpTimeframe, 0);
    double low = iLow(_Symbol, InpTimeframe, 0);
    double close = iClose(_Symbol, InpTimeframe, 0);
    
    // Get previous candle data
    double prevHigh = iHigh(_Symbol, InpTimeframe, 1);
    double prevLow = iLow(_Symbol, InpTimeframe, 1);
    
    // Calculate wick sizes
    double upperWick = high - MathMax(open, close);
    double lowerWick = MathMin(open, close) - low;
    
    // Check for open positions
    bool hasPosition = HasOpenPosition();
    
    // Entry logic - only if no open positions
    if(!hasPosition)
    {
        CheckEntrySignals(open, high, low, close, upperWick, lowerWick);
    }
    else
    {
        // Exit logic - manage existing positions
        CheckExitSignals(open, high, low, close, prevHigh, prevLow, upperWick, lowerWick);
        
        // Update entry bar count for fallback exit
        if(entryTime > 0)
        {
            entryBarCount++;
            
            // Fallback exit after specified number of candles
            if(entryBarCount >= InpFallbackCandles)
            {
                CloseAllPositions();
                Print("Position closed due to fallback exit criteria (", InpFallbackCandles, " candles)");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
bool UpdateIndicatorValues()
{
    // Copy Bollinger Bands values
    if(CopyBuffer(bbHandle, 1, 0, 3, bbUpper) <= 0 ||
       CopyBuffer(bbHandle, 0, 0, 3, bbMiddle) <= 0 ||
       CopyBuffer(bbHandle, 2, 0, 3, bbLower) <= 0)
    {
        Print("Error copying Bollinger Bands values");
        return false;
    }
    
    // Copy SMA values
    if(CopyBuffer(smaHandle, 0, 0, 3, smaValues) <= 0)
    {
        Print("Error copying SMA values");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                   |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    
    int currentHour = timeStruct.hour;
    int currentMinute = timeStruct.min;
    int currentTimeMinutes = currentHour * 60 + currentMinute;
    int startTimeMinutes = InpStartHour * 60 + InpStartMinute;
    int endTimeMinutes = InpEndHour * 60 + InpEndMinute;
    
    // Handle overnight trading sessions
    if(startTimeMinutes <= endTimeMinutes)
    {
        return (currentTimeMinutes >= startTimeMinutes && currentTimeMinutes <= endTimeMinutes);
    }
    else
    {
        return (currentTimeMinutes >= startTimeMinutes || currentTimeMinutes <= endTimeMinutes);
    }
}

//+------------------------------------------------------------------+
//| Check if there are open positions                               |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check entry signals                                             |
//+------------------------------------------------------------------+
void CheckEntrySignals(double open, double high, double low, double close, double upperWick, double lowerWick)
{
    // Buy Signal Criteria:
    // Enter buy if current candle closes or opens below lower BB and lower wick > upper wick
    if((close < bbLower[0] || open < bbLower[0]) && lowerWick > upperWick)
    {
        if(trade.Buy(InpLotSize, _Symbol))
        {
            entryTime = TimeCurrent();
            entryBarCount = 0;
            Print("BUY position opened - Price below lower BB, lower wick > upper wick");
        }
        else
        {
            Print("Failed to open BUY position. Error: ", GetLastError());
        }
    }
    
    // Sell Signal Criteria:
    // Enter sell if current candle closes or opens above upper BB and upper wick > lower wick
    else if((close > bbUpper[0] || open > bbUpper[0]) && upperWick > lowerWick)
    {
        if(trade.Sell(InpLotSize, _Symbol))
        {
            entryTime = TimeCurrent();
            entryBarCount = 0;
            Print("SELL position opened - Price above upper BB, upper wick > lower wick");
        }
        else
        {
            Print("Failed to open SELL position. Error: ", GetLastError());
        }
    }
}

//+------------------------------------------------------------------+
//| Check exit signals                                              |
//+------------------------------------------------------------------+
void CheckExitSignals(double open, double high, double low, double close, double prevHigh, double prevLow, double upperWick, double lowerWick)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                if(posType == POSITION_TYPE_BUY)
                {
                    // Buy Exit Criteria:
                    // Exit if candle closes above SMA OR close below prev low with upper wick > lower wick
                    if(close > smaValues[0] || 
                       (close < prevLow && upperWick > lowerWick))
                    {
                        if(trade.PositionClose(PositionGetTicket(i)))
                        {
                            entryTime = 0;
                            entryBarCount = 0;
                            Print("BUY position closed - Exit criteria met");
                        }
                    }
                }
                else if(posType == POSITION_TYPE_SELL)
                {
                    // Sell Exit Criteria:
                    // Exit if candle closes below SMA OR close above prev high with lower wick > upper wick
                    if(close < smaValues[0] || 
                       (close > prevHigh && lowerWick > upperWick))
                    {
                        if(trade.PositionClose(PositionGetTicket(i)))
                        {
                            entryTime = 0;
                            entryBarCount = 0;
                            Print("SELL position closed - Exit criteria met");
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close all positions                                             |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
                trade.PositionClose(PositionGetTicket(i));
            }
        }
    }
    entryTime = 0;
    entryBarCount = 0;
}

//+------------------------------------------------------------------+