//+------------------------------------------------------------------+
//|                                           Triple_EMA_Cross_EA.mq5 |
//|                               Copyright 2024, Your Trading System |
//|                                              https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Trading System"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Triple EMA Crossover Expert Advisor for MT5"
#property description "Optimized for 5-minute timeframe with 1000 unit starting capital"

//--- Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- Create objects for trading operations
CTrade trade;
CPositionInfo position;
CAccountInfo account;

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== EMA Settings ==="
input int FastEMA_Period    = 8;     // Fast EMA Period
input int MidEMA_Period     = 21;    // Mid EMA Period  
input int SlowEMA_Period    = 55;    // Slow EMA Period

input group "=== Risk Management ==="
input double RiskPercent    = 2.0;   // Risk per trade (% of account)
input double StopLossPips   = 25.0;  // Stop Loss in pips
input double TakeProfitPips = 50.0;  // Take Profit in pips
input double MaxLotSize     = 0.10;  // Maximum lot size
input double MinLotSize     = 0.01;  // Minimum lot size

input group "=== Trading Settings ==="
input int MagicNumber       = 123456; // Magic Number
input bool UseTrailingStop  = true;   // Use trailing stop
input double TrailingStop   = 15.0;   // Trailing stop in pips
input double TrailingStep   = 5.0;    // Trailing step in pips
input int MaxSpread         = 30;     // Maximum allowed spread in points

input group "=== Time Filter ==="
input bool UseTimeFilter    = true;   // Use trading time filter
input int StartHour         = 8;      // Trading start hour (server time)
input int EndHour           = 22;     // Trading end hour (server time)

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
int handleFastEMA, handleMidEMA, handleSlowEMA;
double fastEMA[], midEMA[], slowEMA[];
datetime lastBarTime = 0;
double pointValue;
bool newBar = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Check if we're on 5-minute timeframe
    if(Period() != PERIOD_M5)
    {
        Alert("This EA is designed for 5-minute timeframe only!");
        return(INIT_FAILED);
    }
    
    //--- Validate input parameters
    if(FastEMA_Period >= MidEMA_Period || MidEMA_Period >= SlowEMA_Period)
    {
        Alert("EMA periods must be: Fast < Mid < Slow");
        return(INIT_FAILED);
    }
    
    if(StopLossPips <= 0 || TakeProfitPips <= 0)
    {
        Alert("Stop Loss and Take Profit must be positive values");
        return(INIT_FAILED);
    }
    
    //--- Initialize EMA handles
    handleFastEMA = iMA(Symbol(), PERIOD_CURRENT, FastEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    handleMidEMA  = iMA(Symbol(), PERIOD_CURRENT, MidEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    handleSlowEMA = iMA(Symbol(), PERIOD_CURRENT, SlowEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    
    //--- Check if handles are valid
    if(handleFastEMA == INVALID_HANDLE || handleMidEMA == INVALID_HANDLE || handleSlowEMA == INVALID_HANDLE)
    {
        Alert("Failed to create EMA handles");
        return(INIT_FAILED);
    }
    
    //--- Set array properties
    ArraySetAsSeries(fastEMA, true);
    ArraySetAsSeries(midEMA, true);
    ArraySetAsSeries(slowEMA, true);
    
    //--- Calculate point value for pip calculations
    pointValue = Point();
    if(Digits() == 5 || Digits() == 3)
        pointValue *= 10;
    
    //--- Set trade parameters
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(30);
    
    //--- Print initialization info
    Print("Triple EMA Crossover EA initialized successfully");
    Print("Fast EMA: ", FastEMA_Period, ", Mid EMA: ", MidEMA_Period, ", Slow EMA: ", SlowEMA_Period);
    Print("Risk per trade: ", RiskPercent, "%, SL: ", StopLossPips, " pips, TP: ", TakeProfitPips, " pips");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release indicator handles
    IndicatorRelease(handleFastEMA);
    IndicatorRelease(handleMidEMA);
    IndicatorRelease(handleSlowEMA);
    
    Print("Triple EMA Crossover EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check for new bar
    if(!IsNewBar()) return;
    
    //--- Check market conditions
    if(!IsMarketSuitable()) return;
    
    //--- Update EMA values
    if(!UpdateEMAValues()) return;
    
    //--- Apply trailing stop to existing positions
    if(UseTrailingStop)
        ApplyTrailingStop();
    
    //--- Check for trading signals
    CheckTradingSignals();
}

//+------------------------------------------------------------------+
//| Check if new bar has formed                                      |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentBarTime = iTime(Symbol(), PERIOD_CURRENT, 0);
    
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        newBar = true;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check market suitability for trading                            |
//+------------------------------------------------------------------+
bool IsMarketSuitable()
{
    //--- Check spread
    long spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    if(spread > MaxSpread)
    {
        Comment("Spread too high: ", spread, " points");
        return false;
    }
    
    //--- Check trading time
    if(UseTimeFilter)
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        
        if(dt.hour < StartHour || dt.hour >= EndHour)
        {
            Comment("Outside trading hours");
            return false;
        }
    }
    
    //--- Check if market is open
    if(!SymbolInfoInteger(Symbol(), SYMBOL_TRADE_MODE))
    {
        Comment("Market is closed");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update EMA values                                                |
//+------------------------------------------------------------------+
bool UpdateEMAValues()
{
    //--- Copy EMA values
    if(CopyBuffer(handleFastEMA, 0, 0, 3, fastEMA) <= 0) return false;
    if(CopyBuffer(handleMidEMA, 0, 0, 3, midEMA) <= 0) return false;
    if(CopyBuffer(handleSlowEMA, 0, 0, 3, slowEMA) <= 0) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for trading signals and execute trades                    |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
    //--- Check if we already have a position
    if(PositionSelect(Symbol()))
    {
        Comment("Position already open");
        return;
    }
    
    //--- Check for bullish crossover (BUY signal)
    bool buySignal = (fastEMA[0] > midEMA[0] && fastEMA[0] > slowEMA[0] &&
                      midEMA[0] > slowEMA[0] &&
                      (fastEMA[1] <= midEMA[1] || fastEMA[1] <= slowEMA[1]));
    
    //--- Check for bearish crossover (SELL signal)  
    bool sellSignal = (fastEMA[0] < midEMA[0] && fastEMA[0] < slowEMA[0] &&
                       midEMA[0] < slowEMA[0] &&
                       (fastEMA[1] >= midEMA[1] || fastEMA[1] >= slowEMA[1]));
    
    //--- Execute trades
    if(buySignal)
    {
        OpenBuyPosition();
    }
    else if(sellSignal)
    {
        OpenSellPosition();
    }
}

//+------------------------------------------------------------------+
//| Open Buy Position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double sl = ask - StopLossPips * pointValue;
    double tp = ask + TakeProfitPips * pointValue;
    
    double lotSize = CalculateLotSize(StopLossPips);
    
    //--- Normalize prices
    sl = NormalizeDouble(sl, Digits());
    tp = NormalizeDouble(tp, Digits());
    
    if(trade.Buy(lotSize, Symbol(), ask, sl, tp, "Triple EMA Buy"))
    {
        Print("BUY order opened successfully. Lot: ", lotSize, ", SL: ", sl, ", TP: ", tp);
        Comment("BUY position opened at ", ask);
    }
    else
    {
        Print("Failed to open BUY position. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Open Sell Position                                              |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double sl = bid + StopLossPips * pointValue;
    double tp = bid - TakeProfitPips * pointValue;
    
    double lotSize = CalculateLotSize(StopLossPips);
    
    //--- Normalize prices
    sl = NormalizeDouble(sl, Digits());
    tp = NormalizeDouble(tp, Digits());
    
    if(trade.Sell(lotSize, Symbol(), bid, sl, tp, "Triple EMA Sell"))
    {
        Print("SELL order opened successfully. Lot: ", lotSize, ", SL: ", sl, ", TP: ", tp);
        Comment("SELL position opened at ", bid);
    }
    else
    {
        Print("Failed to open SELL position. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk management                     |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPips)
{
    double accountBalance = account.Balance();
    double riskAmount = accountBalance * RiskPercent / 100.0;
    
    //--- Calculate tick value
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    if(tickValue == 0) tickValue = 1.0;
    
    //--- Calculate lot size based on risk
    double lotSize = riskAmount / (stopLossPips * pointValue / Point() * tickValue);
    
    //--- Apply lot size limits
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    if(minLot == 0) minLot = MinLotSize;
    if(maxLot == 0) maxLot = MaxLotSize;
    
    //--- Normalize lot size
    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);
    lotSize = MathMin(lotSize, MaxLotSize);
    
    //--- Round to lot step
    lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Apply trailing stop to open positions                           |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
    if(!PositionSelect(Symbol())) return;
    
    double currentSL = position.StopLoss();
    double openPrice = position.PriceOpen();
    long positionType = position.PositionType();
    
    if(positionType == POSITION_TYPE_BUY)
    {
        double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        double newSL = bid - TrailingStop * pointValue;
        
        if(bid - openPrice > TrailingStop * pointValue)
        {
            if(currentSL < newSL - TrailingStep * pointValue || currentSL == 0)
            {
                newSL = NormalizeDouble(newSL, Digits());
                if(trade.PositionModify(Symbol(), newSL, position.TakeProfit()))
                {
                    Print("Trailing stop updated for BUY position. New SL: ", newSL);
                }
            }
        }
    }
    else if(positionType == POSITION_TYPE_SELL)
    {
        double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        double newSL = ask + TrailingStop * pointValue;
        
        if(openPrice - ask > TrailingStop * pointValue)
        {
            if(currentSL > newSL + TrailingStep * pointValue || currentSL == 0)
            {
                newSL = NormalizeDouble(newSL, Digits());
                if(trade.PositionModify(Symbol(), newSL, position.TakeProfit()))
                {
                    Print("Trailing stop updated for SELL position. New SL: ", newSL);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Display current status on chart                                 |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
    string displayText = "\n";
    displayText += "=== Triple EMA Crossover EA ===\n";
    displayText += "Fast EMA: " + DoubleToString(fastEMA[0], Digits()) + "\n";
    displayText += "Mid EMA: " + DoubleToString(midEMA[0], Digits()) + "\n";
    displayText += "Slow EMA: " + DoubleToString(slowEMA[0], Digits()) + "\n";
    displayText += "Account Balance: " + DoubleToString(account.Balance(), 2) + "\n";
    displayText += "Spread: " + IntegerToString(SymbolInfoInteger(Symbol(), SYMBOL_SPREAD)) + " points\n";
    
    if(PositionSelect(Symbol()))
    {
        displayText += "Position: " + EnumToString((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)) + "\n";
        displayText += "Profit: " + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2) + "\n";
    }
    else
    {
        displayText += "Position: None\n";
    }
    
    Comment(displayText);
}