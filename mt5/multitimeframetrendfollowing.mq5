//+------------------------------------------------------------------+
//|                          Multi_Timeframe_Trend_Following.mq5    |
//|                                                                  |
//|              Multi-Timeframe Trend Following with Pullbacks EA  |
//+------------------------------------------------------------------+
#property copyright "Multi-Timeframe Strategy EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// Input Parameters
input group "=== Timeframe Settings ==="
input ENUM_TIMEFRAMES Higher_Timeframe = PERIOD_H4;    // Higher Timeframe for Trend
input ENUM_TIMEFRAMES Lower_Timeframe = PERIOD_H1;     // Lower Timeframe for Entry

input group "=== EMA Settings ==="
input int EMA_200_Period = 200;                       // 200 EMA Period for Trend
input int EMA_20_Period = 20;                         // 20 EMA Period for Entry
input ENUM_APPLIED_PRICE EMA_Price = PRICE_CLOSE;     // EMA Applied Price

input group "=== Risk Management ==="
input double Risk_Percent = 2.0;                      // Risk Percentage per Trade
input double Min_RR_Ratio = 2.0;                      // Minimum Risk-Reward Ratio
input double Max_RR_Ratio = 3.0;                      // Maximum Risk-Reward Ratio

input group "=== Pattern Recognition ==="
input double Engulfing_Min_Body_Ratio = 0.6;          // Minimum body ratio for engulfing
input int Pullback_Bars = 5;                          // Minimum bars for pullback confirmation

input group "=== Trading Settings ==="
input int MagicNumber = 789123;                       // Magic Number
input string OrderComment = "MTF_Trend_Follow";            // Order OrderComment
input bool Use_Trailing_Stop = true;                  // Use Trailing Stop
input double Trailing_Stop_Points = 50;               // Trailing Stop in Points

// Global Variables
CTrade trade;
int ema_200_handle_higher;
int ema_20_handle_lower;
datetime last_bar_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    ema_200_handle_higher = iMA(_Symbol, Higher_Timeframe, EMA_200_Period, 0, MODE_EMA, EMA_Price);
    ema_20_handle_lower = iMA(_Symbol, Lower_Timeframe, EMA_20_Period, 0, MODE_EMA, EMA_Price);
    
    // Check if indicators are created successfully
    if(ema_200_handle_higher == INVALID_HANDLE || ema_20_handle_lower == INVALID_HANDLE)
    {
        Print("Error creating indicators");
        return(INIT_FAILED);
    }
    
    // Set trade parameters
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    
    Print("Multi-Timeframe Trend Following EA initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(ema_200_handle_higher != INVALID_HANDLE) IndicatorRelease(ema_200_handle_higher);
    if(ema_20_handle_lower != INVALID_HANDLE) IndicatorRelease(ema_20_handle_lower);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if new bar has formed on lower timeframe
    datetime current_bar_time = iTime(_Symbol, Lower_Timeframe, 0);
    if(current_bar_time == last_bar_time)
        return;
    
    last_bar_time = current_bar_time;
    
    // Manage existing positions
    if(Use_Trailing_Stop)
        ManageTrailingStop();
    
    // Check if we already have an open position
    if(PositionsTotal() > 0)
        return;
    
    // Get trend direction from higher timeframe
    int trend_direction = GetTrendDirection();
    if(trend_direction == 0) // No clear trend
        return;
    
    // Look for pullback and entry signals on lower timeframe
    if(trend_direction == 1) // Bullish trend
    {
        if(CheckBullishPullbackEntry())
            OpenBuyOrder();
    }
    else if(trend_direction == -1) // Bearish trend
    {
        if(CheckBearishPullbackEntry())
            OpenSellOrder();
    }
}

//+------------------------------------------------------------------+
//| Get trend direction from higher timeframe                        |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
    double ema_200_buffer[];
    if(CopyBuffer(ema_200_handle_higher, 0, 1, 3, ema_200_buffer) <= 0)
        return 0;
    
    double current_price = iClose(_Symbol, Higher_Timeframe, 1);
    double prev_price_1 = iClose(_Symbol, Higher_Timeframe, 2);
    double prev_price_2 = iClose(_Symbol, Higher_Timeframe, 3);
    
    // Check if price is consistently above/below 200 EMA
    bool bullish_trend = (current_price > ema_200_buffer[2] && 
                         prev_price_1 > ema_200_buffer[1] && 
                         prev_price_2 > ema_200_buffer[0]);
    
    bool bearish_trend = (current_price < ema_200_buffer[2] && 
                         prev_price_1 < ema_200_buffer[1] && 
                         prev_price_2 < ema_200_buffer[0]);
    
    if(bullish_trend) return 1;
    if(bearish_trend) return -1;
    return 0; // No clear trend
}

//+------------------------------------------------------------------+
//| Check for bullish pullback entry                                 |
//+------------------------------------------------------------------+
bool CheckBullishPullbackEntry()
{
    double ema_20_buffer[];
    if(CopyBuffer(ema_20_handle_lower, 0, 1, 5, ema_20_buffer) <= 0)
        return false;
    
    // Check if we had a pullback (price below 20 EMA)
    bool had_pullback = false;
    for(int i = 1; i <= Pullback_Bars; i++)
    {
        double close_price = iClose(_Symbol, Lower_Timeframe, i);
        if(close_price < ema_20_buffer[5-i])
        {
            had_pullback = true;
            break;
        }
    }
    
    if(!had_pullback)
        return false;
    
    // Current price should be back above 20 EMA
    double current_close = iClose(_Symbol, Lower_Timeframe, 1);
    if(current_close <= ema_20_buffer[4])
        return false;
    
    // Check for bullish price action (engulfing pattern or trend line break)
    bool bullish_signal = IsBullishEngulfing(1) || IsTrendLineBreak(1, true);
    
    return bullish_signal;
}

//+------------------------------------------------------------------+
//| Check for bearish pullback entry                                 |
//+------------------------------------------------------------------+
bool CheckBearishPullbackEntry()
{
    double ema_20_buffer[];
    if(CopyBuffer(ema_20_handle_lower, 0, 1, 5, ema_20_buffer) <= 0)
        return false;
    
    // Check if we had a pullback (price above 20 EMA)
    bool had_pullback = false;
    for(int i = 1; i <= Pullback_Bars; i++)
    {
        double close_price = iClose(_Symbol, Lower_Timeframe, i);
        if(close_price > ema_20_buffer[5-i])
        {
            had_pullback = true;
            break;
        }
    }
    
    if(!had_pullback)
        return false;
    
    // Current price should be back below 20 EMA
    double current_close = iClose(_Symbol, Lower_Timeframe, 1);
    if(current_close >= ema_20_buffer[4])
        return false;
    
    // Check for bearish price action (engulfing pattern or trend line break)
    bool bearish_signal = IsBearishEngulfing(1) || IsTrendLineBreak(1, false);
    
    return bearish_signal;
}

//+------------------------------------------------------------------+
//| Check for bullish engulfing pattern                              |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(int shift)
{
    double open_1 = iOpen(_Symbol, Lower_Timeframe, shift);
    double close_1 = iClose(_Symbol, Lower_Timeframe, shift);
    double high_1 = iHigh(_Symbol, Lower_Timeframe, shift);
    double low_1 = iLow(_Symbol, Lower_Timeframe, shift);
    
    double open_2 = iOpen(_Symbol, Lower_Timeframe, shift + 1);
    double close_2 = iClose(_Symbol, Lower_Timeframe, shift + 1);
    double high_2 = iHigh(_Symbol, Lower_Timeframe, shift + 1);
    double low_2 = iLow(_Symbol, Lower_Timeframe, shift + 1);
    
    // Current candle is bullish
    if(close_1 <= open_1)
        return false;
    
    // Previous candle is bearish
    if(close_2 >= open_2)
        return false;
    
    // Current candle engulfs previous candle
    bool engulfs = (open_1 < close_2 && close_1 > open_2);
    
    // Check minimum body ratio
    double current_body = MathAbs(close_1 - open_1);
    double current_range = high_1 - low_1;
    double body_ratio = current_body / current_range;
    
    return (engulfs && body_ratio >= Engulfing_Min_Body_Ratio);
}

//+------------------------------------------------------------------+
//| Check for bearish engulfing pattern                              |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(int shift)
{
    double open_1 = iOpen(_Symbol, Lower_Timeframe, shift);
    double close_1 = iClose(_Symbol, Lower_Timeframe, shift);
    double high_1 = iHigh(_Symbol, Lower_Timeframe, shift);
    double low_1 = iLow(_Symbol, Lower_Timeframe, shift);
    
    double open_2 = iOpen(_Symbol, Lower_Timeframe, shift + 1);
    double close_2 = iClose(_Symbol, Lower_Timeframe, shift + 1);
    double high_2 = iHigh(_Symbol, Lower_Timeframe, shift + 1);
    double low_2 = iLow(_Symbol, Lower_Timeframe, shift + 1);
    
    // Current candle is bearish
    if(close_1 >= open_1)
        return false;
    
    // Previous candle is bullish
    if(close_2 <= open_2)
        return false;
    
    // Current candle engulfs previous candle
    bool engulfs = (open_1 > close_2 && close_1 < open_2);
    
    // Check minimum body ratio
    double current_body = MathAbs(close_1 - open_1);
    double current_range = high_1 - low_1;
    double body_ratio = current_body / current_range;
    
    return (engulfs && body_ratio >= Engulfing_Min_Body_Ratio);
}

//+------------------------------------------------------------------+
//| Check for trend line break (simplified)                          |
//+------------------------------------------------------------------+
bool IsTrendLineBreak(int shift, bool bullish)
{
    // Simplified trend line break detection
    // Look for break of recent swing high/low
    
    if(bullish)
    {
        // Find recent swing low
        double swing_low = iLow(_Symbol, Lower_Timeframe, shift + 1);
        for(int i = shift + 2; i <= shift + 5; i++)
        {
            double low = iLow(_Symbol, Lower_Timeframe, i);
            if(low < swing_low)
                swing_low = low;
        }
        
        // Check if current close is above recent swing high
        double current_close = iClose(_Symbol, Lower_Timeframe, shift);
        double swing_high = iHigh(_Symbol, Lower_Timeframe, shift + 1);
        
        return (current_close > swing_high);
    }
    else
    {
        // Find recent swing high
        double swing_high = iHigh(_Symbol, Lower_Timeframe, shift + 1);
        for(int i = shift + 2; i <= shift + 5; i++)
        {
            double high = iHigh(_Symbol, Lower_Timeframe, i);
            if(high > swing_high)
                swing_high = high;
        }
        
        // Check if current close is below recent swing low
        double current_close = iClose(_Symbol, Lower_Timeframe, shift);
        double swing_low = iLow(_Symbol, Lower_Timeframe, shift + 1);
        
        return (current_close < swing_low);
    }
}

//+------------------------------------------------------------------+
//| Open buy order                                                   |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // Find recent swing low for stop loss
    double swing_low = FindRecentSwingLow();
    double stop_loss = NormalizeDouble(swing_low, digits);
    
    // Calculate take profit based on risk-reward ratio
    double stop_distance = ask - stop_loss;
    double take_profit = NormalizeDouble(ask + (stop_distance * Min_RR_Ratio), digits);
    
    // Calculate lot size based on risk percentage
    double lot_size = CalculateLotSize(stop_distance);
    
    if(lot_size > 0 && stop_loss < ask)
    {
        if(trade.Buy(lot_size, _Symbol, ask, stop_loss, take_profit, OrderComment))
        {
            Print("Buy order opened successfully at ", ask);
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
void OpenSellOrder()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // Find recent swing high for stop loss
    double swing_high = FindRecentSwingHigh();
    double stop_loss = NormalizeDouble(swing_high, digits);
    
    // Calculate take profit based on risk-reward ratio
    double stop_distance = stop_loss - bid;
    double take_profit = NormalizeDouble(bid - (stop_distance * Min_RR_Ratio), digits);
    
    // Calculate lot size based on risk percentage
    double lot_size = CalculateLotSize(stop_distance);
    
    if(lot_size > 0 && stop_loss > bid)
    {
        if(trade.Sell(lot_size, _Symbol, bid, stop_loss, take_profit, OrderComment))
        {
            Print("Sell order opened successfully at ", bid);
        }
        else
        {
            Print("Failed to open sell order. Error: ", GetLastError());
        }
    }
}

//+------------------------------------------------------------------+
//| Find recent swing low                                            |
//+------------------------------------------------------------------+
double FindRecentSwingLow()
{
    double swing_low = iLow(_Symbol, Lower_Timeframe, 1);
    
    for(int i = 2; i <= 10; i++)
    {
        double low = iLow(_Symbol, Lower_Timeframe, i);
        if(low < swing_low)
            swing_low = low;
    }
    
    return swing_low;
}

//+------------------------------------------------------------------+
//| Find recent swing high                                           |
//+------------------------------------------------------------------+
double FindRecentSwingHigh()
{
    double swing_high = iHigh(_Symbol, Lower_Timeframe, 1);
    
    for(int i = 2; i <= 10; i++)
    {
        double high = iHigh(_Symbol, Lower_Timeframe, i);
        if(high > swing_high)
            swing_high = high;
    }
    
    return swing_high;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                      |
//+------------------------------------------------------------------+
double CalculateLotSize(double stop_distance)
{
    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount = account_balance * Risk_Percent / 100.0;
    
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    if(tick_value == 0 || tick_size == 0 || stop_distance == 0)
        return 0;
    
    double lot_size = (risk_amount * tick_size) / (stop_distance * tick_value);
    
    // Normalize lot size
    lot_size = MathFloor(lot_size / lot_step) * lot_step;
    
    // Check bounds
    if(lot_size < min_lot) lot_size = min_lot;
    if(lot_size > max_lot) lot_size = max_lot;
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Manage trailing stop                                             |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                double position_profit = PositionGetDouble(POSITION_PROFIT);
                if(position_profit > 0)
                {
                    double current_sl = PositionGetDouble(POSITION_SL);
                    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
                    ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                    
                    double new_sl = current_sl;
                    bool modify = false;
                    
                    if(pos_type == POSITION_TYPE_BUY)
                    {
                        double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                        double trail_sl = bid - Trailing_Stop_Points * _Point;
                        if(trail_sl > current_sl && trail_sl > open_price)
                        {
                            new_sl = trail_sl;
                            modify = true;
                        }
                    }
                    else if(pos_type == POSITION_TYPE_SELL)
                    {
                        double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                        double trail_sl = ask + Trailing_Stop_Points * _Point;
                        if(trail_sl < current_sl && trail_sl < open_price)
                        {
                            new_sl = trail_sl;
                            modify = true;
                        }
                    }
                    
                    if(modify)
                    {
                        trade.PositionModify(PositionGetTicket(i), new_sl, PositionGetDouble(POSITION_TP));
                    }
                }
            }
        }
    }
}