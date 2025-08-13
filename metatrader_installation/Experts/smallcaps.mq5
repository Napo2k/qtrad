//+------------------------------------------------------------------+
//|                                    SmallCapTradingStrategy.mq5 |
//|                                  Copyright 2025, Your Name     |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Name"
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Input parameters
input group "=== Strategy Parameters ==="
input double   VolumeMultiplier = 3.0;        // Volume spike multiplier
input int      VolumeLookback = 20;            // Bars to check for average volume
input double   MaxMarketCap = 2000000000;     // Maximum market cap (2B)
input double   MinPrice = 1.0;                // Minimum stock price
input double   MaxPrice = 50.0;               // Maximum stock price
input int      VWAPPeriod = 20;               // VWAP calculation period
input double   VWAPBuffer = 0.002;            // VWAP buffer (0.2%)

input group "=== Risk Management ==="
input double   TrailingStopPercent = 15.0;    // Initial trailing stop (%)
input double   TakeProfitPercent = 100.0;     // Take profit target (%)
input double   RiskPerTrade = 2.0;            // Risk per trade (% of account)
input double   MinRiskReward = 2.0;           // Minimum risk/reward ratio

input group "=== Trading Settings ==="
input int      MagicNumber = 123456;          // Magic number
input string   TradeComment = "SmallCap_EA";  // Trade comment
input bool     EnableTrading = true;          // Enable trading
input int      MaxPositions = 1;              // Maximum open positions

//--- Global variables
CTrade         trade;
CPositionInfo  position;
COrderInfo     order;

double vwap_buffer[];
long volume_buffer[];
double high_buffer[];
double low_buffer[];
double close_buffer[];
double typical_price[];

//--- Strategy state variables
bool signal_generated = false;
double entry_price = 0.0;
double trailing_stop = 0.0;
double take_profit_level = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Set magic number for trade operations
    trade.SetExpertMagicNumber(MagicNumber);
    
    //--- Initialize arrays
    ArraySetAsSeries(vwap_buffer, true);
    ArraySetAsSeries(volume_buffer, true);
    ArraySetAsSeries(high_buffer, true);
    ArraySetAsSeries(low_buffer, true);
    ArraySetAsSeries(close_buffer, true);
    ArraySetAsSeries(typical_price, true);
    
    //--- Resize arrays
    ArrayResize(vwap_buffer, VWAPPeriod + 10);
    ArrayResize(volume_buffer, VolumeLookback + 10);
    ArrayResize(high_buffer, VWAPPeriod + 10);
    ArrayResize(low_buffer, VWAPPeriod + 10);
    ArrayResize(close_buffer, VWAPPeriod + 10);
    ArrayResize(typical_price, VWAPPeriod + 10);
    
    Print("SmallCap Trading Strategy EA initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("SmallCap Trading Strategy EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!EnableTrading) return;
    
    //--- Check for new bar
    static datetime last_bar_time = 0;
    datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    if(current_bar_time == last_bar_time) return;
    last_bar_time = current_bar_time;
    
    //--- Update buffers
    UpdateBuffers();
    
    //--- Check market conditions
    if(!CheckMarketConditions()) return;
    
    //--- Manage existing positions
    ManagePositions();
    
    //--- Look for new entry signals
    if(CountOpenPositions() < MaxPositions)
    {
        CheckEntrySignals();
    }
}

//+------------------------------------------------------------------+
//| Update price and volume buffers                                 |
//+------------------------------------------------------------------+
void UpdateBuffers()
{
    //--- Copy price data
    if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, VWAPPeriod + 5, high_buffer) <= 0) return;
    if(CopyLow(_Symbol, PERIOD_CURRENT, 0, VWAPPeriod + 5, low_buffer) <= 0) return;
    if(CopyClose(_Symbol, PERIOD_CURRENT, 0, VWAPPeriod + 5, close_buffer) <= 0) return;
    if(CopyRealVolume(_Symbol, PERIOD_CURRENT, 0, VolumeLookback + 5, volume_buffer) <= 0)
    {
        // If real volume is not available, use tick volume
        if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, VolumeLookback + 5, volume_buffer) <= 0) return;
    }
    
    //--- Calculate typical price
    for(int i = 0; i < VWAPPeriod + 5; i++)
    {
        typical_price[i] = (high_buffer[i] + low_buffer[i] + close_buffer[i]) / 3.0;
    }
    
    //--- Calculate VWAP
    CalculateVWAP();
}

//+------------------------------------------------------------------+
//| Calculate Volume Weighted Average Price (VWAP)                  |
//+------------------------------------------------------------------+
void CalculateVWAP()
{
    int available_bars = MathMin(ArraySize(typical_price), ArraySize(volume_buffer));
    if(available_bars < VWAPPeriod) return; // Not enough data
    
    for(int i = 0; i < available_bars - VWAPPeriod + 1; i++)
    {
        double sum_volume = 0.0;
        double sum_typical_volume = 0.0;
        
        for(int j = i; j < i + VWAPPeriod; j++)
        {
            if(j >= available_bars) break; // Safety check
            
            sum_volume += volume_buffer[j];
            sum_typical_volume += typical_price[j] * volume_buffer[j];
        }
        
        if(sum_volume > 0 && i < ArraySize(vwap_buffer))
            vwap_buffer[i] = sum_typical_volume / sum_volume;
        else if(i < ArraySize(vwap_buffer))
            vwap_buffer[i] = (i < ArraySize(typical_price)) ? typical_price[i] : 0.0;
    }
}

//+------------------------------------------------------------------+
//| Check market conditions (price and market cap filters)          |
//+------------------------------------------------------------------+
bool CheckMarketConditions()
{
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    //--- Check price range
    if(current_price < MinPrice || current_price > MaxPrice)
        return false;
    
    //--- Note: Market cap filtering would require external data
    //--- For backtesting, we assume the selected symbol meets criteria
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                         |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    if(ArraySize(volume_buffer) < VolumeLookback + 1) return;
    if(ArraySize(vwap_buffer) < 2) return;
    
    //--- Calculate average volume
    double avg_volume = 0.0;
    for(int i = 1; i <= VolumeLookback; i++)
    {
        avg_volume += volume_buffer[i];
    }
    avg_volume = avg_volume / VolumeLookback;
    
    //--- Check for volume spike
    double current_volume = volume_buffer[0];
    bool volume_spike = (current_volume >= avg_volume * VolumeMultiplier);
    
    //--- Check price vs VWAP
    double current_price = close_buffer[0];
    double current_vwap = vwap_buffer[0];
    double vwap_threshold = current_vwap * (1.0 + VWAPBuffer);
    
    bool price_above_vwap = (current_price > vwap_threshold);
    
    //--- Check for upward momentum
    bool upward_momentum = (close_buffer[0] > close_buffer[1]);
    
    //--- Generate entry signal
    if(volume_spike && price_above_vwap && upward_momentum)
    {
        OpenLongPosition();
    }
}

//+------------------------------------------------------------------+
//| Open long position                                              |
//+------------------------------------------------------------------+
void OpenLongPosition()
{
    double ask_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    //--- Calculate position size based on risk
    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount = account_balance * (RiskPerTrade / 100.0);
    
    //--- Calculate stop loss and take profit
    double stop_loss = ask_price * (1.0 - TrailingStopPercent / 100.0);
    double take_profit = ask_price * (1.0 + TakeProfitPercent / 100.0);
    
    //--- Calculate position size
    double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double pip_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double stop_distance = ask_price - stop_loss;
    
    double lot_size = 0.1; // Default lot size
    if(stop_distance > 0 && pip_value > 0)
    {
        lot_size = NormalizeDouble(risk_amount / (stop_distance / pip_size * pip_value), 2);
    }
    
    //--- Normalize lot size
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lot_size = MathMax(lot_size, min_lot);
    lot_size = MathMin(lot_size, max_lot);
    lot_size = NormalizeDouble(lot_size / lot_step, 0) * lot_step;
    
    //--- Place order
    if(trade.Buy(lot_size, _Symbol, ask_price, stop_loss, take_profit, TradeComment))
    {
        Print("Long position opened: Price=", ask_price, ", Lot=", lot_size, ", SL=", stop_loss, ", TP=", take_profit);
        
        //--- Store trade information for trailing stop
        entry_price = ask_price;
        trailing_stop = stop_loss;
        take_profit_level = take_profit;
        signal_generated = true;
    }
    else
    {
        Print("Failed to open long position. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                       |
//+------------------------------------------------------------------+
void ManagePositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Symbol() == _Symbol && position.Magic() == MagicNumber)
            {
                if(position.PositionType() == POSITION_TYPE_BUY)
                {
                    UpdateTrailingStop(position.Ticket());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update trailing stop for long positions                        |
//+------------------------------------------------------------------+
void UpdateTrailingStop(ulong ticket)
{
    if(!position.SelectByTicket(ticket)) return;
    
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double open_price = position.PriceOpen();
    double current_sl = position.StopLoss();
    
    //--- Calculate new trailing stop
    double new_trailing_stop = current_price * (1.0 - TrailingStopPercent / 100.0);
    
    //--- Only move stop loss up (for long positions)
    if(new_trailing_stop > current_sl && new_trailing_stop > open_price)
    {
        double current_tp = position.TakeProfit();
        
        if(trade.PositionModify(ticket, new_trailing_stop, current_tp))
        {
            Print("Trailing stop updated for ticket ", ticket, ": New SL=", new_trailing_stop);
        }
    }
}

//+------------------------------------------------------------------+
//| Count open positions                                            |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Symbol() == _Symbol && position.Magic() == MagicNumber)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Trade transaction function                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
    //--- Handle trade events
    if(trans.symbol == _Symbol)
    {
        switch(trans.type)
        {
            case TRADE_TRANSACTION_DEAL_ADD:
                if(trans.deal_type == DEAL_TYPE_BUY)
                {
                    Print("Long position opened at ", trans.price);
                }
                else if(trans.deal_type == DEAL_TYPE_SELL)
                {
                    Print("Position closed at ", trans.price);
                    signal_generated = false;
                }
                break;
        }
    }
}