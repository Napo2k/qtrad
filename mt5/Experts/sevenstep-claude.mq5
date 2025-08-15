//+------------------------------------------------------------------+
//|                                  SevenStepBreakoutStrategy.mq5   |
//|                                    Multi-Timeframe Breakout EA   |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Learning Example"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Strategy Settings ==="
input ENUM_TIMEFRAMES HigherTimeframe = PERIOD_H1;    // Higher timeframe (H1 or H4)
input int SupportResistancePeriod = 50;               // Period for S/R identification
input double MinBreakoutSize = 10;                    // Minimum breakout size (points)
input double PullbackThreshold = 0.7;                 // Pullback threshold (0.0-1.0)

input group "=== Risk Management ==="
input double LotSize = 0.1;                          // Lot Size
input double MinRiskReward = 3.0;                     // Minimum Risk:Reward ratio
input double MaxSpread = 3;                           // Maximum Spread (points)
input int MagicNumber = 12345;                        // Magic Number

input group "=== Pattern Recognition ==="
input int ConsolidationMinBars = 5;                   // Min bars for consolidation
input int ConsolidationMaxBars = 20;                  // Max bars for consolidation
input double ConsolidationRange = 15;                 // Max consolidation range (points)
input int TrendlineTouchesMin = 3;                    // Min touches for trendline
input double TrendlineDeviation = 5;                  // Trendline deviation (points)

input group "=== Debugging ==="
input bool ShowDebugInfo = true;                      // Show debug information
input bool DrawSupportResistance = true;              // Draw S/R levels

//--- Global variables
CTrade trade;
datetime lastBarTime;

// Strategy state variables
enum STRATEGY_STATE
{
    WAITING_FOR_BREAKOUT,     // Step 1-2: Looking for breakout
    WAITING_FOR_PULLBACK,     // Step 4: Waiting for pullback
    WAITING_FOR_PATTERN,      // Step 5: Looking for entry pattern
    POSITION_OPEN            // Step 6-7: Position is open
};

STRATEGY_STATE currentState = WAITING_FOR_BREAKOUT;
double breakoutLevel = 0;
bool isResistanceBreakout = false;  // true for resistance, false for support
datetime breakoutTime = 0;
double pullbackZoneHigh = 0;
double pullbackZoneLow = 0;

// Support/Resistance arrays
double supportLevels[];
double resistanceLevels[];
int supportCount = 0;
int resistanceCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    
    // Initialize arrays
    ArrayResize(supportLevels, 10);
    ArrayResize(resistanceLevels, 10);
    
    Print("Seven-Step Breakout Strategy initialized");
    Print("Higher Timeframe: ", EnumToString(HigherTimeframe));
    
    return INIT_SUCCEEDED;
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
    
    // Execute strategy based on current state
    switch(currentState)
    {
        case WAITING_FOR_BREAKOUT:
            CheckForBreakout();
            break;
            
        case WAITING_FOR_PULLBACK:
            CheckForPullback();
            break;
            
        case WAITING_FOR_PATTERN:
            CheckForEntryPattern();
            break;
            
        case POSITION_OPEN:
            ManageOpenPosition();
            break;
    }
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
//| Step 1-2: Identify S/R zones and check for breakout            |
//+------------------------------------------------------------------+
void CheckForBreakout()
{
    // Update support/resistance levels
    UpdateSupportResistanceLevels();
    
    // Get higher timeframe data
    double htfHigh = iHigh(_Symbol, HigherTimeframe, 1);
    double htfLow = iLow(_Symbol, HigherTimeframe, 1);
    double htfClose = iClose(_Symbol, HigherTimeframe, 1);
    double htfOpen = iOpen(_Symbol, HigherTimeframe, 1);
    
    // Check for resistance breakout
    for(int i = 0; i < resistanceCount; i++)
    {
        if(resistanceLevels[i] > 0 && 
           htfClose > resistanceLevels[i] && 
           htfOpen <= resistanceLevels[i] &&
           (htfClose - resistanceLevels[i]) >= MinBreakoutSize * _Point)
        {
            breakoutLevel = resistanceLevels[i];
            isResistanceBreakout = true;
            breakoutTime = iTime(_Symbol, HigherTimeframe, 1);
            
            // Define pullback zone
            pullbackZoneHigh = breakoutLevel + (10 * _Point);
            pullbackZoneLow = breakoutLevel - (10 * _Point);
            
            currentState = WAITING_FOR_PULLBACK;
            
            if(ShowDebugInfo)
                Print("Resistance breakout detected at: ", breakoutLevel);
            
            if(DrawSupportResistance)
                DrawBreakoutLevel();
                
            break;
        }
    }
    
    // Check for support breakout
    if(currentState == WAITING_FOR_BREAKOUT)
    {
        for(int i = 0; i < supportCount; i++)
        {
            if(supportLevels[i] > 0 && 
               htfClose < supportLevels[i] && 
               htfOpen >= supportLevels[i] &&
               (supportLevels[i] - htfClose) >= MinBreakoutSize * _Point)
            {
                breakoutLevel = supportLevels[i];
                isResistanceBreakout = false;
                breakoutTime = iTime(_Symbol, HigherTimeframe, 1);
                
                // Define pullback zone
                pullbackZoneHigh = breakoutLevel + (10 * _Point);
                pullbackZoneLow = breakoutLevel - (10 * _Point);
                
                currentState = WAITING_FOR_PULLBACK;
                
                if(ShowDebugInfo)
                    Print("Support breakout detected at: ", breakoutLevel);
                
                if(DrawSupportResistance)
                    DrawBreakoutLevel();
                    
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Step 4: Wait for pullback to broken level                       |
//+------------------------------------------------------------------+
void CheckForPullback()
{
    double currentPrice = (iHigh(_Symbol, PERIOD_M1, 0) + iLow(_Symbol, PERIOD_M1, 0)) / 2;
    
    // Check if price has pulled back into the zone
    if(currentPrice >= pullbackZoneLow && currentPrice <= pullbackZoneHigh)
    {
        currentState = WAITING_FOR_PATTERN;
        
        if(ShowDebugInfo)
            Print("Pullback detected. Looking for entry pattern...");
    }
    
    // Timeout check - if too much time has passed, reset
    if(TimeCurrent() - breakoutTime > 4 * 3600) // 4 hours timeout
    {
        if(ShowDebugInfo)
            Print("Pullback timeout. Resetting strategy...");
        ResetStrategy();
    }
}

//+------------------------------------------------------------------+
//| Step 5-6: Look for entry patterns and enter trade              |
//+------------------------------------------------------------------+
void CheckForEntryPattern()
{
    // Check for consolidation pattern
    if(IsConsolidationPattern())
    {
        if(ShowDebugInfo)
            Print("Consolidation pattern detected");
        
        if(isResistanceBreakout)
            WaitForBullishBreakout();
        else
            WaitForBearishBreakout();
    }
    
    // Check for trendline pattern
    else if(IsTrendlinePattern())
    {
        if(ShowDebugInfo)
            Print("Trendline pattern detected");
        
        if(isResistanceBreakout)
            WaitForBullishBreakout();
        else
            WaitForBearishBreakout();
    }
    
    // Check for higher low / lower high pattern
    else if(IsHigherLowLowerHighPattern())
    {
        if(ShowDebugInfo)
            Print("Higher Low/Lower High pattern detected");
        
        if(isResistanceBreakout)
            WaitForBullishBreakout();
        else
            WaitForBearishBreakout();
    }
    
    // Pattern timeout
    if(TimeCurrent() - breakoutTime > 6 * 3600) // 6 hours timeout
    {
        if(ShowDebugInfo)
            Print("Pattern timeout. Resetting strategy...");
        ResetStrategy();
    }
}

//+------------------------------------------------------------------+
//| Check for consolidation pattern                                  |
//+------------------------------------------------------------------+
bool IsConsolidationPattern()
{
    double high = iHigh(_Symbol, PERIOD_M1, iHighest(_Symbol, PERIOD_M1, MODE_HIGH, ConsolidationMaxBars, 1));
    double low = iLow(_Symbol, PERIOD_M1, iLowest(_Symbol, PERIOD_M1, MODE_LOW, ConsolidationMaxBars, 1));
    
    double range = high - low;
    
    return (range <= ConsolidationRange * _Point);
}

//+------------------------------------------------------------------+
//| Check for trendline pattern                                      |
//+------------------------------------------------------------------+
bool IsTrendlinePattern()
{
    // Simplified trendline detection
    // In a full implementation, this would be more sophisticated
    
    double prices[];
    ArrayResize(prices, 10);
    
    for(int i = 0; i < 10; i++)
    {
        if(isResistanceBreakout)
            prices[i] = iLow(_Symbol, PERIOD_M1, i + 1);
        else
            prices[i] = iHigh(_Symbol, PERIOD_M1, i + 1);
    }
    
    // Simple check: at least 3 similar price levels
    int touchCount = 0;
    double avgPrice = 0;
    
    for(int i = 0; i < 10; i++)
        avgPrice += prices[i];
    avgPrice /= 10;
    
    for(int i = 0; i < 10; i++)
    {
        if(MathAbs(prices[i] - avgPrice) <= TrendlineDeviation * _Point)
            touchCount++;
    }
    
    return (touchCount >= TrendlineTouchesMin);
}

//+------------------------------------------------------------------+
//| Check for higher low / lower high pattern                       |
//+------------------------------------------------------------------+
bool IsHigherLowLowerHighPattern()
{
    if(isResistanceBreakout)
    {
        // Look for higher lows
        double low1 = iLow(_Symbol, PERIOD_M1, 3);
        double low2 = iLow(_Symbol, PERIOD_M1, 1);
        return (low2 > low1);
    }
    else
    {
        // Look for lower highs
        double high1 = iHigh(_Symbol, PERIOD_M1, 3);
        double high2 = iHigh(_Symbol, PERIOD_M1, 1);
        return (high2 < high1);
    }
}

//+------------------------------------------------------------------+
//| Wait for bullish breakout and enter long                        |
//+------------------------------------------------------------------+
void WaitForBullishBreakout()
{
    double currentHigh = iHigh(_Symbol, PERIOD_M1, 0);
    double previousHigh = iHigh(_Symbol, PERIOD_M1, iHighest(_Symbol, PERIOD_M1, MODE_HIGH, 5, 1));
    
    if(currentHigh > previousHigh)
    {
        // Calculate stop loss and take profit
        double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double stopLoss = iLow(_Symbol, PERIOD_M1, iLowest(_Symbol, PERIOD_M1, MODE_LOW, 10, 1));
        double riskPoints = entryPrice - stopLoss;
        double takeProfit = entryPrice + (riskPoints * MinRiskReward);
        
        // Check risk-reward ratio
        if((takeProfit - entryPrice) / riskPoints >= MinRiskReward)
        {
            if(trade.Buy(LotSize, _Symbol, entryPrice, stopLoss, takeProfit, "7-Step Buy"))
            {
                currentState = POSITION_OPEN;
                if(ShowDebugInfo)
                    Print("Long position opened at: ", entryPrice);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Wait for bearish breakout and enter short                       |
//+------------------------------------------------------------------+
void WaitForBearishBreakout()
{
    double currentLow = iLow(_Symbol, PERIOD_M1, 0);
    double previousLow = iLow(_Symbol, PERIOD_M1, iLowest(_Symbol, PERIOD_M1, MODE_LOW, 5, 1));
    
    if(currentLow < previousLow)
    {
        // Calculate stop loss and take profit
        double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double stopLoss = iHigh(_Symbol, PERIOD_M1, iHighest(_Symbol, PERIOD_M1, MODE_HIGH, 10, 1));
        double riskPoints = stopLoss - entryPrice;
        double takeProfit = entryPrice - (riskPoints * MinRiskReward);
        
        // Check risk-reward ratio
        if((entryPrice - takeProfit) / riskPoints >= MinRiskReward)
        {
            if(trade.Sell(LotSize, _Symbol, entryPrice, stopLoss, takeProfit, "7-Step Sell"))
            {
                currentState = POSITION_OPEN;
                if(ShowDebugInfo)
                    Print("Short position opened at: ", entryPrice);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage open position                                             |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
    // Check if position is still open
    if(PositionsTotal() == 0 || !PositionSelect(_Symbol))
    {
        if(ShowDebugInfo)
            Print("Position closed. Resetting strategy...");
        ResetStrategy();
    }
}

//+------------------------------------------------------------------+
//| Update support and resistance levels                            |
//+------------------------------------------------------------------+
void UpdateSupportResistanceLevels()
{
    supportCount = 0;
    resistanceCount = 0;
    
    // Get pivot points from higher timeframe
    for(int i = 2; i < SupportResistancePeriod; i++)
    {
        double high = iHigh(_Symbol, HigherTimeframe, i);
        double low = iLow(_Symbol, HigherTimeframe, i);
        double prevHigh = iHigh(_Symbol, HigherTimeframe, i + 1);
        double prevLow = iLow(_Symbol, HigherTimeframe, i + 1);
        double nextHigh = iHigh(_Symbol, HigherTimeframe, i - 1);
        double nextLow = iLow(_Symbol, HigherTimeframe, i - 1);
        
        // Resistance level (pivot high)
        if(high > prevHigh && high > nextHigh && resistanceCount < 10)
        {
            resistanceLevels[resistanceCount] = high;
            resistanceCount++;
        }
        
        // Support level (pivot low)
        if(low < prevLow && low < nextLow && supportCount < 10)
        {
            supportLevels[supportCount] = low;
            supportCount++;
        }
    }
    
    if(ShowDebugInfo)
        Print("Updated S/R levels: ", supportCount, " support, ", resistanceCount, " resistance");
}

//+------------------------------------------------------------------+
//| Reset strategy to initial state                                 |
//+------------------------------------------------------------------+
void ResetStrategy()
{
    currentState = WAITING_FOR_BREAKOUT;
    breakoutLevel = 0;
    isResistanceBreakout = false;
    breakoutTime = 0;
    pullbackZoneHigh = 0;
    pullbackZoneLow = 0;
}

//+------------------------------------------------------------------+
//| Draw breakout level on chart                                     |
//+------------------------------------------------------------------+
void DrawBreakoutLevel()
{
    string objName = "BreakoutLevel_" + TimeToString(TimeCurrent());
    
    ObjectCreate(0, objName, OBJ_HLINE, 0, TimeCurrent(), breakoutLevel);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, isResistanceBreakout ? clrRed : clrBlue);
    ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASH);
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
}