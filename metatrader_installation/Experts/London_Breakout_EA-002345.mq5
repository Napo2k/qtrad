//+------------------------------------------------------------------+
//|                                        London Breakout EA.mq5    |
//|                           Copyright 2025, Allan Munene Mutiiria. |
//|                                   https://t.me/Forex_Algo_Trader |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Allan Munene Mutiiria."
#property link      "https://t.me/Forex_Algo_Trader"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh> //--- Include Trade library for trading operations

//--- Enumerations
enum ENUM_TRADE_TYPE {     //--- Enumeration for trade types
   TRADE_ALL,              // All Trades (Buy and Sell)
   TRADE_BUY_ONLY,         // Buy Trades Only
   TRADE_SELL_ONLY         // Sell Trades Only
};

//--- Input parameters
sinput group "General EA Settings"
input double inpTradeLotsize = 0.01; // Lotsize
input ENUM_TRADE_TYPE TradeType = TRADE_ALL; // Trade Type Selection
input int MagicNumber = 002345;     // Magic Number
input double RRRatio = 1.0;        // Risk to Reward Ratio
input int StopLossPoints = 300;    // Stop loss in points
input int OrderOffsetPoints = 1;   // Points offset for Orders
input bool DeleteOppositeOrder = true; // Delete opposite order when one is activated?
input bool UseTrailing = false;    // Use Trailing Stop?
input int TrailingPoints = 50;     // Trailing Points (distance)
input int MinProfitPoints = 100;   // Minimum Profit Points to start trailing

sinput group "London Session Settings"
input int LondonStartHour = 9;        // London Start Hour
input int LondonStartMinute = 0;      // London Start Minute
input int LondonEndHour = 8;          // London End Hour
input int LondonEndMinute = 0;        // London End Minute
input int MinRangePoints = 150;       // Min Pre-London Range in points
input int MaxRangePoints = 500;       // Max Pre-London Range in points

sinput group "Risk Management"
input int MaxOpenTrades = 2;       // Maximum simultaneous open trades
input double MaxDailyDrawdownPercent = 5.0; // Max daily drawdown % to stop trading

//--- Structures
struct PositionInfo {      //--- Structure for position information
   ulong ticket;           // Position ticket
   double openPrice;      // Entry price
   double londonRange;    // Pre-London range in points for this position
   datetime sessionID;    // Session identifier (day)
   bool trailingActive;   // Trailing active flag
};

//--- Global variables
CTrade obj_Trade;                 //--- Trade object
double PreLondonHigh = 0.0;       //--- Pre-London session high
double PreLondonLow = 0.0;        //--- Pre-London session low
datetime PreLondonHighTime = 0;   //--- Time of Pre-London high
datetime PreLondonLowTime = 0;    //--- Time of Pre-London low
ulong buyOrderTicket = 0;         //--- Buy stop order ticket
ulong sellOrderTicket = 0;        //--- Sell stop order ticket
bool panelVisible = true;         //--- Panel visibility flag
double LondonRangePoints = 0.0;   //--- Current session's Pre-London range
PositionInfo positionList[];      //--- Array to store position info
datetime lastCheckedDay = 0;      //--- Last checked day
bool noTradeToday = false;        //--- Flag to prevent trading today
bool sessionChecksDone = false;   //--- Flag for session checks completion
datetime analysisTime = 0;        //--- Time for London analysis
double dailyDrawdown = 0.0;       //--- Current daily drawdown
bool isTrailing = false;          //--- Global flag for any trailing active
const int PreLondonStartHour = 3; //--- Fixed Pre-London Start Hour
const int PreLondonStartMinute = 0; //--- Fixed Pre-London Start Minute

//--- Panel Functions ---

//+------------------------------------------------------------------+
//| Create a rectangle label for the panel background                |
//+------------------------------------------------------------------+
bool createRecLabel(string objName, int xD, int yD, int xS, int yS,
                    color clrBg, int widthBorder, color clrBorder = clrNONE,
                    ENUM_BORDER_TYPE borderType = BORDER_FLAT, ENUM_LINE_STYLE borderStyle = STYLE_SOLID) {
    ResetLastError();              //--- Reset last error
    if (!ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) { //--- Create rectangle label
        Print(__FUNCTION__, ": failed to create rec label! Error code = ", _LastError); //--- Log creation failure
        return false;              //--- Return failure
    }
    ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, xD); //--- Set x-distance
    ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, yD); //--- Set y-distance
    ObjectSetInteger(0, objName, OBJPROP_XSIZE, xS); //--- Set x-size
    ObjectSetInteger(0, objName, OBJPROP_YSIZE, yS); //--- Set y-size
    ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER); //--- Set corner
    ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, clrBg); //--- Set background color
    ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, borderType); //--- Set border type
    ObjectSetInteger(0, objName, OBJPROP_STYLE, borderStyle); //--- Set border style
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, widthBorder); //--- Set border width
    ObjectSetInteger(0, objName, OBJPROP_COLOR, clrBorder); //--- Set border color
    ObjectSetInteger(0, objName, OBJPROP_BACK, false); //--- Set foreground
    ObjectSetInteger(0, objName, OBJPROP_STATE, false); //--- Set state
    ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false); //--- Disable selectable
    ObjectSetInteger(0, objName, OBJPROP_SELECTED, false); //--- Disable selected
    ChartRedraw(0);                //--- Redraw chart
    return true;                   //--- Return success
}

//+------------------------------------------------------------------+
//| Create a text label for panel elements                           |
//+------------------------------------------------------------------+
bool createLabel(string objName, int xD, int yD,
                 string txt, color clrTxt = clrBlack, int fontSize = 10,
                 string font = "Arial") {
    ResetLastError();              //--- Reset last error
    if (!ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0)) { //--- Create label
        Print(__FUNCTION__, ": failed to create the label! Error code = ", _LastError); //--- Log creation failure
        return false;              //--- Return failure
    }
    ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, xD); //--- Set x-distance
    ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, yD); //--- Set y-distance
    ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER); //--- Set corner
    ObjectSetString(0, objName, OBJPROP_TEXT, txt); //--- Set text
    ObjectSetInteger(0, objName, OBJPROP_COLOR, clrTxt); //--- Set color
    ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize); //--- Set font size
    ObjectSetString(0, objName, OBJPROP_FONT, font); //--- Set font
    ObjectSetInteger(0, objName, OBJPROP_BACK, false); //--- Set foreground
    ObjectSetInteger(0, objName, OBJPROP_STATE, false); //--- Set state
    ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false); //--- Disable selectable
    ObjectSetInteger(0, objName, OBJPROP_SELECTED, false); //--- Disable selected
    ChartRedraw(0);                //--- Redraw chart
    return true;                   //--- Return success
}

string panelPrefix = "LondonPanel_"; //--- Prefix for panel objects

//+------------------------------------------------------------------+
//| Create the information panel                                     |
//+------------------------------------------------------------------+
void CreatePanel() {
   createRecLabel(panelPrefix + "Background", 10, 10, 270, 200, clrMidnightBlue, 1, clrSilver); //--- Create background
   createLabel(panelPrefix + "Title", 20, 15, "London Breakout Control Center", clrGold, 12); //--- Create title
   createLabel(panelPrefix + "RangePoints", 20, 40, "Range (points): ", clrWhite, 10); //--- Create range label
   createLabel(panelPrefix + "HighPrice", 20, 60, "High Price: ", clrWhite); //--- Create high price label
   createLabel(panelPrefix + "LowPrice", 20, 80, "Low Price: ", clrWhite); //--- Create low price label
   createLabel(panelPrefix + "BuyLevel", 20, 100, "Buy Level: ", clrWhite); //--- Create buy level label
   createLabel(panelPrefix + "SellLevel", 20, 120, "Sell Level: ", clrWhite); //--- Create sell level label
   createLabel(panelPrefix + "AccountBalance", 20, 140, "Balance: ", clrWhite); //--- Create balance label
   createLabel(panelPrefix + "AccountEquity", 20, 160, "Equity: ", clrWhite); //--- Create equity label
   createLabel(panelPrefix + "CurrentDrawdown", 20, 180, "Drawdown (%): ", clrWhite); //--- Create drawdown label
   createRecLabel(panelPrefix + "Hide", 250, 10, 30, 22, clrCrimson, 1, clrNONE); //--- Create hide button
   createLabel(panelPrefix + "HideText", 258, 12, CharToString(251), clrWhite, 13, "Wingdings"); //--- Create hide text
   ObjectSetInteger(0, panelPrefix + "Hide", OBJPROP_SELECTABLE, true); //--- Make hide selectable
   ObjectSetInteger(0, panelPrefix + "Hide", OBJPROP_STATE, true); //--- Set hide state
}

//+------------------------------------------------------------------+
//| Update panel with current data                                   |
//+------------------------------------------------------------------+
void UpdatePanel() {
   string rangeText = "Range (points): " + (LondonRangePoints > 0 ? DoubleToString(LondonRangePoints, 0) : "Calculating..."); //--- Format range text
   ObjectSetString(0, panelPrefix + "RangePoints", OBJPROP_TEXT, rangeText); //--- Update range text
   
   string highText = "High Price: " + (LondonRangePoints > 0 ? DoubleToString(PreLondonHigh, _Digits) : "N/A"); //--- Format high text
   ObjectSetString(0, panelPrefix + "HighPrice", OBJPROP_TEXT, highText); //--- Update high text
   
   string lowText = "Low Price: " + (LondonRangePoints > 0 ? DoubleToString(PreLondonLow, _Digits) : "N/A"); //--- Format low text
   ObjectSetString(0, panelPrefix + "LowPrice", OBJPROP_TEXT, lowText); //--- Update low text
   
   string buyText = "Buy Level: " + (LondonRangePoints > 0 ? DoubleToString(PreLondonHigh + OrderOffsetPoints * _Point, _Digits) : "N/A"); //--- Format buy text
   ObjectSetString(0, panelPrefix + "BuyLevel", OBJPROP_TEXT, buyText); //--- Update buy text
   
   string sellText = "Sell Level: " + (LondonRangePoints > 0 ? DoubleToString(PreLondonLow - OrderOffsetPoints * _Point, _Digits) : "N/A"); //--- Format sell text
   ObjectSetString(0, panelPrefix + "SellLevel", OBJPROP_TEXT, sellText); //--- Update sell text
   
   string balanceText = "Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2); //--- Format balance text
   ObjectSetString(0, panelPrefix + "AccountBalance", OBJPROP_TEXT, balanceText); //--- Update balance text
   
   string equityText = "Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2); //--- Format equity text
   ObjectSetString(0, panelPrefix + "AccountEquity", OBJPROP_TEXT, equityText); //--- Update equity text
   
   string ddText = "Drawdown (%): " + DoubleToString(dailyDrawdown, 2); //--- Format drawdown text
   ObjectSetString(0, panelPrefix + "CurrentDrawdown", OBJPROP_TEXT, ddText); //--- Update drawdown text
   ObjectSetInteger(0, panelPrefix + "CurrentDrawdown", OBJPROP_COLOR, dailyDrawdown > MaxDailyDrawdownPercent / 2 ? clrYellow : clrWhite); //--- Set drawdown color
}

//--- Trading Functions ---

//+------------------------------------------------------------------+
//| Fixed lot size                                                   |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLossPrice) {
   return NormalizeDouble(inpTradeLotsize, 2); //--- Normalize lot size
}

//+------------------------------------------------------------------+
//| Calculate session range (high-low) in points                     |
//+------------------------------------------------------------------+
double GetRange(datetime startTime, datetime endTime, double &highVal, double &lowVal, datetime &highTime, datetime &lowTime) {
   int startBar = iBarShift(_Symbol, _Period, startTime, true); //--- Get start bar
   int endBar = iBarShift(_Symbol, _Period, endTime, true); //--- Get end bar
   if (startBar == -1 || endBar == -1 || startBar < endBar) return -1; //--- Invalid bars

   int highestBar = iHighest(_Symbol, _Period, MODE_HIGH, startBar - endBar + 1, endBar); //--- Get highest bar
   int lowestBar = iLowest(_Symbol, _Period, MODE_LOW, startBar - endBar + 1, endBar); //--- Get lowest bar
   highVal = iHigh(_Symbol, _Period, highestBar); //--- Set high value
   lowVal = iLow(_Symbol, _Period, lowestBar); //--- Set low value
   highTime = iTime(_Symbol, _Period, highestBar); //--- Set high time
   lowTime = iTime(_Symbol, _Period, lowestBar); //--- Set low time
   return (highVal - lowVal) / _Point; //--- Return range in points
}

//+------------------------------------------------------------------+
//| Add position to tracking list when opened                        |
//+------------------------------------------------------------------+
void AddPositionToList(ulong ticket, double openPrice, double londonRange, datetime sessionID) {
   if (londonRange <= 0) return;      //--- Exit if invalid range
   int index = ArraySize(positionList); //--- Get current size
   ArrayResize(positionList, index + 1); //--- Resize array
   positionList[index].ticket = ticket; //--- Set ticket
   positionList[index].openPrice = openPrice; //--- Set open price
   positionList[index].londonRange = londonRange; //--- Set range
   positionList[index].sessionID = sessionID; //--- Set session ID
   positionList[index].trailingActive = false; //--- Set trailing inactive
}

//+------------------------------------------------------------------+
//| Remove position from tracking list when closed                   |
//+------------------------------------------------------------------+
void RemovePositionFromList(ulong ticket) {
   for (int i = 0; i < ArraySize(positionList); i++) { //--- Iterate through list
      if (positionList[i].ticket == ticket) { //--- Match ticket
         for (int j = i; j < ArraySize(positionList) - 1; j++) { //--- Shift elements
            positionList[j] = positionList[j + 1]; //--- Copy next
         }
         ArrayResize(positionList, ArraySize(positionList) - 1); //--- Resize array
         break;                   //--- Exit loop
      }
   }
}

//+------------------------------------------------------------------+
//| Place pending buy/sell stop orders                               |
//+------------------------------------------------------------------+
void PlacePendingOrders(double preLondonHigh, double preLondonLow, datetime sessionID) {
   double buyPrice = preLondonHigh + OrderOffsetPoints * _Point; //--- Calculate buy price
   double sellPrice = preLondonLow - OrderOffsetPoints * _Point; //--- Calculate sell price
   double slPoints = StopLossPoints; //--- Set SL points
   double buySL = buyPrice - slPoints * _Point; //--- Calculate buy SL
   double sellSL = sellPrice + slPoints * _Point; //--- Calculate sell SL
   double tpPoints = slPoints * RRRatio; //--- Calculate TP points
   double buyTP = buyPrice + tpPoints * _Point; //--- Calculate buy TP
   double sellTP = sellPrice - tpPoints * _Point; //--- Calculate sell TP
   double lotSizeBuy = CalculateLotSize(buyPrice, buySL); //--- Calculate buy lot
   double lotSizeSell = CalculateLotSize(sellPrice, sellSL); //--- Calculate sell lot

   if (TradeType == TRADE_ALL || TradeType == TRADE_BUY_ONLY) { //--- Check buy trade
      obj_Trade.BuyStop(lotSizeBuy, buyPrice, _Symbol, buySL, buyTP, 0, 0, "Buy Stop - London"); //--- Place buy stop
      buyOrderTicket = obj_Trade.ResultOrder(); //--- Get buy ticket
   }

   if (TradeType == TRADE_ALL || TradeType == TRADE_SELL_ONLY) { //--- Check sell trade
      obj_Trade.SellStop(lotSizeSell, sellPrice, _Symbol, sellSL, sellTP, 0, 0, "Sell Stop - London"); //--- Place sell stop
      sellOrderTicket = obj_Trade.ResultOrder(); //--- Get sell ticket
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stops                                            |
//+------------------------------------------------------------------+
void ManagePositions() {
   if (PositionsTotal() == 0 || !UseTrailing) return; //--- Exit if no positions or no trailing
   isTrailing = false;                //--- Reset trailing flag

   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID); //--- Get bid
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK); //--- Get ask
   double point = _Point;             //--- Get point value

   for (int i = 0; i < ArraySize(positionList); i++) { //--- Iterate through positions
      ulong ticket = positionList[i].ticket; //--- Get ticket
      if (!PositionSelectByTicket(ticket)) { //--- Select position
         RemovePositionFromList(ticket); //--- Remove if not selected
         continue;                    //--- Skip
      }

      if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue; //--- Skip if not matching

      double openPrice = positionList[i].openPrice; //--- Get open price
      long positionType = PositionGetInteger(POSITION_TYPE); //--- Get type
      double currentPrice = (positionType == POSITION_TYPE_BUY) ? currentBid : currentAsk; //--- Get current price
      double profitPoints = (positionType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / point : (openPrice - currentPrice) / point; //--- Calculate profit points

      if (profitPoints >= MinProfitPoints + TrailingPoints) { //--- Check for trailing
         double newSL = 0.0;          //--- New SL variable
         if (positionType == POSITION_TYPE_BUY) { //--- Buy position
            newSL = currentPrice - TrailingPoints * point; //--- Calculate new SL
         } else {                     //--- Sell position
            newSL = currentPrice + TrailingPoints * point; //--- Calculate new SL
         }
         double currentSL = PositionGetDouble(POSITION_SL); //--- Get current SL
         if ((positionType == POSITION_TYPE_BUY && newSL > currentSL + point) || (positionType == POSITION_TYPE_SELL && newSL < currentSL - point)) { //--- Check move condition
            if (obj_Trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP))) { //--- Modify position
               positionList[i].trailingActive = true; //--- Set trailing active
               isTrailing = true;        //--- Set global trailing
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Delete opposite pending order when one is filled                 |
//+------------------------------------------------------------------+
void CheckAndDeleteOppositeOrder() {
   if (!DeleteOppositeOrder || TradeType != TRADE_ALL) return; //--- Exit if not applicable

   bool buyOrderExists = false;       //--- Buy exists flag
   bool sellOrderExists = false;      //--- Sell exists flag

   for (int i = OrdersTotal() - 1; i >= 0; i--) { //--- Iterate through orders
      ulong orderTicket = OrderGetTicket(i); //--- Get ticket
      if (OrderSelect(orderTicket)) { //--- Select order
         if (OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == MagicNumber) { //--- Check symbol and magic
            if (orderTicket == buyOrderTicket) buyOrderExists = true; //--- Set buy exists
            if (orderTicket == sellOrderTicket) sellOrderExists = true; //--- Set sell exists
         }
      }
   }

   if (!buyOrderExists && sellOrderExists && sellOrderTicket != 0) { //--- Check delete sell
      obj_Trade.OrderDelete(sellOrderTicket); //--- Delete sell order
   } else if (!sellOrderExists && buyOrderExists && buyOrderTicket != 0) { //--- Check delete buy
      obj_Trade.OrderDelete(buyOrderTicket); //--- Delete buy order
   }
}

//+------------------------------------------------------------------+
//| Draw session ranges on the chart                                 |
//+------------------------------------------------------------------+
void DrawSessionRanges(datetime preLondonStart, datetime londonEnd) {
   string sessionID = "Sess_" + IntegerToString(lastCheckedDay); //--- Session ID

   string preRectName = "PreRect_" + sessionID; //--- Rectangle name
   ObjectCreate(0, preRectName, OBJ_RECTANGLE, 0, PreLondonHighTime, PreLondonHigh, PreLondonLowTime, PreLondonLow); //--- Create rectangle
   ObjectSetInteger(0, preRectName, OBJPROP_COLOR, clrTeal); //--- Set color
   ObjectSetInteger(0, preRectName, OBJPROP_FILL, true); //--- Enable fill
   ObjectSetInteger(0, preRectName, OBJPROP_BACK, true); //--- Set background

   string preTopLineName = "PreTopLine_" + sessionID; //--- Top line name
   ObjectCreate(0, preTopLineName, OBJ_TREND, 0, preLondonStart, PreLondonHigh, londonEnd, PreLondonHigh); //--- Create top line
   ObjectSetInteger(0, preTopLineName, OBJPROP_COLOR, clrBlack); //--- Set color
   ObjectSetInteger(0, preTopLineName, OBJPROP_WIDTH, 1); //--- Set width
   ObjectSetInteger(0, preTopLineName, OBJPROP_RAY_RIGHT, false); //--- Disable ray
   ObjectSetInteger(0, preTopLineName, OBJPROP_BACK, true); //--- Set background

   string preBotLineName = "PreBottomLine_" + sessionID; //--- Bottom line name
   ObjectCreate(0, preBotLineName, OBJ_TREND, 0, preLondonStart, PreLondonLow, londonEnd, PreLondonLow); //--- Create bottom line
   ObjectSetInteger(0, preBotLineName, OBJPROP_COLOR, clrRed); //--- Set color
   ObjectSetInteger(0, preBotLineName, OBJPROP_WIDTH, 1); //--- Set width
   ObjectSetInteger(0, preBotLineName, OBJPROP_RAY_RIGHT, false); //--- Disable ray
   ObjectSetInteger(0, preBotLineName, OBJPROP_BACK, true); //--- Set background
}

//+------------------------------------------------------------------+
//| Check trading conditions and place orders                        |
//+------------------------------------------------------------------+
void CheckTradingConditions(datetime currentTime) {
   MqlDateTime timeStruct;            //--- Time structure
   TimeToStruct(currentTime, timeStruct); //--- Convert time
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", timeStruct.year, timeStruct.mon, timeStruct.day)); //--- Get today

   datetime preLondonStart = today + PreLondonStartHour * 3600 + PreLondonStartMinute * 60; //--- Pre-London start
   datetime londonStart = today + LondonStartHour * 3600 + LondonStartMinute * 60; //--- London start
   datetime londonEnd = today + LondonEndHour * 3600 + LondonEndMinute * 60; //--- London end
   analysisTime = londonStart;        //--- Set analysis time

   if (currentTime < analysisTime) return; //--- Exit if before analysis

   double preLondonRange = GetRange(preLondonStart, currentTime, PreLondonHigh, PreLondonLow, PreLondonHighTime, PreLondonLowTime); //--- Get range
   if (preLondonRange < MinRangePoints || preLondonRange > MaxRangePoints) { //--- Check range limits
      noTradeToday = true;            //--- Set no trade
      sessionChecksDone = true;       //--- Set checks done
      DrawSessionRanges(preLondonStart, londonEnd); //--- Draw ranges
      return;                         //--- Exit
   }

   LondonRangePoints = preLondonRange; //--- Set range points
   PlacePendingOrders(PreLondonHigh, PreLondonLow, today); //--- Place orders
   noTradeToday = true;               //--- Set no trade
   sessionChecksDone = true;          //--- Set checks done
   DrawSessionRanges(preLondonStart, londonEnd); //--- Draw ranges
}

//+------------------------------------------------------------------+
//| Check if it's a new trading day                                  |
//+------------------------------------------------------------------+
bool IsNewDay(datetime currentBarTime) {
   MqlDateTime barTime;               //--- Bar time structure
   TimeToStruct(currentBarTime, barTime); //--- Convert time
   datetime currentDay = StringToTime(StringFormat("%04d.%02d.%02d", barTime.year, barTime.mon, barTime.day)); //--- Get current day
   if (currentDay != lastCheckedDay) { //--- Check new day
      lastCheckedDay = currentDay;    //--- Update last day
      sessionChecksDone = false;      //--- Reset checks
      noTradeToday = false;           //--- Reset no trade
      buyOrderTicket = 0;             //--- Reset buy ticket
      sellOrderTicket = 0;            //--- Reset sell ticket
      LondonRangePoints = 0.0;        //--- Reset range
      return true;                    //--- Return new day
   }
   return false;                      //--- Return not new day
}

//+------------------------------------------------------------------+
//| Update daily drawdown                                            |
//+------------------------------------------------------------------+
void UpdateDailyDrawdown() {
   static double maxEquity = 0.0;     //--- Max equity tracker
   double equity = AccountInfoDouble(ACCOUNT_EQUITY); //--- Get equity
   if (equity > maxEquity) maxEquity = equity; //--- Update max equity
   dailyDrawdown = (maxEquity - equity) / maxEquity * 100; //--- Calculate drawdown
   if (dailyDrawdown >= MaxDailyDrawdownPercent) noTradeToday = true; //--- Set no trade if exceeded
}

//+------------------------------------------------------------------+
//| Initialize EA                                                    |
//+------------------------------------------------------------------+
int OnInit() {
   obj_Trade.SetExpertMagicNumber(MagicNumber); //--- Set magic number
   ArrayFree(positionList);           //--- Free position list
   CreatePanel();                     //--- Create panel
   panelVisible = true;               //--- Set panel visible
   return(INIT_SUCCEEDED);            //--- Return success
}

//+------------------------------------------------------------------+
//| Deinitialize EA                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "LondonPanel_"); //--- Delete panel objects
   ArrayFree(positionList);           //--- Free position list
}

//+------------------------------------------------------------------+
//| Main tick handler                                                |
//+------------------------------------------------------------------+
void OnTick() {
   datetime currentBarTime = iTime(_Symbol, _Period, 0); //--- Get current bar time
   IsNewDay(currentBarTime);          //--- Check new day
   
   UpdatePanel();                     //--- Update panel
   UpdateDailyDrawdown();             //--- Update drawdown

   if (!noTradeToday && !sessionChecksDone) { //--- Check trading conditions
      CheckTradingConditions(TimeCurrent()); //--- Check conditions
   }

   CheckAndDeleteOppositeOrder();     //--- Delete opposite order
   ManagePositions();                 //--- Manage positions

   // Add untracked positions
   for (int i = 0; i < PositionsTotal(); i++) { //--- Iterate through positions
      ulong ticket = PositionGetTicket(i); //--- Get ticket
      if (PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber) { //--- Check position
         bool tracked = false;        //--- Tracked flag
         for (int j = 0; j < ArraySize(positionList); j++) { //--- Check list
            if (positionList[j].ticket == ticket) tracked = true; //--- Set tracked
         }
         if (!tracked) {              //--- If not tracked
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN); //--- Get open price
            AddPositionToList(ticket, openPrice, LondonRangePoints, lastCheckedDay); //--- Add to list
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Handle chart events (e.g., panel close)                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if (id == CHARTEVENT_OBJECT_CLICK && sparam == panelPrefix + "Hide") { //--- Check hide click
      panelVisible = false;           //--- Set panel hidden
      ObjectsDeleteAll(0, "LondonPanel_"); //--- Delete panel objects
      ChartRedraw(0);                 //--- Redraw chart
   }
}

//+------------------------------------------------------------------+