//+------------------------------------------------------------------+
//| Expert Advisor: Call Setup EMA Break                             |
//| Strategy:                                                        |
//| - Entry: Price breaks above 200 EMA on H4                        |
//| - Stop Loss: Below recent swing low (last 10 candles)           |
//| - Take Profit: 2x risk (R:R = 2:1)                               |
//| - Timeframe: H4                                                  |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- input parameters
input double LotSize         = 0.1;   // Position size
input int    RiskRewardRatio = 2;     // Risk-to-reward ratio (TP = R*SL)
input int    Lookback        = 10;    // Swing low lookback
input int    Slippage        = 10;    // Max slippage in points

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Call Setup EA initialized.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastTradeTime = 0;
   MqlRates price[];

   //--- Check timeframe
   if(_Period != PERIOD_H4)
      return;

   //--- Don't repeat trade in the same candle
   if(TimeCurrent() == lastTradeTime)
      return;

   //--- No open position
   if(!PositionSelect(_Symbol))
   {
      //--- Load recent candles
      if(CopyRates(_Symbol, PERIOD_H4, 0, Lookback + 2, price) <= Lookback + 1)
         return;

      ArraySetAsSeries(price, true);

      //--- Load 200 EMA
      double ema_buffer[2];
      int ema_handle = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);

      if(ema_handle == INVALID_HANDLE)
      {
         Print("Failed to create EMA handle");
         return;
      }

      if(CopyBuffer(ema_handle, 0, 0, 2, ema_buffer) != 2)
      {
         Print("Failed to read EMA buffer");
         return;
      }

      double ema_current = ema_buffer[0];
      double ema_previous = ema_buffer[1];

      double close_current = price[0].close;
      double close_previous = price[1].close;

      //--- Entry condition: Clean break above 200 EMA
      if(close_previous < ema_previous && close_current > ema_current)
      {
         //--- Calculate swing low for stop loss
         double swingLow = price[1].low;
         for(int i = 2; i <= Lookback; i++)
         {
            if(price[i].low < swingLow)
               swingLow = price[i].low;
         }

         double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double stopLoss   = swingLow;
         double risk       = entryPrice - stopLoss;

         if(risk <= 0) return; // avoid invalid trades

         double takeProfit = entryPrice + RiskRewardRatio * risk;

         //--- Normalize
         stopLoss   = NormalizeDouble(stopLoss, _Digits);
         takeProfit = NormalizeDouble(takeProfit, _Digits);
         entryPrice = NormalizeDouble(entryPrice, _Digits);

         //--- Execute trade
         trade.SetDeviationInPoints(Slippage);
         if(trade.Buy(LotSize, _Symbol, entryPrice, stopLoss, takeProfit, "Call Setup EMA Break"))
         {
            lastTradeTime = TimeCurrent();
            Print("BUY executed at ", entryPrice, " | SL: ", stopLoss, " | TP: ", takeProfit);
         }
         else
         {
            Print("Trade failed: ", trade.ResultRetcodeDescription());
         }
      }
   }
}
