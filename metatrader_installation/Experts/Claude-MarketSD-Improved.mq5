//+------------------------------------------------------------------+
//|                         EnhancedMarketStructureSupplyDemand.mq5 |
//|                           Enhanced Market Structure & S/D Zone  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Enhanced Market Structure S/D"
#property link      ""
#property version   "2.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Strategy Settings ==="
input ENUM_TIMEFRAMES AnalysisTimeframe = PERIOD_H1;
input ENUM_TIMEFRAMES EntryTimeframe = PERIOD_M15;     // NEW: Entry timeframe
input int StructurePeriod = 50;
input double MinImpulsiveMove = 50;
input double ZoneBuffer = 5;
input int MinZoneBars = 3;                             // NEW: Min bars for zone formation
input double MinZoneStrength = 0.6;                   // NEW: Min zone strength (0-1)

input group "=== Risk Management ==="
input double RiskPercent = 1.0;                       // NEW: Risk per trade (%)
input double MinRiskReward = 2.0;
input double MaxRiskReward = 10.0;                     // NEW: Max R:R to avoid unrealistic targets
input double MaxSpread = 3;
input int MagicNumber = 100145;
input bool UseATRStops = true;                         // NEW: Use ATR-based stops
input double ATRMultiplier = 1.5;                     // NEW: ATR multiplier for stops

input group "=== Zone Settings ==="
input int MaxZones = 10;                               // Increased from 5
input double ZoneValidityHours = 48;                   // Increased from 24
input bool RequireZoneRetest = true;
input int MaxZoneRetests = 3;                          // NEW: Max retests before zone expires
input bool UseZoneStrength = true;                     // NEW: Filter zones by strength

input group "=== Confluence Settings ==="              // NEW: Confluence filters
input bool UseMovingAverageFilter = true;
input ENUM_MA_METHOD MA_Method = MODE_EMA;
input int MA_Period = 50;
input bool UseFibonacciLevels = true;
input bool UseVolumeFilter = false;                    // Set to false if volume not available

input group "=== Display Settings ==="
input bool ShowDebugInfo = true;
input bool DrawZones = true;
input bool DrawStructure = true;
input bool ShowZoneInfo = true;                        // NEW: Show zone information
input bool ShowRiskReward = true;                      // NEW: Show R:R on chart

//--- Global variables
CTrade trade;
datetime lastBarTime;
int atrHandle;
int maHandle;

// Enhanced market structure variables
enum TREND_STATE
{
    TREND_UPTREND,
    TREND_DOWNTREND,
    TREND_SIDEWAYS
};

enum ZONE_QUALITY                                      // NEW: Zone quality rating
{
    ZONE_WEAK,
    ZONE_MEDIUM,
    ZONE_STRONG
};

TREND_STATE currentTrend = TREND_SIDEWAYS;
double lastValidHigh = 0;
double lastValidLow = 0;
datetime lastValidHighTime = 0;
datetime lastValidLowTime = 0;
bool structureBroken = false;                          // NEW: Track structure breaks

// Enhanced Supply/Demand zone structure
struct SupplyDemandZone
{
    double zoneHigh;
    double zoneLow;
    datetime zoneTime;
    bool isSupplyZone;
    bool isValid;
    bool hasBeenTested;
    int touchCount;
    int retestCount;                                   // NEW: Track retests
    double strength;                                   // NEW: Zone strength (0-1)
    ZONE_QUALITY quality;                             // NEW: Zone quality
    double volume;                                    // NEW: Zone formation volume
    bool isRespected;                                 // NEW: Track if zone held on retest
};

SupplyDemandZone zones[];

// Enhanced swing points structure
struct SwingPoint
{
    double price;
    datetime time;
    bool isHigh;
    bool isValidated;
    double strength;                                  // NEW: Swing point strength
    bool isMajor;                                    // NEW: Major vs minor swing
};

SwingPoint swingPoints[];
int swingCount = 0;

// NEW: Trade management structure
struct TradeInfo
{
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double riskReward;
    int zoneIndex;
    datetime entryTime;
};

TradeInfo currentTrade;
bool inTrade = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    
    // Initialize indicators
    atrHandle = iATR(_Symbol, AnalysisTimeframe, 14);
    if(UseMovingAverageFilter)
        maHandle = iMA(_Symbol, AnalysisTimeframe, MA_Period, 0, MA_Method, PRICE_CLOSE);
    
    // Initialize arrays
    ArrayResize(zones, MaxZones);
    ArrayResize(swingPoints, 200);                    // Increased size
    
    // Initialize zones
    for(int i = 0; i < MaxZones; i++)
    {
        zones[i].isValid = false;
        zones[i].hasBeenTested = false;
        zones[i].touchCount = 0;
        zones[i].retestCount = 0;
        zones[i].strength = 0;
        zones[i].quality = ZONE_WEAK;
        zones[i].isRespected = true;
    }
    
    Print("Enhanced Market Structure & Supply/Demand Strategy initialized");
    Print("Analysis TF: ", EnumToString(AnalysisTimeframe), " | Entry TF: ", EnumToString(EntryTimeframe));
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
    if(maHandle != INVALID_HANDLE) IndicatorRelease(maHandle);
    
    if(DrawZones || DrawStructure)
        CleanupChartObjects();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Manage existing trades
    if(inTrade)
        ManageOpenTrade();
    
    // Check if new bar formed on analysis timeframe
    if(!IsNewBar(AnalysisTimeframe)) return;
    
    // Check spread condition
    if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > MaxSpread) return;
    
    // Step 1: Analyze market structure
    AnalyzeMarketStructure();
    
    // Step 2: Identify and update supply/demand zones
    IdentifySupplyDemandZones();
    
    // Step 3: Update zone quality and strength
    UpdateZoneQuality();
    
    // Step 4: Look for trading opportunities (on entry timeframe)
    if(IsNewBar(EntryTimeframe))
        CheckTradingOpportunities();
    
    // Update visual elements
    if(DrawStructure) DrawMarketStructure();
    if(DrawZones) DrawSupplyDemandZones();
}

//+------------------------------------------------------------------+
//| Check if new bar formed for specific timeframe                  |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
    static datetime lastBarTimes[];
    static bool initialized = false;
    
    if(!initialized)
    {
        ArrayResize(lastBarTimes, 2);
        lastBarTimes[0] = 0; // Analysis timeframe
        lastBarTimes[1] = 0; // Entry timeframe
        initialized = true;
    }
    
    int index = (timeframe == AnalysisTimeframe) ? 0 : 1;
    datetime currentBarTime = iTime(_Symbol, timeframe, 0);
    
    if(currentBarTime != lastBarTimes[index])
    {
        lastBarTimes[index] = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Enhanced market structure analysis                               |
//+------------------------------------------------------------------+
void AnalyzeMarketStructure()
{
    FindSwingPoints();
    ValidateSwingPoints();
    DetermineTrend();
    CheckStructureBreak();                            // NEW: Check for structure breaks
    
    if(ShowDebugInfo)
        Print("Trend: ", EnumToString(currentTrend), 
              " | Structure Broken: ", structureBroken,
              " | Valid High: ", lastValidHigh, 
              " | Valid Low: ", lastValidLow);
}

//+------------------------------------------------------------------+
//| Enhanced swing point detection                                   |
//+------------------------------------------------------------------+
void FindSwingPoints()
{
    swingCount = 0;
    
    for(int i = 3; i < StructurePeriod - 3; i++)      // Increased lookback
    {
        double high = iHigh(_Symbol, AnalysisTimeframe, i);
        double low = iLow(_Symbol, AnalysisTimeframe, i);
        datetime barTime = iTime(_Symbol, AnalysisTimeframe, i);
        
        // More robust swing high detection
        bool isSwingHigh = true;
        for(int j = 1; j <= 3; j++)
        {
            if(high <= iHigh(_Symbol, AnalysisTimeframe, i + j) || 
               high <= iHigh(_Symbol, AnalysisTimeframe, i - j))
            {
                isSwingHigh = false;
                break;
            }
        }
        
        // More robust swing low detection  
        bool isSwingLow = true;
        for(int j = 1; j <= 3; j++)
        {
            if(low >= iLow(_Symbol, AnalysisTimeframe, i + j) || 
               low >= iLow(_Symbol, AnalysisTimeframe, i - j))
            {
                isSwingLow = false;
                break;
            }
        }
        
        if(isSwingHigh && swingCount < ArraySize(swingPoints) - 1)
        {
            swingPoints[swingCount].price = high;
            swingPoints[swingCount].time = barTime;
            swingPoints[swingCount].isHigh = true;
            swingPoints[swingCount].isValidated = false;
            swingPoints[swingCount].strength = CalculateSwingStrength(i, true);
            swingPoints[swingCount].isMajor = (swingPoints[swingCount].strength > 0.7);
            swingCount++;
        }
        
        if(isSwingLow && swingCount < ArraySize(swingPoints) - 1)
        {
            swingPoints[swingCount].price = low;
            swingPoints[swingCount].time = barTime;
            swingPoints[swingCount].isHigh = false;
            swingPoints[swingCount].isValidated = false;
            swingPoints[swingCount].strength = CalculateSwingStrength(i, false);
            swingPoints[swingCount].isMajor = (swingPoints[swingCount].strength > 0.7);
            swingCount++;
        }
    }
    
    SortSwingPointsByTime();
}

//+------------------------------------------------------------------+
//| Calculate swing point strength                                   |
//+------------------------------------------------------------------+
double CalculateSwingStrength(int barIndex, bool isHigh)
{
    double strength = 0.0;
    double price = isHigh ? iHigh(_Symbol, AnalysisTimeframe, barIndex) : 
                           iLow(_Symbol, AnalysisTimeframe, barIndex);
    
    // Factor 1: Distance from surrounding bars
    double avgDistance = 0;
    int count = 0;
    for(int i = 1; i <= 5; i++)
    {
        if(barIndex + i < iBars(_Symbol, AnalysisTimeframe) && barIndex - i >= 0)
        {
            double comparePrice = isHigh ? iHigh(_Symbol, AnalysisTimeframe, barIndex + i) :
                                         iLow(_Symbol, AnalysisTimeframe, barIndex + i);
            avgDistance += MathAbs(price - comparePrice);
            
            comparePrice = isHigh ? iHigh(_Symbol, AnalysisTimeframe, barIndex - i) :
                                  iLow(_Symbol, AnalysisTimeframe, barIndex - i);
            avgDistance += MathAbs(price - comparePrice);
            count += 2;
        }
    }
    if(count > 0) strength += (avgDistance / count) / _Point / 100; // Normalize
    
    // Factor 2: Volume (if available)
    if(UseVolumeFilter)
    {
        long volume = iVolume(_Symbol, AnalysisTimeframe, barIndex);
        long avgVolume = 0;
        for(int i = 1; i <= 10; i++)
            avgVolume += iVolume(_Symbol, AnalysisTimeframe, barIndex + i);
        avgVolume /= 10;
        
        if(avgVolume > 0)
            strength += (double)volume / avgVolume * 0.3;
    }
    
    return MathMin(strength, 1.0);
}

//+------------------------------------------------------------------+
//| Check for structure breaks                                       |
//+------------------------------------------------------------------+
void CheckStructureBreak()
{
    structureBroken = false;
    double currentPrice = iClose(_Symbol, AnalysisTimeframe, 1);
    
    if(currentTrend == TREND_UPTREND && lastValidLow > 0)
    {
        if(currentPrice < lastValidLow)
        {
            structureBroken = true;
            InvalidateZonesByTrend(false); // Invalidate demand zones
        }
    }
    else if(currentTrend == TREND_DOWNTREND && lastValidHigh > 0)
    {
        if(currentPrice > lastValidHigh)
        {
            structureBroken = true;
            InvalidateZonesByTrend(true); // Invalidate supply zones
        }
    }
}

//+------------------------------------------------------------------+
//| Invalidate zones when structure breaks                           |
//+------------------------------------------------------------------+
void InvalidateZonesByTrend(bool invalidateSupply)
{
    for(int i = 0; i < MaxZones; i++)
    {
        if(zones[i].isValid && zones[i].isSupplyZone == invalidateSupply)
        {
            zones[i].isValid = false;
            if(ShowDebugInfo)
                Print("Zone invalidated due to structure break: ", 
                      zones[i].zoneLow, " - ", zones[i].zoneHigh);
        }
    }
}

//+------------------------------------------------------------------+
//| Enhanced zone identification                                      |
//+------------------------------------------------------------------+
void IdentifySupplyDemandZones()
{
    CleanExpiredZones();
    
    for(int i = MinZoneBars; i < 30; i++)
    {
        if(IsImpulsiveMove(i))
        {
            double zoneStrength = CalculateZoneStrength(i);
            if(zoneStrength >= MinZoneStrength)
            {
                bool isBullishMove = iClose(_Symbol, AnalysisTimeframe, i-1) > 
                                   iClose(_Symbol, AnalysisTimeframe, i+1);
                
                if(isBullishMove && (currentTrend == TREND_UPTREND || currentTrend == TREND_SIDEWAYS))
                {
                    CreateEnhancedDemandZone(i, zoneStrength);
                }
                else if(!isBullishMove && (currentTrend == TREND_DOWNTREND || currentTrend == TREND_SIDEWAYS))
                {
                    CreateEnhancedSupplyZone(i, zoneStrength);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if move is impulsive                                       |
//+------------------------------------------------------------------+
bool IsImpulsiveMove(int barIndex)
{
    double move = MathAbs(iClose(_Symbol, AnalysisTimeframe, barIndex-1) - 
                         iOpen(_Symbol, AnalysisTimeframe, barIndex+MinZoneBars));
    
    // Check if move is significant
    if(move < MinImpulsiveMove * _Point) return false;
    
    // Check if move happened quickly (impulsive characteristic)
    double timeMove = move / (MinZoneBars + 1);
    double avgMove = 0;
    for(int i = 0; i < 20; i++)
    {
        avgMove += MathAbs(iClose(_Symbol, AnalysisTimeframe, barIndex + i + 10) - 
                          iOpen(_Symbol, AnalysisTimeframe, barIndex + i + 10));
    }
    avgMove /= 20;
    
    return timeMove > avgMove * 1.5; // Move should be 50% faster than average
}

//+------------------------------------------------------------------+
//| Calculate zone strength                                           |
//+------------------------------------------------------------------+
double CalculateZoneStrength(int barIndex)
{
    double strength = 0.0;
    
    // Factor 1: Size of impulsive move
    double move = MathAbs(iClose(_Symbol, AnalysisTimeframe, barIndex-1) - 
                         iOpen(_Symbol, AnalysisTimeframe, barIndex+MinZoneBars));
    double avgMove = 0;
    for(int i = 10; i < 30; i++)
    {
        avgMove += MathAbs(iClose(_Symbol, AnalysisTimeframe, barIndex + i) - 
                          iOpen(_Symbol, AnalysisTimeframe, barIndex + i));
    }
    avgMove /= 20;
    
    if(avgMove > 0)
        strength += MathMin((move / avgMove) * 0.3, 0.5);
    
    // Factor 2: Volume at zone formation
    if(UseVolumeFilter)
    {
        long zoneVolume = 0;
        long avgVolume = 0;
        
        for(int i = 0; i < MinZoneBars; i++)
        {
            zoneVolume += iVolume(_Symbol, AnalysisTimeframe, barIndex + i);
            avgVolume += iVolume(_Symbol, AnalysisTimeframe, barIndex + i + 10);
        }
        
        if(avgVolume > 0)
            strength += MathMin((double)zoneVolume / avgVolume * 0.2, 0.3);
    }
    
    // Factor 3: Time spent in consolidation
    double consolidationSize = 0;
    for(int i = 1; i <= MinZoneBars; i++)
    {
        consolidationSize += iHigh(_Symbol, AnalysisTimeframe, barIndex + i) - 
                            iLow(_Symbol, AnalysisTimeframe, barIndex + i);
    }
    consolidationSize /= MinZoneBars;
    
    if(consolidationSize > 0 && move > 0)
    {
        double ratio = consolidationSize / move;
        if(ratio < 0.3) // Tight consolidation before move
            strength += 0.2;
    }
    
    return MathMin(strength, 1.0);
}

//+------------------------------------------------------------------+
//| Create enhanced demand zone                                       |
//+------------------------------------------------------------------+
void CreateEnhancedDemandZone(int barIndex, double strength)
{
    int zoneIndex = FindAvailableZoneSlot();
    if(zoneIndex == -1) return;
    
    // Find the consolidation area
    double zoneLow = DBL_MAX;
    double zoneHigh = 0;
    
    for(int i = 1; i <= MinZoneBars; i++)
    {
        zoneLow = MathMin(zoneLow, iLow(_Symbol, AnalysisTimeframe, barIndex + i));
        zoneHigh = MathMax(zoneHigh, iHigh(_Symbol, AnalysisTimeframe, barIndex + i));
    }
    
    // Apply buffer
    zoneLow -= ZoneBuffer * _Point;
    zoneHigh += ZoneBuffer * _Point;
    
    // Calculate volume if available
    long volume = 0;
    if(UseVolumeFilter)
    {
        for(int i = 1; i <= MinZoneBars; i++)
            volume += iVolume(_Symbol, AnalysisTimeframe, barIndex + i);
    }
    
    zones[zoneIndex].zoneLow = zoneLow;
    zones[zoneIndex].zoneHigh = zoneHigh;
    zones[zoneIndex].zoneTime = iTime(_Symbol, AnalysisTimeframe, barIndex);
    zones[zoneIndex].isSupplyZone = false;
    zones[zoneIndex].isValid = true;
    zones[zoneIndex].hasBeenTested = false;
    zones[zoneIndex].touchCount = 0;
    zones[zoneIndex].retestCount = 0;
    zones[zoneIndex].strength = strength;
    zones[zoneIndex].volume = volume;
    zones[zoneIndex].isRespected = true;
    
    // Determine quality
    if(strength >= 0.8) zones[zoneIndex].quality = ZONE_STRONG;
    else if(strength >= 0.6) zones[zoneIndex].quality = ZONE_MEDIUM;
    else zones[zoneIndex].quality = ZONE_WEAK;
    
    if(ShowDebugInfo)
        Print("Enhanced Demand zone created: ", zoneLow, " - ", zoneHigh, 
              " | Strength: ", DoubleToString(strength, 2),
              " | Quality: ", EnumToString(zones[zoneIndex].quality));
}

//+------------------------------------------------------------------+
//| Create enhanced supply zone                                       |
//+------------------------------------------------------------------+
void CreateEnhancedSupplyZone(int barIndex, double strength)
{
    int zoneIndex = FindAvailableZoneSlot();
    if(zoneIndex == -1) return;
    
    // Find the consolidation area
    double zoneLow = DBL_MAX;
    double zoneHigh = 0;
    
    for(int i = 1; i <= MinZoneBars; i++)
    {
        zoneLow = MathMin(zoneLow, iLow(_Symbol, AnalysisTimeframe, barIndex + i));
        zoneHigh = MathMax(zoneHigh, iHigh(_Symbol, AnalysisTimeframe, barIndex + i));
    }
    
    // Apply buffer
    zoneLow -= ZoneBuffer * _Point;
    zoneHigh += ZoneBuffer * _Point;
    
    // Calculate volume if available
    long volume = 0;
    if(UseVolumeFilter)
    {
        for(int i = 1; i <= MinZoneBars; i++)
            volume += iVolume(_Symbol, AnalysisTimeframe, barIndex + i);
    }
    
    zones[zoneIndex].zoneLow = zoneLow;
    zones[zoneIndex].zoneHigh = zoneHigh;
    zones[zoneIndex].zoneTime = iTime(_Symbol, AnalysisTimeframe, barIndex);
    zones[zoneIndex].isSupplyZone = true;
    zones[zoneIndex].isValid = true;
    zones[zoneIndex].hasBeenTested = false;
    zones[zoneIndex].touchCount = 0;
    zones[zoneIndex].retestCount = 0;
    zones[zoneIndex].strength = strength;
    zones[zoneIndex].volume = volume;
    zones[zoneIndex].isRespected = true;
    
    // Determine quality
    if(strength >= 0.8) zones[zoneIndex].quality = ZONE_STRONG;
    else if(strength >= 0.6) zones[zoneIndex].quality = ZONE_MEDIUM;
    else zones[zoneIndex].quality = ZONE_WEAK;
    
    if(ShowDebugInfo)
        Print("Enhanced Supply zone created: ", zoneLow, " - ", zoneHigh,
              " | Strength: ", DoubleToString(strength, 2),
              " | Quality: ", EnumToString(zones[zoneIndex].quality));
}

//+------------------------------------------------------------------+
//| Find available zone slot                                         |
//+------------------------------------------------------------------+
int FindAvailableZoneSlot()
{
    // First try to find an empty slot
    for(int i = 0; i < MaxZones; i++)
    {
        if(!zones[i].isValid)
            return i;
    }
    
    // If no empty slots, replace the weakest zone
    int weakestIndex = 0;
    double weakestStrength = zones[0].strength;
    
    for(int i = 1; i < MaxZones; i++)
    {
        if(zones[i].strength < weakestStrength)
        {
            weakestStrength = zones[i].strength;
            weakestIndex = i;
        }
    }
    
    return weakestIndex;
}

//+------------------------------------------------------------------+
//| Update zone quality based on price action                        |
//+------------------------------------------------------------------+
void UpdateZoneQuality()
{
    double currentPrice = iClose(_Symbol, EntryTimeframe, 1);
    
    for(int i = 0; i < MaxZones; i++)
    {
        if(!zones[i].isValid) continue;
        
        // Check if zone is being respected
        if(currentPrice >= zones[i].zoneLow && currentPrice <= zones[i].zoneHigh)
        {
            zones[i].touchCount++;
            
            // If price penetrates through zone without reaction, reduce strength
            bool priceRejected = CheckZoneRejection(i);
            if(!priceRejected && zones[i].touchCount > 1)
            {
                zones[i].strength *= 0.8; // Reduce strength
                zones[i].isRespected = false;
                
                // Update quality
                if(zones[i].strength < 0.4)
                {
                    zones[i].isValid = false; // Invalidate weak zones
                }
            }
            else if(priceRejected)
            {
                zones[i].strength = MathMin(zones[i].strength * 1.1, 1.0); // Increase strength
                zones[i].isRespected = true;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if zone showed rejection                                    |
//+------------------------------------------------------------------+
bool CheckZoneRejection(int zoneIndex)
{
    // Simple rejection check - look for reversal candle patterns
    double open1 = iOpen(_Symbol, EntryTimeframe, 1);
    double close1 = iClose(_Symbol, EntryTimeframe, 1);
    double high1 = iHigh(_Symbol, EntryTimeframe, 1);
    double low1 = iLow(_Symbol, EntryTimeframe, 1);
    
    if(zones[zoneIndex].isSupplyZone)
    {
        // Look for bearish rejection from supply zone
        return (close1 < open1 && (high1 - MathMax(open1, close1)) > 2 * MathAbs(open1 - close1));
    }
    else
    {
        // Look for bullish rejection from demand zone  
        return (close1 > open1 && (MathMin(open1, close1) - low1) > 2 * MathAbs(open1 - close1));
    }
}

//+------------------------------------------------------------------+
//| Enhanced trading opportunity detection                            |
//+------------------------------------------------------------------+
void CheckTradingOpportunities()
{
    if(PositionSelect(_Symbol)) return; // Already in trade
    
    double currentPrice = iClose(_Symbol, EntryTimeframe, 1);
    
    for(int i = 0; i < MaxZones; i++)
    {
        if(!zones[i].isValid || !zones[i].isRespected) continue;
        
        // Only trade strong zones or medium zones with confluence
        if(zones[i].quality == ZONE_WEAK && !HasConfluence(i)) continue;
        
        if(currentPrice >= zones[i].zoneLow && currentPrice <= zones[i].zoneHigh)
        {
            zones[i].retestCount++;
            
            // Check max retests
            if(zones[i].retestCount > MaxZoneRetests)
            {
                zones[i].isValid = false;
                continue;
            }
            
            if(!zones[i].isSupplyZone && (currentTrend == TREND_UPTREND || 
                (currentTrend == TREND_SIDEWAYS && HasBullishConfluence())))
            {
                if(!RequireZoneRetest || zones[i].hasBeenTested)
                {
                    CheckEnhancedLongEntry(i);
                }
                else
                {
                    zones[i].hasBeenTested = true;
                }
            }
            else if(zones[i].isSupplyZone && (currentTrend == TREND_DOWNTREND ||
                    (currentTrend == TREND_SIDEWAYS && HasBearishConfluence())))
            {
                if(!RequireZoneRetest || zones[i].hasBeenTested)
                {
                    CheckEnhancedShortEntry(i);
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
//| Check for confluence factors                                      |
//+------------------------------------------------------------------+
bool HasConfluence(int zoneIndex)
{
    int confluenceCount = 0;
    
    // Moving average confluence
    if(UseMovingAverageFilter && maHandle != INVALID_HANDLE)
    {
        double ma[];
        if(CopyBuffer(maHandle, 0, 1, 1, ma) > 0)
        {
            double currentPrice = iClose(_Symbol, EntryTimeframe, 1);
            if(zones[zoneIndex].isSupplyZone && currentPrice < ma[0])
                confluenceCount++;
            else if(!zones[zoneIndex].isSupplyZone && currentPrice > ma[0])
                confluenceCount++;
        }
    }
    
    // Fibonacci confluence
    if(UseFibonacciLevels)
    {
        if(IsFibonacciLevel(zones[zoneIndex]))
            confluenceCount++;
    }
    
    return confluenceCount >= 1;
}

//+------------------------------------------------------------------+
//| Check bullish confluence                                         |
//+------------------------------------------------------------------+
bool HasBullishConfluence()
{
    if(!UseMovingAverageFilter || maHandle == INVALID_HANDLE) return false;
    
    double ma[];
    if(CopyBuffer(maHandle, 0, 1, 1, ma) > 0)
    {
        double currentPrice = iClose(_Symbol, EntryTimeframe, 1);
        return currentPrice > ma[0];
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check bearish confluence                                         |
//+------------------------------------------------------------------+
bool HasBearishConfluence()
{
    if(!UseMovingAverageFilter || maHandle == INVALID_HANDLE) return false;
    
    double ma[];
    if(CopyBuffer(maHandle, 0, 1, 1, ma) > 0)
    {
        double currentPrice = iClose(_Symbol, EntryTimeframe, 1);
        return currentPrice < ma[0];
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if zone aligns with Fibonacci levels                      |
//+------------------------------------------------------------------+
bool IsFibonacciLevel(const SupplyDemandZone &zone)
{
    if(!lastValidHigh || !lastValidLow) return false;
    
    double range = MathAbs(lastValidHigh - lastValidLow);
    if(range == 0) return false;
    
    // Common Fibonacci retracement levels
    double fib236 = lastValidLow + range * 0.236;
    double fib382 = lastValidLow + range * 0.382;
    double fib500 = lastValidLow + range * 0.500;
    double fib618 = lastValidLow + range * 0.618;
    double fib786 = lastValidLow + range * 0.786;
    
    double tolerance = range * 0.02; // 2% tolerance
    
    // Check if zone overlaps with any Fibonacci level
    return (MathAbs(zone.zoneLow - fib236) <= tolerance ||
            MathAbs(zone.zoneHigh - fib236) <= tolerance ||
            MathAbs(zone.zoneLow - fib382) <= tolerance ||
            MathAbs(zone.zoneHigh - fib382) <= tolerance ||
            MathAbs(zone.zoneLow - fib500) <= tolerance ||
            MathAbs(zone.zoneHigh - fib500) <= tolerance ||
            MathAbs(zone.zoneLow - fib618) <= tolerance ||
            MathAbs(zone.zoneHigh - fib618) <= tolerance ||
            MathAbs(zone.zoneLow - fib786) <= tolerance ||
            MathAbs(zone.zoneHigh - fib786) <= tolerance);
}

//+------------------------------------------------------------------+
//| Enhanced long entry with better risk management                  |
//+------------------------------------------------------------------+
void CheckEnhancedLongEntry(int zoneIndex)
{
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double stopLoss, takeProfit;
    
    // Calculate stop loss
    if(UseATRStops && atrHandle != INVALID_HANDLE)
    {
        double atr[];
        if(CopyBuffer(atrHandle, 0, 1, 1, atr) > 0)
        {
            stopLoss = entryPrice - (atr[0] * ATRMultiplier);
        }
        else
        {
            stopLoss = zones[zoneIndex].zoneLow - (10 * _Point);
        }
    }
    else
    {
        stopLoss = zones[zoneIndex].zoneLow - (5 * _Point);
    }
    
    // Calculate take profit based on structure
    takeProfit = CalculateTakeProfit(true, entryPrice, stopLoss);
    
    // Calculate risk-reward ratio
    double riskPoints = entryPrice - stopLoss;
    double rewardPoints = takeProfit - entryPrice;
    
    if(riskPoints <= 0 || rewardPoints <= 0) return;
    
    double riskReward = rewardPoints / riskPoints;
    
    // Enhanced filters
    if(riskReward >= MinRiskReward && riskReward <= MaxRiskReward)
    {
        // Calculate position size based on risk percentage
        double lotSize = CalculatePositionSize(riskPoints);
        
        if(lotSize > 0 && trade.Buy(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, 
                                   "Enhanced Structure Long"))
        {
            // Store trade information
            currentTrade.entryPrice = entryPrice;
            currentTrade.stopLoss = stopLoss;
            currentTrade.takeProfit = takeProfit;
            currentTrade.riskReward = riskReward;
            currentTrade.zoneIndex = zoneIndex;
            currentTrade.entryTime = TimeCurrent();
            inTrade = true;
            
            if(ShowDebugInfo)
                Print("Enhanced Long opened: Entry=", entryPrice, 
                      " SL=", stopLoss, " TP=", takeProfit, 
                      " R:R=", DoubleToString(riskReward, 2),
                      " Lot=", lotSize,
                      " Zone Quality=", EnumToString(zones[zoneIndex].quality));
            
            // Mark zone as used
            zones[zoneIndex].isValid = false;
        }
    }
    else if(ShowDebugInfo)
    {
        Print("Long rejected: R:R=", DoubleToString(riskReward, 2), 
              " (Required: ", MinRiskReward, "-", MaxRiskReward, ")");
    }
}

//+------------------------------------------------------------------+
//| Enhanced short entry with better risk management                 |
//+------------------------------------------------------------------+
void CheckEnhancedShortEntry(int zoneIndex)
{
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stopLoss, takeProfit;
    
    // Calculate stop loss
    if(UseATRStops && atrHandle != INVALID_HANDLE)
    {
        double atr[];
        if(CopyBuffer(atrHandle, 0, 1, 1, atr) > 0)
        {
            stopLoss = entryPrice + (atr[0] * ATRMultiplier);
        }
        else
        {
            stopLoss = zones[zoneIndex].zoneHigh + (10 * _Point);
        }
    }
    else
    {
        stopLoss = zones[zoneIndex].zoneHigh + (5 * _Point);
    }
    
    // Calculate take profit based on structure
    takeProfit = CalculateTakeProfit(false, entryPrice, stopLoss);
    
    // Calculate risk-reward ratio
    double riskPoints = stopLoss - entryPrice;
    double rewardPoints = entryPrice - takeProfit;
    
    if(riskPoints <= 0 || rewardPoints <= 0) return;
    
    double riskReward = rewardPoints / riskPoints;
    
    // Enhanced filters
    if(riskReward >= MinRiskReward && riskReward <= MaxRiskReward)
    {
        // Calculate position size based on risk percentage
        double lotSize = CalculatePositionSize(riskPoints);
        
        if(lotSize > 0 && trade.Sell(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, 
                                    "Enhanced Structure Short"))
        {
            // Store trade information
            currentTrade.entryPrice = entryPrice;
            currentTrade.stopLoss = stopLoss;
            currentTrade.takeProfit = takeProfit;
            currentTrade.riskReward = riskReward;
            currentTrade.zoneIndex = zoneIndex;
            currentTrade.entryTime = TimeCurrent();
            inTrade = true;
            
            if(ShowDebugInfo)
                Print("Enhanced Short opened: Entry=", entryPrice, 
                      " SL=", stopLoss, " TP=", takeProfit, 
                      " R:R=", DoubleToString(riskReward, 2),
                      " Lot=", lotSize,
                      " Zone Quality=", EnumToString(zones[zoneIndex].quality));
            
            // Mark zone as used
            zones[zoneIndex].isValid = false;
        }
    }
    else if(ShowDebugInfo)
    {
        Print("Short rejected: R:R=", DoubleToString(riskReward, 2), 
              " (Required: ", MinRiskReward, "-", MaxRiskReward, ")");
    }
}

//+------------------------------------------------------------------+
//| Calculate take profit based on market structure                  |
//+------------------------------------------------------------------+
double CalculateTakeProfit(bool isLong, double entryPrice, double stopLoss)
{
    double takeProfit;
    
    if(isLong)
    {
        // For longs, target the next significant high or structure level
        takeProfit = lastValidHigh > 0 ? lastValidHigh : entryPrice + (entryPrice - stopLoss) * MinRiskReward;
        
        // Look for nearer swing highs
        for(int i = 0; i < swingCount && i < 10; i++)
        {
            if(swingPoints[i].isHigh && swingPoints[i].price > entryPrice && 
               swingPoints[i].price < takeProfit && swingPoints[i].isValidated)
            {
                takeProfit = swingPoints[i].price - (5 * _Point);
                break;
            }
        }
    }
    else
    {
        // For shorts, target the next significant low or structure level  
        takeProfit = lastValidLow > 0 ? lastValidLow : entryPrice - (stopLoss - entryPrice) * MinRiskReward;
        
        // Look for nearer swing lows
        for(int i = 0; i < swingCount && i < 10; i++)
        {
            if(!swingPoints[i].isHigh && swingPoints[i].price < entryPrice && 
               swingPoints[i].price > takeProfit && swingPoints[i].isValidated)
            {
                takeProfit = swingPoints[i].price + (5 * _Point);
                break;
            }
        }
    }
    
    return takeProfit;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk percentage                 |
//+------------------------------------------------------------------+
double CalculatePositionSize(double riskPoints)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * RiskPercent / 100.0;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tickValue == 0 || tickSize == 0 || riskPoints == 0) return 0;
    
    double riskInTicks = riskPoints / tickSize;
    double lotSize = riskAmount / (riskInTicks * tickValue);
    
    // Apply volume constraints
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);
    lotSize = NormalizeDouble(lotSize / stepLot, 0) * stepLot;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Manage open trades                                               |
//+------------------------------------------------------------------+
void ManageOpenTrade()
{
    if(!PositionSelect(_Symbol))
    {
        inTrade = false;
        return;
    }
    
    double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Implement trailing stop based on market structure
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
    {
        // For long positions, trail stop using swing lows
        for(int i = 0; i < swingCount && i < 5; i++)
        {
            if(!swingPoints[i].isHigh && swingPoints[i].time > currentTrade.entryTime &&
               swingPoints[i].price > currentTrade.stopLoss && swingPoints[i].price < currentPrice)
            {
                double newStopLoss = swingPoints[i].price - (3 * _Point);
                if(newStopLoss > currentTrade.stopLoss)
                {
                    if(trade.PositionModify(_Symbol, newStopLoss, currentTrade.takeProfit))
                    {
                        currentTrade.stopLoss = newStopLoss;
                        if(ShowDebugInfo)
                            Print("Long stop trailed to: ", newStopLoss);
                    }
                }
                break;
            }
        }
    }
    else
    {
        // For short positions, trail stop using swing highs
        for(int i = 0; i < swingCount && i < 5; i++)
        {
            if(swingPoints[i].isHigh && swingPoints[i].time > currentTrade.entryTime &&
               swingPoints[i].price < currentTrade.stopLoss && swingPoints[i].price > currentPrice)
            {
                double newStopLoss = swingPoints[i].price + (3 * _Point);
                if(newStopLoss < currentTrade.stopLoss)
                {
                    if(trade.PositionModify(_Symbol, newStopLoss, currentTrade.takeProfit))
                    {
                        currentTrade.stopLoss = newStopLoss;
                        if(ShowDebugInfo)
                            Print("Short stop trailed to: ", newStopLoss);
                    }
                }
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Remaining functions (DrawMarketStructure, DrawSupplyDemandZones, etc.) |
//+------------------------------------------------------------------+

void ValidateSwingPoints()
{
    for(int i = 0; i < swingCount; i++)
    {
        if(swingPoints[i].isHigh)
        {
            for(int j = i + 1; j < swingCount; j++)
            {
                if(!swingPoints[j].isHigh)
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
            for(int j = i + 1; j < swingCount; j++)
            {
                if(swingPoints[j].isHigh)
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

void DetermineTrend()
{
    double currentPrice = iClose(_Symbol, AnalysisTimeframe, 1);
    
    if(lastValidLow > 0 && currentPrice > lastValidLow)
    {
        bool lowBroken = false;
        for(int i = 1; i < 10; i++)
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
    else if(lastValidHigh > 0 && currentPrice < lastValidHigh)
    {
        bool highBroken = false;
        for(int i = 1; i < 10; i++)
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

void CleanExpiredZones()
{
    datetime currentTime = TimeCurrent();
    
    for(int i = 0; i < MaxZones; i++)
    {
        if(zones[i].isValid)
        {
            if((currentTime - zones[i].zoneTime) > ZoneValidityHours * 3600)
            {
                zones[i].isValid = false;
                if(ShowDebugInfo)
                    Print("Zone expired: ", zones[i].zoneLow, " - ", zones[i].zoneHigh);
            }
        }
    }
}

void DrawMarketStructure()
{
    for(int i = 0; i < swingCount && i < 10; i++)
    {
        if(swingPoints[i].isValidated)
        {
            string objName = "SwingPoint_" + IntegerToString(i);
            
            if(swingPoints[i].isHigh)
            {
                ObjectCreate(0, objName, OBJ_ARROW_DOWN, 0, 
                           swingPoints[i].time, swingPoints[i].price);
                ObjectSetInteger(0, objName, OBJPROP_COLOR, swingPoints[i].isMajor ? clrDarkRed : clrRed);
                ObjectSetInteger(0, objName, OBJPROP_WIDTH, swingPoints[i].isMajor ? 3 : 1);
            }
            else
            {
                ObjectCreate(0, objName, OBJ_ARROW_UP, 0, 
                           swingPoints[i].time, swingPoints[i].price);
                ObjectSetInteger(0, objName, OBJPROP_COLOR, swingPoints[i].isMajor ? clrDarkBlue : clrBlue);
                ObjectSetInteger(0, objName, OBJPROP_WIDTH, swingPoints[i].isMajor ? 3 : 1);
            }
        }
    }
}

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
            
            color zoneColor;
            if(zones[i].isSupplyZone)
            {
                switch(zones[i].quality)
                {
                    case ZONE_STRONG: zoneColor = clrDarkRed; break;
                    case ZONE_MEDIUM: zoneColor = clrRed; break;
                    default: zoneColor = clrLightPink; break;
                }
            }
            else
            {
                switch(zones[i].quality)
                {
                    case ZONE_STRONG: zoneColor = clrDarkBlue; break;
                    case ZONE_MEDIUM: zoneColor = clrBlue; break;
                    default: zoneColor = clrLightBlue; break;
                }
            }
            
            ObjectSetInteger(0, objName, OBJPROP_COLOR, zoneColor);
            ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, zoneColor);
            ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, objName, OBJPROP_FILL, true);
            
            // Add zone information text
            if(ShowZoneInfo)
            {
                string textName = "ZoneInfo_" + IntegerToString(i);
                string info = StringFormat("S:%.2f Q:%s T:%d", 
                                         zones[i].strength,
                                         EnumToString(zones[i].quality),
                                         zones[i].touchCount);
                
                ObjectCreate(0, textName, OBJ_TEXT, 0, zones[i].zoneTime, zones[i].zoneHigh);
                ObjectSetString(0, textName, OBJPROP_TEXT, info);
                ObjectSetInteger(0, textName, OBJPROP_COLOR, zoneColor);
                ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
            }
        }
    }
}

void CleanupChartObjects()
{
    int totalObjects = ObjectsTotal(0);
    
    for(int i = totalObjects - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i);
        
        if(StringFind(objName, "SwingPoint_") >= 0 || 
           StringFind(objName, "Zone_") >= 0 ||
           StringFind(objName, "ZoneInfo_") >= 0)
        {
            ObjectDelete(0, objName);
        }
    }
}