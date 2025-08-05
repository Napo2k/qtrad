//+------------------------------------------------------------------+
//|                           MACD_EMA_PriceAction_Strategy.mq5     |
//|                    MACD + 200 EMA + Price Action Strategy       |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Learning Example"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Strategy Settings ==="
input int EMA_Period = 200;                          // 200-Day EMA Period
input int MACD_FastEMA = 12;                         // MACD Fast EMA
input int MACD_SlowEMA = 26;                         // MACD Slow EMA
input int MACD_Signal = 9;                           // MACD Signal Line
input ENUM_APPLIED_PRICE MACD_Price = PRICE_CLOSE;   // MACD Applied Price

input group "=== Risk Management ==="
input double LotSize = 0.1;                         // Lot Size
input double ProfitRatio = 1.5;                     // Profit Target Ratio
input double MaxSpread = 3;                          // Maximum Spread (points)
input int MagicNumber = 67890;                       // Magic Number

input group "=== Price Action Settings ==="
input int SupportResistancePeriod = 50;              // S/R Detection Period
input double KeyLevelTolerance = 10;                 // Key Level Tolerance (points)
input int MinTouchesForKeyLevel = 2;                 // Min touches for key level
input double RetestTolerance = 15;                   // Retest tolerance (points)

input group "=== Display Settings ==="
input bool ShowDebugInfo = true;                     // Show debug information
input bool DrawKeyLevels = true;                     // Draw key S/R levels
input bool DrawEMA = true;                           // Draw 200 EMA on chart

//--- Global variables
CTrade trade;
datetime lastBarTime;

// Indicator handles
int emaHandle;
int macdHandle;

// Indicator arrays
double emaValues[];
double macdMain[];
double macdSignal[];

// Key levels structure
struct KeyLevel
{
    double price;
    bool isSupport;        // true = support, false = resistance
    int touchCount;
    datetime lastTouch;
    bool isValid;
};

KeyLevel keyLevels[];
int keyLevelCount = 0;

// Strategy state
enum SIGNAL_STATE
{
    NO_SIGNAL,
    WAITING_FOR_LONG_SETUP,
    WAITING_FOR_SHORT_SETUP,
    LONG_SIGNAL_CONFIRMED,
    SHORT_SIGNAL_CONFIRMED
};

SIGNAL_STATE currentSignal = NO_SIGNAL;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    
    // Initialize indicators
    emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    macdHandle = iMACD(_Symbol, _Period, MACD_FastEMA, MACD_SlowEMA, MACD_Signal, MACD_Price);
    
    // Check if indicators are created successfully
    if(emaHandle == INVALID_HANDLE || macdHandle == INVALID_HANDLE)
    {
        Print("Error creating indicators");
        return INIT_FAILED;
    }
    
    // Set arrays as series
    ArraySetAsSeries(emaValues, true);
    ArraySetAsSeries(macdMain, true);
    ArraySetAsSeries(macdSignal, true);
    
    // Initialize key levels array
    ArrayResize(keyLevels, 20);
    for(int i = 0; i < 20; i++)
    {
        keyLevels[i].isValid = false;
        keyLevels[i].touchCount = 0;
    }
    
    Print("MACD + 200 EMA + Price Action Strategy initialized");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    IndicatorRelease(emaHandle);
    IndicatorRelease(macdHandle);
    
    // Clean up chart objects
    if(DrawKeyLevels) CleanupChartObjects();
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
    
    // Update key support/resistance levels
    UpdateKeyLevels();
    
    // Check for trading signals
    CheckTradingSignals();
    
    // Execute trades based on confirmed signals
    ExecuteTrades();
    
    // Update visual elements
    if(DrawKeyLevels) DrawSupportResistanceLevels();
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
    if(CopyBuffer(emaHandle, 0, 0, 5, emaValues) < 5) return false;
    if(CopyBuffer(macdHandle, 0, 0, 5, macdMain) < 5) return false;
    if(CopyBuffer(macdHandle, 1, 0, 5, macdSignal) < 5) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Update key support and resistance levels                        |
//+------------------------------------------------------------------+
void UpdateKeyLevels()
{
    keyLevelCount = 0;
    
    // Find pivot points for potential S/R levels
    for(int i = 2; i < SupportResistancePeriod - 2; i++)
    {
        double high = iHigh(_Symbol, _Period, i);
        double low = iLow(_Symbol, _Period, i);
        double prevHigh = iHigh(_Symbol, _Period, i + 1);
        double prevLow = iLow(_Symbol, _Period, i + 1);
        double nextHigh = iHigh(_Symbol, _Period, i - 1);
        double nextLow = iLow(_Symbol, _Period, i - 1);
        
        // Potential resistance level (pivot high)
        if(high > prevHigh && high > nextHigh && keyLevelCount < ArraySize(keyLevels) - 1)
        {
            if(CountTouchesAtLevel(high, false) >= MinTouchesForKeyLevel)
            {
                keyLevels[keyLevelCount].price = high;
                keyLevels[keyLevelCount].isSupport = false;
                keyLevels[keyLevelCount].touchCount = CountTouchesAtLevel(high, false);
                keyLevels[keyLevelCount].isValid = true;
                keyLevelCount++;
            }
        }
        
        // Potential support level (pivot low)
        if(low < prevLow && low < nextLow && keyLevelCount < ArraySize(keyLevels) - 1)
        {
            if(CountTouchesAtLevel(low, true) >= MinTouchesForKeyLevel)
            {
                keyLevels[keyLevelCount].price = low;
                keyLevels[keyLevelCount].isSupport = true;
                keyLevels[keyLevelCount].touchCount = CountTouchesAtLevel(low, true);
                keyLevels[keyLevelCount].isValid = true;
                keyLevelCount++;
            }
        }
    }
    
    if(ShowDebugInfo)
        Print("Updated key levels: ", keyLevelCount, " levels found");
}

//+------------------------------------------------------------------+
//| Count touches at a specific level                               |
//+------------------------------------------------------------------+
int CountTouchesAtLevel(double level, bool isSupport)
{
    int touches = 0;
    double tolerance = KeyLevelTolerance * _Point;
    
    for(int i = 1; i < SupportResistancePeriod; i++)
    {
        double high = iHigh(_Symbol, _Period, i);
        double low = iLow(_Symbol, _Period, i);
        
        if(isSupport)
        {
            if(MathAbs(low - level) <= tolerance) touches++;
        }
        else
        {
            if(MathAbs(high - level) <= tolerance) touches++;
        }
    }
    
    return touches;
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
    double currentPrice = iClose(_Symbol, _Period, 1);
    double currentEMA = emaValues[1];
    double currentMACD = macdMain[1];
    double prevMACD = macdMain[2];
    double currentSignal = macdSignal[1];
    double prevSignal = macdSignal[2];
    
    // Reset signal state
    currentSignal = NO_SIGNAL;
    
    // Check for long setup conditions
    if(currentPrice > currentEMA) // Price above 200 EMA (uptrend)
    {
        // MACD cross upward below zero line
        if(currentMACD > currentSignal && prevMACD <= prevSignal && currentMACD < 0)
        {
            // Check if price is near a support level (retest)
            for(int i = 0; i < keyLevelCount; i++)
            {
                if(keyLevels[i].isValid && keyLevels[i].isSupport)
                {
                    double distanceToLevel = MathAbs(currentPrice - keyLevels[i].price);
                    if(distanceToLevel <= RetestTolerance * _Point)
                    {
                        currentSignal = LONG_SIGNAL_CONFIRMED;
                        if(ShowDebugInfo)
                            Print("Long signal confirmed at support level: ", keyLevels[i].price);
                        break;
                    }
                }
            }
            
            // If no key level retest, still consider basic long setup
            if(currentSignal == NO_SIGNAL)
            {
                currentSignal = WAITING_FOR_LONG_SETUP;
                if(ShowDebugInfo)
                    Print("Long setup detected (waiting for key level retest)");
            }
        }
    }
    
    // Check for short setup conditions
    if(currentPrice < currentEMA) // Price below 200 EMA (downtrend)
    {
        // MACD cross downward above zero line
        if(currentMACD < currentSignal && prevMACD >= prevSignal && currentMACD > 0)
        {
            // Check if price is near a resistance level (retest)
            for(int i = 0; i < keyLevelCount; i++)
            {
                if(keyLevels[i].isValid && !keyLevels[i].isSupport)
                {
                    double distanceToLevel = MathAbs(currentPrice - keyLevels[i].price);
                    if(distanceToLevel <= RetestTolerance * _Point)
                    {
                        currentSignal = SHORT_SIGNAL_CONFIRMED;
                        if(ShowDebugInfo)
                            Print("Short signal confirmed at resistance level: ", keyLevels[i].price);
                        break;
                    }
                }
            }
            
            // If no key level retest, still consider basic short setup
            if(currentSignal == NO_SIGNAL)
            {
                currentSignal = WAITING_FOR_SHORT_SETUP;
                if(ShowDebugInfo)
                    Print("Short setup detected (waiting for key level retest)");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Execute trades based on confirmed signals                       |
//+------------------------------------------------------------------+
void ExecuteTrades()
{
    // Don't trade if we already have an open position
    if(PositionSelect(_Symbol)) return;
    
    if(currentSignal == LONG_SIGNAL_CONFIRMED)
    {
        ExecuteLongTrade();
    }
    else if(currentSignal == SHORT_SIGNAL_CONFIRMED)
    {
        ExecuteShortTrade();
    }
}

//+------------------------------------------------------------------+
//| Execute long trade                                               |
//+------------------------------------------------------------------+
void ExecuteLongTrade()
{
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double stopLoss = emaValues[1] - (5 * _Point); // Below 200 EMA
    double riskPoints = entryPrice - stopLoss;
    double takeProfit = entryPrice + (riskPoints * ProfitRatio);
    
    // Normalize prices
    stopLoss = NormalizeDouble(stopLoss, _Digits);
    takeProfit = NormalizeDouble(takeProfit, _Digits);
    
    if(riskPoints > 0 && takeProfit > entryPrice)
    {
        if(trade.Buy(LotSize, _Symbol, entryPrice, stopLoss, takeProfit, "MACD-EMA Long"))
        {
            if(ShowDebugInfo)
                Print("Long trade executed. Entry: ", entryPrice, 
                      " SL: ", stopLoss, " TP: ", takeProfit,
                      " Risk: ", DoubleToString(riskPoints/_Point, 1), " points");
        }
        else
        {
            if(ShowDebugInfo)
                Print("Failed to execute long trade: ", trade.ResultRetcode());
        }
    }
}

//+------------------------------------------------------------------+
//| Execute short trade                                              |
//+------------------------------------------------------------------+
void ExecuteShortTrade()
{
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stopLoss = emaValues[1] + (5 * _Point); // Above 200 EMA
    double riskPoints = stopLoss - entryPrice;
    double takeProfit = entryPrice - (riskPoints * ProfitRatio);
    
    // Normalize prices
    stopLoss = NormalizeDouble(stopLoss, _Digits);
    takeProfit = NormalizeDouble(takeProfit, _Digits);
    
    if(riskPoints > 0 && takeProfit < entryPrice)
    {
        if(trade.Sell(LotSize, _Symbol, entryPrice, stopLoss, takeProfit, "MACD-EMA Short"))
        {
            if(ShowDebugInfo)
                Print("Short trade executed. Entry: ", entryPrice, 
                      " SL: ", stopLoss, " TP: ", takeProfit,
                      " Risk: ", DoubleToString(riskPoints/_Point, 1), " points");
        }
        else
        {
            if(ShowDebugInfo)
                Print("Failed to execute short trade: ", trade.ResultRetcode());
        }
    }
}

//+------------------------------------------------------------------+
//| Draw support and resistance levels                              |
//+------------------------------------------------------------------+
void DrawSupportResistanceLevels()
{
    // Clean existing level lines
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i);
        if(StringFind(objName, "KeyLevel_") >= 0)
            ObjectDelete(0, objName);
    }
    
    // Draw current key levels
    for(int i = 0; i < keyLevelCount; i++)
    {
        if(keyLevels[i].isValid)
        {
            string objName = "KeyLevel_" + IntegerToString(i);
            
            ObjectCreate(0, objName, OBJ_HLINE, 0, TimeCurrent(), keyLevels[i].price);
            
            if(keyLevels[i].isSupport)
            {
                ObjectSetInteger(0, objName, OBJPROP_COLOR, clrBlue);
                ObjectSetString(0, objName, OBJPROP_TEXT, "Support (" + 
                               IntegerToString(keyLevels[i].touchCount) + " touches)");
            }
            else
            {
                ObjectSetInteger(0, objName, OBJPROP_COLOR, clrRed);
                ObjectSetString(0, objName, OBJPROP_TEXT, "Resistance (" + 
                               IntegerToString(keyLevels[i].touchCount) + " touches)");
            }
            
            ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
        }
    }
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
        
        if(StringFind(objName, "KeyLevel_") >= 0)
        {
            ObjectDelete(0, objName);
        }
    }
}

//+------------------------------------------------------------------+
//| Check if price is retesting a key level                         |
//+------------------------------------------------------------------+
bool IsPriceRetestingLevel(double currentPrice, bool lookingForSupport)
{
    for(int i = 0; i < keyLevelCount; i++)
    {
        if(keyLevels[i].isValid && keyLevels[i].isSupport == lookingForSupport)
        {
            double distanceToLevel = MathAbs(currentPrice - keyLevels[i].price);
            if(distanceToLevel <= RetestTolerance * _Point)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get trend direction based on 200 EMA                            |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
    double currentPrice = iClose(_Symbol, _Period, 1);
    double currentEMA = emaValues[1];
    
    if(currentPrice > currentEMA) return 1;  // Uptrend
    if(currentPrice < currentEMA) return -1; // Downtrend
    return 0; // Sideways
}