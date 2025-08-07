//+------------------------------------------------------------------+
//|                                    Mean Reversion Trend EA.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== Trend Filter Settings ==="
input int      MA_Period = 50;              // Moving Average Period
input ENUM_MA_METHOD MA_Method = MODE_SMA;  // Moving Average Method
input ENUM_APPLIED_PRICE MA_Price = PRICE_CLOSE; // Applied Price

input group "=== Entry Signal Settings ==="
input int      ConsecutiveBars = 3;         // Consecutive bars for signal
input double   MinCorrectionPct = 0.5;      // Minimum correction % (optional filter)

input group "=== Risk Management ==="
input double   LotSize = 0.1;               // Position Size
input int      StopLossPips = 100;          // Stop Loss in Pips
input int      TakeProfitPips = 0;          // Take Profit in Pips (0 = no TP)

input group "=== Exit Settings ==="
input int      MaxHoldBars = 10;            // Maximum bars to hold position
input bool     UseTimeExit = true;          // Use time-based exit

input group "=== General Settings ==="
input int      MagicNumber = 123456;        // Magic Number
input string   TradeComment = "MeanRev";    // Trade Comment

//--- Global Variables
CTrade trade;
int ma_handle;
double ma_buffer[];
datetime last_trade_time = 0;
int bars_in_position = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize trade object
    trade.SetExpertMagicNumber(MagicNumber);
    
    // Create moving average indicator
    ma_handle = iMA(_Symbol, _Period, MA_Period, 0, MA_Method, MA_Price);
    if(ma_handle == INVALID_HANDLE)
    {
        Print("Error creating MA indicator: ", GetLastError());
        return INIT_FAILED;
    }
    
    // Set array as series
    ArraySetAsSeries(ma_buffer, true);
    
    Print("Mean Reversion Trend EA initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handle
    if(ma_handle != INVALID_HANDLE)
        IndicatorRelease(ma_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if new bar
    static datetime last_bar_time = 0;
    if(iTime(_Symbol, _Period, 0) <= last_bar_time)
        return;
    last_bar_time = iTime(_Symbol, _Period, 0);
    
    // Update MA buffer
    if(CopyBuffer(ma_handle, 0, 0, ConsecutiveBars + 5, ma_buffer) <= 0)
    {
        Print("Error copying MA buffer: ", GetLastError());
        return;
    }
    
    // Check current position
    bool hasPosition = HasOpenPosition();
    
    if(hasPosition)
    {
        bars_in_position++;
        
        // Check time-based exit
        if(UseTimeExit && bars_in_position >= MaxHoldBars)
        {
            CloseAllPositions();
            bars_in_position = 0;
        }
    }
    else
    {
        bars_in_position = 0;
        
        // Check for entry signals
        CheckEntrySignals();
    }
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    // Get current price and MA
    double current_price = iClose(_Symbol, _Period, 0);
    double current_ma = ma_buffer[0];
    
    // Determine trend direction
    bool uptrend = current_price > current_ma;
    bool downtrend = current_price < current_ma;
    
    if(uptrend)
    {
        // Look for correction in uptrend (consecutive lower closes)
        if(CheckCorrectionSignal(true))
        {
            OpenLongPosition();
        }
    }
    else if(downtrend)
    {
        // Look for rally in downtrend (consecutive higher closes)
        if(CheckCorrectionSignal(false))
        {
            OpenShortPosition();
        }
    }
}

//+------------------------------------------------------------------+
//| Check for correction/rally signal                                |
//+------------------------------------------------------------------+
bool CheckCorrectionSignal(bool lookForCorrection)
{
    int consecutiveCount = 0;
    
    for(int i = 1; i <= ConsecutiveBars; i++)
    {
        double current_close = iClose(_Symbol, _Period, i);
        double previous_close = iClose(_Symbol, _Period, i + 1);
        
        if(lookForCorrection)
        {
            // Looking for correction (lower closes) in uptrend
            if(current_close < previous_close)
                consecutiveCount++;
            else
                break;
        }
        else
        {
            // Looking for rally (higher closes) in downtrend
            if(current_close > previous_close)
                consecutiveCount++;
            else
                break;
        }
    }
    
    return consecutiveCount >= ConsecutiveBars;
}

//+------------------------------------------------------------------+
//| Open long position                                               |
//+------------------------------------------------------------------+
void OpenLongPosition()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = 0, tp = 0;
    
    // Calculate stop loss
    if(StopLossPips > 0)
    {
        double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        if(SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5 || 
           SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3)
            pip_value *= 10;
        
        sl = ask - (StopLossPips * pip_value);
    }
    
    // Calculate take profit
    if(TakeProfitPips > 0)
    {
        double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        if(SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5 || 
           SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3)
            pip_value *= 10;
        
        tp = ask + (TakeProfitPips * pip_value);
    }
    
    // Open position
    if(trade.Buy(LotSize, _Symbol, ask, sl, tp, TradeComment))
    {
        Print("Long position opened at ", ask);
        last_trade_time = TimeCurrent();
    }
    else
    {
        Print("Error opening long position: ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Open short position                                              |
//+------------------------------------------------------------------+
void OpenShortPosition()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = 0, tp = 0;
    
    // Calculate stop loss
    if(StopLossPips > 0)
    {
        double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        if(SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5 || 
           SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3)
            pip_value *= 10;
        
        sl = bid + (StopLossPips * pip_value);
    }
    
    // Calculate take profit
    if(TakeProfitPips > 0)
    {
        double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        if(SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5 || 
           SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3)
            pip_value *= 10;
        
        tp = bid - (TakeProfitPips * pip_value);
    }
    
    // Open position
    if(trade.Sell(LotSize, _Symbol, bid, sl, tp, TradeComment))
    {
        Print("Short position opened at ", bid);
        last_trade_time = TimeCurrent();
    }
    else
    {
        Print("Error opening short position: ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Check if there's an open position                               |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                ulong ticket = PositionGetTicket(i);
                if(trade.PositionClose(ticket))
                {
                    Print("Position closed by time exit: ", ticket);
                }
                else
                {
                    Print("Error closing position: ", trade.ResultRetcode());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get pip value for current symbol                                 |
//+------------------------------------------------------------------+
double GetPipValue()
{
    double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5 || 
       SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3)
        pip_value *= 10;
    
    return pip_value;
}

//+------------------------------------------------------------------+