//+------------------------------------------------------------------+
//|                                    MA_Cross_RSI_TrendFollow.mq5 |
//|                                   Trend-Following MA Cross + RSI |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property link      ""
#property version   "1.00"

//--- Input parameters
input group "=== Moving Averages ==="
input int               FastMA_Period = 50;        // Fast MA Period (50 EMA)
input int               SlowMA_Period = 200;       // Slow MA Period (200 EMA)
input ENUM_MA_METHOD    MA_Method = MODE_EMA;      // MA Method

input group "=== RSI Settings ==="
input int               RSI_Period = 14;           // RSI Period
input double            RSI_Level = 50.0;          // RSI Entry Level

input group "=== Risk Management ==="
input double            RiskPercent = 1.5;         // Risk per trade (%)
input double            RiskReward = 2.0;          // Risk:Reward Ratio (TP = SL * RR)

input group "=== Trade Settings ==="
input int               SwingLookback = 20;        // Bars to look for swing low
input int               Magic = 123456;            // Magic Number
input string            TradeComment = "MA_RSI_EA"; // Trade Comment

input group "=== Filter Settings ==="
input bool              UseD1Filter = true;        // Use Daily trend filter
input int               D1_MA_Period = 50;         // Daily MA period for trend filter

//--- Global variables
int handleFastMA, handleSlowMA, handleRSI;
int handleD1_MA;
double fastMA[], slowMA[], rsiValues[];
double d1MA[];
MqlTick lastTick;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Create indicators
    handleFastMA = iMA(_Symbol, PERIOD_H1, FastMA_Period, 0, MA_Method, PRICE_CLOSE);
    handleSlowMA = iMA(_Symbol, PERIOD_H1, SlowMA_Period, 0, MA_Method, PRICE_CLOSE);
    handleRSI = iRSI(_Symbol, PERIOD_H1, RSI_Period, PRICE_CLOSE);
    
    if(UseD1Filter)
        handleD1_MA = iMA(_Symbol, PERIOD_D1, D1_MA_Period, 0, MA_Method, PRICE_CLOSE);
    
    //--- Check if indicators are created successfully
    if(handleFastMA == INVALID_HANDLE || handleSlowMA == INVALID_HANDLE || 
       handleRSI == INVALID_HANDLE || (UseD1Filter && handleD1_MA == INVALID_HANDLE))
    {
        Print("Error creating indicators");
        return INIT_FAILED;
    }
    
    //--- Set array as series
    ArraySetAsSeries(fastMA, true);
    ArraySetAsSeries(slowMA, true);
    ArraySetAsSeries(rsiValues, true);
    ArraySetAsSeries(d1MA, true);
    
    Print("EA initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release indicator handles
    if(handleFastMA != INVALID_HANDLE) IndicatorRelease(handleFastMA);
    if(handleSlowMA != INVALID_HANDLE) IndicatorRelease(handleSlowMA);
    if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
    if(handleD1_MA != INVALID_HANDLE) IndicatorRelease(handleD1_MA);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Get current tick
    if(!SymbolInfoTick(_Symbol, lastTick))
        return;
    
    //--- Check for new bar
    datetime currentBarTime = iTime(_Symbol, PERIOD_H1, 0);
    if(currentBarTime == lastBarTime)
        return;
    
    lastBarTime = currentBarTime;
    
    //--- Get indicator values
    if(!GetIndicatorValues())
        return;
    
    //--- Check for entry signals
    CheckForEntry();
    
    //--- Manage existing trades
    ManageTrades();
}

//+------------------------------------------------------------------+
//| Get indicator values                                             |
//+------------------------------------------------------------------+
bool GetIndicatorValues()
{
    //--- Get MA values
    if(CopyBuffer(handleFastMA, 0, 0, 3, fastMA) < 3 ||
       CopyBuffer(handleSlowMA, 0, 0, 3, slowMA) < 3 ||
       CopyBuffer(handleRSI, 0, 0, 2, rsiValues) < 2)
    {
        Print("Error copying indicator buffers");
        return false;
    }
    
    //--- Get daily MA if filter is enabled
    if(UseD1Filter)
    {
        if(CopyBuffer(handleD1_MA, 0, 0, 2, d1MA) < 2)
        {
            Print("Error copying daily MA buffer");
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckForEntry()
{
    //--- Check if we already have a position
    if(PositionSelect(_Symbol))
        return;
    
    //--- Check for bullish signal
    if(CheckBullishSignal())
    {
        double sl = FindSwingLow();
        if(sl > 0)
            OpenBuyTrade(sl);
    }
}

//+------------------------------------------------------------------+
//| Check bullish signal conditions                                  |
//+------------------------------------------------------------------+
bool CheckBullishSignal()
{
    //--- Check MA crossover (50 EMA crosses above 200 EMA)
    bool maCross = (fastMA[1] > slowMA[1] && fastMA[2] <= slowMA[2]);
    
    //--- Check RSI condition
    bool rsiCondition = (rsiValues[0] > RSI_Level);
    
    //--- Check daily trend filter
    bool dailyTrend = true;
    if(UseD1Filter)
    {
        dailyTrend = (lastTick.bid > d1MA[0]); // Price above daily MA
    }
    
    //--- Check if price is above key support (using slow MA as support)
    bool aboveSupport = (lastTick.bid > slowMA[0]);
    
    return (maCross && rsiCondition && dailyTrend && aboveSupport);
}

//+------------------------------------------------------------------+
//| Find swing low for stop loss                                    |
//+------------------------------------------------------------------+
double FindSwingLow()
{
    double lowestLow = DBL_MAX;
    
    for(int i = 1; i <= SwingLookback; i++)
    {
        double low = iLow(_Symbol, PERIOD_H1, i);
        if(low < lowestLow)
            lowestLow = low;
    }
    
    if(lowestLow == DBL_MAX)
        return 0;
    
    return lowestLow;
}

//+------------------------------------------------------------------+
//| Open buy trade                                                   |
//+------------------------------------------------------------------+
void OpenBuyTrade(double stopLoss)
{
    double ask = lastTick.ask;
    double sl = stopLoss;
    double slDistance = ask - sl;
    double tp = ask + (slDistance * RiskReward);
    
    //--- Calculate lot size based on risk percentage
    double lotSize = CalculateLotSize(slDistance);
    if(lotSize <= 0)
    {
        Print("Invalid lot size calculated");
        return;
    }
    
    //--- Prepare trade request
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = ORDER_TYPE_BUY;
    request.price = ask;
    request.sl = sl;
    request.tp = tp;
    request.magic = Magic;
    request.comment = TradeComment;
    request.type_filling = ORDER_FILLING_IOC;
    
    //--- Send trade request
    if(OrderSend(request, result))
    {
        Print("Buy order opened successfully. Ticket: ", result.order, 
              " Volume: ", lotSize, " SL: ", sl, " TP: ", tp);
    }
    else
    {
        Print("Failed to open buy order. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                     |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (RiskPercent / 100.0);
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    //--- Calculate lot size
    double lotSize = (riskAmount / (slDistance / tickSize * tickValue));
    
    //--- Normalize lot size
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    //--- Check limits
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Manage existing trades                                           |
//+------------------------------------------------------------------+
void ManageTrades()
{
    //--- This function can be expanded for advanced trade management
    //--- Currently, the EA relies on SL/TP for trade management
    
    if(!PositionSelect(_Symbol))
        return;
    
    //--- You can add trailing stop, break-even, or other management logic here
    //--- For this basic strategy, we let SL/TP handle the exits
}

//+------------------------------------------------------------------+
//| Trade transaction function                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
    //--- Handle trade transactions if needed
    if(trans.symbol == _Symbol && trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        Print("Trade executed: ", trans.deal, " Volume: ", trans.volume, 
              " Price: ", trans.price);
    }
}