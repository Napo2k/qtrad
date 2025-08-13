//+------------------------------------------------------------------+
//|                                  LW_Volatility_Breakout_EA.mq5 |
//|                      Copyright 2025, Gemini AI by Google         |
//|                                  https://www.google.com          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Gemini AI by Google"
#property link      "https://www.google.com"
#property version   "1.30" // Version updated for final fix

#include <Trade\Trade.mqh>
#include <MovingAverages.mqh>
#include <iMAOnArray.mqh> // <<< Required for iMAOnArray()

//--- EA Inputs
input group           "Strategy Parameters"
input int             Donchian_Period     = 96;     // Donchian Channels Period
input int             LWTI_Period         = 25;     // LWTI Period
input int             LWTI_Smoothing      = 20;     // LWTI Smoothing Period
input int             Volume_MA_Period    = 30;     // Volume Moving Average Period
input double          RiskRewardRatio     = 2.0;    // Risk:Reward Ratio for Take Profit

input group           "Trade Management"
input double          LotSize             = 0.01;   // Fixed lot size
input long            MagicNumber         = 198607; // Unique ID for trades from this EA

//--- Global Variables
CTrade trade;
int    donchian_handle;
int    lwti_handle;

//--- Buffers for LWTI colors (assuming standard color buffer setup)
const int LWTI_UP_BUFFER = 1;
const int LWTI_DOWN_BUFFER = 2;

//--- Buffers for Donchian Channels (assuming standard buffer setup)
const int DONCHIAN_UPPER_BUFFER = 0;
const int DONCHIAN_LOWER_BUFFER = 1;
const int DONCHIAN_MIDDLE_BUFFER = 2;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Check if on the correct timeframe
   if(_Period != PERIOD_M5)
     {
      Alert("This EA is designed for the M5 timeframe. Please attach it to an M5 chart.");
      return(INIT_FAILED);
     }

//--- Initialize trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);

//--- Get Donchian Channel indicator handle
   donchian_handle = iCustom(_Symbol, _Period, "Donchian", Donchian_Period);
   if(donchian_handle == INVALID_HANDLE)
     {
      Alert("Error creating Donchian Channels indicator. Make sure 'Donchian Channels.ex5' is in MQL5/Indicators.");
      return(INIT_FAILED);
     }

//--- Get LWTI indicator handle
   lwti_handle = iCustom(_Symbol, _Period, "LWTI", LWTI_Period);
   if(lwti_handle == INVALID_HANDLE)
     {
      Alert("Error creating LWTI indicator. Make sure 'LWTI.ex5' is in MQL5/Indicators.");
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
   IndicatorRelease(donchian_handle);
   IndicatorRelease(lwti_handle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Only run logic on a new bar
   static datetime prev_time = 0;
   int data_to_copy = Volume_MA_Period + 5;
   MqlRates rates[];
   if(CopyRates(_Symbol, _Period, 0, data_to_copy, rates) < data_to_copy)
      return;
   if(rates[1].time == prev_time)
      return;
   prev_time = rates[1].time;

//--- Check if there is already an open position for this symbol and magic number
   if(PositionSelectByTicket(PositionGetTicket(0)) && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
     {
      return; // Already have a trade open, do nothing
     }

//--- Define arrays for indicator data
   double donchian_upper[2], donchian_lower[2], donchian_middle[2];
   double lwti_up[2], lwti_down[2];
   
//--- Define arrays for Volume MA calculation
   double volume_data[];
   double volume_ma_values[];
   
//--- Set array sizes
   ArrayResize(volume_data, data_to_copy);
   ArrayResize(volume_ma_values, data_to_copy);

//--- Copy indicator data (Donchian and LWTI)
   if(CopyBuffer(donchian_handle, DONCHIAN_UPPER_BUFFER, 0, 2, donchian_upper) < 2 ||
      CopyBuffer(donchian_handle, DONCHIAN_LOWER_BUFFER, 0, 2, donchian_lower) < 2 ||
      CopyBuffer(donchian_handle, DONCHIAN_MIDDLE_BUFFER, 0, 2, donchian_middle) < 2 ||
      CopyBuffer(lwti_handle, LWTI_UP_BUFFER, 0, 2, lwti_up) < 2 ||
      CopyBuffer(lwti_handle, LWTI_DOWN_BUFFER, 0, 2, lwti_down) < 2)
     {
      Print("Error copying indicator buffers.");
      return;
     }

//--- Manually populate the volume array from the rates data
   for(int i = 0; i < data_to_copy; i++)
     {
      volume_data[i] = (double)rates[i].tick_volume;
     }
     
//--- Reverse the array to be in chronological order for MA calculation
   ArraySetAsSeries(volume_data, true);

//--- Calculate the Moving Average on the volume data array
   if(iMAOnArray(volume_data, 0, Volume_MA_Period, 0, MODE_SMA, volume_ma_values) < data_to_copy)
     {
      Print("Error calculating Volume MA on array.");
      return;
     }
     
//--- Reverse the MA array back to match the 'rates' array series
   ArraySetAsSeries(volume_ma_values, true);
   
//--- Get current prices
   MqlTick last_tick;
   SymbolInfoTick(_Symbol, last_tick);
   double ask = last_tick.ask;
   double bid = last_tick.bid;

//--- Check for LONG trade conditions on the last completed bar [index 1]
   bool long_signal = false;
   if(rates[1].high >= donchian_upper[1])
     {
      if(lwti_up[1] != EMPTY_VALUE && lwti_down[1] == EMPTY_VALUE)
        {
         //--- Check volume against the calculated MA value
         if(rates[1].close > rates[1].open && (double)rates[1].tick_volume > volume_ma_values[1])
           {
            long_signal = true;
           }
        }
     }

//--- Check for SHORT trade conditions on the last completed bar [index 1]
   bool short_signal = false;
   if(rates[1].low <= donchian_lower[1])
     {
      if(lwti_down[1] != EMPTY_VALUE && lwti_up[1] == EMPTY_VALUE)
        {
         //--- Check volume against the calculated MA value
         if(rates[1].close < rates[1].open && (double)rates[1].tick_volume > volume_ma_values[1])
           {
            short_signal = true;
           }
        }
     }

//--- Execute Trades
   if(long_signal)
     {
      double sl = donchian_middle[1];
      double risk = ask - sl;
      if(risk <= 0) return; // Invalid risk
      double tp = ask + (risk * RiskRewardRatio);
      trade.Buy(LotSize, _Symbol, ask, sl, tp, "LW Volatility Breakout Long");
     }

   if(short_signal)
     {
      double sl = donchian_middle[1];
      double risk = sl - bid;
      if(risk <= 0) return; // Invalid risk
      double tp = bid - (risk * RiskRewardRatio);
      trade.Sell(LotSize, _Symbol, bid, sl, tp, "LW Volatility Breakout Short");
     }
  }
//+------------------------------------------------------------------+