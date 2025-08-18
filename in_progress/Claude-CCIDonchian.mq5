//+------------------------------------------------------------------+
//|                                           CCI_Donchian_Breakout.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Input Parameters
input group "=== Trading Parameters ==="
input double LotSize = 0.1;                    // Lot size for trading
input int CCI_Period = 14;                     // CCI Period
input int Donchian_Period = 40;                // Donchian Channel Period
input double ATR_Multiplier = 1.1;             // ATR multiplier for stop loss
input int ATR_Period = 14;                     // ATR Period
input int Exit_Bars = 10;                      // Exit after N bars if SL not hit
input int Magic_Number = 12345;                // Magic number for trades

input group "=== Risk Management ==="
input double MaxSpread = 3.0;                  // Maximum spread in pips
input bool UseMaxRisk = true;                  // Use maximum risk per trade
input double MaxRiskPercent = 2.0;             // Maximum risk per trade (%)

input group "=== Time Filters ==="
input bool UseTimeFilter = false;              // Enable time filter
input int StartHour = 8;                       // Start trading hour
input int EndHour = 18;                        // Stop trading hour

// Global Variables
int cci_handle;
int atr_handle;
double cci_buffer[];
double atr_buffer[];
datetime last_trade_time = 0;
ulong current_ticket = 0;
int bars_since_entry = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    cci_handle = iCCI(_Symbol, PERIOD_CURRENT, CCI_Period, PRICE_TYPICAL);
    atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
    
    if(cci_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
    {
        Print("Failed to initialize indicators");
        return INIT_FAILED;
    }
    
    // Set array properties
    ArraySetAsSeries(cci_buffer, true);
    ArraySetAsSeries(atr_buffer, true);
    
    // Validate symbol
    if(_Symbol != "USDJPY")
    {
        Print("Warning: This EA is designed for USD/JPY pair");
    }
    
    // Validate timeframe
    if(_Period != PERIOD_H1)
    {
        Print("Warning: This EA is designed for H1 timeframe");
    }
    
    Print("CCI Donchian Breakout EA initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    if(cci_handle != INVALID_HANDLE)
        IndicatorRelease(cci_handle);
    if(atr_handle != INVALID_HANDLE)
        IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if new bar
    static datetime last_bar_time = 0;
    datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    if(current_bar_time == last_bar_time)
        return;
        
    last_bar_time = current_bar_time;
    
    // Update position status
    UpdatePositionStatus();
    
    // Check exit conditions first
    CheckExitConditions();
    
    // Check entry conditions if no position
    if(current_ticket == 0)
    {
        CheckEntryConditions();
    }
}

//+------------------------------------------------------------------+
//| Check entry conditions                                           |
//+------------------------------------------------------------------+
void CheckEntryConditions()
{
    // Time filter
    if(UseTimeFilter && !IsTimeToTrade())
        return;
    
    // Spread filter
    if(GetCurrentSpread() > MaxSpread)
        return;
    
    // Get CCI values
    if(CopyBuffer(cci_handle, 0, 1, 4, cci_buffer) < 4)
    {
        Print("Failed to get CCI values");
        return;
    }
    
    // Check for 3 consecutive rising CCI candles
    if(!(cci_buffer[3] < cci_buffer[2] && cci_buffer[2] < cci_buffer[1] && cci_buffer[1] < cci_buffer[0]))
        return;
    
    // Get Donchian Channel high (highest high of last 40 bars)
    double donchian_high = GetDonchianHigh(Donchian_Period);
    if(donchian_high <= 0)
        return;
    
    // Get ATR for stop loss calculation
    if(CopyBuffer(atr_handle, 0, 1, 1, atr_buffer) < 1)
    {
        Print("Failed to get ATR values");
        return;
    }
    
    // Calculate lot size based on risk
    double lot_size = LotSize;
    if(UseMaxRisk)
    {
        double sl_distance = atr_buffer[0] * ATR_Multiplier;
        lot_size = CalculateLotSize(sl_distance);
    }
    
    // Normalize lot size
    lot_size = NormalizeLotSize(lot_size);
    
    // Place buy stop order
    double entry_price = donchian_high + 1 * _Point; // 1 pip above Donchian high
    double stop_loss = entry_price - (atr_buffer[0] * ATR_Multiplier);
    
    if(PlaceBuyStopOrder(entry_price, stop_loss, lot_size))
    {
        Print("Buy stop order placed at: ", entry_price, " SL: ", stop_loss, " Lot: ", lot_size);
        last_trade_time = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Check exit conditions                                            |
//+------------------------------------------------------------------+
void CheckExitConditions()
{
    if(current_ticket == 0)
        return;
    
    // Check if position exists
    if(!PositionSelectByTicket(current_ticket))
    {
        current_ticket = 0;
        bars_since_entry = 0;
        return;
    }
    
    // Increment bars counter
    bars_since_entry++;
    
    // Exit after specified number of bars
    if(bars_since_entry >= Exit_Bars)
    {
        if(ClosePosition(current_ticket))
        {
            Print("Position closed after ", Exit_Bars, " bars");
            current_ticket = 0;
            bars_since_entry = 0;
        }
    }
}

//+------------------------------------------------------------------+
//| Update position status                                           |
//+------------------------------------------------------------------+
void UpdatePositionStatus()
{
    // Check if we have an active position
    if(current_ticket > 0)
    {
        if(!PositionSelectByTicket(current_ticket))
        {
            // Position was closed
            current_ticket = 0;
            bars_since_entry = 0;
        }
    }
    
    // Check for new positions opened by pending orders
    if(current_ticket == 0)
    {
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(PositionGetTicket(i) > 0)
            {
                if(PositionGetInteger(POSITION_MAGIC) == Magic_Number &&
                   PositionGetString(POSITION_SYMBOL) == _Symbol)
                {
                    current_ticket = PositionGetTicket(i);
                    bars_since_entry = 0;
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get Donchian Channel High                                        |
//+------------------------------------------------------------------+
double GetDonchianHigh(int period)
{
    double high_array[];
    ArraySetAsSeries(high_array, true);
    
    if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, period, high_array) < period)
    {
        Print("Failed to get high prices for Donchian calculation");
        return -1;
    }
    
    return ArrayMaximum(high_array, 0, WHOLE_ARRAY);
}

//+------------------------------------------------------------------+
//| Place buy stop order                                             |
//+------------------------------------------------------------------+
bool PlaceBuyStopOrder(double price, double sl, double lots)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_PENDING;
    request.type = ORDER_TYPE_BUY_STOP;
    request.symbol = _Symbol;
    request.volume = lots;
    request.price = NormalizeDouble(price, _Digits);
    request.sl = NormalizeDouble(sl, _Digits);
    request.tp = 0; // No take profit
    request.magic = Magic_Number;
    request.comment = "CCI Donchian Breakout";
    
    // Set expiration to end of next day
    request.type_time = ORDER_TIME_SPECIFIED;
    request.expiration = TimeCurrent() + 86400; // 24 hours
    
    bool success = OrderSend(request, result);
    
    if(!success)
    {
        Print("Failed to place buy stop order. Error: ", GetLastError(),
              " RetCode: ", result.retcode);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
    if(!PositionSelectByTicket(ticket))
        return false;
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_deal;
    request.type = ORDER_TYPE_SELL; // Opposite of buy position
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.position = ticket;
    request.magic = Magic_Number;
    request.comment = "Time Exit";
    
    bool success = OrderSend(request, result);
    
    if(!success)
    {
        Print("Failed to close position. Error: ", GetLastError(),
              " RetCode: ", result.retcode);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_distance)
{
    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount = account_balance * MaxRiskPercent / 100.0;
    
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    double sl_distance_money = (sl_distance / tick_size) * tick_value;
    
    if(sl_distance_money <= 0)
        return LotSize;
    
    double calculated_lots = risk_amount / sl_distance_money;
    
    return calculated_lots;
}

//+------------------------------------------------------------------+
//| Normalize lot size                                               |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots)
{
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(lots < min_lot)
        lots = min_lot;
    if(lots > max_lot)
        lots = max_lot;
    
    lots = MathFloor(lots / lot_step) * lot_step;
    
    return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Get current spread in pips                                       |
//+------------------------------------------------------------------+
double GetCurrentSpread()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double spread = (ask - bid) / _Point;
    
    // For JPY pairs, convert to pips
    if(StringFind(_Symbol, "JPY") > 0)
        spread = spread / 10.0;
    
    return spread;
}

//+------------------------------------------------------------------+
//| Check if it's time to trade                                      |
//+------------------------------------------------------------------+
bool IsTimeToTrade()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    return (dt.hour >= StartHour && dt.hour < EndHour);
}

//+------------------------------------------------------------------+
//| Trade event handler                                              |
//+------------------------------------------------------------------+
void OnTrade()
{
    // Update position status when trade events occur
    UpdatePositionStatus();
}