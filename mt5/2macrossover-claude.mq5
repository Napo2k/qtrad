//+------------------------------------------------------------------+
//|                                           MA_Crossover_EA.mq5   |
//|                                         2-MA Crossover Strategy  |
//|                          Uses CTrade class for order management  |
//+------------------------------------------------------------------+
#property copyright "MA Crossover Expert Advisor"
#property version   "1.00"
#property description "Two Moving Average Crossover Strategy with CTrade"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== Moving Average Settings ==="
input int Fast_MA_Period = 10;                        // Fast MA Period
input int Slow_MA_Period = 30;                        // Slow MA Period
input ENUM_MA_METHOD Fast_MA_Method = MODE_EMA;        // Fast MA Method
input ENUM_MA_METHOD Slow_MA_Method = MODE_SMA;        // Slow MA Method
input ENUM_APPLIED_PRICE MA_Applied_Price = PRICE_CLOSE; // MA Applied Price

input group "=== Risk Management ==="
input double Lot_Size = 0.1;                          // Fixed Lot Size
input bool Use_Percentage_Risk = false;               // Use Percentage Risk instead of Fixed Lot
input double Risk_Percentage = 2.0;                   // Risk Percentage (if enabled)
input double Stop_Loss_Points = 500;                  // Stop Loss in Points (0 = no SL)
input double Take_Profit_Points = 1000;               // Take Profit in Points (0 = no TP)

input group "=== Trading Settings ==="
input bool Close_Opposite_Trades = true;              // Close opposite trades on signal
input bool One_Trade_Per_Signal = true;               // Allow only one trade per crossover
input int Magic_Number = 12345;                       // Magic Number for EA identification
input string Trade_Comment = "MA_Cross";              // Trade Comment
input int Max_Spread = 30;                            // Maximum allowed spread in points

input group "=== Time Filter ==="
input bool Use_Time_Filter = false;                   // Enable time filter
input int Start_Hour = 8;                             // Trading start hour
input int End_Hour = 18;                              // Trading end hour

//--- Global Variables
CTrade trade;                                          // CTrade object for trading operations
int fast_ma_handle;                                    // Handle for fast moving average
int slow_ma_handle;                                    // Handle for slow moving average
datetime last_crossover_time = 0;                     // Time of last crossover to prevent duplicate trades
bool last_signal_was_buy = false;                     // Track last signal type
bool last_signal_was_sell = false;                    // Track last signal type

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Initialize moving average indicators
    fast_ma_handle = iMA(_Symbol, PERIOD_CURRENT, Fast_MA_Period, 0, Fast_MA_Method, MA_Applied_Price);
    slow_ma_handle = iMA(_Symbol, PERIOD_CURRENT, Slow_MA_Period, 0, Slow_MA_Method, MA_Applied_Price);
    
    //--- Check if indicators were created successfully
    if(fast_ma_handle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create Fast MA indicator handle");
        return(INIT_FAILED);
    }
    
    if(slow_ma_handle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create Slow MA indicator handle");
        return(INIT_FAILED);
    }
    
    //--- Validate input parameters
    if(Fast_MA_Period >= Slow_MA_Period)
    {
        Print("ERROR: Fast MA period must be less than Slow MA period");
        return(INIT_FAILED);
    }
    
    if(Lot_Size <= 0 && !Use_Percentage_Risk)
    {
        Print("ERROR: Invalid lot size");
        return(INIT_FAILED);
    }
    
    if(Use_Percentage_Risk && (Risk_Percentage <= 0 || Risk_Percentage > 100))
    {
        Print("ERROR: Invalid risk percentage");
        return(INIT_FAILED);
    }
    
    //--- Setup CTrade object
    trade.SetExpertMagicNumber(Magic_Number);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    trade.SetDeviationInPoints(10);
    
    //--- Print initialization information
    Print("=== MA Crossover EA Initialized Successfully ===");
    Print("Fast MA: ", Fast_MA_Period, " (", EnumToString(Fast_MA_Method), ")");
    Print("Slow MA: ", Slow_MA_Period, " (", EnumToString(Slow_MA_Method), ")");
    Print("Symbol: ", _Symbol);
    Print("Magic Number: ", Magic_Number);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release indicator handles
    if(fast_ma_handle != INVALID_HANDLE)
        IndicatorRelease(fast_ma_handle);
    if(slow_ma_handle != INVALID_HANDLE)
        IndicatorRelease(slow_ma_handle);
    
    Print("MA Crossover EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check if we have enough bars
    if(Bars(_Symbol, PERIOD_CURRENT) < Slow_MA_Period + 10)
    {
        return;
    }
    
    //--- Check spread
    if(!CheckSpread())
    {
        return;
    }
    
    //--- Check time filter
    if(Use_Time_Filter && !IsWithinTradingHours())
    {
        return;
    }
    
    //--- Get current MA values
    double fast_ma_current, fast_ma_previous;
    double slow_ma_current, slow_ma_previous;
    
    if(!GetMAValues(fast_ma_current, fast_ma_previous, slow_ma_current, slow_ma_previous))
    {
        return;
    }
    
    //--- Check for crossover signals
    bool buy_signal = CheckBuySignal(fast_ma_current, fast_ma_previous, slow_ma_current, slow_ma_previous);
    bool sell_signal = CheckSellSignal(fast_ma_current, fast_ma_previous, slow_ma_current, slow_ma_previous);
    
    //--- Execute trades based on signals
    if(buy_signal)
    {
        ProcessBuySignal();
    }
    else if(sell_signal)
    {
        ProcessSellSignal();
    }
}

//+------------------------------------------------------------------+
//| Get moving average values                                         |
//+------------------------------------------------------------------+
bool GetMAValues(double &fast_current, double &fast_previous, double &slow_current, double &slow_previous)
{
    double fast_ma_buffer[];
    double slow_ma_buffer[];
    
    //--- Get fast MA values
    if(CopyBuffer(fast_ma_handle, 0, 0, 2, fast_ma_buffer) != 2)
    {
        Print("ERROR: Failed to copy Fast MA buffer");
        return false;
    }
    
    //--- Get slow MA values
    if(CopyBuffer(slow_ma_handle, 0, 0, 2, slow_ma_buffer) != 2)
    {
        Print("ERROR: Failed to copy Slow MA buffer");
        return false;
    }
    
    //--- Assign values
    fast_current = fast_ma_buffer[1];      // Current completed bar
    fast_previous = fast_ma_buffer[0];     // Previous bar
    slow_current = slow_ma_buffer[1];      // Current completed bar
    slow_previous = slow_ma_buffer[0];     // Previous bar
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for buy signal (fast MA crosses above slow MA)            |
//+------------------------------------------------------------------+
bool CheckBuySignal(double fast_current, double fast_previous, double slow_current, double slow_previous)
{
    //--- Fast MA crosses above Slow MA
    bool crossover = (fast_previous <= slow_previous && fast_current > slow_current);
    
    //--- Prevent duplicate signals
    if(One_Trade_Per_Signal && crossover)
    {
        datetime current_time = iTime(_Symbol, PERIOD_CURRENT, 0);
        if(current_time == last_crossover_time && last_signal_was_buy)
        {
            return false;
        }
    }
    
    return crossover;
}

//+------------------------------------------------------------------+
//| Check for sell signal (fast MA crosses below slow MA)           |
//+------------------------------------------------------------------+
bool CheckSellSignal(double fast_current, double fast_previous, double slow_current, double slow_previous)
{
    //--- Fast MA crosses below Slow MA
    bool crossover = (fast_previous >= slow_previous && fast_current < slow_current);
    
    //--- Prevent duplicate signals
    if(One_Trade_Per_Signal && crossover)
    {
        datetime current_time = iTime(_Symbol, PERIOD_CURRENT, 0);
        if(current_time == last_crossover_time && last_signal_was_sell)
        {
            return false;
        }
    }
    
    return crossover;
}

//+------------------------------------------------------------------+
//| Process buy signal                                               |
//+------------------------------------------------------------------+
void ProcessBuySignal()
{
    Print("BUY SIGNAL DETECTED - Fast MA crossed above Slow MA");
    
    //--- Close opposite positions if enabled
    if(Close_Opposite_Trades)
    {
        ClosePositionsByType(POSITION_TYPE_SELL);
    }
    
    //--- Check if we already have a buy position
    if(HasPosition(POSITION_TYPE_BUY))
    {
        Print("Buy position already exists, skipping trade");
        return;
    }
    
    //--- Calculate lot size
    double lot_size = CalculateLotSize();
    if(lot_size <= 0)
    {
        Print("ERROR: Invalid lot size calculated");
        return;
    }
    
    //--- Get current prices
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    //--- Calculate SL and TP
    double sl = 0, tp = 0;
    if(Stop_Loss_Points > 0)
        sl = NormalizeDouble(ask - Stop_Loss_Points * _Point, _Digits);
    if(Take_Profit_Points > 0)
        tp = NormalizeDouble(ask + Take_Profit_Points * _Point, _Digits);
    
    //--- Open buy position
    if(trade.Buy(lot_size, _Symbol, ask, sl, tp, Trade_Comment))
    {
        Print("BUY order opened successfully:");
        Print("- Price: ", ask);
        Print("- Lot Size: ", lot_size);
        Print("- Stop Loss: ", sl);
        Print("- Take Profit: ", tp);
        
        //--- Update signal tracking
        last_crossover_time = iTime(_Symbol, PERIOD_CURRENT, 0);
        last_signal_was_buy = true;
        last_signal_was_sell = false;
    }
    else
    {
        Print("ERROR: Failed to open BUY order. Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Process sell signal                                              |
//+------------------------------------------------------------------+
void ProcessSellSignal()
{
    Print("SELL SIGNAL DETECTED - Fast MA crossed below Slow MA");
    
    //--- Close opposite positions if enabled
    if(Close_Opposite_Trades)
    {
        ClosePositionsByType(POSITION_TYPE_BUY);
    }
    
    //--- Check if we already have a sell position
    if(HasPosition(POSITION_TYPE_SELL))
    {
        Print("Sell position already exists, skipping trade");
        return;
    }
    
    //--- Calculate lot size
    double lot_size = CalculateLotSize();
    if(lot_size <= 0)
    {
        Print("ERROR: Invalid lot size calculated");
        return;
    }
    
    //--- Get current prices
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    //--- Calculate SL and TP
    double sl = 0, tp = 0;
    if(Stop_Loss_Points > 0)
        sl = NormalizeDouble(bid + Stop_Loss_Points * _Point, _Digits);
    if(Take_Profit_Points > 0)
        tp = NormalizeDouble(bid - Take_Profit_Points * _Point, _Digits);
    
    //--- Open sell position
    if(trade.Sell(lot_size, _Symbol, bid, sl, tp, Trade_Comment))
    {
        Print("SELL order opened successfully:");
        Print("- Price: ", bid);
        Print("- Lot Size: ", lot_size);
        Print("- Stop Loss: ", sl);
        Print("- Take Profit: ", tp);
        
        //--- Update signal tracking
        last_crossover_time = iTime(_Symbol, PERIOD_CURRENT, 0);
        last_signal_was_sell = true;
        last_signal_was_buy = false;
    }
    else
    {
        Print("ERROR: Failed to open SELL order. Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk management settings            |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double lot_size = Lot_Size;
    
    if(Use_Percentage_Risk && Stop_Loss_Points > 0)
    {
        //--- Calculate lot size based on risk percentage
        double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double risk_amount = account_balance * Risk_Percentage / 100.0;
        
        double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        
        if(tick_value > 0 && tick_size > 0)
        {
            double sl_distance = Stop_Loss_Points * _Point;
            lot_size = risk_amount / (sl_distance / tick_size * tick_value);
        }
    }
    
    //--- Normalize lot size
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lot_size = MathMax(min_lot, MathMin(max_lot, MathRound(lot_size / lot_step) * lot_step));
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Check if position of specified type exists                      |
//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE pos_type)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic_Number &&
               PositionGetInteger(POSITION_TYPE) == pos_type)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Close all positions of specified type                           |
//+------------------------------------------------------------------+
void ClosePositionsByType(ENUM_POSITION_TYPE pos_type)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic_Number &&
               PositionGetInteger(POSITION_TYPE) == pos_type)
            {
                ulong ticket = PositionGetInteger(POSITION_TICKET);
                if(trade.PositionClose(ticket))
                {
                    Print("Closed ", (pos_type == POSITION_TYPE_BUY ? "BUY" : "SELL"), " position #", ticket);
                }
                else
                {
                    Print("ERROR: Failed to close position #", ticket, ". Error: ", trade.ResultRetcode());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check spread condition                                           |
//+------------------------------------------------------------------+
bool CheckSpread()
{
    if(Max_Spread <= 0)
        return true;
    
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    if(spread > Max_Spread)
    {
        static datetime last_spread_warning = 0;
        datetime current_time = TimeCurrent();
        
        //--- Show warning once per minute
        if(current_time - last_spread_warning >= 60)
        {
            Print("WARNING: Spread too high (", spread, " > ", Max_Spread, "). Trading suspended.");
            last_spread_warning = current_time;
        }
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                   |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime time_struct;
    TimeToStruct(TimeCurrent(), time_struct);
    
    int current_hour = time_struct.hour;
    
    if(Start_Hour <= End_Hour)
    {
        //--- Normal time range (e.g., 8-18)
        return (current_hour >= Start_Hour && current_hour < End_Hour);
    }
    else
    {
        //--- Overnight range (e.g., 22-6)
        return (current_hour >= Start_Hour || current_hour < End_Hour);
    }
}

//+------------------------------------------------------------------+
//| Trade transaction event handler                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
    //--- Handle trade transactions for logging purposes
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.symbol == _Symbol)
    {
        if(HistoryDealSelect(trans.deal))
        {
            long deal_magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
            if(deal_magic == Magic_Number)
            {
                long deal_type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
                double deal_profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                
                if(deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL)
                {
                    Print("Trade completed - Profit/Loss: ", deal_profit, " ", AccountInfoString(ACCOUNT_CURRENCY));
                }
            }
        }
    }
}