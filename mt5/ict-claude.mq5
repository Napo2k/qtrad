//+------------------------------------------------------------------+
//|                                           ICT_Trading_Strategy.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input double   RiskPercent = 2.0;           // Risk percentage per trade
input double   RiskRewardRatio = 2.0;       // Risk to reward ratio
input bool     UseCBranchTarget = false;    // Use C branch beginning as target
input int      ABCLookbackBars = 100;       // Bars to look back for ABC pattern
input double   MinPullbackPercent = 30.0;   // Minimum pullback percentage for B branch
input double   MaxPullbackPercent = 70.0;   // Maximum pullback percentage for B branch
input int      MagicNumber = 12345;         // Magic number for trades

//--- Global variables
CTrade trade;
datetime lastSignalTime = 0;

//--- Structure to hold ABC pattern data
struct ABCPattern {
    int    A_start;
    int    A_end;
    double A_high;
    double A_low;
    int    B_start;
    int    B_end;
    double B_high;
    double B_low;
    int    C_start;
    int    C_end;
    double C_high;
    double C_low;
    bool   isValid;
    bool   isBullish;
};

//--- Structure to hold Fair Value Gap data
struct FVG {
    int    startBar;
    int    middleBar;
    int    endBar;
    double high;
    double low;
    double gapHigh;
    double gapLow;
    bool   isValid;
    bool   isBearish;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    Print("ICT Trading Strategy EA initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("ICT Trading Strategy EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Check if we already have an open position
    if(PositionSelect(_Symbol)) return;
    
    // Prevent multiple signals on the same bar
    if(iTime(_Symbol, PERIOD_M15, 0) == lastSignalTime) return;
    
    // Step 1: Identify ABC Pattern on higher timeframe
    ABCPattern pattern = IdentifyABCPattern();
    if(!pattern.isValid) return;
    
    // Step 2: Check for breakout and reversal on M15
    if(!CheckBreakoutAndReversal(pattern)) return;
    
    // Step 3: Look for Change of Character on M1
    if(!CheckChangeOfCharacter()) return;
    
    // Step 4: Execute trade using FVG
    ExecuteTrade(pattern);
    
    lastSignalTime = iTime(_Symbol, PERIOD_M15, 0);
}

//+------------------------------------------------------------------+
//| Identify ABC Pattern                                             |
//+------------------------------------------------------------------+
ABCPattern IdentifyABCPattern() {
    ABCPattern pattern;
    pattern.isValid = false;
    
    // Get M15 data
    MqlRates rates[];
    if(CopyRates(_Symbol, PERIOD_M15, 0, ABCLookbackBars, rates) < ABCLookbackBars) {
        return pattern;
    }
    
    // Look for swing highs and lows
    for(int i = 20; i < ABCLookbackBars - 20; i++) {
        // Check for potential A branch (upward movement)
        if(IsSwingLow(rates, i - 10) && IsSwingHigh(rates, i)) {
            pattern.A_start = i - 10;
            pattern.A_end = i;
            pattern.A_low = rates[i - 10].low;
            pattern.A_high = rates[i].high;
            
            // Look for B branch (pullback)
            for(int j = i + 3; j < i + 30 && j < ABCLookbackBars - 10; j++) {
                if(IsSwingLow(rates, j)) {
                    double pullbackPercent = (pattern.A_high - rates[j].low) / (pattern.A_high - pattern.A_low) * 100;
                    
                    // Check if pullback is within acceptable range and forms higher low
                    if(pullbackPercent >= MinPullbackPercent && pullbackPercent <= MaxPullbackPercent && 
                       rates[j].low > pattern.A_low) {
                        
                        pattern.B_start = i;
                        pattern.B_end = j;
                        pattern.B_high = pattern.A_high;
                        pattern.B_low = rates[j].low;
                        
                        // Look for C branch (slow move up)
                        for(int k = j + 3; k < j + 30 && k < ABCLookbackBars - 5; k++) {
                            if(rates[k].high > pattern.A_high) {
                                // Check if C branch movement is relatively slow
                                double cBranchSlope = (rates[k].high - pattern.B_low) / (k - j);
                                double aBranchSlope = (pattern.A_high - pattern.A_low) / (pattern.A_end - pattern.A_start);
                                
                                if(cBranchSlope < aBranchSlope * 1.5) { // C should be slower than A
                                    pattern.C_start = j;
                                    pattern.C_end = k;
                                    pattern.C_low = pattern.B_low;
                                    pattern.C_high = rates[k].high;
                                    pattern.isValid = true;
                                    pattern.isBullish = true;
                                    return pattern;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    return pattern;
}

//+------------------------------------------------------------------+
//| Check for breakout and reversal on M15                          |
//+------------------------------------------------------------------+
bool CheckBreakoutAndReversal(ABCPattern &pattern) {
    MqlRates rates[];
    if(CopyRates(_Symbol, PERIOD_M15, 0, 10, rates) < 3) return false;
    
    // Check if current candle (index 1) broke above A high
    if(rates[1].high <= pattern.A_high) return false;
    
    // Check if the next candle (current forming - index 0) is bearish so far
    // or if the previous completed candle closed bearish after the breakout
    if(rates[1].close >= rates[1].open) {
        // The breakout candle was bullish, check if current candle is bearish
        if(rates[0].close >= rates[0].open) return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for Change of Character on M1                             |
//+------------------------------------------------------------------+
bool CheckChangeOfCharacter() {
    MqlRates rates[];
    if(CopyRates(_Symbol, PERIOD_M1, 0, 50, rates) < 50) return false;
    
    // Find the most recent swing high and low
    int recentHighIndex = -1, recentLowIndex = -1;
    double recentHigh = 0, recentLow = DBL_MAX;
    
    // Look for recent swing points
    for(int i = 5; i < 30; i++) {
        if(IsSwingHigh(rates, i) && rates[i].high > recentHigh) {
            recentHigh = rates[i].high;
            recentHighIndex = i;
        }
        if(IsSwingLow(rates, i) && rates[i].low < recentLow) {
            recentLow = rates[i].low;
            recentLowIndex = i;
        }
    }
    
    if(recentHighIndex == -1 || recentLowIndex == -1) return false;
    
    // Check if price has broken below the recent low (Change of Character)
    for(int i = 0; i < MathMin(recentLowIndex, recentHighIndex); i++) {
        if(rates[i].close < recentLow) {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Execute trade using Fair Value Gap                              |
//+------------------------------------------------------------------+
void ExecuteTrade(ABCPattern &pattern) {
    FVG fvg = FindFirstBearishFVG();
    if(!fvg.isValid) return;
    
    double entryPrice = fvg.gapHigh;
    double stopLoss = fvg.high + 10 * _Point;
    double takeProfit;
    
    if(UseCBranchTarget) {
        // Use beginning of C branch as target
        MqlRates cBranchRates[];
        if(CopyRates(_Symbol, PERIOD_M15, 0, pattern.C_start + 5, cBranchRates) > pattern.C_start) {
            takeProfit = cBranchRates[pattern.C_start].low;
        } else {
            takeProfit = entryPrice - (stopLoss - entryPrice) * RiskRewardRatio;
        }
    } else {
        // Use risk-reward ratio
        takeProfit = entryPrice - (stopLoss - entryPrice) * RiskRewardRatio;
    }
    
    // Calculate lot size based on risk percentage
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double lotSize = riskAmount / ((stopLoss - entryPrice) / tickSize * tickValue);
    
    // Normalize lot size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, NormalizeDouble(lotSize / lotStep, 0) * lotStep));
    
    // Place sell order
    if(trade.Sell(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, "ICT Strategy")) {
        Print("Sell order placed successfully at ", entryPrice);
    } else {
        Print("Failed to place sell order. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Find first bearish Fair Value Gap                               |
//+------------------------------------------------------------------+
FVG FindFirstBearishFVG() {
    FVG fvg;
    fvg.isValid = false;
    
    MqlRates rates[];
    if(CopyRates(_Symbol, PERIOD_M1, 0, 50, rates) < 50) return fvg;
    
    // Look for three-candle bearish FVG pattern
    for(int i = 2; i < 20; i++) {
        // Check for bearish FVG: rates[i+2].high < rates[i].low
        if(rates[i + 2].high < rates[i].low && 
           rates[i + 1].close < rates[i + 1].open) { // Middle candle should be bearish
           
            fvg.startBar = i + 2;
            fvg.middleBar = i + 1;
            fvg.endBar = i;
            fvg.gapHigh = rates[i].low;
            fvg.gapLow = rates[i + 2].high;
            fvg.high = rates[i].high;
            fvg.low = rates[i + 2].low;
            fvg.isValid = true;
            fvg.isBearish = true;
            return fvg;
        }
    }
    
    return fvg;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                    |
//+------------------------------------------------------------------+
bool IsSwingHigh(MqlRates &rates[], int index, int lookback = 5) {
    if(index < lookback || index >= ArraySize(rates) - lookback) return false;
    
    for(int i = index - lookback; i <= index + lookback; i++) {
        if(i != index && rates[i].high >= rates[index].high) {
            return false;
        }
    }
    return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing low                                     |
//+------------------------------------------------------------------+
bool IsSwingLow(MqlRates &rates[], int index, int lookback = 5) {
    if(index < lookback || index >= ArraySize(rates) - lookback) return false;
    
    for(int i = index - lookback; i <= index + lookback; i++) {
        if(i != index && rates[i].low <= rates[index].low) {
            return false;
        }
    }
    return true;
}