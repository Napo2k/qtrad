//+------------------------------------------------------------------+
//|                                            GridTradingEA.mq5     |
//|                              Copyright 2024, Advanced Trading EA |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Advanced Trading EA"
#property version   "1.00"
#property description "Grid Trading EA with alternating Buy/Sell orders and lot multiplication"

//--- Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Input parameters
input datetime ActiveTime = D'2024.10.01 01:00:00';  // Active Time (Local Time)
input double InitialLot = 1.0;                       // Initial Lot Size
input int DistancePO = 200;                          // Distance for Pending Order (points)
input double LotMultiplier = 2.0;                    // Lot Multiplier
input int MaxPosition = 10;                          // Max Position
input double TakeProfitUSD = 10.0;                   // Take Profit in USD
input double StopLossUSD = 1000.0;                   // Stop Loss in USD
input double PartialCloseProfitUSD = 5.0;            // Partial Close Profit in USD
input int TakeProfitCount = 10;                      // Take Profit Count (shutdown after this many)
input int NextStartOrderDelay = 3;                   // Next Start Order Delay (seconds)

//--- Global variables
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

bool g_isActive = false;
datetime g_lastOrderTime = 0;
double g_totalTakeProfit = 0.0;
int g_takeProfitCounter = 0;
double g_openPrice = 0.0;
bool g_firstOrderPlaced = false;
datetime g_cycleStartTime = 0;

//--- Dashboard variables
int g_dashboardX = 20;
int g_dashboardY = 50;
color g_textColor = clrWhite;
color g_bgColor = clrBlack;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Set magic number for this EA
    trade.SetExpertMagicNumber(123456);
    
    //--- Initialize variables
    g_isActive = false;
    g_lastOrderTime = 0;
    g_totalTakeProfit = 0.0;
    g_takeProfitCounter = 0;
    g_openPrice = 0.0;
    g_firstOrderPlaced = false;
    
    //--- Create dashboard
    CreateDashboard();
    
    Print("GridTradingEA initialized successfully");
    Print("Active Time: ", TimeToString(ActiveTime));
    Print("Waiting for activation...");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Remove dashboard objects
    RemoveDashboard();
    
    Print("GridTradingEA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Update dashboard every tick
    UpdateDashboard();
    
    //--- Check if EA should be active
    if (!g_isActive)
    {
        if (TimeCurrent() >= ActiveTime)
        {
            g_isActive = true;
            g_openPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            Print("EA Activated at: ", TimeToString(TimeCurrent()));
            Print("Open price stored: ", g_openPrice);
        }
        else
        {
            return; // Wait for activation time
        }
    }
    
    //--- Check if maximum take profit count reached
    if (g_takeProfitCounter >= TakeProfitCount)
    {
        Print("Maximum Take Profit count (", TakeProfitCount, ") reached. EA shutting down.");
        ExpertRemove();
        return;
    }
    
    //--- Main trading logic
    ExecuteTradingLogic();
}

//+------------------------------------------------------------------+
//| Main trading logic                                              |
//+------------------------------------------------------------------+
void ExecuteTradingLogic()
{
    //--- Check for take profit conditions
    if (CheckTakeProfit())
    {
        CloseAllOrders();
        g_takeProfitCounter++;
        g_totalTakeProfit += TakeProfitUSD;
        g_lastOrderTime = TimeCurrent();
        g_firstOrderPlaced = false;
        
        Print("Take Profit achieved! Total TP: ", g_totalTakeProfit, " USD, Count: ", g_takeProfitCounter);
        
        // Wait for delay before next cycle
        Sleep(NextStartOrderDelay * 1000);
        
        // Update open price for new cycle
        g_openPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        return;
    }
    
    //--- Check for partial close conditions
    CheckPartialClose();
    
    //--- Check if we need to place the first order
    if (!g_firstOrderPlaced && (TimeCurrent() - g_lastOrderTime >= NextStartOrderDelay))
    {
        PlaceFirstOrder();
        return;
    }
    
    //--- Check for pending order triggers and place new orders
    CheckAndPlacePendingOrders();
}

//+------------------------------------------------------------------+
//| Place first order based on price comparison                     |
//+------------------------------------------------------------------+
void PlaceFirstOrder()
{
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    if (g_openPrice < currentPrice)
    {
        // Place Buy order
        if (trade.Buy(InitialLot, _Symbol))
        {
            Print("First Buy order placed: ", InitialLot, " lots at ", currentPrice);
            g_firstOrderPlaced = true;
            g_cycleStartTime = TimeCurrent();
            
            // Place corresponding Sell Stop pending order
            PlacePendingOrder(ORDER_TYPE_SELL_STOP, InitialLot * LotMultiplier);
        }
    }
    else if (g_openPrice > currentPrice)
    {
        // Place Sell order
        if (trade.Sell(InitialLot, _Symbol))
        {
            Print("First Sell order placed: ", InitialLot, " lots at ", currentPrice);
            g_firstOrderPlaced = true;
            g_cycleStartTime = TimeCurrent();
            
            // Place corresponding Buy Stop pending order
            PlacePendingOrder(ORDER_TYPE_BUY_STOP, InitialLot * LotMultiplier);
        }
    }
}

//+------------------------------------------------------------------+
//| Place pending order                                             |
//+------------------------------------------------------------------+
void PlacePendingOrder(ENUM_ORDER_TYPE orderType, double lots)
{
    double price = 0.0;
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    if (orderType == ORDER_TYPE_BUY_STOP)
    {
        price = currentPrice + (DistancePO * point);
    }
    else if (orderType == ORDER_TYPE_SELL_STOP)
    {
        price = currentPrice - (DistancePO * point);
    }
    
    price = NormalizeDouble(price, digits);
    
    if (trade.OrderOpen(_Symbol, orderType, lots, 0, price, 0, 0))
    {
        Print("Pending order placed: ", EnumToString(orderType), " ", lots, " lots at ", price);
    }
    else
    {
        Print("Failed to place pending order: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Check and place pending orders when positions are triggered     |
//+------------------------------------------------------------------+
void CheckAndPlacePendingOrders()
{
    if (!g_firstOrderPlaced) return;
    
    // Count current positions and calculate lot sizes
    double totalBuyLots = 0.0;
    double totalSellLots = 0.0;
    int totalPositions = 0;
    
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (positionInfo.SelectByIndex(i) && positionInfo.Symbol() == _Symbol && 
            positionInfo.Magic() == trade.RequestMagic())
        {
            totalPositions++;
            if (positionInfo.PositionType() == POSITION_TYPE_BUY)
                totalBuyLots += positionInfo.Volume();
            else
                totalSellLots += positionInfo.Volume();
        }
    }
    
    // Check if we have pending orders
    bool hasPendingOrder = false;
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (orderInfo.SelectByIndex(i) && orderInfo.Symbol() == _Symbol && 
            orderInfo.Magic() == trade.RequestMagic())
        {
            hasPendingOrder = true;
            break;
        }
    }
    
    // Place pending order if needed and within max position limit
    if (!hasPendingOrder && totalPositions < MaxPosition)
    {
        if (totalBuyLots > totalSellLots)
        {
            // Need Sell Stop order
            double newLots = totalBuyLots * LotMultiplier;
            PlacePendingOrder(ORDER_TYPE_SELL_STOP, newLots);
        }
        else if (totalSellLots > totalBuyLots)
        {
            // Need Buy Stop order
            double newLots = totalSellLots * LotMultiplier;
            PlacePendingOrder(ORDER_TYPE_BUY_STOP, newLots);
        }
    }
}

//+------------------------------------------------------------------+
//| Check take profit conditions                                    |
//+------------------------------------------------------------------+
bool CheckTakeProfit()
{
    double totalProfit = 0.0;
    
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (positionInfo.SelectByIndex(i) && positionInfo.Symbol() == _Symbol && 
            positionInfo.Magic() == trade.RequestMagic())
        {
            totalProfit += positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();
        }
    }
    
    return (totalProfit >= TakeProfitUSD);
}

//+------------------------------------------------------------------+
//| Check partial close conditions                                  |
//+------------------------------------------------------------------+
void CheckPartialClose()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if (positionInfo.SelectByIndex(i) && positionInfo.Symbol() == _Symbol && 
            positionInfo.Magic() == trade.RequestMagic())
        {
            double positionProfit = positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();
            
            // Check if this is a losing position that can be partially closed for $5 profit
            if (positionProfit < 0)
            {
                double totalProfit = GetTotalFloatingProfit();
                if (totalProfit >= PartialCloseProfitUSD)
                {
                    // Calculate how much to close to achieve $5 profit
                    double volumeToClose = CalculatePartialCloseVolume(positionInfo.Ticket());
                    if (volumeToClose > 0)
                    {
                        if (trade.PositionClosePartial(positionInfo.Ticket(), volumeToClose))
                        {
                            Print("Partial close executed for $", PartialCloseProfitUSD, " profit");
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate volume for partial close                              |
//+------------------------------------------------------------------+
double CalculatePartialCloseVolume(ulong ticket)
{
    if (!positionInfo.SelectByTicket(ticket)) return 0.0;
    
    double positionProfit = positionInfo.Profit();
    double positionVolume = positionInfo.Volume();
    
    if (positionProfit >= 0) return 0.0; // Don't close profitable positions
    
    // Calculate what portion to close to achieve $5 profit
    double profitPerLot = positionProfit / positionVolume;
    double volumeToClose = PartialCloseProfitUSD / MathAbs(profitPerLot);
    
    // Ensure we don't close more than available
    volumeToClose = MathMin(volumeToClose, positionVolume);
    
    // Normalize to lot step
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    volumeToClose = NormalizeDouble(volumeToClose, 2);
    
    return volumeToClose;
}

//+------------------------------------------------------------------+
//| Get total floating profit                                       |
//+------------------------------------------------------------------+
double GetTotalFloatingProfit()
{
    double totalProfit = 0.0;
    
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (positionInfo.SelectByIndex(i) && positionInfo.Symbol() == _Symbol && 
            positionInfo.Magic() == trade.RequestMagic())
        {
            totalProfit += positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();
        }
    }
    
    return totalProfit;
}

//+------------------------------------------------------------------+
//| Close all orders and positions                                  |
//+------------------------------------------------------------------+
void CloseAllOrders()
{
    // Close all positions
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if (positionInfo.SelectByIndex(i) && positionInfo.Symbol() == _Symbol && 
            positionInfo.Magic() == trade.RequestMagic())
        {
            trade.PositionClose(positionInfo.Ticket());
        }
    }
    
    // Delete all pending orders
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if (orderInfo.SelectByIndex(i) && orderInfo.Symbol() == _Symbol && 
            orderInfo.Magic() == trade.RequestMagic())
        {
            trade.OrderDelete(orderInfo.Ticket());
        }
    }
    
    Print("All positions and orders closed");
}

//+------------------------------------------------------------------+
//| Create dashboard                                                |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    // Create background rectangle
    ObjectCreate(0, "DashboardBG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "DashboardBG", OBJPROP_XDISTANCE, g_dashboardX - 5);
    ObjectSetInteger(0, "DashboardBG", OBJPROP_YDISTANCE, g_dashboardY - 5);
    ObjectSetInteger(0, "DashboardBG", OBJPROP_XSIZE, 300);
    ObjectSetInteger(0, "DashboardBG", OBJPROP_YSIZE, 200);
    ObjectSetInteger(0, "DashboardBG", OBJPROP_BGCOLOR, g_bgColor);
    ObjectSetInteger(0, "DashboardBG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "DashboardBG", OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, "DashboardBG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    
    // Create text labels
    string labels[] = {
        "DashTitle", "DashActiveTime", "DashRemainingTime", "DashInitialLot",
        "DashFloatingPosition", "DashTotalTP", "DashTPRemaining"
    };
    
    for (int i = 0; i < 7; i++)
    {
        ObjectCreate(0, labels[i], OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, labels[i], OBJPROP_XDISTANCE, g_dashboardX);
        ObjectSetInteger(0, labels[i], OBJPROP_YDISTANCE, g_dashboardY + (i * 25));
        ObjectSetInteger(0, labels[i], OBJPROP_COLOR, g_textColor);
        ObjectSetInteger(0, labels[i], OBJPROP_FONTSIZE, 9);
        ObjectSetString(0, labels[i], OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(0, labels[i], OBJPROP_CORNER, CORNER_LEFT_UPPER);
    }
}

//+------------------------------------------------------------------+
//| Update dashboard                                                |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
    // Title
    ObjectSetString(0, "DashTitle", OBJPROP_TEXT, "=== Grid Trading EA ===");
    
    // Active Time
    ObjectSetString(0, "DashActiveTime", OBJPROP_TEXT, 
                   "Active Time: " + TimeToString(ActiveTime, TIME_DATE|TIME_MINUTES));
    
    // Remaining time until active
    string remainingTime = "";
    if (!g_isActive && TimeCurrent() < ActiveTime)
    {
        int remainingSeconds = (int)(ActiveTime - TimeCurrent());
        int hours = remainingSeconds / 3600;
        int minutes = (remainingSeconds % 3600) / 60;
        int seconds = remainingSeconds % 60;
        remainingTime = StringFormat("Remaining: %02d.%02d.%02d", hours, minutes, seconds);
    }
    else if (g_isActive)
    {
        remainingTime = "Status: ACTIVE";
    }
    else
    {
        remainingTime = "Status: WAITING";
    }
    ObjectSetString(0, "DashRemainingTime", OBJPROP_TEXT, remainingTime);
    
    // Initial Lot
    ObjectSetString(0, "DashInitialLot", OBJPROP_TEXT, 
                   "Initial Lot: " + DoubleToString(InitialLot, 2));
    
    // Floating Position
    double floatingProfit = GetTotalFloatingProfit();
    ObjectSetString(0, "DashFloatingPosition", OBJPROP_TEXT, 
                   "Floating P/L: $" + DoubleToString(floatingProfit, 2));
    
    // Total Take Profit
    ObjectSetString(0, "DashTotalTP", OBJPROP_TEXT, 
                   "Total TP: $" + DoubleToString(g_totalTakeProfit, 2));
    
    // Take Profit Count Remaining
    int remaining = TakeProfitCount - g_takeProfitCounter;
    ObjectSetString(0, "DashTPRemaining", OBJPROP_TEXT, 
                   "TP Remaining: " + IntegerToString(remaining));
}

//+------------------------------------------------------------------+
//| Remove dashboard                                                |
//+------------------------------------------------------------------+
void RemoveDashboard()
{
    ObjectDelete(0, "DashboardBG");
    ObjectDelete(0, "DashTitle");
    ObjectDelete(0, "DashActiveTime");
    ObjectDelete(0, "DashRemainingTime");
    ObjectDelete(0, "DashInitialLot");
    ObjectDelete(0, "DashFloatingPosition");
    ObjectDelete(0, "DashTotalTP");
    ObjectDelete(0, "DashTPRemaining");
}