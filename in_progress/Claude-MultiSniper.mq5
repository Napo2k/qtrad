//+------------------------------------------------------------------+
//|                                    Multi-Indicator Sniper EA.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Multi-Indicator Sniper Strategy - Triple-layered system for high-accuracy entries"

//--- Include trade library
#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== EMA Settings ==="
input int EMA1_Period = 25;              // EMA 1 Period (Fast)
input int EMA2_Period = 75;              // EMA 2 Period (Medium)  
input int EMA3_Period = 140;             // EMA 3 Period (Slow)

input group "=== RSI Settings ==="
input int RSI_Period = 75;               // RSI Period
input double RSI_Level = 50.0;           // RSI Trend Confirmation Level

input group "=== Stochastic Settings ==="
input int Stoch_K = 14;                  // Stochastic %K Period
input int Stoch_D = 3;                   // Stochastic %D Period
input int Stoch_Slowing = 3;             // Stochastic Slowing
input double Stoch_Oversold = 20.0;      // Stochastic Oversold Level
input double Stoch_Overbought = 80.0;    // Stochastic Overbought Level

input group "=== Risk Management ==="
input double LotSize = 0.1;              // Fixed Lot Size
input bool UseRiskPercent = true;        // Use Risk Percentage instead of fixed lot
input double RiskPercent = 2.0;          // Risk Percentage of account balance
input int StopLoss = 50;                 // Stop Loss in points
input int TakeProfit = 100;              // Take Profit in points
input bool UseTrailingStop = true;       // Enable Trailing Stop
input int TrailingStart = 20;            // Trailing Stop Start (points)
input int TrailingStep = 10;             // Trailing Stop Step (points)

input group "=== Trade Settings ==="
input bool AllowLongTrades = true;       // Allow Long Trades
input bool AllowShortTrades = true;      // Allow Short Trades
input int MaxTrades = 1;                 // Maximum Open Trades
input int MagicNumber = 123456;          // Magic Number
input string TradeComment = "SniperEA";  // Trade Comment

input group "=== Signal Filters ==="
input int MinBarsForSignal = 5;          // Minimum bars since last opposite signal
input bool UseTimeFilter = false;        // Enable Time Filter
input int StartHour = 8;                 // Trading Start Hour
input int EndHour = 22;                  // Trading End Hour

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
// Indicator handles
int hEMA1, hEMA2, hEMA3;
int hRSI;
int hStoch;

// Indicator buffers
double EMA1[], EMA2[], EMA3[];
double RSI[];
double StochMain[], StochSignal[];

// Signal tracking
datetime lastSignalTime = 0;
int lastSignalType = 0; // 1 = bullish, -1 = bearish, 0 = none

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    hEMA1 = iMA(_Symbol, PERIOD_CURRENT, EMA1_Period, 0, MODE_EMA, PRICE_CLOSE);
    hEMA2 = iMA(_Symbol, PERIOD_CURRENT, EMA2_Period, 0, MODE_EMA, PRICE_CLOSE);
    hEMA3 = iMA(_Symbol, PERIOD_CURRENT, EMA3_Period, 0, MODE_EMA, PRICE_CLOSE);
    hRSI = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    hStoch = iStochastic(_Symbol, PERIOD_CURRENT, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
    
    // Check if indicators are created successfully
    if(hEMA1 == INVALID_HANDLE || hEMA2 == INVALID_HANDLE || hEMA3 == INVALID_HANDLE ||
       hRSI == INVALID_HANDLE || hStoch == INVALID_HANDLE)
    {
        Print("Error creating indicators");
        return INIT_FAILED;
    }
    
    // Set array as series
    ArraySetAsSeries(EMA1, true);
    ArraySetAsSeries(EMA2, true);
    ArraySetAsSeries(EMA3, true);
    ArraySetAsSeries(RSI, true);
    ArraySetAsSeries(StochMain, true);
    ArraySetAsSeries(StochSignal, true);
    
    // Set trade parameters
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    
    Print("Multi-Indicator Sniper EA initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    if(hEMA1 != INVALID_HANDLE) IndicatorRelease(hEMA1);
    if(hEMA2 != INVALID_HANDLE) IndicatorRelease(hEMA2);
    if(hEMA3 != INVALID_HANDLE) IndicatorRelease(hEMA3);
    if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
    if(hStoch != INVALID_HANDLE) IndicatorRelease(hStoch);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if it's a new bar
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    if(currentBarTime == lastBarTime)
        return;
        
    lastBarTime = currentBarTime;
    
    // Update indicator values
    if(!UpdateIndicators())
        return;
    
    // Check time filter
    if(UseTimeFilter && !IsTimeToTrade())
        return;
    
    // Check maximum trades
    if(CountOpenTrades() >= MaxTrades)
    {
        ManageOpenTrades();
        return;
    }
    
    // Check for trading signals
    CheckTradingSignals();
    
    // Manage open trades
    ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Update all indicator values                                      |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
    // Copy indicator values
    if(CopyBuffer(hEMA1, 0, 0, 3, EMA1) < 3) return false;
    if(CopyBuffer(hEMA2, 0, 0, 3, EMA2) < 3) return false;
    if(CopyBuffer(hEMA3, 0, 0, 3, EMA3) < 3) return false;
    if(CopyBuffer(hRSI, 0, 0, 3, RSI) < 3) return false;
    if(CopyBuffer(hStoch, 0, 0, 3, StochMain) < 3) return false;
    if(CopyBuffer(hStoch, 1, 0, 3, StochSignal) < 3) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
    // Get current price
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check bullish setup
    if(AllowLongTrades && IsBullishSetup())
    {
        // Check if stochastic gives entry signal
        if(IsStochasticBuySignal())
        {
            // Check minimum bars since last opposite signal
            if(BarsSinceLastSignal(-1) >= MinBarsForSignal)
            {
                OpenBuyTrade();
                lastSignalTime = TimeCurrent();
                lastSignalType = 1;
            }
        }
    }
    
    // Check bearish setup
    if(AllowShortTrades && IsBearishSetup())
    {
        // Check if stochastic gives entry signal
        if(IsStochasticSellSignal())
        {
            // Check minimum bars since last opposite signal
            if(BarsSinceLastSignal(1) >= MinBarsForSignal)
            {
                OpenSellTrade();
                lastSignalTime = TimeCurrent();
                lastSignalType = -1;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check bullish setup (EMA + RSI confirmation)                    |
//+------------------------------------------------------------------+
bool IsBullishSetup()
{
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // EMA trend confirmation: Price above all EMAs and EMAs in correct order
    bool emaConfirm = (currentPrice > EMA1[0]) && 
                      (EMA1[0] > EMA2[0]) && 
                      (EMA2[0] > EMA3[0]);
    
    // RSI confirmation: RSI above 50 (trend strength)
    bool rsiConfirm = RSI[0] > RSI_Level;
    
    return emaConfirm && rsiConfirm;
}

//+------------------------------------------------------------------+
//| Check bearish setup (EMA + RSI confirmation)                    |
//+------------------------------------------------------------------+
bool IsBearishSetup()
{
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // EMA trend confirmation: Price below all EMAs and EMAs in correct order
    bool emaConfirm = (currentPrice < EMA1[0]) && 
                      (EMA1[0] < EMA2[0]) && 
                      (EMA2[0] < EMA3[0]);
    
    // RSI confirmation: RSI below 50 (trend strength)
    bool rsiConfirm = RSI[0] < RSI_Level;
    
    return emaConfirm && rsiConfirm;
}

//+------------------------------------------------------------------+
//| Check stochastic buy signal                                     |
//+------------------------------------------------------------------+
bool IsStochasticBuySignal()
{
    // Stochastic was in oversold zone and now crossing upward
    bool wasOversold = (StochMain[1] < Stoch_Oversold) && (StochSignal[1] < Stoch_Oversold);
    bool crossingUp = (StochMain[0] > StochSignal[0]) && (StochMain[1] <= StochSignal[1]);
    bool aboveOversold = (StochMain[0] > Stoch_Oversold) || (StochSignal[0] > Stoch_Oversold);
    
    return wasOversold && crossingUp && aboveOversold;
}

//+------------------------------------------------------------------+
//| Check stochastic sell signal                                    |
//+------------------------------------------------------------------+
bool IsStochasticSellSignal()
{
    // Stochastic was in overbought zone and now crossing downward
    bool wasOverbought = (StochMain[1] > Stoch_Overbought) && (StochSignal[1] > Stoch_Overbought);
    bool crossingDown = (StochMain[0] < StochSignal[0]) && (StochMain[1] >= StochSignal[1]);
    bool belowOverbought = (StochMain[0] < Stoch_Overbought) || (StochSignal[0] < Stoch_Overbought);
    
    return wasOverbought && crossingDown && belowOverbought;
}

//+------------------------------------------------------------------+
//| Open buy trade                                                  |
//+------------------------------------------------------------------+
void OpenBuyTrade()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    double lotSize = CalculateLotSize();
    double sl = (StopLoss > 0) ? ask - (StopLoss * point) : 0;
    double tp = (TakeProfit > 0) ? ask + (TakeProfit * point) : 0;
    
    if(trade.Buy(lotSize, _Symbol, ask, sl, tp, TradeComment))
    {
        Print("Buy order opened: ", trade.ResultOrder(), " at price: ", ask);
    }
    else
    {
        Print("Failed to open buy order: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Open sell trade                                                 |
//+------------------------------------------------------------------+
void OpenSellTrade()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    double lotSize = CalculateLotSize();
    double sl = (StopLoss > 0) ? bid + (StopLoss * point) : 0;
    double tp = (TakeProfit > 0) ? bid - (TakeProfit * point) : 0;
    
    if(trade.Sell(lotSize, _Symbol, bid, sl, tp, TradeComment))
    {
        Print("Sell order opened: ", trade.ResultOrder(), " at price: ", bid);
    }
    else
    {
        Print("Failed to open sell order: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk management                     |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    if(!UseRiskPercent)
        return LotSize;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * RiskPercent / 100.0;
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(StopLoss <= 0)
        return LotSize;
    
    double lotSize = riskAmount / (StopLoss * point * tickValue / point);
    
    // Normalize lot size
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Count open trades                                               |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Manage open trades (trailing stop, etc.)                       |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    if(!UseTrailingStop)
        return;
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;
        
        ulong ticket = PositionGetInteger(POSITION_TICKET);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        if(posType == POSITION_TYPE_BUY)
        {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            
            if(bid - openPrice >= TrailingStart * point)
            {
                double newSL = bid - TrailingStep * point;
                if(newSL > currentSL + point || currentSL == 0)
                {
                    trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                }
            }
        }
        else if(posType == POSITION_TYPE_SELL)
        {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            if(openPrice - ask >= TrailingStart * point)
            {
                double newSL = ask + TrailingStep * point;
                if(newSL < currentSL - point || currentSL == 0)
                {
                    trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if it's time to trade                                     |
//+------------------------------------------------------------------+
bool IsTimeToTrade()
{
    MqlDateTime time;
    TimeToStruct(TimeCurrent(), time);
    
    int currentHour = time.hour;
    
    if(StartHour <= EndHour)
        return (currentHour >= StartHour && currentHour <= EndHour);
    else
        return (currentHour >= StartHour || currentHour <= EndHour);
}

//+------------------------------------------------------------------+
//| Calculate bars since last opposite signal                       |
//+------------------------------------------------------------------+
int BarsSinceLastSignal(int oppositeSignalType)
{
    if(lastSignalType != oppositeSignalType)
        return MinBarsForSignal;
    
    datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    return (int)((currentTime - lastSignalTime) / PeriodSeconds(PERIOD_CURRENT));
}

//+------------------------------------------------------------------+