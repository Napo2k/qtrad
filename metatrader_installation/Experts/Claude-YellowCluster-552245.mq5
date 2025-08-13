//+------------------------------------------------------------------+
//|                                           YellowClusterEA.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Input parameters
input double InpTotalRisk = 1.0;        // Total risk percent per signal
input double InpTotalLot = 5.0;         // Total lot size for all signals
input int    InpBarsToAnalyze = 1000;   // Number of bars to analyze
input int    InpMagicNumber = 552245;   // Magic number for orders
input bool   InpTradeEnabled = true;    // Enable trading

//--- Global variables
struct SignalData
{
   string symbol;
   int direction;           // 1 for buy, -1 for sell
   double entry_price;
   double stop_loss;
   double take_profit;
   double risk_pips;
   double reward_pips;
   double reversal_chance;
   double signal_strength;
   int cluster_size;
   double historical_accuracy;
   datetime cluster_start_time;
};

SignalData g_signals[];
int g_signal_count = 0;
datetime g_last_scan_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Yellow Cluster EA initialized");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Yellow Cluster EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Run market scan every 15 minutes
   if(TimeCurrent() - g_last_scan_time > 900) // 15 minutes
   {
      ScanMarket();
      g_last_scan_time = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Normalize price according to symbol specifications              |
//+------------------------------------------------------------------+
double NormalizePrice(string symbol, double price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   price = NormalizeDouble(price, digits);
   return price;
}

//+------------------------------------------------------------------+
//| Calculate trend moves and analyze price action                  |
//+------------------------------------------------------------------+
bool AnalyzePair(string symbol, SignalData &signal)
{
   MqlRates rates[];
   int bars_copied = CopyRates(symbol, PERIOD_M15, 0, InpBarsToAnalyze, rates);
   
   if(bars_copied < 100)
   {
      Print("Not enough data for ", symbol);
      return false;
   }
   
   // Calculate trend moves
   double trend_moves[];
   int current_trend = 0;
   int trend_count = 0;
   
   ArrayResize(trend_moves, bars_copied);
   
   for(int i = 1; i < bars_copied; i++)
   {
      if(rates[i].close > rates[i-1].close)
      {
         if(current_trend <= 0)
         {
            if(current_trend < 0 && trend_count < ArraySize(trend_moves))
            {
               trend_moves[trend_count] = MathAbs(current_trend);
               trend_count++;
            }
            current_trend = 0;
         }
         current_trend++;
      }
      else
      {
         if(current_trend >= 0)
         {
            if(current_trend > 0 && trend_count < ArraySize(trend_moves))
            {
               trend_moves[trend_count] = current_trend;
               trend_count++;
            }
            current_trend = 0;
         }
         current_trend--;
      }
   }
   
   if(trend_count == 0) return false;
   
   // Calculate average trend move
   double avg_trend_move = 0;
   for(int i = 0; i < trend_count; i++)
   {
      avg_trend_move += trend_moves[i];
   }
   avg_trend_move /= trend_count;
   
   // Calculate volatility and other indicators
   double typical_prices[];
   double volatilities[];
   bool is_yellow[];
   
   ArrayResize(typical_prices, bars_copied);
   ArrayResize(volatilities, bars_copied);
   ArrayResize(is_yellow, bars_copied);
   
   for(int i = 0; i < bars_copied; i++)
   {
      typical_prices[i] = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      
      if(i >= 20)
      {
         double price_returns[20];
         for(int j = 0; j < 20; j++)
         {
            if(i-j-1 >= 0)
               price_returns[j] = (typical_prices[i-j] - typical_prices[i-j-1]) / typical_prices[i-j-1];
         }
         
         volatilities[i] = CalculateStdDev(price_returns, 20);
         
         // Calculate color intensity (volatility * relative volume)
         double avg_volume = 0;
         for(int j = 0; j < 20 && (i-j) >= 0; j++)
         {
            avg_volume += rates[i-j].tick_volume;
         }
         avg_volume /= 20.0;
         
         double color_intensity = volatilities[i] * (rates[i].tick_volume / avg_volume);
         
         // Calculate quantile (75th percentile approximation)
         double intensities[100];
         int intensity_count = 0;
         for(int j = MathMax(0, i-99); j <= i && intensity_count < 100; j++)
         {
            if(j >= 20)
            {
               double vi = volatilities[j] * (rates[j].tick_volume / avg_volume);
               intensities[intensity_count] = vi;
               intensity_count++;
            }
         }
         
         if(intensity_count > 0)
         {
            ArraySort(intensities);
            double quantile_75 = intensities[(int)(intensity_count * 0.75)];
            is_yellow[i] = (color_intensity > quantile_75);
         }
      }
   }
   
   // Find yellow clusters
   int clusters[][3]; // [start_index, size, end_price_index]
   int cluster_count = 0;
   ArrayResize(clusters, bars_copied);
   
   int current_cluster_start = -1;
   int current_cluster_size = 0;
   
   for(int i = 20; i < bars_copied; i++)
   {
      if(is_yellow[i])
      {
         if(current_cluster_start == -1)
         {
            current_cluster_start = i;
         }
         current_cluster_size++;
      }
      else
      {
         if(current_cluster_size >= 5)
         {
            clusters[cluster_count][0] = current_cluster_start;
            clusters[cluster_count][1] = current_cluster_size;
            clusters[cluster_count][2] = i - 1;
            cluster_count++;
         }
         current_cluster_start = -1;
         current_cluster_size = 0;
      }
   }
   
   if(cluster_count == 0) return false;
   
   // Find biggest cluster
   int biggest_cluster_idx = 0;
   for(int i = 1; i < cluster_count; i++)
   {
      if(clusters[i][1] > clusters[biggest_cluster_idx][1])
      {
         biggest_cluster_idx = i;
      }
   }
   
   int cluster_start = clusters[biggest_cluster_idx][0];
   int cluster_size = clusters[biggest_cluster_idx][1];
   int cluster_end = clusters[biggest_cluster_idx][2];
   
   // Calculate cluster high/low
   double cluster_high = rates[cluster_start].high;
   double cluster_low = rates[cluster_start].low;
   
   for(int i = cluster_start; i <= cluster_end; i++)
   {
      if(rates[i].high > cluster_high) cluster_high = rates[i].high;
      if(rates[i].low < cluster_low) cluster_low = rates[i].low;
   }
   
   double cluster_close = rates[cluster_end].close;
   
   // Calculate moving average for trend determination
   double ma_sum = 0;
   for(int i = bars_copied - 20; i < bars_copied; i++)
   {
      ma_sum += rates[i].close;
   }
   double prev_ma = ma_sum / 20.0;
   
   // Determine direction
   bool is_buy = (cluster_close <= prev_ma);
   
   // Calculate optimal stops
   double avg_volatility = 0;
   int vol_count = 0;
   for(int i = bars_copied - 100; i < bars_copied; i++)
   {
      if(i >= 20)
      {
         avg_volatility += volatilities[i];
         vol_count++;
      }
   }
   if(vol_count > 0) avg_volatility /= vol_count;
   
   double optimal_stop = avg_volatility * 2.0;
   double optimal_take = optimal_stop * 3.0;
   
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   // Calculate entry, stop, and take profit
   double entry, stop, take;
   
   if(is_buy)
   {
      entry = NormalizePrice(symbol, cluster_high);
      double raw_stop = cluster_low - optimal_stop;
      double raw_take = entry + optimal_take;
      
      stop = NormalizePrice(symbol, MathMin(raw_stop, entry - point * 10));
      take = NormalizePrice(symbol, MathMax(raw_take, entry + point * 20));
      
      // Ensure minimum 1:2 risk/reward
      if((take - entry) < (entry - stop) * 2.0)
      {
         take = entry + (entry - stop) * 2.0;
         take = NormalizePrice(symbol, take);
      }
      
      // Validate levels
      if(stop >= entry || entry >= take)
         return false;
   }
   else
   {
      entry = NormalizePrice(symbol, cluster_low);
      double raw_stop = cluster_high + optimal_stop;
      double raw_take = entry - optimal_take;
      
      stop = NormalizePrice(symbol, MathMax(raw_stop, entry + point * 10));
      take = NormalizePrice(symbol, MathMin(raw_take, entry - point * 20));
      
      // Ensure minimum 1:2 risk/reward
      if((entry - take) < (stop - entry) * 2.0)
      {
         take = entry - (stop - entry) * 2.0;
         take = NormalizePrice(symbol, take);
      }
      
      // Validate levels
      if(take >= entry || entry >= stop)
         return false;
   }
   
   // Fill signal structure
   signal.symbol = symbol;
   signal.direction = is_buy ? 1 : -1;
   signal.entry_price = entry;
   signal.stop_loss = stop;
   signal.take_profit = take;
   signal.risk_pips = MathAbs(stop - entry) / point;
   signal.reward_pips = MathAbs(take - entry) / point;
   signal.reversal_chance = 65.0; // Simplified calculation
   signal.signal_strength = cluster_size * 0.2; // Simplified
   signal.cluster_size = cluster_size;
   signal.historical_accuracy = 70.0; // Simplified
   signal.cluster_start_time = rates[cluster_start].time;
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate standard deviation                                     |
//+------------------------------------------------------------------+
double CalculateStdDev(const double &array[], int count)
{
   if(count <= 1) return 0.0;
   
   double sum = 0.0;
   for(int i = 0; i < count; i++)
   {
      sum += array[i];
   }
   double mean = sum / count;
   
   double variance = 0.0;
   for(int i = 0; i < count; i++)
   {
      double diff = array[i] - mean;
      variance += diff * diff;
   }
   variance /= (count - 1);
   
   return MathSqrt(variance);
}

//+------------------------------------------------------------------+
//| Scan market for signals                                         |
//+------------------------------------------------------------------+
void ScanMarket()
{
   string pairs[] = {
      "EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD",
      "NZDUSD", "EURGBP", "EURJPY", "GBPJPY", "EURCHF", "AUDJPY",
      "CADJPY", "NZDJPY", "GBPCHF", "EURAUD", "EURCAD", "GBPCAD",
      "AUDNZD", "AUDCAD"
   };
   
   g_signal_count = 0;
   ArrayResize(g_signals, ArraySize(pairs));
   
   for(int i = 0; i < ArraySize(pairs); i++)
   {
      SignalData signal;
      if(AnalyzePair(pairs[i], signal))
      {
         g_signals[g_signal_count] = signal;
         g_signal_count++;
      }
   }
   
   // Sort signals by strength
   SortSignalsByStrength();
   
   // Process top 5 signals
   int max_signals = MathMin(5, g_signal_count);
   ProcessSignals(max_signals);
   
   PrintSignals(max_signals);
}

//+------------------------------------------------------------------+
//| Sort signals by strength                                        |
//+------------------------------------------------------------------+
void SortSignalsByStrength()
{
   for(int i = 0; i < g_signal_count - 1; i++)
   {
      for(int j = i + 1; j < g_signal_count; j++)
      {
         if(g_signals[j].signal_strength > g_signals[i].signal_strength)
         {
            SignalData temp = g_signals[i];
            g_signals[i] = g_signals[j];
            g_signals[j] = temp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Process trading signals                                         |
//+------------------------------------------------------------------+
void ProcessSignals(int count)
{
   if(!InpTradeEnabled) return;
   
   MqlTradeRequest request;
   MqlTradeResult result;
   
   for(int i = 0; i < count; i++)
   {
      SignalData signal = g_signals[i];
      
      // Check if position already exists
      if(PositionSelect(signal.symbol))
      {
         // Check if direction changed - close if needed
         long pos_type = PositionGetInteger(POSITION_TYPE);
         int current_direction = (pos_type == POSITION_TYPE_BUY) ? 1 : -1;
         
         if(current_direction != signal.direction)
         {
            ClosePosition(signal.symbol);
            Sleep(100); // Small delay before opening new position
         }
         else
         {
            continue; // Same direction, keep position
         }
      }
      
      // Calculate lot size (simplified)
      double lot_size = CalculateLotSize(signal);
      
      // Prepare order request
      ZeroMemory(request);
      request.action = TRADE_ACTION_DEAL;
      request.symbol = signal.symbol;
      request.volume = lot_size;
      request.type = (signal.direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      request.price = (signal.direction > 0) ? 
                     SymbolInfoDouble(signal.symbol, SYMBOL_ASK) :
                     SymbolInfoDouble(signal.symbol, SYMBOL_BID);
      request.sl = signal.stop_loss;
      request.tp = signal.take_profit;
      request.deviation = 10;
      request.magic = InpMagicNumber;
      request.comment = "YellowCluster";
      
      // Send order
      if(OrderSend(request, result))
      {
         Print("Order placed: ", signal.symbol, " ", 
               (signal.direction > 0 ? "BUY" : "SELL"), 
               " ", lot_size, " lots");
      }
      else
      {
         Print("Order failed: ", signal.symbol, " Error: ", result.comment);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size for signal                                   |
//+------------------------------------------------------------------+
double CalculateLotSize(const SignalData &signal)
{
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = account_balance * (InpTotalRisk / 100.0);
   
   // Simplified lot calculation
   double risk_per_signal = risk_money / 5.0; // Assume max 5 signals
   double point_value = SymbolInfoDouble(signal.symbol, SYMBOL_TRADE_TICK_VALUE);
   
   double lot_size = risk_per_signal / (signal.risk_pips * point_value);
   
   // Normalize lot size
   double min_lot = SymbolInfoDouble(signal.symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(signal.symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(signal.symbol, SYMBOL_VOLUME_STEP);
   
   lot_size = MathMax(min_lot, lot_size);
   lot_size = MathMin(max_lot, lot_size);
   lot_size = NormalizeDouble(lot_size / lot_step, 0) * lot_step;
   
   return lot_size;
}

//+------------------------------------------------------------------+
//| Close position                                                  |
//+------------------------------------------------------------------+
void ClosePosition(string symbol)
{
   if(!PositionSelect(symbol)) return;
   
   MqlTradeRequest request;
   MqlTradeResult result;
   
   ZeroMemory(request);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                  ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = (request.type == ORDER_TYPE_BUY) ?
                   SymbolInfoDouble(symbol, SYMBOL_ASK) :
                   SymbolInfoDouble(symbol, SYMBOL_BID);
   request.deviation = 10;
   request.magic = InpMagicNumber;
   request.comment = "Close YellowCluster";
   
   if(OrderSend(request, result))
   {
      Print("Position closed: ", symbol);
   }
   else
   {
      Print("Close failed: ", symbol, " Error: ", result.comment);
   }
}

//+------------------------------------------------------------------+
//| Print signals to log                                           |
//+------------------------------------------------------------------+
void PrintSignals(int count)
{
   Print("=== Yellow Cluster Signals ===");
   for(int i = 0; i < count; i++)
   {
      SignalData signal = g_signals[i];
      Print(StringFormat("%s: %s Entry:%.5f SL:%.5f TP:%.5f RR:1:%.1f Strength:%.2f",
            signal.symbol,
            (signal.direction > 0 ? "BUY" : "SELL"),
            signal.entry_price,
            signal.stop_loss,
            signal.take_profit,
            signal.reward_pips / signal.risk_pips,
            signal.signal_strength));
   }
}