//+------------------------------------------------------------------+
//|                        MeanReversionTrendFilter.mq5             |
//|              Mean Reversion with Trend Filter Strategy          |
//|     Buy oversold in uptrends, Sell overbought in downtrends     |
//+------------------------------------------------------------------+
#property copyright "Learning Example"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Trend Filter Settings ==="
input int TrendEMA_Fast = 21;                        // Fast EMA for trend
input int TrendEMA_Slow = 50;                        // Slow EMA for trend
input int TrendEMA_Long = 200;                       // Long-term trend EMA
input double TrendStrengthMin = 20;                  // Min points between EMAs for strong trend

input group "=== Mean Reversion Settings ==="
input int RSI_Period = 14;                           // RSI Period
input double RSI_Oversold = 30;                      // RSI Oversold Level
input double RSI_Overbought = 70;                    // RSI Overbought Level
input int Stoch_K = 5;                               // Stochastic %K
input int Stoch_D = 3;                               // Stochastic %D
input int Stoch_Slowing = 3;                         // Stochastic Slowing
input double Stoch_Oversold = 20;                    // Stochastic Oversold
input double Stoch_Overbought = 80;                  // Stochastic Overbought

input group "=== Volatility Filter ==="
input int ATR_Period = 14;                           // ATR Period
input double ATR_MultiplierMin = 1.2;                // Min ATR multiplier for entries
input double ATR_MultiplierMax = 3.0;                // Max ATR multiplier (too volatile)

input group "=== Risk Management ==="
input double RiskPercent = 1.0;                      // Risk per trade (% of account)
input double RewardRiskRatio = 2.5;                  // Minimum reward:risk ratio
input double MaxSpread = 3;                          // Maximum Spread (points)
input int MagicNumber = 99999;                       // Magic Number

input group "=== Time Filter ==="
input bool UseTimeFilter = true;                     // Use trading time filter
input string StartTime = "08:00";                    // Start trading time
input string EndTime = "20:00";                      // End trading time
input bool AvoidNews = true;                          // Avoid trading around news times

input group "=== Position Management ==="
input bool UseTrailingStop = true;                   // Use trailing stop
input double TrailingStart = 1.5;                    // Start trailing at R:R ratio
input double TrailingStep = 0.5;                     // Trailing step (R:R ratio)
input int MaxPositions = 1;                          // Maximum concurrent positions

input group "=== Display Settings ==="
input bool ShowDebugInfo = true;                     // Show debug information
input bool DrawTrendLines = true;                    // Draw trend EMAs
input bool DrawSignals = true;                       // Draw entry signals

//--- Global variables
CTrade trade;
datetime lastBarTime;

// Indicator handles
int emaFastHandle;
int emaSlowHandle;
int emaLongHandle;
int rsiHandle;
int stochHandle;
int atrHandle;

// Indicator arrays
double emaFast[], emaSlow[], emaLong[];
double rsiValues[];
double stochMain[], stochSignal[];
double atrValues[];

// Strategy state
enum MARKET_STATE
{
    STRONG_UPTREND,
    WEAK_UPTREND,
    SIDEWAYS,
    WEAK_DOWNTREND,
    STRONG_DOWNTREND
};

MARKET_STATE currentMarketState = SIDEWAYS;

// Position tracking
struct TradeInfo
{
    ulong ticket;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double riskAmount;
    double rewardAmount;
    bool isLong;
    datetime entryTime;
    double trailingLevel;
};

TradeInfo activeTrade;
bool hasActiveTrade = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    
    // Initialize indicators
    emaFastHandle = iMA(_Symbol, _Period, TrendEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    emaSlowHandle = iMA(_Symbol, _Period, TrendEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    emaLongHandle = iMA(_Symbol, _Period, TrendEMA_Long, 0, MODE_EMA, PRICE_CLOSE);
    rsiHandle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
    stochHandle = iStochastic(_Symbol, _Period, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
    atrHandle = iATR(_Symbol, _Period, ATR_Period);
    
    // Check if indicators are created successfully
    if(emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE || 
       emaLongHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE || 
       stochHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
    {
        Print("Error creating indicators");
        return INIT_FAILED;
    }
    
    // Set arrays as series
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);
    ArraySetAsSeries(emaLong, true);
    ArraySetAsSeries(rsiValues, true);
    ArraySetAsSeries(stochMain, true);
    ArraySetAsSeries(stochSignal, true);
    ArraySetAsSeries(atrValues, true);
    
    // Initialize trade info
    ResetTradeInfo();
    
    Print("Mean Reversion with Trend Filter Strategy initialized");
    Print("Strategy: Buy oversold in uptrends, Sell overbought in downtrends");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    IndicatorRelease(emaFastHandle);
    IndicatorRelease(emaSlowHandle);
    IndicatorRelease(emaLongHandle);
    IndicatorRelease(rsiHandle);
    IndicatorRelease(stochHandle);
    IndicatorRelease(atrHandle);
    
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
    
    // Check time filter
    if(UseTimeFilter && !IsWithinTradingHours()) return;
    
    // Update market state
    UpdateMarketState();
    
    // Update position tracking
    UpdatePositionStatus();
    
    // Manage existing positions
    if(hasActiveTrade)
    {
        ManageActivePosition();
    }
    else if(PositionsTotal() < MaxPositions)
    {
        // Look for new trading opportunities
        CheckForTradingOpportunities();
    }
    
    // Update visual elements
    if(DrawSignals) UpdateSignalDisplay();
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
    if(CopyBuffer(emaFastHandle, 0, 0, 5, emaFast) < 5) return false;
    if(CopyBuffer(emaSlowHandle, 0, 0, 5, emaSlow) < 5) return false;
    if(CopyBuffer(emaLongHandle, 0, 0, 5, emaLong) < 5) return false;
    if(CopyBuffer(rsiHandle, 0, 0, 5, rsiValues) < 5) return false;
    if(CopyBuffer(stochHandle, 0, 0, 5, stochMain) < 5) return false;
    if(CopyBuffer(stochHandle, 1, 0, 5, stochSignal) < 5) return false;
    if(CopyBuffer(atrHandle, 0, 0, 5, atrValues) < 5) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime dt;
    TimeCurrent(dt);
    
    string currentTime = StringFormat("%02d:%02d", dt.hour, dt.min);
    return (StringCompare(currentTime, StartTime) >= 0 && 
            StringCompare(currentTime, EndTime) <= 0);
}

//+------------------------------------------------------------------+
//| Update market state based on EMAs                               |
//+------------------------------------------------------------------+
void UpdateMarketState()
{
    double currentPrice = iClose(_Symbol, _Period, 1);
    double fastEMA = emaFast[1];
    double slowEMA = emaSlow[1];
    double longEMA = emaLong[1];
    
    double fastSlowDiff = MathAbs(fastEMA - slowEMA);
    double trendStrength = fastSlowDiff / _Point;
    
    // Determine market state
    if(fastEMA > slowEMA && slowEMA > longEMA && currentPrice > fastEMA)
    {
        if(trendStrength >= TrendStrengthMin)
            currentMarketState = STRONG_UPTREND;
        else
            currentMarketState = WEAK_UPTREND;
    }
    else if(fastEMA < slowEMA && slowEMA < longEMA && currentPrice < fastEMA)
    {
        if(trendStrength >= TrendStrengthMin)
            currentMarketState = STRONG_DOWNTREND;
        else
            currentMarketState = WEAK_DOWNTREND;
    }
    else
    {
        currentMarketState = SIDEWAYS;
    }
    
    if(ShowDebugInfo)
        Print("Market State: ", EnumToString(currentMarketState), 
              " | Trend Strength: ", DoubleToString(trendStrength, 1));
}

//+------------------------------------------------------------------+
//| Update position status                                           |
//+------------------------------------------------------------------+
void UpdatePositionStatus()
{
    if(PositionSelect(_Symbol))
    {
        if(!hasActiveTrade)
        {
            // Position detected
            activeTrade.ticket = PositionGetInteger(POSITION_TICKET);
            activeTrade.entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            activeTrade.stopLoss = PositionGetDouble(POSITION_SL);
            activeTrade.takeProfit = PositionGetDouble(POSITION_TP);
            activeTrade.isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            activeTrade.entryTime = (datetime)PositionGetInteger(POSITION_TIME);
            hasActiveTrade = true;
        }
    }
    else
    {
        if(hasActiveTrade)
        {
            if(ShowDebugInfo)
                Print("Position closed - Ticket: ", activeTrade.ticket);
            ResetTradeInfo();
        }
    }
}

//+------------------------------------------------------------------+
//| Reset trade information                                          |
//+------------------------------------------------------------------+
void ResetTradeInfo()
{
    activeTrade.ticket = 0;
    activeTrade.entryPrice = 0;
    activeTrade.stopLoss = 0;
    activeTrade.takeProfit = 0;
    activeTrade.riskAmount = 0;
    activeTrade.rewardAmount = 0;
    activeTrade.isLong = true;
    activeTrade.entryTime = 0;
    activeTrade.trailingLevel = 0;
    hasActiveTrade = false;
}

//+------------------------------------------------------------------+
//| Check for trading opportunities                                  |
//+------------------------------------------------------------------+
void CheckForTradingOpportunities()
{
    // Check volatility filter
    double currentATR = atrValues[1];
    double avgATR = (atrValues[1] + atrValues[2] + atrValues[3]) / 3.0;
    double atrRatio = currentATR / avgATR;
    
    if(atrRatio < ATR_MultiplierMin || atrRatio > ATR_MultiplierMax)
    {
        if(ShowDebugInfo)
            Print("ATR filter failed. Ratio: ", DoubleToString(atrRatio, 2));
        return;
    }
    
    // Check for long opportunities (buy oversold in uptrends)
    if((currentMarketState == STRONG_UPTREND || currentMarketState == WEAK_UPTREND) &&
       IsOversoldCondition())
    {
        ExecuteLongEntry();
    }
    
    // Check for short opportunities (sell overbought in downtrends)
    if((currentMarketState == STRONG_DOWNTREND || currentMarketState == WEAK_DOWNTREND) &&
       IsOverboughtCondition())
    {
        ExecuteShortEntry();
    }
}

//+------------------------------------------------------------------+
//| Check if market is oversold                                      |
//+------------------------------------------------------------------+
bool IsOversoldCondition()
{
    double currentRSI = rsiValues[1];
    double currentStoch = stochMain[1];
    
    // RSI oversold
    bool rsiOversold = currentRSI < RSI_Oversold;
    
    // Stochastic oversold
    bool stochOversold = currentStoch < Stoch_Oversold;
    
    // Both indicators must agree
    return (rsiOversold && stochOversold);
}

//+------------------------------------------------------------------+
//| Check if market is overbought                                    |
//+------------------------------------------------------------------+
bool IsOverboughtCondition()
{
    double currentRSI = rsiValues[1];
    double currentStoch = stochMain[1];
    
    // RSI overbought
    bool rsiOverbought = currentRSI > RSI_Overbought;
    
    // Stochastic overbought
    bool stochOverbought = currentStoch > Stoch_Overbought;
    
    // Both indicators must agree
    return (rsiOverbought && stochOverbought);
}

//+------------------------------------------------------------------+
//| Execute long entry                                               |
//+------------------------------------------------------------------+
void ExecuteLongEntry()
{
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double atr = atrValues[1];
    
    // Calculate position size based on risk
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * RiskPercent / 100.0;
    
    // Stop loss below recent swing low or 2 ATR
    double stopLoss = entryPrice - (2.0 * atr);
    double riskPoints = entryPrice - stopLoss;
    
    // Take profit based on reward:risk ratio
    double takeProfit = entryPrice + (riskPoints * RewardRiskRatio);
    
    // Calculate lot size
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = riskAmount / (riskPoints * tickValue / _Point);
    
    // Normalize lot size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, MathRound(lotSize / lotStep) * lotStep));
    
    if(trade.Buy(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, "Mean Reversion Long"))
    {
        activeTrade.ticket = trade.ResultOrder();
        activeTrade.entryPrice = entryPrice;
        activeTrade.stopLoss = stopLoss;
        activeTrade.takeProfit = takeProfit;
        activeTrade.riskAmount = riskAmount;
        activeTrade.rewardAmount = riskAmount * RewardRiskRatio;
        activeTrade.isLong = true;
        activeTrade.entryTime = TimeCurrent();
        hasActiveTrade = true;
        
        if(ShowDebugInfo)
            Print("Long entry: ", entryPrice, " SL: ", stopLoss, " TP: ", takeProfit, 
                  " Size: ", lotSize, " Risk: $", DoubleToString(riskAmount, 2));
        
        if(DrawSignals)
            DrawEntrySignal(true, entryPrice);
    }
}

//+------------------------------------------------------------------+
//| Execute short entry                                              |
//+------------------------------------------------------------------+
void ExecuteShortEntry()
{
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double atr = atrValues[1];
    
    // Calculate position size based on risk
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * RiskPercent / 100.0;
    
    // Stop loss above recent swing high or 2 ATR
    double stopLoss = entryPrice + (2.0 * atr);
    double riskPoints = stopLoss - entryPrice;
    
    // Take profit based on reward:risk ratio
    double takeProfit = entryPrice - (riskPoints * RewardRiskRatio);
    
    // Calculate lot size
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = riskAmount / (riskPoints * tickValue / _Point);
    
    // Normalize lot size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, MathRound(lotSize / lotStep) * lotStep));
    
    if(trade.Sell(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, "Mean Reversion Short"))
    {
        activeTrade.ticket = trade.ResultOrder();
        activeTrade.entryPrice = entryPrice;
        activeTrade.stopLoss = stopLoss;
        activeTrade.takeProfit = takeProfit;
        activeTrade.riskAmount = riskAmount;
        activeTrade.rewardAmount = riskAmount * RewardRiskRatio;
        activeTrade.isLong = false;
        activeTrade.entryTime = TimeCurrent();
        hasActiveTrade = true;
        
        if(ShowDebugInfo)
            Print("Short entry: ", entryPrice, " SL: ", stopLoss, " TP: ", takeProfit, 
                  " Size: ", lotSize, " Risk: $", DoubleToString(riskAmount, 2));
        
        if(DrawSignals)
            DrawEntrySignal(false, entryPrice);
    }
}

//+------------------------------------------------------------------+
//| Manage active position                                           |
//+------------------------------------------------------------------+
void ManageActivePosition()
{
    if(!UseTrailingStop) return;
    
    double currentPrice = SymbolInfoDouble(_Symbol, activeTrade.isLong ? SYMBOL_BID : SYMBOL_ASK);
    double riskPoints = MathAbs(activeTrade.entryPrice - activeTrade.stopLoss);
    double currentProfit;
    
    if(activeTrade.isLong)
        currentProfit = currentPrice - activeTrade.entryPrice;
    else
        currentProfit = activeTrade.entryPrice - currentPrice;
    
    double currentRR = currentProfit / riskPoints;
    
    // Start trailing when profit reaches TrailingStart R:R
    if(currentRR >= TrailingStart)
    {
        double newStopLevel;
        
        if(activeTrade.isLong)
        {
            newStopLevel = currentPrice - (riskPoints * TrailingStep);
            if(newStopLevel > activeTrade.stopLoss + (10 * _Point)) // Minimum 10 points improvement
            {
                if(trade.PositionModify(activeTrade.ticket, newStopLevel, activeTrade.takeProfit))
                {
                    activeTrade.stopLoss = newStopLevel;
                    if(ShowDebugInfo)
                        Print("Trailing stop updated to: ", newStopLevel);
                }
            }
        }
        else
        {
            newStopLevel = currentPrice + (riskPoints * TrailingStep);
            if(newStopLevel < activeTrade.stopLoss - (10 * _Point)) // Minimum 10 points improvement
            {
                if(trade.PositionModify(activeTrade.ticket, newStopLevel, activeTrade.takeProfit))
                {
                    activeTrade.stopLoss = newStopLevel;
                    if(ShowDebugInfo)
                        Print("Trailing stop updated to: ", newStopLevel);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Draw entry signal on chart                                       |
//+------------------------------------------------------------------+
void DrawEntrySignal(bool isLong, double price)
{
    string objName = "Signal_" + TimeToString(TimeCurrent());
    
    if(isLong)
    {
        ObjectCreate(0, objName, OBJ_ARROW_UP, 0, TimeCurrent(), price - (10 * _Point));
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrLime);
        ObjectSetString(0, objName, OBJPROP_TEXT, "BUY OVERSOLD");
    }
    else
    {
        ObjectCreate(0, objName, OBJ_ARROW_DOWN, 0, TimeCurrent(), price + (10 * _Point));
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrOrange);
        ObjectSetString(0, objName, OBJPROP_TEXT, "SELL OVERBOUGHT");
    }
    
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
}

//+------------------------------------------------------------------+
//| Update signal display                                            |
//+------------------------------------------------------------------+
void UpdateSignalDisplay()
{
    // Additional visual elements can be added here
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
        
        if(StringFind(objName, "Signal_") >= 0)
        {
            ObjectDelete(0, objName);
        }
    }
}