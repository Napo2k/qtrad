//+------------------------------------------------------------------+
//|                                    LW Volatility Breakout.mq5   |
//|                                                                  |
//|                       LW Volatility Breakout Strategy EA        |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>

// Input parameters
input group "=== Strategy Settings ==="
input int      DonchianPeriod = 96;           // Donchian Channels Period
input int      LWTIPeriod = 25;               // LWTI Period
input int      LWTISmoothing = 20;            // LWTI Smoothing Period
input int      VolumeMAPeriod = 30;           // Volume MA Period
input double   RiskRewardRatio = 2.0;         // Risk to Reward Ratio

input group "=== Risk Management ==="
input double   LotSize = 0.1;                 // Lot Size
input double   MaxSpreadPips = 3.0;           // Maximum Spread in Pips
input bool     UseFixedSL = false;            // Use Fixed Stop Loss
input int      FixedSLPips = 50;              // Fixed Stop Loss in Pips

input group "=== Trading Hours ==="
input bool     UseTimeFilter = true;          // Enable Time Filter
input int      StartHour = 8;                 // Trading Start Hour
input int      EndHour = 18;                  // Trading End Hour

// Global variables
CTrade trade;
int donchianHandle, lwtiHandle, volumeHandle;
double donchianUpper[], donchianLower[], donchianMiddle[];
double lwtiMain[], lwtiSignal[];
double volumeMA[];
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize trade class
    trade.SetExpertMagicNumber(123456);
    
    // Create Donchian Channels indicator
    donchianHandle = iCustom(_Symbol, PERIOD_CURRENT, "Examples\\Donchian_Channels", DonchianPeriod);
    if(donchianHandle == INVALID_HANDLE)
    {
        Print("Failed to create Donchian Channels indicator");
        return INIT_FAILED;
    }
    
    // Create LWTI indicator (using RSI as approximation since LWTI is proprietary)
    lwtiHandle = iRSI(_Symbol, PERIOD_CURRENT, LWTIPeriod, PRICE_CLOSE);
    if(lwtiHandle == INVALID_HANDLE)
    {
        Print("Failed to create LWTI indicator");
        return INIT_FAILED;
    }
    
    // Create Volume MA indicator
    volumeHandle = iMA(_Symbol, PERIOD_CURRENT, VolumeMAPeriod, 0, MODE_SMA, PRICE_VOLUMES);
    if(volumeHandle == INVALID_HANDLE)
    {
        Print("Failed to create Volume MA indicator");
        return INIT_FAILED;
    }
    
    // Set array as series
    ArraySetAsSeries(donchianUpper, true);
    ArraySetAsSeries(donchianLower, true);
    ArraySetAsSeries(donchianMiddle, true);
    ArraySetAsSeries(lwtiMain, true);
    ArraySetAsSeries(volumeMA, true);
    
    Print("LW Volatility Breakout Strategy EA initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    if(donchianHandle != INVALID_HANDLE) IndicatorRelease(donchianHandle);
    if(lwtiHandle != INVALID_HANDLE) IndicatorRelease(lwtiHandle);
    if(volumeHandle != INVALID_HANDLE) IndicatorRelease(volumeHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if new bar formed
    if(Time[0] == lastBarTime) return;
    lastBarTime = Time[0];
    
    // Check trading conditions
    if(!IsNewBar()) return;
    if(!IsTradeTime()) return;
    if(!IsSpreadAcceptable()) return;
    if(PositionsTotal() > 0) return; // Only one position at a time
    
    // Get indicator values
    if(!GetIndicatorValues()) return;
    
    // Check for trading signals
    CheckLongSignal();
    CheckShortSignal();
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    static datetime lastTime = 0;
    datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    if(lastTime != currentTime)
    {
        lastTime = currentTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check trading time                                               |
//+------------------------------------------------------------------+
bool IsTradeTime()
{
    if(!UseTimeFilter) return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    return (dt.hour >= StartHour && dt.hour < EndHour);
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                    |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
    double spread = (Ask - Bid) / _Point;
    return (spread <= MaxSpreadPips * 10); // Convert pips to points
}

//+------------------------------------------------------------------+
//| Get indicator values                                             |
//+------------------------------------------------------------------+
bool GetIndicatorValues()
{
    // Get Donchian values (using custom implementation)
    CalculateDonchianChannels();
    
    // Get LWTI values (using RSI as approximation)
    if(CopyBuffer(lwtiHandle, 0, 0, 3, lwtiMain) < 3)
    {
        Print("Failed to get LWTI values");
        return false;
    }
    
    // Get Volume MA values
    if(CopyBuffer(volumeHandle, 0, 0, 3, volumeMA) < 3)
    {
        Print("Failed to get Volume MA values");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate Donchian Channels manually                             |
//+------------------------------------------------------------------+
void CalculateDonchianChannels()
{
    ArrayResize(donchianUpper, 3);
    ArrayResize(donchianLower, 3);
    ArrayResize(donchianMiddle, 3);
    
    for(int i = 0; i < 3; i++)
    {
        double highest = High[ArrayMaximum(High, i, DonchianPeriod)];
        double lowest = Low[ArrayMinimum(Low, i, DonchianPeriod)];
        
        donchianUpper[i] = highest;
        donchianLower[i] = lowest;
        donchianMiddle[i] = (highest + lowest) / 2.0;
    }
}

//+------------------------------------------------------------------+
//| Check for long signal                                            |
//+------------------------------------------------------------------+
void CheckLongSignal()
{
    // Price touches upper Donchian band
    bool priceTouchesUpper = (High[1] >= donchianUpper[1]) || (Close[1] >= donchianUpper[1]);
    
    // LWTI is bullish (RSI > 50 as approximation)
    bool lwtiGreen = lwtiMain[1] > 50.0;
    
    // Volume confirmation
    bool volumeConfirm = CheckVolumeCondition(true);
    
    if(priceTouchesUpper && lwtiGreen && volumeConfirm)
    {
        // Calculate stop loss
        double stopLoss = UseFixedSL ? 
                         Ask - FixedSLPips * _Point * 10 : 
                         donchianMiddle[1];
        
        // Calculate take profit based on risk-reward ratio
        double riskPips = (Ask - stopLoss) / (_Point * 10);
        double takeProfit = Ask + (riskPips * RiskRewardRatio * _Point * 10);
        
        // Execute long trade
        if(trade.Buy(LotSize, _Symbol, Ask, stopLoss, takeProfit, "LW Volatility Long"))
        {
            Print("Long trade executed at ", Ask);
        }
    }
}

//+------------------------------------------------------------------+
//| Check for short signal                                           |
//+------------------------------------------------------------------+
void CheckShortSignal()
{
    // Price touches lower Donchian band
    bool priceTouchesLower = (Low[1] <= donchianLower[1]) || (Close[1] <= donchianLower[1]);
    
    // LWTI is bearish (RSI < 50 as approximation)
    bool lwtiRed = lwtiMain[1] < 50.0;
    
    // Volume confirmation
    bool volumeConfirm = CheckVolumeCondition(false);
    
    if(priceTouchesLower && lwtiRed && volumeConfirm)
    {
        // Calculate stop loss
        double stopLoss = UseFixedSL ? 
                         Bid + FixedSLPips * _Point * 10 : 
                         donchianMiddle[1];
        
        // Calculate take profit based on risk-reward ratio
        double riskPips = (stopLoss - Bid) / (_Point * 10);
        double takeProfit = Bid - (riskPips * RiskRewardRatio * _Point * 10);
        
        // Execute short trade
        if(trade.Sell(LotSize, _Symbol, Bid, stopLoss, takeProfit, "LW Volatility Short"))
        {
            Print("Short trade executed at ", Bid);
        }
    }
}

//+------------------------------------------------------------------+
//| Check volume condition                                           |
//+------------------------------------------------------------------+
bool CheckVolumeCondition(bool isLong)
{
    // Current volume should be above moving average
    long currentVolume = Volume[1];
    bool volumeAboveMA = currentVolume > volumeMA[1];
    
    // Volume color check (green for long, red for short)
    bool volumeColor = isLong ? (Close[1] > Open[1]) : (Close[1] < Open[1]);
    
    return volumeAboveMA && volumeColor;
}

//+------------------------------------------------------------------+
//| Trade transaction function                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
    // Handle trade events if needed
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        if(trans.deal_type == DEAL_TYPE_BUY)
            Print("Buy deal executed: ", trans.price);
        else if(trans.deal_type == DEAL_TYPE_SELL)
            Print("Sell deal executed: ", trans.price);
    }
}

//+------------------------------------------------------------------+
//| Custom function to check major support/resistance levels        |
//+------------------------------------------------------------------+
bool IsNearMajorLevel(double price, ENUM_TIMEFRAMES higherTF = PERIOD_H1)
{
    // This is a simplified version - you can enhance it with proper S/R detection
    double high1h = iHigh(_Symbol, higherTF, 1);
    double low1h = iLow(_Symbol, higherTF, 1);
    double range = high1h - low1h;
    double buffer = range * 0.1; // 10% buffer
    
    // Check if price is near recent high or low on higher timeframe
    bool nearHigh = MathAbs(price - high1h) <= buffer;
    bool nearLow = MathAbs(price - low1h) <= buffer;
    
    return (nearHigh || nearLow);
}

//+------------------------------------------------------------------+
//| Enhanced signal validation with major level check               |
//+------------------------------------------------------------------+
bool ValidateSignalWithMajorLevels(bool isLong)
{
    double currentPrice = isLong ? Ask : Bid;
    
    // The "secret trick" - avoid trades near major S/R levels unless breaking through
    if(IsNearMajorLevel(currentPrice))
    {
        // Only take the trade if we're breaking through the level with strong momentum
        double momentum = MathAbs(Close[1] - Close[2]) / _Point;
        return momentum > 20; // Adjust threshold as needed
    }
    
    return true; // No major level nearby, signal is valid
}

//+------------------------------------------------------------------+