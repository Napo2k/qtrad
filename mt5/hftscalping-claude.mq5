//+------------------------------------------------------------------+
//|                                    AggressiveScalpingBot.mq5     |
//|                        Copyright 2025, High-Frequency Trading    |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, High-Frequency Trading"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Aggressive High-Frequency Scalping Bot with Advanced Risk Management"

//--- Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- Create trade objects
CTrade         trade;
CPositionInfo  position;
CAccountInfo   account;

//+------------------------------------------------------------------+
//| Input Parameters - Customizable Trading Settings                 |
//+------------------------------------------------------------------+
input group "=== TRADING STRATEGY SETTINGS ==="
input int      RSI_Period = 14;                    // RSI calculation period
input double   RSI_Oversold = 30.0;               // RSI oversold level
input double   RSI_Overbought = 70.0;             // RSI overbought level
input int      MACD_Fast = 12;                    // MACD fast EMA period
input int      MACD_Slow = 26;                    // MACD slow EMA period
input int      MACD_Signal = 9;                   // MACD signal line period
input int      MA_Fast_Period = 5;                // Fast moving average period
input int      MA_Slow_Period = 20;               // Slow moving average period
input ENUM_MA_METHOD MA_Method = MODE_EMA;        // Moving average method

input group "=== RISK MANAGEMENT ==="
input double   RiskPercent = 2.0;                 // Risk per trade (% of account)
input double   MaxSpreadPips = 3.0;               // Maximum allowed spread in pips
input bool     UseTrailingStop = true;            // Enable trailing stop
input double   TrailingStopPips = 10.0;           // Trailing stop distance in pips
input double   TrailingStepPips = 5.0;            // Trailing step in pips
input bool     UseAdaptiveTP = true;              // Use adaptive take profit based on volatility
input double   BaseTakeProfitPips = 15.0;         // Base take profit in pips
input double   BaseStopLossPips = 10.0;           // Base stop loss in pips

input group "=== AGGRESSIVENESS SETTINGS ==="
input double   AggressivenessLevel = 1.5;         // Trading aggressiveness multiplier (0.5-3.0)
input int      MaxPositions = 3;                  // Maximum simultaneous positions
input int      MinBarsBetweenTrades = 2;          // Minimum bars between new trades
input bool     UseVolatilityFilter = true;        // Enable volatility-based filtering
input double   MinVolatilityLevel = 0.0001;       // Minimum volatility threshold

input group "=== MARTINGALE SYSTEM (OPTIONAL) ==="
input bool     UseMartingale = false;             // Enable Martingale strategy
input double   MartingaleMultiplier = 2.0;        // Lot size multiplier after loss
input int      MaxMartingaleLevels = 3;           // Maximum Martingale levels

input group "=== DAILY TARGETS ==="
input bool     UseDailyTargets = false;           // Enable daily profit/loss targets
input double   DailyProfitTarget = 100.0;         // Daily profit target in account currency
input double   DailyLossLimit = 50.0;             // Daily loss limit in account currency

input group "=== TIME FILTERS ==="
input bool     UseTimeFilter = true;              // Enable trading time filter
input int      StartHour = 8;                     // Trading start hour
input int      EndHour = 22;                      // Trading end hour

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int            rsi_handle;                         // RSI indicator handle
int            macd_handle;                        // MACD indicator handle
int            ma_fast_handle;                     // Fast MA handle
int            ma_slow_handle;                     // Slow MA handle
int            atr_handle;                         // ATR handle for volatility

double         rsi_buffer[];                       // RSI values buffer
double         macd_main[];                        // MACD main line buffer
double         macd_signal[];                      // MACD signal line buffer
double         ma_fast[];                          // Fast MA buffer
double         ma_slow[];                          // Slow MA buffer
double         atr_buffer[];                       // ATR buffer

datetime       last_trade_time = 0;               // Last trade execution time
int            consecutive_losses = 0;             // Track consecutive losses for Martingale
double         daily_profit = 0.0;                // Daily profit tracking
datetime       last_daily_reset = 0;              // Last daily reset time
bool           trading_allowed = true;            // Global trading permission flag

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Initializing Aggressive Scalping Bot...");
    
    //--- Initialize indicators
    rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    macd_handle = iMACD(_Symbol, PERIOD_CURRENT, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
    ma_fast_handle = iMA(_Symbol, PERIOD_CURRENT, MA_Fast_Period, 0, MA_Method, PRICE_CLOSE);
    ma_slow_handle = iMA(_Symbol, PERIOD_CURRENT, MA_Slow_Period, 0, MA_Method, PRICE_CLOSE);
    atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
    
    //--- Check indicator handles
    if(rsi_handle == INVALID_HANDLE || macd_handle == INVALID_HANDLE || 
       ma_fast_handle == INVALID_HANDLE || ma_slow_handle == INVALID_HANDLE ||
       atr_handle == INVALID_HANDLE)
    {
        Print("Failed to initialize indicators!");
        return INIT_FAILED;
    }
    
    //--- Set array properties
    ArraySetAsSeries(rsi_buffer, true);
    ArraySetAsSeries(macd_main, true);
    ArraySetAsSeries(macd_signal, true);
    ArraySetAsSeries(ma_fast, true);
    ArraySetAsSeries(ma_slow, true);
    ArraySetAsSeries(atr_buffer, true);
    
    //--- Initialize trade settings
    trade.SetExpertMagicNumber(123456);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_IOC);
    
    //--- Initialize daily tracking
    ResetDailyCounters();
    
    Print("Aggressive Scalping Bot initialized successfully!");
    Print("Aggressiveness Level: ", AggressivenessLevel);
    Print("Max Positions: ", MaxPositions);
    Print("Risk Per Trade: ", RiskPercent, "%");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Shutting down Aggressive Scalping Bot. Reason: ", reason);
    
    //--- Release indicator handles
    IndicatorRelease(rsi_handle);
    IndicatorRelease(macd_handle);
    IndicatorRelease(ma_fast_handle);
    IndicatorRelease(ma_slow_handle);
    IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function - Main trading logic                        |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check if new bar has formed (for performance optimization)
    static datetime last_bar_time = 0;
    datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    if(current_bar_time == last_bar_time)
        return;
    last_bar_time = current_bar_time;
    
    //--- Update daily profit tracking
    UpdateDailyProfit();
    
    //--- Check daily targets
    if(UseDailyTargets && !CheckDailyTargets())
        return;
    
    //--- Check time filter
    if(UseTimeFilter && !IsWithinTradingHours())
        return;
    
    //--- Check spread
    if(!CheckSpread())
        return;
    
    //--- Update indicator buffers
    if(!UpdateIndicators())
        return;
    
    //--- Check volatility filter
    if(UseVolatilityFilter && !CheckVolatility())
        return;
    
    //--- Manage existing positions (trailing stops, dynamic exits)
    ManagePositions();
    
    //--- Look for new trading opportunities
    if(CanOpenNewPosition())
    {
        //--- Analyze market signals
        int signal = AnalyzeMarketSignals();
        
        if(signal == 1) // Buy signal
        {
            OpenBuyPosition();
        }
        else if(signal == -1) // Sell signal
        {
            OpenSellPosition();
        }
    }
}

//+------------------------------------------------------------------+
//| Update all indicator buffers                                     |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
    //--- Copy indicator data
    if(CopyBuffer(rsi_handle, 0, 0, 3, rsi_buffer) < 3)
        return false;
    
    if(CopyBuffer(macd_handle, MAIN_LINE, 0, 3, macd_main) < 3)
        return false;
    
    if(CopyBuffer(macd_handle, SIGNAL_LINE, 0, 3, macd_signal) < 3)
        return false;
    
    if(CopyBuffer(ma_fast_handle, 0, 0, 3, ma_fast) < 3)
        return false;
    
    if(CopyBuffer(ma_slow_handle, 0, 0, 3, ma_slow) < 3)
        return false;
    
    if(CopyBuffer(atr_handle, 0, 0, 3, atr_buffer) < 3)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Analyze market signals using multiple indicators                 |
//+------------------------------------------------------------------+
int AnalyzeMarketSignals()
{
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int signal_strength = 0;
    
    //--- RSI Analysis
    // Aggressive RSI levels based on aggressiveness setting
    double adj_oversold = RSI_Oversold + (10.0 * (2.0 - AggressivenessLevel));
    double adj_overbought = RSI_Overbought - (10.0 * (2.0 - AggressivenessLevel));
    
    if(rsi_buffer[0] < adj_oversold && rsi_buffer[1] >= adj_oversold)
        signal_strength += 2; // Strong buy signal
    else if(rsi_buffer[0] > adj_overbought && rsi_buffer[1] <= adj_overbought)
        signal_strength -= 2; // Strong sell signal
    
    //--- MACD Analysis
    // MACD crossover with momentum confirmation
    if(macd_main[0] > macd_signal[0] && macd_main[1] <= macd_signal[1])
    {
        if(macd_main[0] > macd_main[1]) // Increasing momentum
            signal_strength += 2;
        else
            signal_strength += 1;
    }
    else if(macd_main[0] < macd_signal[0] && macd_main[1] >= macd_signal[1])
    {
        if(macd_main[0] < macd_main[1]) // Decreasing momentum
            signal_strength -= 2;
        else
            signal_strength -= 1;
    }
    
    //--- Moving Average Analysis
    // Aggressive MA crossover strategy
    if(ma_fast[0] > ma_slow[0] && ma_fast[1] <= ma_slow[1])
        signal_strength += 1; // Buy signal
    else if(ma_fast[0] < ma_slow[0] && ma_fast[1] >= ma_slow[1])
        signal_strength -= 1; // Sell signal
    
    //--- Price momentum confirmation
    double price_change = (current_price - iClose(_Symbol, PERIOD_CURRENT, 1)) / iClose(_Symbol, PERIOD_CURRENT, 1);
    if(price_change > 0.0001 * AggressivenessLevel)
        signal_strength += 1;
    else if(price_change < -0.0001 * AggressivenessLevel)
        signal_strength -= 1;
    
    //--- Apply aggressiveness multiplier to signal threshold
    int signal_threshold = (int)(3.0 / AggressivenessLevel);
    
    if(signal_strength >= signal_threshold)
        return 1;  // Buy
    else if(signal_strength <= -signal_threshold)
        return -1; // Sell
    
    return 0; // No signal
}

//+------------------------------------------------------------------+
//| Open buy position with dynamic lot sizing                        |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    double lot_size = CalculateLotSize();
    double sl_distance = CalculateStopLoss();
    double tp_distance = CalculateTakeProfit();
    
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl_price = current_price - sl_distance;
    double tp_price = current_price + tp_distance;
    
    if(trade.Buy(lot_size, _Symbol, current_price, sl_price, tp_price, "Scalping Bot BUY"))
    {
        last_trade_time = TimeCurrent();
        Print("BUY order opened: Lot=", lot_size, " SL=", sl_price, " TP=", tp_price);
    }
    else
    {
        Print("Failed to open BUY position. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Open sell position with dynamic lot sizing                       |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
    double lot_size = CalculateLotSize();
    double sl_distance = CalculateStopLoss();
    double tp_distance = CalculateTakeProfit();
    
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl_price = current_price + sl_distance;
    double tp_price = current_price - tp_distance;
    
    if(trade.Sell(lot_size, _Symbol, current_price, sl_price, tp_price, "Scalping Bot SELL"))
    {
        last_trade_time = TimeCurrent();
        Print("SELL order opened: Lot=", lot_size, " SL=", sl_price, " TP=", tp_price);
    }
    else
    {
        Print("Failed to open SELL position. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size based on risk and Martingale         |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double balance = account.Balance();
    double risk_amount = balance * (RiskPercent / 100.0);
    
    double sl_distance = CalculateStopLoss();
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    double lot_size = risk_amount / (sl_distance / tick_size * tick_value);
    
    //--- Apply Martingale if enabled
    if(UseMartingale && consecutive_losses > 0 && consecutive_losses <= MaxMartingaleLevels)
    {
        lot_size *= MathPow(MartingaleMultiplier, consecutive_losses);
    }
    
    //--- Apply aggressiveness multiplier
    lot_size *= AggressivenessLevel;
    
    //--- Normalize lot size
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
    lot_size = NormalizeDouble(lot_size / lot_step, 0) * lot_step;
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Calculate dynamic stop loss based on volatility                  |
//+------------------------------------------------------------------+
double CalculateStopLoss()
{
    double base_sl = BaseStopLossPips * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
    
    if(UseVolatilityFilter && atr_buffer[0] > 0)
    {
        // Adjust SL based on current volatility
        double volatility_multiplier = atr_buffer[0] / (20 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
        base_sl *= MathMax(0.5, MathMin(2.0, volatility_multiplier));
    }
    
    // Apply inverse aggressiveness (more aggressive = tighter stops)
    base_sl /= AggressivenessLevel;
    
    return base_sl;
}

//+------------------------------------------------------------------+
//| Calculate dynamic take profit based on volatility                |
//+------------------------------------------------------------------+
double CalculateTakeProfit()
{
    double base_tp = BaseTakeProfitPips * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
    
    if(UseAdaptiveTP && atr_buffer[0] > 0)
    {
        // Adjust TP based on current volatility
        double volatility_multiplier = atr_buffer[0] / (20 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
        base_tp *= MathMax(0.8, MathMin(3.0, volatility_multiplier));
    }
    
    // Apply aggressiveness multiplier
    base_tp *= AggressivenessLevel;
    
    return base_tp;
}

//+------------------------------------------------------------------+
//| Manage existing positions with trailing stops and dynamic exits |
//+------------------------------------------------------------------+
void ManagePositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position.SelectByIndex(i) && position.Symbol() == _Symbol && 
           position.Magic() == trade.RequestMagic())
        {
            //--- Apply trailing stop if enabled
            if(UseTrailingStop)
            {
                ApplyTrailingStop(position.Ticket());
            }
            
            //--- Check for dynamic exit conditions
            CheckDynamicExit(position.Ticket());
        }
    }
}

//+------------------------------------------------------------------+
//| Apply trailing stop to position                                  |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket)
{
    if(!position.SelectByTicket(ticket))
        return;
    
    double trailing_distance = TrailingStopPips * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
    double trailing_step = TrailingStepPips * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
    
    if(position.PositionType() == POSITION_TYPE_BUY)
    {
        double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double new_sl = current_price - trailing_distance;
        
        if(new_sl > position.StopLoss() + trailing_step || position.StopLoss() == 0)
        {
            trade.PositionModify(ticket, new_sl, position.TakeProfit());
        }
    }
    else if(position.PositionType() == POSITION_TYPE_SELL)
    {
        double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double new_sl = current_price + trailing_distance;
        
        if(new_sl < position.StopLoss() - trailing_step || position.StopLoss() == 0)
        {
            trade.PositionModify(ticket, new_sl, position.TakeProfit());
        }
    }
}

//+------------------------------------------------------------------+
//| Check for dynamic exit conditions                                |
//+------------------------------------------------------------------+
void CheckDynamicExit(ulong ticket)
{
    if(!position.SelectByTicket(ticket))
        return;
    
    //--- Exit on opposite signal with high confidence
    int current_signal = AnalyzeMarketSignals();
    
    if(position.PositionType() == POSITION_TYPE_BUY && current_signal <= -3)
    {
        trade.PositionClose(ticket);
        Print("Dynamic exit: BUY position closed on strong SELL signal");
    }
    else if(position.PositionType() == POSITION_TYPE_SELL && current_signal >= 3)
    {
        trade.PositionClose(ticket);
        Print("Dynamic exit: SELL position closed on strong BUY signal");
    }
}

//+------------------------------------------------------------------+
//| Check if we can open new positions                               |
//+------------------------------------------------------------------+
bool CanOpenNewPosition()
{
    //--- Check maximum positions limit
    int current_positions = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(position.SelectByIndex(i) && position.Symbol() == _Symbol && 
           position.Magic() == trade.RequestMagic())
        {
            current_positions++;
        }
    }
    
    if(current_positions >= MaxPositions)
        return false;
    
    //--- Check minimum time between trades
    if(TimeCurrent() - last_trade_time < MinBarsBetweenTrades * PeriodSeconds())
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check spread conditions                                           |
//+------------------------------------------------------------------+
bool CheckSpread()
{
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double max_spread = MaxSpreadPips * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
    
    return spread <= max_spread;
}

//+------------------------------------------------------------------+
//| Check volatility conditions                                      |
//+------------------------------------------------------------------+
bool CheckVolatility()
{
    if(atr_buffer[0] < MinVolatilityLevel)
    {
        Comment("Low volatility - Trading paused");
        return false;
    }
    
    Comment(""); // Clear comment
    return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime time_struct;
    TimeToStruct(TimeCurrent(), time_struct);
    
    return time_struct.hour >= StartHour && time_struct.hour < EndHour;
}

//+------------------------------------------------------------------+
//| Update daily profit tracking                                     |
//+------------------------------------------------------------------+
void UpdateDailyProfit()
{
    MqlDateTime current_time;
    TimeToStruct(TimeCurrent(), current_time);
    
    MqlDateTime last_reset_time;
    TimeToStruct(last_daily_reset, last_reset_time);
    
    //--- Reset daily counters at start of new day
    if(current_time.day != last_reset_time.day)
    {
        ResetDailyCounters();
    }
}

//+------------------------------------------------------------------+
//| Reset daily profit/loss counters                                 |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
    daily_profit = 0.0;
    consecutive_losses = 0;
    last_daily_reset = TimeCurrent();
    trading_allowed = true;
}

//+------------------------------------------------------------------+
//| Check daily profit/loss targets                                  |
//+------------------------------------------------------------------+
bool CheckDailyTargets()
{
    //--- Calculate current daily P&L
    double current_daily_pl = 0.0;
    
    // Add profit from closed positions today
    // Note: This is simplified - in practice, you'd track this more precisely
    current_daily_pl = account.Profit();
    
    //--- Check daily profit target
    if(current_daily_pl >= DailyProfitTarget)
    {
        Comment("Daily profit target reached: ", current_daily_pl);
        return false;
    }
    
    //--- Check daily loss limit
    if(current_daily_pl <= -DailyLossLimit)
    {
        Comment("Daily loss limit reached: ", current_daily_pl);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Handle trade events for Martingale tracking                      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
    //--- Check if it's a position closing
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        CDealInfo deal;
        if(deal.SelectByIndex(trans.deal))
        {
            if(deal.Symbol() == _Symbol && deal.Magic() == trade.RequestMagic())
            {
                double profit = deal.Profit();
                
                if(profit < 0)
                {
                    consecutive_losses++;
                    Print("Consecutive losses: ", consecutive_losses);
                }
                else
                {
                    consecutive_losses = 0;
                    Print("Profitable trade - Martingale counter reset");
                }
                
                daily_profit += profit;
            }
        }
    }
}