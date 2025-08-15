//+------------------------------------------------------------------+
//|                              MarketStructureSupplyDemand.mq5    |
//|                           Market Structure & S/D Zone Strategy  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Market Structure S/D"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Strategy Settings ==="
input ENUM_TIMEFRAMES AnalysisTimeframe = PERIOD_H1;  // Analysis timeframe
input int StructurePeriod = 50;                       // Bars to analyze for structure
input double MinImpulsiveMove = 50;                   // Min points for impulsive move
input double ZoneBuffer = 5;                          // Zone buffer (points)

input group "=== Risk Management ==="
input double LotSize = 0.1;                          // Lot Size
input double MinRiskReward = 2.5;                     // Minimum Risk:Reward ratio
input double MaxSpread = 3;                           // Maximum Spread (points)
input int MagicNumber = 102245;                        // Magic Number

input group "=== Zone Settings ==="
input int MaxZones = 5;                               // Maximum zones to track
input double ZoneValidityHours = 24;                  // Zone validity (hours)
input bool RequireZoneRetest = true;                  // Require zone retest for entry

input group "=== Display Settings ==="
input bool ShowDebugInfo = true;                      // Show debug information
input bool DrawZones = true;                          // Draw supply/demand zones
input bool DrawStructure = true;                      // Draw market structure

//--- Global variables
CTrade trade;
datetime lastBarTime;

// Market structure variables
enum TREND_STATE
{
    TREND_UPTREND,
    TREND_DOWNTREND,
    TREND_SIDEWAYS
};

TREND_STATE currentTrend = TREND_SIDEWAYS;
double lastValidHigh = 0;
double lastValidLow = 0;
datetime lastValidHighTime = 0;
datetime lastValidLowTime = 0;

// Supply/Demand zone structure
struct SupplyDemandZone
{
    double zoneHigh;
    double zoneLow;
    datetime zoneTime;
    bool isSupplyZone;     // true = supply, false = demand
    bool isValid;
    bool hasBeenTested;
    int touchCount;
};

SupplyDemandZone zones[];
int zoneCount = 0;

// Swing points structure
struct SwingPoint
{
    double price;
    datetime time;
    bool isHigh;           // true = swing high, false = swing low
    bool isValidated;
};

SwingPoint swingPoints[];
int swingCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    
    // Initialize arrays
    ArrayResize(zones, MaxZones);
    ArrayResize(swingPoints, 100);
    
    // Initialize zones
    for(int i = 0; i < MaxZones; i++)
    {
        zones[i].isValid = false;
        zones[i].hasBeenTested = false;
        zones[i].touchCount = 0;
    }
    
    Print("Market Structure & Supply/Demand Strategy initialized");
    Print("Analysis Timeframe: ", EnumToString(AnalysisTimeframe));
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Clean up chart objects
    if(DrawZones || DrawStructure)
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
    
    // Step 1: Analyze market structure
    AnalyzeMarketStructure();
    
    // Step 2: Identify and update supply/demand zones
    IdentifySupplyDemandZones();
    
    // Step 3: Look for trading opportunities
    CheckTradingOpportunities();
    
    // Update visual elements
    if(DrawStructure) DrawMarketStructure();
    if(DrawZones) DrawSupplyDemandZones();
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentBarTime = iTime(_Symbol, AnalysisTimeframe, 0);
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Step 1: Analyze market structure                                |
//+------------------------------------------------------------------+
void AnalyzeMarketStructure()
{
    // Find swing points
    FindSwingPoints();
    
    // Validate swing points and determine trend
    ValidateSwingPoints();
    
    // Determine current trend
    DetermineTrend();
    
    if(ShowDebugInfo)
        Print("Current Trend: ", EnumToString(currentTrend), 
              " | Last Valid High: ", lastValidHigh, 
              " | Last Valid Low: ", lastValidLow);
}

//+------------------------------------------------------------------+
//| Find swing points (highs and lows)                              |
//+------------------------------------------------------------------+
void FindSwingPoints()
{
    swingCount = 0;
    
    for(int i = 2; i < StructurePeriod - 2; i++)
    {
        double high = iHigh(_Symbol, AnalysisTimeframe, i);
        double low = iLow(_Symbol, AnalysisTimeframe, i);
        double prevHigh = iHigh(_Symbol, AnalysisTimeframe, i + 1);
        double prevLow = iLow(_Symbol, AnalysisTimeframe, i + 1);
        double nextHigh = iHigh(_Symbol, AnalysisTimeframe, i - 1);
        double nextLow = iLow(_Symbol, AnalysisTimeframe, i - 1);
        datetime barTime = iTime(_Symbol, AnalysisTimeframe, i);
        
        // Swing high
        if(high > prevHigh && high > nextHigh && swingCount < ArraySize(swingPoints) - 1)
        {
            swingPoints[swingCount].price = high;
            swingPoints[swingCount].time = barTime;
            swingPoints[swingCount].isHigh = true;
            swingPoints[swingCount].isValidated = false;
            swingCount++;
        }
        
        // Swing low
        if(low < prevLow && low < nextLow && swingCount < ArraySize(swingPoints) - 1)
        {
            swingPoints[swingCount].price = low;
            swingPoints[swingCount].time = barTime;
            swingPoints[swingCount].isHigh = false;
            swingPoints[swingCount].isValidated = false;
            swingCount++;
        }
    }
    
    // Sort swing points by time (most recent first)
    SortSwingPointsByTime();
}

//+------------------------------------------------------------------+
//| Sort swing points by time                                        |
//+------------------------------------------------------------------+
void SortSwingPointsByTime()
{
    for(int i = 0; i < swingCount - 1; i++)
    {
        for(int j = i + 1; j < swingCount; j++)
        {
            if(swingPoints[i].time < swingPoints[j].time)
            {
                SwingPoint temp = swingPoints[i];
                swingPoints[i] = swingPoints[j];
                swingPoints[j] = temp;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Validate swing points according to market structure rules       |
//+------------------------------------------------------------------+
void ValidateSwingPoints()
{
    for(int i = 0; i < swingCount; i++)
    {
        if(swingPoints[i].isHigh)
        {
            // High is validated if price breaks previous low
            for(int j = i + 1; j < swingCount; j++)
            {
                if(!swingPoints[j].isHigh) // Found a previous low
                {
                    double currentLow = iLow(_Symbol, AnalysisTimeframe, 1);
                    if(currentLow < swingPoints[j].price)
                    {
                        swingPoints[i].isValidated = true;
                        if(swingPoints[i].price > lastValidHigh || lastValidHigh == 0)
                        {
                            lastValidHigh = swingPoints[i].price;
                            lastValidHighTime = swingPoints[i].time;
                        }
                    }
                    break;
                }
            }
        }
        else
        {
            // Low is validated if price breaks previous high
            for(int j = i + 1; j < swingCount; j++)
            {
                if(swingPoints[j].isHigh) // Found a previous high
                {
                    double currentHigh = iHigh(_Symbol, AnalysisTimeframe, 1);
                    if(currentHigh > swingPoints[j].price)
                    {
                        swingPoints[i].isValidated = true;
                        if(swingPoints[i].price < lastValidLow || lastValidLow == 0)
                        {
                            lastValidLow = swingPoints[i].price;
                            lastValidLowTime = swingPoints[i].time;
                        }
                    }
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Determine current trend based on validated swing points         |
//+------------------------------------------------------------------+
void DetermineTrend()
{
    double currentPrice = iClose(_Symbol, AnalysisTimeframe, 1);
    
    // Check if we're in an uptrend
    if(lastValidLow > 0 && currentPrice > lastValidLow)
    {
        // Check if the valid low hasn't been broken
        bool lowBroken = false;
        for(int i = 1; i < 10; i++) // Check last 10 bars
        {
            if(iLow(_Symbol, AnalysisTimeframe, i) < lastValidLow)
            {
                lowBroken = true;
                break;
            }
        }
        
        if(!lowBroken)
            currentTrend = TREND_UPTREND;
        else
            currentTrend = TREND_SIDEWAYS;
    }
    // Check if we're in a downtrend
    else if(lastValidHigh > 0 && currentPrice < lastValidHigh)
    {
        // Check if the valid high hasn't been broken
        bool highBroken = false;
        for(int i = 1; i < 10; i++) // Check last 10 bars
        {
            if(iHigh(_Symbol, AnalysisTimeframe, i) > lastValidHigh)
            {
                highBroken = true;
                break;
            }
        }
        
        if(!highBroken)
            currentTrend = TREND_DOWNTREND;
        else
            currentTrend = TREND_SIDEWAYS;
    }
    else
    {
        currentTrend = TREND_SIDEWAYS;
    }
}

//+------------------------------------------------------------------+
//| Step 2: Identify supply and demand zones                        |
//+------------------------------------------------------------------+
void IdentifySupplyDemandZones()
{
    // Clean expired zones
    CleanExpiredZones();
    
    // Look for new zones
    for(int i = 2; i < 20; i++) // Check recent bars
    {
        // Look for impulsive moves
        double move = MathAbs(iClose(_Symbol, AnalysisTimeframe, i-1) - 
                             iClose(_Symbol, AnalysisTimeframe, i+1));
        
        if(move >= MinImpulsiveMove * _Point)
        {
            // Determine if it's bullish or bearish impulsive move
            bool isBullishMove = iClose(_Symbol, AnalysisTimeframe, i-1) > 
                                iClose(_Symbol, AnalysisTimeframe, i+1);
            
            if(isBullishMove && currentTrend == TREND_UPTREND)
            {
                // Create demand zone
                CreateDemandZone(i);
            }
            else if(!isBullishMove && currentTrend == TREND_DOWNTREND)
            {
                // Create supply zone
                CreateSupplyZone(i);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Create demand zone                                               |
//+------------------------------------------------------------------+
void CreateDemandZone(int barIndex)
{
    // Find an available zone slot
    int zoneIndex = -1;
    for(int i = 0; i < MaxZones; i++)
    {
        if(!zones[i].isValid)
        {
            zoneIndex = i;
            break;
        }
    }
    
    if(zoneIndex == -1) return; // No available slots
    
    // Define zone based on the consolidation before the move
    double zoneLow = iLow(_Symbol, AnalysisTimeframe, barIndex + 1);
    double zoneHigh = iHigh(_Symbol, AnalysisTimeframe, barIndex + 1);
    
    // Extend zone slightly for buffer
    zoneLow -= ZoneBuffer * _Point;
    zoneHigh += ZoneBuffer * _Point;
    
    zones[zoneIndex].zoneLow = zoneLow;
    zones[zoneIndex].zoneHigh = zoneHigh;
    zones[zoneIndex].zoneTime = iTime(_Symbol, AnalysisTimeframe, barIndex);
    zones[zoneIndex].isSupplyZone = false;
    zones[zoneIndex].isValid = true;
    zones[zoneIndex].hasBeenTested = false;
    zones[zoneIndex].touchCount = 0;
    
    if(ShowDebugInfo)
        Print("Demand zone created: ", zoneLow, " - ", zoneHigh);
}

//+------------------------------------------------------------------+
//| Create supply zone                                               |
//+------------------------------------------------------------------+
void CreateSupplyZone(int barIndex)
{
    // Find an available zone slot
    int zoneIndex = -1;
    for(int i = 0; i < MaxZones; i++)
    {
        if(!zones[i].isValid)
        {
            zoneIndex = i;
            break;
        }
    }
    
    if(zoneIndex == -1) return; // No available slots
    
    // Define zone based on the consolidation before the move
    double zoneLow = iLow(_Symbol, AnalysisTimeframe, barIndex + 1);
    double zoneHigh = iHigh(_Symbol, AnalysisTimeframe, barIndex + 1);
    
    // Extend zone slightly for buffer
    zoneLow -= ZoneBuffer * _Point;
    zoneHigh += ZoneBuffer * _Point;
    
    zones[zoneIndex].zoneLow = zoneLow;
    zones[zoneIndex].zoneHigh = zoneHigh;
    zones[zoneIndex].zoneTime = iTime(_Symbol, AnalysisTimeframe, barIndex);
    zones[zoneIndex].isSupplyZone = true;
    zones[zoneIndex].isValid = true;
    zones[zoneIndex].hasBeenTested = false;
    zones[zoneIndex].touchCount = 0;
    
    if(ShowDebugInfo)
        Print("Supply zone created: ", zoneLow, " - ", zoneHigh);
}

//+------------------------------------------------------------------+
//| Clean expired zones                                              |
//+------------------------------------------------------------------+
void CleanExpiredZones()
{
    datetime currentTime = TimeCurrent();
    
    for(int i = 0; i < MaxZones; i++)
    {
        if(zones[i].isValid)
        {
            // Check if zone has expired
            if((currentTime - zones[i].zoneTime) > ZoneValidityHours * 3600)
            {
                zones[i].isValid = false;
                if(ShowDebugInfo)
                    Print("Zone expired: ", zones[i].zoneLow, " - ", zones[i].zoneHigh);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Step 3: Check for trading opportunities                         |
//+------------------------------------------------------------------+
void CheckTradingOpportunities()
{
    // Don't trade if we already have an open position
    if(PositionSelect(_Symbol)) return;
    
    double currentPrice = iClose(_Symbol, AnalysisTimeframe, 1);
    
    // Check each valid zone
    for(int i = 0; i < MaxZones; i++)
    {
        if(!zones[i].isValid) continue;
        
        // Check if price is in the zone
        if(currentPrice >= zones[i].zoneLow && currentPrice <= zones[i].zoneHigh)
        {
            zones[i].touchCount++;
            
            // Only trade demand zones in uptrend and supply zones in downtrend
            if(!zones[i].isSupplyZone && currentTrend == TREND_UPTREND)
            {
                // Demand zone in uptrend - look for long entry
                if(!RequireZoneRetest || zones[i].hasBeenTested)
                {
                    CheckLongEntry(i);
                }
                else
                {
                    zones[i].hasBeenTested = true;
                }
            }
            else if(zones[i].isSupplyZone && currentTrend == TREND_DOWNTREND)
            {
                // Supply zone in downtrend - look for short entry
                if(!RequireZoneRetest || zones[i].hasBeenTested)
                {
                    CheckShortEntry(i);
                }
                else
                {
                    zones[i].hasBeenTested = true;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for long entry                                             |
//+------------------------------------------------------------------+
void CheckLongEntry(int zoneIndex)
{
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double stopLoss = zones[zoneIndex].zoneLow - (5 * _Point);
    double takeProfit = lastValidHigh; // Target recent high
    
    // Calculate risk-reward ratio
    double riskPoints = entryPrice - stopLoss;
    double rewardPoints = takeProfit - entryPrice;
    double riskReward = rewardPoints / riskPoints;
    
    if(riskReward >= MinRiskReward && riskPoints > 0)
    {
        if(trade.Buy(LotSize, _Symbol, entryPrice, stopLoss, takeProfit, "Market-Sd Long"))
        {
            if(ShowDebugInfo)
                Print("Long position opened. Entry: ", entryPrice, 
                      " SL: ", stopLoss, " TP: ", takeProfit, 
                      " R:R: ", DoubleToString(riskReward, 2));
            
            // Invalidate the zone after use
            zones[zoneIndex].isValid = false;
        }
    }
    else if(ShowDebugInfo)
    {
        Print("Long trade rejected. R:R: ", DoubleToString(riskReward, 2), 
              " (Min required: ", MinRiskReward, ")");
    }
}

//+------------------------------------------------------------------+
//| Check for short entry                                            |
//+------------------------------------------------------------------+
void CheckShortEntry(int zoneIndex)
{
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stopLoss = zones[zoneIndex].zoneHigh + (5 * _Point);
    double takeProfit = lastValidLow; // Target recent low
    
    // Calculate risk-reward ratio
    double riskPoints = stopLoss - entryPrice;
    double rewardPoints = entryPrice - takeProfit;
    double riskReward = rewardPoints / riskPoints;
    
    if(riskReward >= MinRiskReward && riskPoints > 0)
    {
        if(trade.Sell(LotSize, _Symbol, entryPrice, stopLoss, takeProfit, "Market-Sd Short"))
        {
            if(ShowDebugInfo)
                Print("Short position opened. Entry: ", entryPrice, 
                      " SL: ", stopLoss, " TP: ", takeProfit, 
                      " R:R: ", DoubleToString(riskReward, 2));
            
            // Invalidate the zone after use
            zones[zoneIndex].isValid = false;
        }
    }
    else if(ShowDebugInfo)
    {
        Print("Short trade rejected. R:R: ", DoubleToString(riskReward, 2), 
              " (Min required: ", MinRiskReward, ")");
    }
}

//+------------------------------------------------------------------+
//| Draw market structure on chart                                   |
//+------------------------------------------------------------------+
void DrawMarketStructure()
{
    // Draw validated swing points
    for(int i = 0; i < swingCount && i < 10; i++)
    {
        if(swingPoints[i].isValidated)
        {
            string objName = "SwingPoint_" + IntegerToString(i);
            
            if(swingPoints[i].isHigh)
            {
                ObjectCreate(0, objName, OBJ_ARROW_DOWN, 0, 
                           swingPoints[i].time, swingPoints[i].price);
                ObjectSetInteger(0, objName, OBJPROP_COLOR, clrRed);
            }
            else
            {
                ObjectCreate(0, objName, OBJ_ARROW_UP, 0, 
                           swingPoints[i].time, swingPoints[i].price);
                ObjectSetInteger(0, objName, OBJPROP_COLOR, clrBlue);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Draw supply and demand zones                                     |
//+------------------------------------------------------------------+
void DrawSupplyDemandZones()
{
    for(int i = 0; i < MaxZones; i++)
    {
        if(zones[i].isValid)
        {
            string objName = "Zone_" + IntegerToString(i);
            
            ObjectCreate(0, objName, OBJ_RECTANGLE, 0, 
                        zones[i].zoneTime, zones[i].zoneHigh,
                        TimeCurrent() + PeriodSeconds(AnalysisTimeframe) * 20, 
                        zones[i].zoneLow);
            
            if(zones[i].isSupplyZone)
            {
                ObjectSetInteger(0, objName, OBJPROP_COLOR, clrRed);
                ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, clrLightPink);
            }
            else
            {
                ObjectSetInteger(0, objName, OBJPROP_COLOR, clrBlue);
                ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, clrLightBlue);
            }
            
            ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, objName, OBJPROP_FILL, true);
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
        
        if(StringFind(objName, "SwingPoint_") >= 0 || 
           StringFind(objName, "Zone_") >= 0)
        {
            ObjectDelete(0, objName);
        }
    }
}