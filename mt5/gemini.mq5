//+------------------------------------------------------------------+
//|                                   Classic_EMA_RSI_Strategy.mq5 |
//|                                  Copyright 2025, AI Assistant |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, AI Assistant"
#property link      "https://www.google.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- EA Input Parameters (for optimization)
input int      fast_ema_period    = 21;      // Fast EMA Period
input int      slow_ema_period    = 55;      // Slow EMA Period
input int      rsi_period         = 14;      // RSI Period
input double   rsi_level_buy      = 50.0;    // RSI level for buy confirmation
input double   rsi_level_sell     = 50.0;    // RSI level for sell confirmation
input int      atr_period         = 14;      // ATR Period for Stop Loss
input double   sl_atr_multiplier  = 1.5;     // ATR Multiplier for Stop Loss
input double   tp_rr_ratio        = 2.0;     // Take Profit as a Risk/Reward Ratio
input double   lot_size           = 0.01;    // Fixed Lot Size

//--- Global objects
CTrade         m_trade;
CPositionInfo  m_position;

//--- Indicator handles
int h_fast_ema;
int h_slow_ema;
int h_rsi;
int h_atr;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize indicator handles
   h_fast_ema = iMA(_Symbol, _Period, fast_ema_period, 0, MODE_EMA, PRICE_CLOSE);
   h_slow_ema = iMA(_Symbol, _Period, slow_ema_period, 0, MODE_EMA, PRICE_CLOSE);
   h_rsi      = iRSI(_Symbol, _Period, rsi_period, PRICE_CLOSE);
   h_atr      = iATR(_Symbol, _Period, atr_period);

//--- Check if handles were created successfully
   if(h_fast_ema == INVALID_HANDLE || h_slow_ema == INVALID_HANDLE || h_rsi == INVALID_HANDLE || h_atr == INVALID_HANDLE)
     {
      Print("Error creating indicator handles. EA will not work.");
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release indicator handles
   IndicatorRelease(h_fast_ema);
   IndicatorRelease(h_slow_ema);
   IndicatorRelease(h_rsi);
   IndicatorRelease(h_atr);
  }
//+------------------------------------------------------------------+
//| Expert tick function (runs on every new bar)                     |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- We only want to trade on the open of a new bar
   static datetime last_bar_time = 0;
   datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(current_bar_time == last_bar_time)
     {
      return; // Not a new bar, do nothing
     }
   last_bar_time = current_bar_time;

//--- Check if we already have an open position for this symbol
   if(m_position.Select(_Symbol))
     {
      return; // A position already exists, do not open another
     }

//--- Get indicator values
   double fast_ema_vals[3]; // [0] is current, [1] is previous, [2] is the one before
   double slow_ema_vals[3];
   double rsi_vals[2];

//--- Copy indicator data into arrays
   if(CopyBuffer(h_fast_ema, 0, 0, 3, fast_ema_vals) < 3 ||
      CopyBuffer(h_slow_ema, 0, 0, 3, slow_ema_vals) < 3 ||
      CopyBuffer(h_rsi, 0, 0, 2, rsi_vals) < 2)
     {
      Print("Error copying indicator data.");
      return;
     }
   
//--- Reverse arrays to have correct chronological order (index 0 is the oldest)
   ArraySetAsSeries(fast_ema_vals, true);
   ArraySetAsSeries(slow_ema_vals, true);
   ArraySetAsSeries(rsi_vals, true);

//--- DEFINE TRADE LOGIC ---

//--- Buy Signal Check (Golden Cross)
   bool buy_signal = fast_ema_vals[2] < slow_ema_vals[2] && // Fast EMA was below Slow EMA 2 bars ago
                     fast_ema_vals[1] > slow_ema_vals[1] && // Fast EMA crossed above Slow EMA on the previous bar
                     rsi_vals[1] > rsi_level_buy;           // RSI confirms momentum

//--- Sell Signal Check (Death Cross)
   bool sell_signal = fast_ema_vals[2] > slow_ema_vals[2] && // Fast EMA was above Slow EMA 2 bars ago
                      fast_ema_vals[1] < slow_ema_vals[1] && // Fast EMA crossed below Slow EMA on the previous bar
                      rsi_vals[1] < rsi_level_sell;          // RSI confirms momentum


//--- EXECUTE TRADES ---
   if(buy_signal)
     {
      ExecuteTrade(ORDER_TYPE_BUY);
     }
   else if(sell_signal)
     {
      ExecuteTrade(ORDER_TYPE_SELL);
     }
  }

//+------------------------------------------------------------------+
//| Function to execute trades                                       |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE order_type)
  {
//--- Get current market prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

//--- Get ATR value for SL calculation
   double atr_val[1];
   if(CopyBuffer(h_atr, 0, 1, 1, atr_val) < 1)
     {
      Print("Error getting ATR value.");
      return;
     }
   
   double stop_loss_pips = atr_val[0] * sl_atr_multiplier;
   double take_profit_pips = stop_loss_pips * tp_rr_ratio;

//--- Calculate SL and TP prices
   double sl_price = 0;
   double tp_price = 0;
   double entry_price = 0;

   if(order_type == ORDER_TYPE_BUY)
     {
      entry_price = ask;
      sl_price = entry_price - stop_loss_pips;
      tp_price = entry_price + take_profit_pips;
     }
   else // ORDER_TYPE_SELL
     {
      entry_price = bid;
      sl_price = entry_price + stop_loss_pips;
      tp_price = entry_price - stop_loss_pips;
     }

//--- Execute the order
   m_trade.PositionOpen(_Symbol, order_type, lot_size, entry_price, sl_price, tp_price);
  }
//+------------------------------------------------------------------+