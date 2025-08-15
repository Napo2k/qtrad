//+------------------------------------------------------------------+
//|                                      AdvancedTradingBot.mq5 |
//|                        Copyright 2025, Advanced Trading Systems |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced Trading Systems"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Advanced Multi-Strategy Trading Bot combining ORB, MSS, and SMC"

//--- Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- Global objects
CTrade         trade;
CPositionInfo  position;
CAccountInfo   account;

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== GENERAL SETTINGS ==="
input double   InitialCapital = 100.0;          // Initial account capital
input double   TargetCapital = 1000.0;          // Target capital
input double   RiskPercentage = 2.0;            // Risk per trade (%)
input bool     UseCompounding = true;           // Enable compounding
input int      MaxDailyTrades = 5;              // Maximum trades per day

input group "=== OPENING RANGE BREAKOUT (ORB) ==="
input int      ORB_StartHour = 9;               // ORB start hour (broker time)
input int      ORB_StartMinute = 30;            // ORB start minute
input int      ORB_PeriodMinutes = 30;          // ORB period in minutes (15, 30, 60)
input double   ORB_BreakoutBuffer = 5.0;       // Breakout buffer in points
input bool     ORB_Enabled = true;             // Enable ORB strategy

input group "=== MARKET STRUCTURE SHIFT (MSS) ==="
input int      MSS_LookbackPeriod = 20;        // Lookback period for structure
input double   MSS_MinRetracementPercent = 38.2; // Minimum retracement %
input bool     MSS_Enabled = true;             // Enable MSS strategy

input group "=== SMART MONEY CONCEPTS (SMC) ==="
input int      SMC_OrderBlockPeriod = 10;      // Order block identification period
input double   SMC_FVG_MinSize = 10.0;         // Fair Value Gap minimum size (points)
input bool     SMC_Enabled = true;             // Enable SMC strategy

input group "=== TECHNICAL INDICATORS ==="
input int      MA_Fast_Period = 21;            // Fast MA period
input int      MA_Slow_Period = 50;            // Slow MA period
input int      RSI_Period = 14;                // RSI period
input double   RSI_Overbought = 70.0;          // RSI overbought level
input double   RSI_Oversold = 30.0;            // RSI oversold level

input group "=== RISK MANAGEMENT ==="
input double   StopLossPoints = 50.0;          // Stop loss in points
input double   TakeProfitPoints = 100.0;       // Take profit in points
input double   TrailingStopPoints = 30.0;      // Trailing stop in points
input double   MaxDrawdownPercent = 15.0;      // Maximum drawdown %

//+------------------------------------------------------------------+
//| Function Declarations                                            |
//+------------------------------------------------------------------+
int GetBarShift(string symbol, ENUM_TIMEFRAMES timeframe, datetime time);

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
double         ORB_High, ORB_Low;              // Opening Range levels
datetime       ORB_StartTime, ORB_EndTime;     // ORB time window
bool           ORB_Calculated = false;         // ORB calculation flag
int            DailyTradeCount = 0;            // Daily trade counter
datetime       LastTradeDay = 0;              // Last trade day tracker

// Indicator handles
int            handle_MA_Fast, handle_MA_Slow, handle_RSI;

// Structure for tracking market structure
struct MarketStructure
{
   double   higher_high;
   double   higher_low;
   double   lower_high;
   double   lower_low;
   datetime hh_time;
   datetime hl_time;
   datetime lh_time;
   datetime ll_time;
   bool     bullish_structure;
   bool     bearish_structure;
};
MarketStructure market_structure;

// Structure for Fair Value Gaps
struct FairValueGap
{
   double   top;
   double   bottom;
   datetime time;
   bool     bullish;
   bool     filled;
};
FairValueGap fvg_array[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Initialize indicators
   handle_MA_Fast = iMA(_Symbol, PERIOD_CURRENT, MA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   handle_MA_Slow = iMA(_Symbol, PERIOD_CURRENT, MA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
   handle_RSI = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   
   //--- Check indicator handles
   if(handle_MA_Fast == INVALID_HANDLE || handle_MA_Slow == INVALID_HANDLE || handle_RSI == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return INIT_FAILED;
   }
   
   //--- Initialize variables
   ORB_Calculated = false;
   DailyTradeCount = 0;
   LastTradeDay = 0;
   
   //--- Initialize market structure
   ResetMarketStructure();
   
   //--- Resize FVG array
   ArrayResize(fvg_array, 0);
   
   Print("Advanced Trading Bot initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if(handle_MA_Fast != INVALID_HANDLE) IndicatorRelease(handle_MA_Fast);
   if(handle_MA_Slow != INVALID_HANDLE) IndicatorRelease(handle_MA_Slow);
   if(handle_RSI != INVALID_HANDLE) IndicatorRelease(handle_RSI);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlDateTime current;
   TimeToStruct(TimeCurrent(),current);
   MqlDateTime last;
   TimeToStruct(LastTradeDay,last);
   
   //--- Check if new day for trade counting
   if(current.day != last.day)
   {
      DailyTradeCount = 0;
      LastTradeDay = TimeCurrent();
   }
   
   //--- Check maximum daily trades
   if(DailyTradeCount >= MaxDailyTrades)
      return;
   
   //--- Check drawdown limit
   if(CheckDrawdownLimit())
      return;
   
   //--- Update ORB levels
   if(ORB_Enabled)
      UpdateORB();
   
   //--- Update Market Structure
   if(MSS_Enabled)
      UpdateMarketStructure();
   
   //--- Update Fair Value Gaps
   if(SMC_Enabled)
      UpdateFairValueGaps();
   
   //--- Check for trading signals
   CheckTradingSignals();
   
   //--- Manage existing positions
   ManagePositions();
}

//+------------------------------------------------------------------+
//| Update Opening Range Breakout levels                            |
//+------------------------------------------------------------------+
void UpdateORB()
{
   MqlDateTime current_time;
   TimeToStruct(TimeCurrent(), current_time);
   
   //--- Calculate ORB start time for current day
   MqlDateTime orb_start = current_time;
   orb_start.hour = ORB_StartHour;
   orb_start.min = ORB_StartMinute;
   orb_start.sec = 0;
   ORB_StartTime = StructToTime(orb_start);
   
   //--- Calculate ORB end time
   ORB_EndTime = ORB_StartTime + ORB_PeriodMinutes * 60;
   
   //--- Check if we're in ORB period and calculate levels
   if(TimeCurrent() >= ORB_StartTime && TimeCurrent() <= ORB_EndTime && !ORB_Calculated)
   {
      CalculateORBLevels();
   }
   
   //--- Reset for next day
   if(current_time.hour == 0 && current_time.min == 0)
   {
      ORB_Calculated = false;
   }
}

//+------------------------------------------------------------------+
//| Calculate ORB High and Low levels                               |
//+------------------------------------------------------------------+
void CalculateORBLevels()
{
   int start_bar = GetBarShift(_Symbol, PERIOD_M1, ORB_StartTime);
   int end_bar = GetBarShift(_Symbol, PERIOD_M1, ORB_EndTime);
   
   if(start_bar == -1 || end_bar == -1)
      return;
   
   // Get high and low values for the ORB period
   double highs[], lows[];
   int bars_count = start_bar - end_bar + 1;
   
   if(CopyHigh(_Symbol, PERIOD_M1, end_bar, bars_count, highs) <= 0 ||
      CopyLow(_Symbol, PERIOD_M1, end_bar, bars_count, lows) <= 0)
      return;
   
   ORB_High = highs[ArrayMaximum(highs)];
   ORB_Low = lows[ArrayMinimum(lows)];
   
   ORB_Calculated = true;
   
   Print("ORB Levels calculated - High: ", ORB_High, " Low: ", ORB_Low);
}

//+------------------------------------------------------------------+
//| Update Market Structure                                          |
//+------------------------------------------------------------------+
void UpdateMarketStructure()
{
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, MSS_LookbackPeriod, highs) <= 0 ||
      CopyLow(_Symbol, PERIOD_CURRENT, 0, MSS_LookbackPeriod, lows) <= 0)
      return;
   
   //--- Find recent highs and lows
   int hh_index = ArrayMaximum(highs, 1, MSS_LookbackPeriod - 1);
   int ll_index = ArrayMinimum(lows, 1, MSS_LookbackPeriod - 1);
   
   if(hh_index > 0 && ll_index > 0)
   {
      //--- Update structure based on new highs/lows
      if(highs[hh_index] > market_structure.higher_high)
      {
         market_structure.higher_high = highs[hh_index];
         market_structure.hh_time = iTime(_Symbol, PERIOD_CURRENT, hh_index);
      }
      
      if(lows[ll_index] < market_structure.lower_low)
      {
         market_structure.lower_low = lows[ll_index];
         market_structure.ll_time = iTime(_Symbol, PERIOD_CURRENT, ll_index);
      }
      
      //--- Determine market structure bias
      market_structure.bullish_structure = (market_structure.hh_time > market_structure.ll_time);
      market_structure.bearish_structure = (market_structure.ll_time > market_structure.hh_time);
   }
}

//+------------------------------------------------------------------+
//| Update Fair Value Gaps                                          |
//+------------------------------------------------------------------+
void UpdateFairValueGaps()
{
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, 10, high) <= 0 ||
      CopyLow(_Symbol, PERIOD_CURRENT, 0, 10, low) <= 0 ||
      CopyClose(_Symbol, PERIOD_CURRENT, 0, 10, close) <= 0)
      return;
   
   //--- Check for bullish FVG (gap up)
   if(low[0] > high[2] && (low[0] - high[2]) >= SMC_FVG_MinSize * _Point)
   {
      AddFairValueGap(low[0], high[2], iTime(_Symbol, PERIOD_CURRENT, 0), true);
   }
   
   //--- Check for bearish FVG (gap down)
   if(high[0] < low[2] && (low[2] - high[0]) >= SMC_FVG_MinSize * _Point)
   {
      AddFairValueGap(high[0], low[2], iTime(_Symbol, PERIOD_CURRENT, 0), false);
   }
   
   //--- Update FVG status (check if filled)
   UpdateFVGStatus();
}

//+------------------------------------------------------------------+
//| Add Fair Value Gap to array                                     |
//+------------------------------------------------------------------+
void AddFairValueGap(double top, double bottom, datetime time, bool bullish)
{
   int size = ArraySize(fvg_array);
   ArrayResize(fvg_array, size + 1);
   
   fvg_array[size].top = top;
   fvg_array[size].bottom = bottom;
   fvg_array[size].time = time;
   fvg_array[size].bullish = bullish;
   fvg_array[size].filled = false;
}

//+------------------------------------------------------------------+
//| Update FVG fill status                                          |
//+------------------------------------------------------------------+
void UpdateFVGStatus()
{
   double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   for(int i = 0; i < ArraySize(fvg_array); i++)
   {
      if(!fvg_array[i].filled)
      {
         if(fvg_array[i].bullish && current_price <= fvg_array[i].bottom)
            fvg_array[i].filled = true;
         else if(!fvg_array[i].bullish && current_price >= fvg_array[i].top)
            fvg_array[i].filled = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Check for trading signals                                       |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
   //--- Get current market data
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   //--- Get indicator values
   double ma_fast[], ma_slow[], rsi[];
   ArraySetAsSeries(ma_fast, true);
   ArraySetAsSeries(ma_slow, true);
   ArraySetAsSeries(rsi, true);
   
   if(CopyBuffer(handle_MA_Fast, 0, 0, 3, ma_fast) <= 0 ||
      CopyBuffer(handle_MA_Slow, 0, 0, 3, ma_slow) <= 0 ||
      CopyBuffer(handle_RSI, 0, 0, 3, rsi) <= 0)
      return;
   
   //--- Check for buy signals
   if(CheckBuySignal(bid, ask, ma_fast, ma_slow, rsi))
   {
      ExecuteBuyOrder();
   }
   
   //--- Check for sell signals
   if(CheckSellSignal(bid, ask, ma_fast, ma_slow, rsi))
   {
      ExecuteSellOrder();
   }
}

//+------------------------------------------------------------------+
//| Check buy signal conditions                                     |
//+------------------------------------------------------------------+
bool CheckBuySignal(double bid, double ask, double &ma_fast[], double &ma_slow[], double &rsi[])
{
   bool signal = false;
   
   //--- ORB Bullish Breakout
   bool orb_buy = false;
   if(ORB_Enabled && ORB_Calculated)
   {
      orb_buy = (ask > ORB_High + ORB_BreakoutBuffer * _Point);
   }
   
   //--- MSS Bullish Structure
   bool mss_buy = false;
   if(MSS_Enabled)
   {
      mss_buy = market_structure.bullish_structure && (bid > market_structure.higher_low);
   }
   
   //--- SMC Bullish conditions
   bool smc_buy = false;
   if(SMC_Enabled)
   {
      smc_buy = CheckBullishFVG(bid);
   }
   
   //--- Technical indicator confirmation
   bool tech_buy = (ma_fast[0] > ma_slow[0]) && (rsi[0] < RSI_Overbought) && (rsi[0] > 50);
   
   //--- Combine signals (at least 2 strategies must agree)
   int signal_count = 0;
   if(orb_buy) signal_count++;
   if(mss_buy) signal_count++;
   if(smc_buy) signal_count++;
   
   signal = (signal_count >= 2) && tech_buy;
   
   return signal;
}

//+------------------------------------------------------------------+
//| Check sell signal conditions                                    |
//+------------------------------------------------------------------+
bool CheckSellSignal(double bid, double ask, double &ma_fast[], double &ma_slow[], double &rsi[])
{
   bool signal = false;
   
   //--- ORB Bearish Breakout
   bool orb_sell = false;
   if(ORB_Enabled && ORB_Calculated)
   {
      orb_sell = (bid < ORB_Low - ORB_BreakoutBuffer * _Point);
   }
   
   //--- MSS Bearish Structure
   bool mss_sell = false;
   if(MSS_Enabled)
   {
      mss_sell = market_structure.bearish_structure && (ask < market_structure.lower_high);
   }
   
   //--- SMC Bearish conditions
   bool smc_sell = false;
   if(SMC_Enabled)
   {
      smc_sell = CheckBearishFVG(ask);
   }
   
   //--- Technical indicator confirmation
   bool tech_sell = (ma_fast[0] < ma_slow[0]) && (rsi[0] > RSI_Oversold) && (rsi[0] < 50);
   
   //--- Combine signals (at least 2 strategies must agree)
   int signal_count = 0;
   if(orb_sell) signal_count++;
   if(mss_sell) signal_count++;
   if(smc_sell) signal_count++;
   
   signal = (signal_count >= 2) && tech_sell;
   
   return signal;
}

//+------------------------------------------------------------------+
//| Check for bullish Fair Value Gap                               |
//+------------------------------------------------------------------+
bool CheckBullishFVG(double price)
{
   for(int i = 0; i < ArraySize(fvg_array); i++)
   {
      if(fvg_array[i].bullish && !fvg_array[i].filled)
      {
         if(price >= fvg_array[i].bottom && price <= fvg_array[i].top)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check for bearish Fair Value Gap                               |
//+------------------------------------------------------------------+
bool CheckBearishFVG(double price)
{
   for(int i = 0; i < ArraySize(fvg_array); i++)
   {
      if(!fvg_array[i].bullish && !fvg_array[i].filled)
      {
         if(price <= fvg_array[i].top && price >= fvg_array[i].bottom)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Execute buy order                                               |
//+------------------------------------------------------------------+
void ExecuteBuyOrder()
{
   if(PositionSelect(_Symbol))
      return; // Already in position
   
   double lot_size = CalculateLotSize();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = ask - StopLossPoints * _Point;
   double tp = ask + TakeProfitPoints * _Point;
   
   if(trade.Buy(lot_size, _Symbol, ask, sl, tp, "Advanced Bot - Buy"))
   {
      DailyTradeCount++;
      Print("Buy order executed - Lot: ", lot_size, " Price: ", ask);
   }
}

//+------------------------------------------------------------------+
//| Execute sell order                                              |
//+------------------------------------------------------------------+
void ExecuteSellOrder()
{
   if(PositionSelect(_Symbol))
      return; // Already in position
   
   double lot_size = CalculateLotSize();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = bid + StopLossPoints * _Point;
   double tp = bid - TakeProfitPoints * _Point;
   
   if(trade.Sell(lot_size, _Symbol, bid, sl, tp, "Advanced Bot - Sell"))
   {
      DailyTradeCount++;
      Print("Sell order executed - Lot: ", lot_size, " Price: ", bid);
   }
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size for compounding                     |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double balance = account.Balance();
   double equity = account.Equity();
   double free_margin = account.FreeMargin();
   
   //--- Use equity for compounding if enabled, otherwise use balance
   double capital = UseCompounding ? equity : InitialCapital;
   
   //--- Calculate risk amount
   double risk_amount = capital * RiskPercentage / 100.0;
   
   //--- Calculate lot size based on stop loss
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point_value = tick_value * _Point / tick_size;
   
   double lot_size = risk_amount / (StopLossPoints * point_value);
   
   //--- Apply lot size limits
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
   lot_size = MathRound(lot_size / lot_step) * lot_step;
   
   //--- Ensure sufficient margin
   double required_margin = lot_size * SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
   if(required_margin > free_margin * 0.8) // Use max 80% of free margin
   {
      lot_size = (free_margin * 0.8) / SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
      lot_size = MathRound(lot_size / lot_step) * lot_step;
   }
   
   return MathMax(min_lot, lot_size);
}

//+------------------------------------------------------------------+
//| Manage existing positions                                       |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(!PositionSelect(_Symbol))
      return;
   
   double position_profit = PositionGetDouble(POSITION_PROFIT);
   double position_volume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double position_price_open = PositionGetDouble(POSITION_PRICE_OPEN);
   
   //--- Implement trailing stop
   if(position_profit > 0)
   {
      double current_price = (position_type == POSITION_TYPE_BUY) ? 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double new_sl = 0;
      
      if(position_type == POSITION_TYPE_BUY)
      {
         new_sl = current_price - TrailingStopPoints * _Point;
         if(new_sl > PositionGetDouble(POSITION_SL) + _Point)
         {
            trade.PositionModify(_Symbol, new_sl, PositionGetDouble(POSITION_TP));
         }
      }
      else
      {
         new_sl = current_price + TrailingStopPoints * _Point;
         if(new_sl < PositionGetDouble(POSITION_SL) - _Point || PositionGetDouble(POSITION_SL) == 0)
         {
            trade.PositionModify(_Symbol, new_sl, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check drawdown limit                                            |
//+------------------------------------------------------------------+
bool CheckDrawdownLimit()
{
   double balance = account.Balance();
   double equity = account.Equity();
   
   if(balance > 0)
   {
      double drawdown_percent = (balance - equity) / balance * 100.0;
      if(drawdown_percent > MaxDrawdownPercent)
      {
         Print("Maximum drawdown reached: ", drawdown_percent, "%");
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Reset market structure                                          |
//+------------------------------------------------------------------+
void ResetMarketStructure()
{
   market_structure.higher_high = 0;
   market_structure.higher_low = 0;
   market_structure.lower_high = 0;
   market_structure.lower_low = DBL_MAX;
   market_structure.hh_time = 0;
   market_structure.hl_time = 0;
   market_structure.lh_time = 0;
   market_structure.ll_time = 0;
   market_structure.bullish_structure = false;
   market_structure.bearish_structure = false;
}

//+------------------------------------------------------------------+
//| Get BarShift equivalent for MQL5                               |
//+------------------------------------------------------------------+
int GetBarShift(string symbol, ENUM_TIMEFRAMES timeframe, datetime time)
{
   datetime bar_time[];
   ArraySetAsSeries(bar_time, true);
   int copied = CopyTime(symbol, timeframe, 0, 1000, bar_time);
   
   if(copied <= 0)
      return -1;
   
   for(int i = 0; i < copied; i++)
   {
      if(bar_time[i] <= time)
         return i;
   }
   
   return -1;
}