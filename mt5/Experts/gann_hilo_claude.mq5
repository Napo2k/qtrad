//+------------------------------------------------------------------+
//|                                        DualIndicatorStrategy.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- input parameters
input group "=== GANN HI-LO SETTINGS ==="
input int HPeriod = 13;              // HIGH Period
input int LPeriod = 21;              // LOW Period

input group "=== MARKET REVERSAL SETTINGS ==="
input int    bb_length = 20;         // BB Length
input double bb_mult = 2.0;          // BB StdDev Multiplier
input int    rsi_length = 14;        // RSI Length
input int    rsi_lower = 20;         // RSI Lower Level
input int    rsi_upper = 80;         // RSI Upper Level

input group "=== TRADING SETTINGS ==="
input double lot_size = 0.1;         // Lot Size
input int    stop_loss_pips = 50;    // Stop Loss (pips)
input int    take_profit_pips = 100; // Take Profit (pips)
input int    max_positions = 1;      // Maximum Positions
input bool   use_trailing_stop = true; // Use Trailing Stop
input int    trailing_stop_pips = 30;  // Trailing Stop (pips)
input int    trailing_step_pips = 10;  // Trailing Step (pips)

input group "=== TIME FILTER ==="
input bool   use_time_filter = true; // Use Time Filter
input int    start_hour = 8;         // Start Hour (broker time)
input int    end_hour = 18;          // End Hour (broker time)

//--- global variables
CTrade trade;
CPositionInfo position;
CAccountInfo account;

int gann_high_ma_handle;
int gann_low_ma_handle;
int bb_handle;
int rsi_handle;

double gann_high_ma[];
double gann_low_ma[];
double bb_upper[];
double bb_lower[];
double bb_middle[];
double rsi_values[];

datetime last_bar_time = 0;
double pip_value;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- initialize pip value
    pip_value = (_Digits == 5 || _Digits == 3) ? 10 * _Point : _Point;
    
    //--- create indicator handles
    gann_high_ma_handle = iMA(_Symbol, _Period, HPeriod, 0, MODE_SMA, PRICE_HIGH);
    gann_low_ma_handle = iMA(_Symbol, _Period, LPeriod, 0, MODE_SMA, PRICE_LOW);
    bb_handle = iBands(_Symbol, _Period, bb_length, 0, bb_mult, PRICE_CLOSE);
    rsi_handle = iRSI(_Symbol, _Period, rsi_length, PRICE_CLOSE);
    
    //--- check handles
    if(gann_high_ma_handle == INVALID_HANDLE || gann_low_ma_handle == INVALID_HANDLE ||
       bb_handle == INVALID_HANDLE || rsi_handle == INVALID_HANDLE)
    {
        Print("Error creating indicator handles");
        return INIT_FAILED;
    }
    
    //--- set arrays as series
    ArraySetAsSeries(gann_high_ma, true);
    ArraySetAsSeries(gann_low_ma, true);
    ArraySetAsSeries(bb_upper, true);
    ArraySetAsSeries(bb_lower, true);
    ArraySetAsSeries(bb_middle, true);
    ArraySetAsSeries(rsi_values, true);
    
    //--- set trade parameters
    trade.SetExpertMagicNumber(123456);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    Print("Dual Indicator Strategy initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- release indicator handles
    if(gann_high_ma_handle != INVALID_HANDLE) IndicatorRelease(gann_high_ma_handle);
    if(gann_low_ma_handle != INVALID_HANDLE) IndicatorRelease(gann_low_ma_handle);
    if(bb_handle != INVALID_HANDLE) IndicatorRelease(bb_handle);
    if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- check for new bar
    if(!IsNewBar()) return;
    
    //--- check time filter
    if(use_time_filter && !IsWithinTradingHours()) return;
    
    //--- update indicator data
    if(!UpdateIndicatorData()) return;
    
    //--- manage existing positions
    ManagePositions();
    
    //--- check for trading signals
    CheckTradingSignals();
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                         |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime current_time = iTime(_Symbol, _Period, 0);
    if(current_time != last_bar_time)
    {
        last_bar_time = current_time;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                   |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    if(start_hour <= end_hour)
        return (dt.hour >= start_hour && dt.hour < end_hour);
    else // overnight session
        return (dt.hour >= start_hour || dt.hour < end_hour);
}

//+------------------------------------------------------------------+
//| Update indicator data                                           |
//+------------------------------------------------------------------+
bool UpdateIndicatorData()
{
    //--- get Gann HiLo data
    if(CopyBuffer(gann_high_ma_handle, 0, 0, 3, gann_high_ma) <= 0) return false;
    if(CopyBuffer(gann_low_ma_handle, 0, 0, 3, gann_low_ma) <= 0) return false;
    
    //--- get Bollinger Bands data
    if(CopyBuffer(bb_handle, 1, 0, 3, bb_upper) <= 0) return false;
    if(CopyBuffer(bb_handle, 2, 0, 3, bb_lower) <= 0) return false;
    if(CopyBuffer(bb_handle, 0, 0, 3, bb_middle) <= 0) return false;
    
    //--- get RSI data
    if(CopyBuffer(rsi_handle, 0, 0, 3, rsi_values) <= 0) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate Gann HiLo value                                       |
//+------------------------------------------------------------------+
double GetGannHiLo(int shift = 0)
{
    double close_price = iClose(_Symbol, _Period, shift);
    double prev_close = iClose(_Symbol, _Period, shift + 1);
    
    // Determine direction
    int HLd = 0;
    if(prev_close > gann_high_ma[shift + 1])
        HLd = 1;
    else if(prev_close < gann_low_ma[shift + 1])
        HLd = -1;
    
    // Find last non-zero direction
    int HLv = HLd;
    if(HLd == 0)
    {
        // Look back for last signal
        for(int i = shift + 1; i < shift + 50; i++)
        {
            double hist_close = iClose(_Symbol, _Period, i + 1);
            if(hist_close > gann_high_ma[i + 1])
            {
                HLv = 1;
                break;
            }
            else if(hist_close < gann_low_ma[i + 1])
            {
                HLv = -1;
                break;
            }
        }
    }
    
    // Return appropriate level
    return (HLv == -1) ? gann_high_ma[shift] : gann_low_ma[shift];
}

//+------------------------------------------------------------------+
//| Check for trading signals                                       |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
    //--- don't trade if max positions reached
    if(PositionsTotal() >= max_positions) return;
    
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double gann_level = GetGannHiLo(0);
    double prev_gann_level = GetGannHiLo(1);
    
    //--- get previous prices
    double prev_close = iClose(_Symbol, _Period, 1);
    double prev_close2 = iClose(_Symbol, _Period, 2);
    
    //--- check for Gann HiLo crossover signals
    bool gann_bullish = (prev_close > gann_level && prev_close2 <= prev_gann_level);
    bool gann_bearish = (prev_close < gann_level && prev_close2 >= prev_gann_level);
    
    //--- check Market Reversal conditions
    bool bb_expansion = (bb_upper[0] - bb_lower[0]) > (bb_upper[1] - bb_lower[1]);
    bool rsi_oversold = rsi_values[0] < rsi_lower;
    bool rsi_overbought = rsi_values[0] > rsi_upper;
    bool rsi_extreme = rsi_oversold || rsi_overbought;
    
    //--- additional confirmation: price position relative to BB
    bool price_near_bb_lower = current_price <= bb_lower[0] + (bb_upper[0] - bb_lower[0]) * 0.2;
    bool price_near_bb_upper = current_price >= bb_upper[0] - (bb_upper[0] - bb_lower[0]) * 0.2;
    
    //--- BUY signal
    if(gann_bullish && rsi_oversold && price_near_bb_lower && bb_expansion)
    {
        OpenBuyPosition();
    }
    
    //--- SELL signal
    if(gann_bearish && rsi_overbought && price_near_bb_upper && bb_expansion)
    {
        OpenSellPosition();
    }
}

//+------------------------------------------------------------------+
//| Open buy position                                               |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = ask - stop_loss_pips * pip_value;
    double tp = ask + take_profit_pips * pip_value;
    
    if(trade.Buy(lot_size, _Symbol, ask, sl, tp, "Dual Strategy BUY"))
    {
        Print("Buy order opened at ", ask);
    }
    else
    {
        Print("Failed to open buy order. Error: ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Open sell position                                              |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = bid + stop_loss_pips * pip_value;
    double tp = bid - take_profit_pips * pip_value;
    
    if(trade.Sell(lot_size, _Symbol, bid, sl, tp, "Dual Strategy SELL"))
    {
        Print("Sell order opened at ", bid);
    }
    else
    {
        Print("Failed to open sell order. Error: ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                       |
//+------------------------------------------------------------------+
void ManagePositions()
{
    if(!use_trailing_stop) return;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol) continue;
        if(position.Magic() != 123456) continue;
        
        TrailingStop(position.Ticket());
    }
}

//+------------------------------------------------------------------+
//| Trailing stop function                                          |
//+------------------------------------------------------------------+
void TrailingStop(ulong ticket)
{
    if(!position.SelectByTicket(ticket)) return;
    
    double current_price;
    double new_sl;
    
    if(position.PositionType() == POSITION_TYPE_BUY)
    {
        current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        new_sl = current_price - trailing_stop_pips * pip_value;
        
        if(new_sl > position.StopLoss() + trailing_step_pips * pip_value)
        {
            trade.PositionModify(ticket, new_sl, position.TakeProfit());
        }
    }
    else if(position.PositionType() == POSITION_TYPE_SELL)
    {
        current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        new_sl = current_price + trailing_stop_pips * pip_value;
        
        if(new_sl < position.StopLoss() - trailing_step_pips * pip_value || position.StopLoss() == 0)
        {
            trade.PositionModify(ticket, new_sl, position.TakeProfit());
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                          |
//+------------------------------------------------------------------+
double CalculatePositionSize(double stop_loss_pips, double risk_percent = 2.0)
{
    double account_balance = account.Balance();
    double risk_amount = account_balance * risk_percent / 100.0;
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    
    if(tick_value == 0) return lot_size;
    
    double calculated_lots = risk_amount / (stop_loss_pips * tick_value * 10);
    
    //--- normalize lot size
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    calculated_lots = MathMax(min_lot, MathMin(max_lot, calculated_lots));
    calculated_lots = MathFloor(calculated_lots / lot_step) * lot_step;
    
    return calculated_lots;
}