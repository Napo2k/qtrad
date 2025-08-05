//+------------------------------------------------------------------+
//|                            Grid_Trigger_EA.mq5                   |
//|                 Auto-Trading EA with Dashboard & Logic          |
//+------------------------------------------------------------------+
#property copyright "OpenAI"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <ChartObjects\ChartObjectsTxtControls.mqh>

input datetime ActiveTime = D'2024.10.01 01:00:00';
input double InitialLot = 1.0;
input int DistancePO = 200;
input double LotMultiplier = 2.0;
input int MaxPositions = 10;
input double TakeProfitUSD = 10.0;
input double StopLossUSD = 1000.0;
input double PartialCloseUSD = 5.0;
input int TakeProfitCountLimit = 10;
input int NextStartDelaySec = 3;

CTrade trade;
double totalBuyLots = 0;
double totalSellLots = 0;
double totalProfitSinceActive = 0;
int takeProfitHits = 0;
bool EA_Active = false;
datetime lastOrderTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    EventSetTimer(1); // Timer every second for display update
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
    DrawDashboard();
}

//+------------------------------------------------------------------+
//| Dashboard Display                                                |
//+------------------------------------------------------------------+
void DrawDashboard()
{
    string prefix = "DASH_";
    datetime now = TimeLocal();
    int remaining = int(ActiveTime - now);
    int h = remaining / 3600;
    int m = (remaining % 3600) / 60;
    int s = remaining % 60;

    string content =
        "EA Activation Time: " + TimeToString(ActiveTime, TIME_DATE | TIME_MINUTES) + "\n" +
        "Time Until Active: " + IntegerToString(h, 2, '0') + ":" + IntegerToString(m, 2, '0') + ":" + IntegerToString(s, 2, '0') + "\n" +
        "Initial Lot: " + DoubleToString(InitialLot, 2) + "\n" +
        "Floating P/L: $" + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + "\n" +
        "Total Profit Since Start: $" + DoubleToString(totalProfitSinceActive, 2) + "\n" +
        "TP Count Left: " + IntegerToString(TakeProfitCountLimit - takeProfitHits);

    string labelName = prefix + "INFO";
    if (!ObjectFind(0, labelName))
    {
        ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, 10);
        ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
        ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrWhite);
    }
    ObjectSetString(0, labelName, OBJPROP_TEXT, content);
}

//+------------------------------------------------------------------+
//| Main Tick Function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    if (TimeLocal() < ActiveTime || takeProfitHits >= TakeProfitCountLimit)
        return;

    EA_Active = true;

    double openPrice = iOpen(_Symbol, PERIOD_CURRENT, 0);
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    int totalOrders = OrdersTotal();

    double profit = AccountInfoDouble(ACCOUNT_PROFIT);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);

    // Check TP and SL
    if (profit >= TakeProfitUSD)
    {
        CloseAllPositions();
        totalProfitSinceActive += profit;
        takeProfitHits++;
        Sleep(NextStartDelaySec * 1000);
        lastOrderTime = TimeCurrent();
        return;
    }

    if (profit <= -StopLossUSD)
    {
        CloseAllPositions();
        Print("Stopped out at loss.");
        return;
    }

    // Partial Close Logic
    if (profit >= PartialCloseUSD)
    {
        PartialClose();
    }

    // Entry Trigger
    if (totalOrders == 0 && TimeCurrent() - lastOrderTime > 3)
    {
        if (currentPrice > openPrice)
        {
            OpenPosition(ORDER_TYPE_BUY, InitialLot);
            totalBuyLots = InitialLot;
            SchedulePending(ORDER_TYPE_SELL_STOP, totalBuyLots * LotMultiplier);
        }
        else
        {
            OpenPosition(ORDER_TYPE_SELL, InitialLot);
            totalSellLots = InitialLot;
            SchedulePending(ORDER_TYPE_BUY_STOP, totalSellLots * LotMultiplier);
        }
        lastOrderTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Open Market Order                                                |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type, double lot)
{
    double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    trade.SetTypeFilling(ORDER_FILLING_IOC);
    trade.SetDeviationInPoints(20);
    trade.PositionOpen(_Symbol, type, lot, price, 0, 0, "");
}

//+------------------------------------------------------------------+
//| Schedule Pending Orders                                          |
//+------------------------------------------------------------------+
void SchedulePending(ENUM_ORDER_TYPE type, double lot)
{
    double price;
    if (type == ORDER_TYPE_BUY_STOP)
        price = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + DistancePO * _Point;
    else
        price = SymbolInfoDouble(_Symbol, SYMBOL_BID) - DistancePO * _Point;

    trade.SetTypeFilling(ORDER_FILLING_IOC);
    trade.SetDeviationInPoints(20);
    if (type == ORDER_TYPE_BUY_STOP)
       trade.BuyStop(lot, price, _Symbol, 0, 0, "Grid Layer");
   else if (type == ORDER_TYPE_SELL_STOP)
       trade.SellStop(lot, price, _Symbol, 0, 0, "Grid Layer");

}

//+------------------------------------------------------------------+
//| Close All Positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket))
        {
            trade.PositionClose(ticket);
        }
    }
    for (int j = OrdersTotal() - 1; j >= 0; j--)
    {
        ulong oticket = OrderGetTicket(j);
        if (OrderSelect(oticket))
        {
            trade.OrderDelete(oticket);
        }
    }
    totalBuyLots = 0;
    totalSellLots = 0;
}

//+------------------------------------------------------------------+
//| Partial Close Logic                                              |
//+------------------------------------------------------------------+
void PartialClose()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if (PositionGetTicket(i) > 0)
        {
            string sym = PositionGetString(POSITION_SYMBOL);
            double vol = PositionGetDouble(POSITION_VOLUME);
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            trade.PositionClosePartial(ticket, vol / 2.0);
        }
    }
}
