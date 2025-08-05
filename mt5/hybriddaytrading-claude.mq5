//+------------------------------------------------------------------+
//|                              DayTradingSMAMACD.mq5              |
//|                      Day Trading SMA + MACD Strategy            |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Learning Example"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Strategy Settings ==="
input int SMA_Period = 10;                          // 10-Day SMA Period
input int MACD_FastEMA = 12;                         // MACD Fast EMA
input int MACD_SlowEMA = 26;                         // MACD Slow EMA
input int MACD_Signal = 9;                           // MACD Signal Line
input ENUM_APPLIED_PRICE MACD_Price = PRICE_CLOSE;   // MACD Applied Price

input group "=== Position Management ==="
input double InitialLotSize = 0.1;                  // Initial Lot Size
input double ScaleOut1Percent = 1.0;                // First scale out at % profit
input double ScaleOut2Percent = 2.0;                // Second scale out at % profit
input double ScaleOut3Percent = 3.0;                // Third scale out at % profit
input double FinalPositionPercent = 25.0;           // Final position % to let run

input group "=== Risk Management ==="
input double MaxSpread = 3;                          // Maximum Spread (points)
input int MagicNumber = 11111;                       // Magic Number
input bool CloseAllAtEndOfDay = true;                // Close all positions at end of day
input string EndOfDayTime = "22:00";                 // End of day time (24h format)

input group "=== Display Settings ==="
input bool ShowDebugInfo = true;                     // Show debug information
input bool DrawSMA = true;                           // Draw SMA on chart
input bool DrawEntrySignals = true;                  // Draw entry signals

//--- Global variables
CTrade trade;
datetime lastBarTime;

// Indicator handles
int smaHandle;
int macdHandle;

// Indicator arrays
double smaValues[];
double macdMain[];
double macdSignal[];

// Position tracking
struct PositionInfo
{
    ulong ticket;
    double entryPrice;
    double initialLots;
    double currentLots;
    bool scaleOut1Done;
    bool scaleOut2Done;
    bool scaleOut3Done;
    bool isLong;
    datetime entryTime;
    double previousDayLow;
    double previousDayHigh;
};

PositionInfo currentPosition;
bool hasPosition = false;

// Daily levels
double prevDayHigh = 0;
double prevDayLow = 0;
datetime lastDayCalculated = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    
    // Initialize indicators
    smaHandle = iMA(_Symbol, _Period, SMA_Period, 0, MODE_SMA, PRICE_CLOSE);
    macdHandle = iMACD(_Symbol, _Period, MACD_FastEMA, MACD_SlowEMA, MACD_Signal, MACD_Price);
    
    // Check if indicators are created successfully
    if(smaHandle == INVALID_HANDLE || macdHandle == INVALID_HANDLE)
    {
        Print("Error creating indicators");
        return INIT_FAILED;
    }
    
    // Set arrays as series
    ArraySetAsSeries(smaValues, true);
    ArraySetAsSeries(macdMain, true);
    ArraySetAsSeries(macdSignal, true);
    
    // Initialize position tracking
    ResetPositionInfo();
    
    // Calculate previous day levels
    CalculatePreviousDayLevels();
    
    Print("Day Trading SMA + MACD Strategy initialized");
    Print("SMA Period: ", SMA_Period);
    Print("Trading on ", EnumToString(_Period), " timeframe");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    IndicatorRelease(smaHandle);
    IndicatorRelease(macdHandle);
    
    // Clean up chart objects
    CleanupChartObjects();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if new bar formed
    if(!IsNewBar()) return;
    
    // Check spread condition
    if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > MaxSpread) return;
    
    // Copy indicator data
    if(!CopyIndicatorData()) return;
    
    // Update daily levels if new day
    UpdateDailyLevels();
    
    // Check for end of day closure
    if(CloseAllAtEndOfDay && IsEndOfDay())
    {
        CloseAllPositions("End of day closure");
        return;
    }
    
    // Update position tracking
    UpdatePositionStatus();
    
    // Manage existing positions (scaling out)
    if(hasPosition)
    {
        ManageExistingPosition();
    }
    else
    {
        // Look for new entry signals
        CheckForEntrySignals();
    }
    
    // Update visual elements
    if(DrawEntrySignals) UpdateEntrySignals();
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Copy indicator data                                              |
//+------------------------------------------------------------------+
bool CopyIndicatorData()
{
    if(CopyBuffer(smaHandle, 0, 0, 5, smaValues) < 5) return false;
    if(CopyBuffer(macdHandle, 0, 0, 5, macdMain) < 5) return false;
    if(CopyBuffer(macdHandle, 1, 0, 5, macdSignal) < 5) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Calculate previous day high/low levels                          |
//+------------------------------------------------------------------+
void CalculatePreviousDayLevels()
{
    // Get yesterday's data
    MqlRates rates[];
    if(CopyRates(_Symbol, PERIOD_D1, 1, 1, rates) > 0)
    {
        prevDayHigh = rates[0].high;
        prevDayLow = rates[0].low;
        lastDayCalculated = rates[0].time;
        
        if(ShowDebugInfo)
            Print("Previous day levels - High: ", prevDayHigh, " Low: ", prevDayLow);
    }
}

//+------------------------------------------------------------------+
//| Update daily levels if new day                                  |
//+------------------------------------------------------------------+
void UpdateDailyLevels()
{
    datetime currentDay = TimeCurrent() - (TimeCurrent() % 86400); // Start of current day
    datetime lastCalculatedDay = lastDayCalculated - (lastDayCalculated % 86400);
    
    if(currentDay > lastCalculatedDay)
    {
        CalculatePreviousDayLevels();
    }
}

//+------------------------------------------------------------------+
//| Check if it's end of trading day                                |
//+------------------------------------------------------------------+
bool IsEndOfDay()
{
    MqlDateTime dt;
    TimeCurrent(dt);
    
    string currentTime = StringFormat("%02d:%02d", dt.hour, dt.min);
    return StringCompare(currentTime, EndOfDayTime) >= 0;
}

//+------------------------------------------------------------------+
//| Update position status                                           |
//+------------------------------------------------------------------+
void UpdatePositionStatus()
{
    if(PositionSelect(_Symbol))
    {
        if(!hasPosition)
        {
            // Position was opened externally or we missed it
            currentPosition.ticket = PositionGetInteger(POSITION_TICKET);
            currentPosition.entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            currentPosition.initialLots = PositionGetDouble(POSITION_VOLUME);
            currentPosition.currentLots = PositionGetDouble(POSITION_VOLUME);
            currentPosition.isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            currentPosition.entryTime = (datetime)PositionGetInteger(POSITION_TIME);
            currentPosition.previousDayLow = prevDayLow;
            currentPosition.previousDayHigh = prevDayHigh;
            hasPosition = true;
            
            if(ShowDebugInfo)
                Print("Position detected - Ticket: ", currentPosition.ticket);
        }
    }
    else
    {
        if(hasPosition)
        {
            if(ShowDebugInfo)
                Print("Position closed - Ticket: ", currentPosition.ticket);
            ResetPositionInfo();
        }
    }
}

//+------------------------------------------------------------------+
//| Reset position information                                       |
//+------------------------------------------------------------------+
void ResetPositionInfo()
{
    currentPosition.ticket = 0;
    currentPosition.entryPrice = 0;
    currentPosition.initialLots = 0;
    currentPosition.currentLots = 0;
    currentPosition.scaleOut1Done = false;
    currentPosition.scaleOut2Done = false;
    currentPosition.scaleOut3Done = false;
    currentPosition.isLong = true;
    currentPosition.entryTime = 0;
    currentPosition.previousDayLow = 0;
    currentPosition.previousDayHigh = 0;
    hasPosition = false;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckForEntrySignals()
{
    double currentPrice = iClose(_Symbol, _Period, 1);
    double currentSMA = smaValues[1];
    double prevPrice = iClose(_Symbol, _Period, 2);
    double prevSMA = smaValues[2];
    
    double currentMACD = macdMain[1];
    double currentSignal = macdSignal[1];
    double prevMACD = macdMain[2];
    double prevSignal = macdSignal[2];
    
    // Long signal: Price breaks above SMA + MACD bullish crossover
    if(prevPrice <= prevSMA && currentPrice > currentSMA && // Price breaks above SMA
       prevMACD <= prevSignal && currentMACD > currentSignal) // MACD bullish crossover
    {
        ExecuteLongEntry();
    }
    
    // Short signal: Price breaks below SMA + MACD bearish crossover
    if(prevPrice >= prevSMA && currentPrice < currentSMA && // Price breaks below SMA
       prevMACD >= prevSignal && currentMACD < currentSignal) // MACD bearish crossover
    {
        ExecuteShortEntry();
    }
}

//+------------------------------------------------------------------+
//| Execute long entry                                               |
//+------------------------------------------------------------------+
void ExecuteLongEntry()
{
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double stopLoss = prevDayLow - (2 * _Point); // Stop at previous day low
    
    if(trade.Buy(InitialLotSize, _Symbol, entryPrice, stopLoss, 0, "SMA-MACD Long"))
    {
        currentPosition.ticket = trade.ResultOrder();
        currentPosition.entryPrice = entryPrice;
        currentPosition.initialLots = InitialLotSize;
        currentPosition.currentLots = InitialLotSize;
        currentPosition.isLong = true;
        currentPosition.entryTime = TimeCurrent();
        currentPosition.previousDayLow = prevDayLow;
        currentPosition.previousDayHigh = prevDayHigh;
        hasPosition = true;
        
        if(ShowDebugInfo)
            Print("Long entry executed at: ", entryPrice, " SL: ", stopLoss);
        
        if(DrawEntrySignals)
            DrawEntryArrow(true, entryPrice);
    }
}

//+------------------------------------------------------------------+
//| Execute short entry                                              |
//+------------------------------------------------------------------+
void ExecuteShortEntry()
{
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stopLoss = prevDayHigh + (2 * _Point); // Stop at previous day high
    
    if(trade.Sell(InitialLotSize, _Symbol, entryPrice, stopLoss, 0, "SMA-MACD Short"))
    {
        currentPosition.ticket = trade.ResultOrder();
        currentPosition.entryPrice = entryPrice;
        currentPosition.initialLots = InitialLotSize;
        currentPosition.currentLots = InitialLotSize;
        currentPosition.isLong = false;
        currentPosition.entryTime = TimeCurrent();
        currentPosition.previousDayLow = prevDayLow;
        currentPosition.previousDayHigh = prevDayHigh;
        hasPosition = true;
        
        if(ShowDebugInfo)
            Print("Short entry executed at: ", entryPrice, " SL: ", stopLoss);
        
        if(DrawEntrySignals)
            DrawEntryArrow(false, entryPrice);
    }
}

//+------------------------------------------------------------------+
//| Manage existing position (scaling out)                          |
//+------------------------------------------------------------------+
void ManageExistingPosition()
{
    double currentPrice = SymbolInfoDouble(_Symbol, currentPosition.isLong ? SYMBOL_BID : SYMBOL_ASK);
    double profitPercent;
    
    if(currentPosition.isLong)
        profitPercent = ((currentPrice - currentPosition.entryPrice) / currentPosition.entryPrice) * 100;
    else
        profitPercent = ((currentPosition.entryPrice - currentPrice) / currentPosition.entryPrice) * 100;
    
    // Scale out at profit targets
    if(!currentPosition.scaleOut1Done && profitPercent >= ScaleOut1Percent)
    {
        ScaleOutPosition(25, "1% profit scale out"); // Scale out 25%
        currentPosition.scaleOut1Done = true;
    }
    
    if(!currentPosition.scaleOut2Done && profitPercent >= ScaleOut2Percent)
    {
        ScaleOutPosition(25, "2% profit scale out"); // Scale out another 25%
        currentPosition.scaleOut2Done = true;
    }
    
    if(!currentPosition.scaleOut3Done && profitPercent >= ScaleOut3Percent)
    {
        ScaleOutPosition(25, "3% profit scale out"); // Scale out another 25%
        currentPosition.scaleOut3Done = true;
        
        // Update stop loss to entry for remaining position
        UpdateStopLossToEntry();
    }
    
    if(ShowDebugInfo && (int)profitPercent != 0)
        Print("Position P&L: ", DoubleToString(profitPercent, 2), "%");
}

//+------------------------------------------------------------------+
//| Scale out portion of position                                    |
//+------------------------------------------------------------------+
void ScaleOutPosition(double percentage, string comment)
{
    double lotsToClose = (currentPosition.currentLots * percentage) / 100.0;
    lotsToClose = NormalizeDouble(lotsToClose, 2);
    
    if(lotsToClose > 0)
    {
        if(trade.PositionClosePartial(currentPosition.ticket, lotsToClose))
        {
            currentPosition.currentLots -= lotsToClose;
            currentPosition.currentLots = NormalizeDouble(currentPosition.currentLots, 2);
            
            if(ShowDebugInfo)
                Print(comment, " - Closed: ", lotsToClose, " lots. Remaining: ", currentPosition.currentLots);
        }
    }
}

//+------------------------------------------------------------------+
//| Update stop loss to entry price                                 |
//+------------------------------------------------------------------+
void UpdateStopLossToEntry()
{
    if(PositionSelect(_Symbol))
    {
        double newStopLoss = currentPosition.entryPrice;
        
        if(trade.PositionModify(currentPosition.ticket, newStopLoss, 0))
        {
            if(ShowDebugInfo)
                Print("Stop loss updated to entry: ", newStopLoss);
        }
    }
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
    if(hasPosition)
    {
        if(trade.PositionClose(currentPosition.ticket))
        {
            if(ShowDebugInfo)
                Print("Position closed: ", reason);
        }
    }
}

//+------------------------------------------------------------------+
//| Draw entry arrow on chart                                        |
//+------------------------------------------------------------------+
void DrawEntryArrow(bool isLong, double price)
{
    string objName = "Entry_" + TimeToString(TimeCurrent());
    
    if(isLong)
    {
        ObjectCreate(0, objName, OBJ_ARROW_UP, 0, TimeCurrent(), price);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrGreen);
    }
    else
    {
        ObjectCreate(0, objName, OBJ_ARROW_DOWN, 0, TimeCurrent(), price);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrRed);
    }
    
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
    ObjectSetString(0, objName, OBJPROP_TEXT, isLong ? "LONG" : "SHORT");
}

//+------------------------------------------------------------------+
//| Update entry signals visualization                               |
//+------------------------------------------------------------------+
void UpdateEntrySignals()
{
    // This could include additional visual aids
    // Current implementation focuses on entry arrows
}

//+------------------------------------------------------------------+
//| Clean up chart objects                                           |
//+------------------------------------------------------------------+
void CleanupChartObjects()
{
    int totalObjects = ObjectsTotal(0);
    
    for(int i = totalObjects - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i);
        
        if(StringFind(objName, "Entry_") >= 0)
        {
            ObjectDelete(0, objName);
        }
    }
}

//+------------------------------------------------------------------+
//| Get current profit percentage                                    |
//+------------------------------------------------------------------+
double GetCurrentProfitPercent()
{
    if(!hasPosition) return 0;
    
    double currentPrice = SymbolInfoDouble(_Symbol, currentPosition.isLong ? SYMBOL_BID : SYMBOL_ASK);
    
    if(currentPosition.isLong)
        return ((currentPrice - currentPosition.entryPrice) / currentPosition.entryPrice) * 100;
    else
        return ((currentPosition.entryPrice - currentPrice) / currentPosition.entryPrice) * 100;
}