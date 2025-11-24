//+------------------------------------------------------------------+
//|                                   Daily Break of Structure EA   |
//|                                  Copyright 2024, Your Name      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Name"
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Input parameters
input group "=== Trading Settings ==="
input bool InpEnabled = true;                    // Enable Trading
input double InpLotSize = 0.01;                 // Lot Size
input int InpSlippage = 3;                      // Slippage (points)
input int InpMagicNumber = 012245;              // Magic Number

input group "=== Time Settings ==="
input int InpStartHour = 20;                    // Trading Start Hour (NY Time)
input int InpStartMinute = 0;                   // Trading Start Minute
input int InpEndHour = 22;                      // Trading End Hour (NY Time)
input int InpEndMinute = 0;                     // Trading End Minute

input group "=== Risk Management ==="
input double InpRiskRewardRatio = 2.0;          // Risk-Reward Ratio (2:1, 4:1, 5:1)
input bool InpUseOrderBlock = true;             // Use Order Block Entry
input int InpOrderBlockLookback = 10;           // Order Block Lookback Candles

input group "=== Asset Specific Settings ==="
input bool InpIsGold = false;                   // Is Gold (use 4:1 RR if true)
input bool InpIsEURUSD = false;                 // Is EUR/USD (use 5:1 RR if true)

//--- Global variables
double g_prevDayHigh = 0;
double g_prevDayLow = 0;
bool g_levelsMarked = false;
bool g_tradeExecutedToday = false;
bool g_structureBroken = false;
bool g_waitingForChoCh = false;
bool g_longSetup = false;
bool g_shortSetup = false;
double g_breakLevel = 0;
double g_orderBlockHigh = 0;
double g_orderBlockLow = 0;
datetime g_lastTradeDate = 0;
datetime g_currentDay = 0;

//--- Trade management
#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(InpSlippage);
    
    Print("Daily Break of Structure EA initialized");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Daily Break of Structure EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if (!InpEnabled) return;
    
    // Check if it's a new day
    CheckNewDay();
    
    // Mark previous day levels if not done
    if (!g_levelsMarked)
    {
        MarkPreviousDayLevels();
    }
    
    // Check if we're in trading window
    if (IsInTradingWindow() && !g_tradeExecutedToday)
    {
        // Look for break of structure
        if (!g_structureBroken)
        {
            CheckBreakOfStructure();
        }
        // Look for change of structure confirmation
        else if (g_waitingForChoCh)
        {
            CheckChangeOfStructure();
        }
        // Execute trade if conditions are met
        else if ((g_longSetup || g_shortSetup) && !g_tradeExecutedToday)
        {
            if (InpUseOrderBlock)
            {
                CheckOrderBlockEntry();
            }
            else
            {
                ExecuteImmediateTrade();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if it's a new day and reset variables                     |
//+------------------------------------------------------------------+
void CheckNewDay()
{
    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);
    
    datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));
    
    if (g_currentDay != todayStart)
    {
        g_currentDay = todayStart;
        g_levelsMarked = false;
        g_tradeExecutedToday = false;
        g_structureBroken = false;
        g_waitingForChoCh = false;
        g_longSetup = false;
        g_shortSetup = false;
        g_breakLevel = 0;
        g_orderBlockHigh = 0;
        g_orderBlockLow = 0;
        
        Print("New day detected - Variables reset");
    }
}

//+------------------------------------------------------------------+
//| Mark previous day high and low levels                           |
//+------------------------------------------------------------------+
void MarkPreviousDayLevels()
{
    // Get 15-minute data for previous day
    MqlRates rates[];
    int copied = CopyRates(Symbol(), PERIOD_M15, 1, 96, rates); // 96 = 24 hours * 4 (15min bars)
    
    if (copied <= 0)
    {
        Print("Failed to copy 15-minute rates");
        return;
    }
    
    g_prevDayHigh = rates[0].high;
    g_prevDayLow = rates[0].low;
    
    // Find the actual high and low of previous day
    for (int i = 1; i < copied; i++)
    {
        if (rates[i].high > g_prevDayHigh)
            g_prevDayHigh = rates[i].high;
        if (rates[i].low < g_prevDayLow)
            g_prevDayLow = rates[i].low;
    }
    
    g_levelsMarked = true;
    
    Print(StringFormat("Previous day levels marked - High: %.5f, Low: %.5f", 
          g_prevDayHigh, g_prevDayLow));
    
    // Draw horizontal lines for visualization
    DrawLevels();
}

//+------------------------------------------------------------------+
//| Draw horizontal lines for previous day levels                   |
//+------------------------------------------------------------------+
void DrawLevels()
{
    // Remove existing lines
    ObjectDelete(0, "PrevDayHigh");
    ObjectDelete(0, "PrevDayLow");
    
    // Draw previous day high
    ObjectCreate(0, "PrevDayHigh", OBJ_HLINE, 0, 0, g_prevDayHigh);
    ObjectSetInteger(0, "PrevDayHigh", OBJPROP_COLOR, clrRed);
    ObjectSetInteger(0, "PrevDayHigh", OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, "PrevDayHigh", OBJPROP_STYLE, STYLE_DASH);
    
    // Draw previous day low
    ObjectCreate(0, "PrevDayLow", OBJ_HLINE, 0, 0, g_prevDayLow);
    ObjectSetInteger(0, "PrevDayLow", OBJPROP_COLOR, clrBlue);
    ObjectSetInteger(0, "PrevDayLow", OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, "PrevDayLow", OBJPROP_STYLE, STYLE_DASH);
}

//+------------------------------------------------------------------+
//| Check if current time is within trading window                  |
//+------------------------------------------------------------------+
bool IsInTradingWindow()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    int currentMinutes = dt.hour * 60 + dt.min;
    int startMinutes = InpStartHour * 60 + InpStartMinute;
    int endMinutes = InpEndHour * 60 + InpEndMinute;
    
    return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
}

//+------------------------------------------------------------------+
//| Check for break of structure                                    |
//+------------------------------------------------------------------+
void CheckBreakOfStructure()
{
    double currentAsk = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double currentBid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    // Check for break above previous day high
    if (currentAsk > g_prevDayHigh)
    {
        g_structureBroken = true;
        g_waitingForChoCh = true;
        g_longSetup = true;
        g_breakLevel = g_prevDayHigh;
        
        Print("Break of structure detected - LONG setup");
        IdentifyOrderBlock(true);
    }
    // Check for break below previous day low
    else if (currentBid < g_prevDayLow)
    {
        g_structureBroken = true;
        g_waitingForChoCh = true;
        g_shortSetup = true;
        g_breakLevel = g_prevDayLow;
        
        Print("Break of structure detected - SHORT setup");
        IdentifyOrderBlock(false);
    }
}

//+------------------------------------------------------------------+
//| Check for change of structure confirmation                      |
//+------------------------------------------------------------------+
void CheckChangeOfStructure()
{
    MqlRates rates[];
    int copied = CopyRates(Symbol(), PERIOD_M1, 1, 10, rates);
    
    if (copied < 3) return;
    
    if (g_longSetup)
    {
        // Look for a lower low after the break (change of structure for long)
        for (int i = 1; i < copied - 1; i++)
        {
            if (rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low)
            {
                // Check if current price is above this low (confirmation)
                if (SymbolInfoDouble(Symbol(), SYMBOL_BID) > rates[i].high)
                {
                    g_waitingForChoCh = false;
                    Print("Change of Structure confirmed - LONG");
                    break;
                }
            }
        }
    }
    else if (g_shortSetup)
    {
        // Look for a higher high after the break (change of structure for short)
        for (int i = 1; i < copied - 1; i++)
        {
            if (rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high)
            {
                // Check if current price is below this high (confirmation)
                if (SymbolInfoDouble(Symbol(), SYMBOL_ASK) < rates[i].low)
                {
                    g_waitingForChoCh = false;
                    Print("Change of Structure confirmed - SHORT");
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Identify order block for better entry                           |
//+------------------------------------------------------------------+
void IdentifyOrderBlock(bool isLong)
{
    MqlRates rates[];
    int copied = CopyRates(Symbol(), PERIOD_M1, 1, InpOrderBlockLookback, rates);
    
    if (copied < InpOrderBlockLookback) return;
    
    if (isLong)
    {
        // Find the last bearish candle before the break
        for (int i = 0; i < copied; i++)
        {
            if (rates[i].close < rates[i].open) // Bearish candle
            {
                g_orderBlockHigh = rates[i].open;
                g_orderBlockLow = rates[i].close;
                break;
            }
        }
    }
    else
    {
        // Find the last bullish candle before the break
        for (int i = 0; i < copied; i++)
        {
            if (rates[i].close > rates[i].open) // Bullish candle
            {
                g_orderBlockHigh = rates[i].close;
                g_orderBlockLow = rates[i].open;
                break;
            }
        }
    }
    
    Print(StringFormat("Order Block identified - High: %.5f, Low: %.5f", 
          g_orderBlockHigh, g_orderBlockLow));
}

//+------------------------------------------------------------------+
//| Check for order block entry                                     |
//+------------------------------------------------------------------+
void CheckOrderBlockEntry()
{
    double currentPrice = (SymbolInfoDouble(Symbol(), SYMBOL_ASK) + SymbolInfoDouble(Symbol(), SYMBOL_BID)) / 2;
    
    if (g_longSetup && currentPrice <= g_orderBlockHigh && currentPrice >= g_orderBlockLow)
    {
        ExecuteTrade(ORDER_TYPE_BUY);
    }
    else if (g_shortSetup && currentPrice <= g_orderBlockHigh && currentPrice >= g_orderBlockLow)
    {
        ExecuteTrade(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Execute immediate trade                                          |
//+------------------------------------------------------------------+
void ExecuteImmediateTrade()
{
    if (g_longSetup)
    {
        ExecuteTrade(ORDER_TYPE_BUY);
    }
    else if (g_shortSetup)
    {
        ExecuteTrade(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Execute trade with proper risk management                       |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
    double price, sl, tp;
    double riskReward = InpRiskRewardRatio;
    
    // Adjust risk-reward based on asset
    if (InpIsGold)
        riskReward = 4.0;
    else if (InpIsEURUSD)
        riskReward = 5.0;
    
    if (orderType == ORDER_TYPE_BUY)
    {
        price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        sl = g_prevDayLow - (10 * SymbolInfoDouble(Symbol(), SYMBOL_POINT));
        tp = price + (price - sl) * riskReward;
    }
    else // ORDER_TYPE_SELL
    {
        price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        sl = g_prevDayHigh + (10 * SymbolInfoDouble(Symbol(), SYMBOL_POINT));
        tp = price - (sl - price) * riskReward;
    }
    
    // Normalize prices
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    sl = NormalizeDouble(MathRound(sl / tickSize) * tickSize, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
    tp = NormalizeDouble(MathRound(tp / tickSize) * tickSize, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
    
    string comment = StringFormat("Daily BOS %.1f:1", riskReward);
    
    if (trade.PositionOpen(Symbol(), orderType, InpLotSize, price, sl, tp, comment))
    {
        g_tradeExecutedToday = true;
        Print(StringFormat("Trade executed - Type: %s, Price: %.5f, SL: %.5f, TP: %.5f", 
              (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL", price, sl, tp));
    }
    else
    {
        Print("Failed to execute trade. Error: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Normalize lot size according to broker requirements             |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots)
{
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    if (lots < minLot) lots = minLot;
    if (lots > maxLot) lots = maxLot;
    
    lots = MathRound(lots / stepLot) * stepLot;
    
    return lots;
}