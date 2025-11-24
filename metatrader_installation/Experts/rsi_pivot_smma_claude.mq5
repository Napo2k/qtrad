//+------------------------------------------------------------------+
//|                                    RSI_Pivot_SMMA_Strategy.mq5   |
//|                                                                  |
//|                      RSI + Pivots + SMMA Trading Strategy EA     |
//+------------------------------------------------------------------+
#property copyright "Trading Strategy EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// Input Parameters
input group "=== Indicator Settings ==="
input int RSI_Period = 14;                    // RSI Period
input ENUM_APPLIED_PRICE RSI_Price = PRICE_CLOSE; // RSI Applied Price
input double RSI_Overbought = 70.0;           // RSI Overbought Level
input double RSI_Oversold = 30.0;             // RSI Oversold Level

input int SMMA_Period = 20;                   // SMMA Period
input ENUM_APPLIED_PRICE SMMA_Price = PRICE_CLOSE; // SMMA Applied Price

input group "=== Risk Management ==="
input double FixedRiskAmount = 100.0;         // Fixed Risk Amount (USD)
input double ATR_Period = 14;                 // ATR Period for SL/TP
input double ATR_SL_Multiplier = 2.0;         // ATR Stop Loss Multiplier
input double ATR_TP_Multiplier = 1.6;         // ATR Take Profit Multiplier (0.8 * 2.0)

input group "=== Trading Hours ==="
input int StartHour = 1;                      // Start Trading Hour
input int StartMinute = 30;                   // Start Trading Minute
input int EndHour = 23;                       // End Trading Hour
input int EndMinute = 30;                     // End Trading Minute

input group "=== Strategy Settings ==="
input int MagicNumber = 123456;               // Magic Number
input string OrderComment = "RSI_Pivot_SMMA";      // Order OrderComment

// Global Variables
CTrade trade;
int rsi_handle;
int smma_handle;
int atr_handle;

double pivot_resistance1, pivot_support1;
double pivot_resistance2, pivot_support2;
double pivot_point;

datetime last_bar_time = 0;
int total_trades = 0;
int winning_trades = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    rsi_handle = iRSI(_Symbol, PERIOD_H1, RSI_Period, RSI_Price);
    smma_handle = iMA(_Symbol, PERIOD_H1, SMMA_Period, 0, MODE_SMMA, SMMA_Price);
    atr_handle = iATR(_Symbol, PERIOD_H1, ATR_Period);
    
    // Check if indicators are created successfully
    if(rsi_handle == INVALID_HANDLE || smma_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
    {
        Print("Error creating indicators");
        return(INIT_FAILED);
    }
    
    // Set trade parameters
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    
    Print("RSI Pivot SMMA Strategy EA initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
    if(smma_handle != INVALID_HANDLE) IndicatorRelease(smma_handle);
    if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if new bar has formed (1-hour timeframe)
    datetime current_bar_time = iTime(_Symbol, PERIOD_H1, 0);
    if(current_bar_time == last_bar_time)
        return;
    
    last_bar_time = current_bar_time;
    
    // Check trading hours
    if(!IsTradingTime())
        return;
    
    // Check if we already have an open position
    if(PositionsTotal() > 0)
        return;
    
    // Calculate pivot points
    CalculatePivotPoints();
    
    // Get indicator values
    double rsi_current = GetRSIValue(1);
    double rsi_previous = GetRSIValue(2);
    double smma_current = GetSMMAValue(1);
    double atr_value = GetATRValue(1);
    
    if(rsi_current == EMPTY_VALUE || smma_current == EMPTY_VALUE || atr_value == EMPTY_VALUE)
        return;
    
    // Get current price data
    double close_current = iClose(_Symbol, PERIOD_H1, 1);
    double close_previous = iClose(_Symbol, PERIOD_H1, 2);
    
    // Entry conditions
    bool buy_signal = CheckBuySignal(rsi_current, rsi_previous, smma_current, close_current, close_previous);
    bool sell_signal = CheckSellSignal(rsi_current, rsi_previous, smma_current, close_current, close_previous);
    
    // Execute trades
    if(buy_signal)
    {
        OpenBuyOrder(atr_value);
    }
    else if(sell_signal)
    {
        OpenSellOrder(atr_value);
    }
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                    |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
    MqlDateTime time_struct;
    TimeToStruct(TimeCurrent(), time_struct);
    
    int current_minutes = time_struct.hour * 60 + time_struct.min;
    int start_minutes = StartHour * 60 + StartMinute;
    int end_minutes = EndHour * 60 + EndMinute;
    
    return (current_minutes >= start_minutes && current_minutes <= end_minutes);
}

//+------------------------------------------------------------------+
//| Calculate pivot points                                           |
//+------------------------------------------------------------------+
void CalculatePivotPoints()
{
    double high = iHigh(_Symbol, PERIOD_D1, 1);
    double low = iLow(_Symbol, PERIOD_D1, 1);
    double close = iClose(_Symbol, PERIOD_D1, 1);
    
    pivot_point = (high + low + close) / 3.0;
    pivot_resistance1 = 2 * pivot_point - low;
    pivot_support1 = 2 * pivot_point - high;
    pivot_resistance2 = pivot_point + (high - low);
    pivot_support2 = pivot_point - (high - low);
}

//+------------------------------------------------------------------+
//| Get RSI value                                                    |
//+------------------------------------------------------------------+
double GetRSIValue(int shift)
{
    double rsi_buffer[];
    if(CopyBuffer(rsi_handle, 0, shift, 1, rsi_buffer) <= 0)
        return EMPTY_VALUE;
    return rsi_buffer[0];
}

//+------------------------------------------------------------------+
//| Get SMMA value                                                   |
//+------------------------------------------------------------------+
double GetSMMAValue(int shift)
{
    double smma_buffer[];
    if(CopyBuffer(smma_handle, 0, shift, 1, smma_buffer) <= 0)
        return EMPTY_VALUE;
    return smma_buffer[0];
}

//+------------------------------------------------------------------+
//| Get ATR value                                                    |
//+------------------------------------------------------------------+
double GetATRValue(int shift)
{
    double atr_buffer[];
    if(CopyBuffer(atr_handle, 0, shift, 1, atr_buffer) <= 0)
        return EMPTY_VALUE;
    return atr_buffer[0];
}

//+------------------------------------------------------------------+
//| Check buy signal conditions                                      |
//+------------------------------------------------------------------+
bool CheckBuySignal(double rsi_current, double rsi_previous, double smma_current, double close_current, double close_previous)
{
    // RSI oversold condition and moving up
    bool rsi_condition = (rsi_previous <= RSI_Oversold && rsi_current > RSI_Oversold);
    
    // Price above SMMA
    bool smma_condition = (close_current > smma_current);
    
    // Price near support level (pivot point analysis)
    bool pivot_condition = (close_current > pivot_support1 && close_current < pivot_point);
    
    // Additional momentum condition
    bool momentum_condition = (close_current > close_previous);
    
    return (rsi_condition && smma_condition && pivot_condition && momentum_condition);
}

//+------------------------------------------------------------------+
//| Check sell signal conditions                                     |
//+------------------------------------------------------------------+
bool CheckSellSignal(double rsi_current, double rsi_previous, double smma_current, double close_current, double close_previous)
{
    // RSI overbought condition and moving down
    bool rsi_condition = (rsi_previous >= RSI_Overbought && rsi_current < RSI_Overbought);
    
    // Price below SMMA
    bool smma_condition = (close_current < smma_current);
    
    // Price near resistance level (pivot point analysis)
    bool pivot_condition = (close_current < pivot_resistance1 && close_current > pivot_point);
    
    // Additional momentum condition
    bool momentum_condition = (close_current < close_previous);
    
    return (rsi_condition && smma_condition && pivot_condition && momentum_condition);
}

//+------------------------------------------------------------------+
//| Open buy order                                                   |
//+------------------------------------------------------------------+
void OpenBuyOrder(double atr_value)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // Calculate position size based on fixed risk amount
    double stop_loss_distance = atr_value * ATR_SL_Multiplier;
    double stop_loss = ask - stop_loss_distance;
    double take_profit = ask + (atr_value * ATR_TP_Multiplier);
    
    // Normalize prices
    stop_loss = NormalizeDouble(stop_loss, digits);
    take_profit = NormalizeDouble(take_profit, digits);
    
    // Calculate lot size based on fixed risk
    double lot_size = CalculateLotSize(stop_loss_distance, FixedRiskAmount);
    
    if(lot_size > 0)
    {
        if(trade.Buy(lot_size, _Symbol, ask, stop_loss, take_profit, OrderComment))
        {
            Print("Buy order opened successfully at ", ask);
            total_trades++;
        }
        else
        {
            Print("Failed to open buy order. Error: ", GetLastError());
        }
    }
}

//+------------------------------------------------------------------+
//| Open sell order                                                  |
//+------------------------------------------------------------------+
void OpenSellOrder(double atr_value)
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // Calculate position size based on fixed risk amount
    double stop_loss_distance = atr_value * ATR_SL_Multiplier;
    double stop_loss = bid + stop_loss_distance;
    double take_profit = bid - (atr_value * ATR_TP_Multiplier);
    
    // Normalize prices
    stop_loss = NormalizeDouble(stop_loss, digits);
    take_profit = NormalizeDouble(take_profit, digits);
    
    // Calculate lot size based on fixed risk
    double lot_size = CalculateLotSize(stop_loss_distance, FixedRiskAmount);
    
    if(lot_size > 0)
    {
        if(trade.Sell(lot_size, _Symbol, bid, stop_loss, take_profit, OrderComment))
        {
            Print("Sell order opened successfully at ", bid);
            total_trades++;
        }
        else
        {
            Print("Failed to open sell order. Error: ", GetLastError());
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on fixed risk amount                    |
//+------------------------------------------------------------------+
double CalculateLotSize(double stop_loss_distance, double risk_amount)
{
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    if(tick_value == 0 || tick_size == 0 || stop_loss_distance == 0)
        return 0;
    
    // Calculate lot size
    double lot_size = (risk_amount * tick_size) / (stop_loss_distance * tick_value);
    
    // Normalize lot size
    lot_size = MathFloor(lot_size / lot_step) * lot_step;
    
    // Check bounds
    if(lot_size < min_lot) lot_size = min_lot;
    if(lot_size > max_lot) lot_size = max_lot;
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Trade transaction event handler                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
    // Track winning trades for statistics
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        if(HistoryDealSelect(trans.deal))
        {
            long deal_magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
            if(deal_magic == MagicNumber)
            {
                double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                if(profit > 0)
                    winning_trades++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get current win rate                                             |
//+------------------------------------------------------------------+
double GetWinRate()
{
    if(total_trades == 0)
        return 0.0;
    return (double)winning_trades / total_trades * 100.0;
}