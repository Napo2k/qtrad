//+------------------------------------------------------------------+
//|                                         AdaptiveATRStopLoss.mq5 |
//|                              Custom Indicator for MetaTrader 5  |
//|                   Calculates a dynamic stop loss based on ATR   |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

//--- Plotting settings
#property indicator_label1  "Adaptive Stop Loss"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_DASH
#property indicator_width1  2

//--- Input parameters
input int atrPeriod = 14;                        // ATR calculation period
input double multiplier = 1.5;                   // Stop loss distance multiplier
input double entryPrice = 0.0;                   // Entry price (manual or strategy)
input ENUM_POSITION_TYPE tradeDirection = POSITION_TYPE_BUY; // Trade direction: Buy/Sell

//--- Indicator buffer
double stopLossBuffer[];

//--- ATR handle
int atrHandle;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create ATR indicator handle
   atrHandle = iATR(_Symbol, _Period, atrPeriod);
   if (atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle. Check parameters.");
      return(INIT_FAILED);
   }

   //--- Set buffer
   SetIndexBuffer(0, stopLossBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, atrPeriod);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle); // release ATR indicator handle
}

//+------------------------------------------------------------------+
//| Custom indicator calculation function                            |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- Sanity check
   if (rates_total <= atrPeriod || entryPrice <= 0.0)
      return(0); // not enough data or entry price not set

   //--- Temporary array to hold ATR values
   double atrValues[];
   ArraySetAsSeries(atrValues, true);

   //--- Copy ATR values into array
   if (CopyBuffer(atrHandle, 0, 0, rates_total, atrValues) <= 0)
   {
      Print("Failed to retrieve ATR data. Error: ", GetLastError());
      return(0);
   }

   //--- Calculate and store stop loss values
   for (int i = 0; i < rates_total; i++)
   {
      double atr = atrValues[i];

      //--- Sanity check for extreme ATR values
      if (atr <= 0 || atr > 10000.0)
      {
         stopLossBuffer[i] = EMPTY_VALUE;
         continue;
      }

      //--- Calculate stop loss level based on direction
      double stopLoss = 0.0;
      if (tradeDirection == POSITION_TYPE_BUY)
         stopLoss = entryPrice - (atr * multiplier);
      else if (tradeDirection == POSITION_TYPE_SELL)
         stopLoss = entryPrice + (atr * multiplier);

      stopLossBuffer[i] = stopLoss;
   }

   return(rates_total);
}
