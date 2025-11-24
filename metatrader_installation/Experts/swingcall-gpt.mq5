//+------------------------------------------------------------------+
//| Simple Swing Call Setup based on 200 EMA break on 4H             |
//+------------------------------------------------------------------+
#property strict

input double  LotSize = 0.1;              // Trade lot size
input double  MaxAthDistancePercent = 2; // Price must be at least 2% below ATH
input int     LookbackDaysForATH = 90;   // Lookback days to find ATH
input int     Slippage = 5;

datetime lastTradeTime=0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("Swing Call Setup EA initialized.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   static datetime lastBarTime=0;
   MqlRates rates[];
   
   // Copy 4H bars - we need recent 10 bars to check conditions
   if(CopyRates(_Symbol, PERIOD_H4, 0, 10, rates) <= 0)
     return;

   ArraySetAsSeries(rates,true);
   if(rates[0].time == lastBarTime) return; // Already processed this bar
   lastBarTime = rates[0].time;

   // Check if already have a position open on this symbol
   if(PositionSelect(_Symbol))
     return;

//--- Get 200 EMA using iMA handle and CopyBuffer
double ema200_buffer[2];
int ema_handle = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);

if(ema_handle == INVALID_HANDLE)
{
   Print("EMA handle invalid");
   return;
}

if(CopyBuffer(ema_handle, 0, 0, 2, ema200_buffer) != 2)
{
   Print("Failed to get EMA data");
   return;
}

double ema200 = ema200_buffer[0];
double prevEma200 = ema200_buffer[1];

   double priceNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Check uptrend - price above 200 EMA currently and previously below or crossing above
   bool isTrendingUp = (priceNow > ema200);

   // Detect clean break: previous bar close below EMA, current price above EMA
   double prevClose = rates[1].close;
   bool cleanBreak = (prevClose < prevEma200) && (priceNow > ema200);

   if(!isTrendingUp || !cleanBreak)
     return;

   // Check distance from ATH over last LookbackDaysForATH days (~LookbackDaysForATH*6 4H bars)
   int barsToLookback = LookbackDaysForATH * 6;
   if(barsToLookback > CopyRates(_Symbol, PERIOD_H4, 0, 1000, rates))
      barsToLookback = 1000; // max available

   double ath = -1;
   for(int i=barsToLookback-1; i>=0; i--)
     {
      if(rates[i].high > ath)
         ath = rates[i].high;
     }

   if(ath < 0)
      return;

   double distanceToAthPercent = ((ath - priceNow)/ath)*100.0;

   if(distanceToAthPercent < MaxAthDistancePercent)
      return; // Price too close to ATH, avoid buying calls

   // Optional retest: check if price touched EMA recently (within last 2 bars) and bounced back up
   // For simplicity, skip retest condition here or you can add more logic

   // Place Buy order
   MqlTradeRequest request;
   MqlTradeResult  result;

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.deviation = Slippage;
   request.magic = 123456;
   request.comment = "Swing Call Setup Buy";

   if(!OrderSend(request, result))
     Print("OrderSend failed: ", GetLastError());
   else
     Print("Buy order placed: ", result.order);
  }

//+------------------------------------------------------------------+
