//+------------------------------------------------------------------+
//|                                        Sabino_Hybrid_Strategy.mq5 |
//|                                    Sabino Figueroa Strategy EA |
//|                     Hybrid Strategy with Manual Execution Support |
//+------------------------------------------------------------------+
#property copyright "Sabino Figueroa Hybrid Strategy"
#property version   "1.00"
#property description "Low-risk hybrid strategy with automated risk management"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== RISK MANAGEMENT ==="
input double   RiskPercentage = 0.12;        // Risk per trade (0.10% to 0.15%)
input double   RiskRewardRatio = 1.0;        // Risk to Reward Ratio (1:1 for NASDAQ, 1:2 for BTC)
input bool     UseFixedLotSize = false;      // Use fixed lot size instead of risk-based
input double   FixedLotSize = 0.01;          // Fixed lot size if enabled

input group "=== TRADING PARAMETERS ==="
input string   TradingSymbol = "NAS100";     // Trading Symbol (NAS100, SPX500, BTCUSD)
input int      MagicNumber = 123456;         // Magic Number
input int      Slippage = 10;                // Slippage in points

input group "=== TIME FILTER ==="
input bool     UseTimeFilter = true;         // Enable time filter (4 PM - 6 PM)
input int      StartHour = 16;               // Start hour (4 PM)
input int      EndHour = 18;                 // End hour (6 PM)
input string   TimeZone = "EST";             // Time zone reference

input group "=== PIVOT POINTS ==="
input bool     UsePivotPoints = true;        // Use pivot points for SL placement
input ENUM_TIMEFRAMES PivotTimeframe = PERIOD_D1; // Timeframe for pivot calculation

input group "=== MANUAL EXECUTION ASSIST ==="
input bool     ShowTradePanel = true;        // Show manual trading panel
input bool     AutoCalculateSize = true;     // Auto-calculate position size
input bool     ShowRiskInfo = true;          // Show risk information on chart

input group "=== ALERTS ==="
input bool     SendAlerts = true;            // Send alerts for trade opportunities
input bool     SendEmails = false;           // Send email notifications
input bool     PlaySounds = true;            // Play sound alerts

//--- Global variables
CTrade trade;
double pivot_point, support1, support2, resistance1, resistance2;
double account_balance;
double risk_amount;
double calculated_lot_size;
bool trade_executed_today = false;
datetime last_trade_date = 0;

//--- Panel variables
int panel_x = 20, panel_y = 50;
int panel_width = 250, panel_height = 200;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Set trading parameters
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage);
    trade.SetTypeFilling(ORDER_FILLING_RETURN);
    
    //--- Initialize variables
    account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    risk_amount = account_balance * (RiskPercentage / 100.0);
    
    //--- Calculate daily pivots
    CalculatePivotPoints();
    
    //--- Create trading panel if enabled
    if(ShowTradePanel)
        CreateTradingPanel();
    
    //--- Print initialization info
    Print("Sabino Hybrid Strategy EA initialized");
    Print("Account Balance: $", DoubleToString(account_balance, 2));
    Print("Risk Amount: $", DoubleToString(risk_amount, 2));
    Print("Trading Symbol: ", TradingSymbol);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Remove all objects created by EA
    ObjectsDeleteAll(0, "SabinoPanel_");
    ObjectsDeleteAll(0, "SabinoPivot_");
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
      MqlDateTime new_day = {};
      TimeToStruct(TimeCurrent(), new_day);
      MqlDateTime old_day = {};
      TimeToStruct(last_trade_date, old_day);
    //--- Check if it's a new day
    if(new_day.day != old_day.day)
    {
        trade_executed_today = false;
        CalculatePivotPoints();
        DrawPivotLevels();
    }
    
    //--- Update risk calculations
    UpdateRiskCalculations();
    
    //--- Update trading panel
    if(ShowTradePanel)
        UpdateTradingPanel();
    
    //--- Check for trading opportunities (manual signal confirmation)
    CheckTradingOpportunity();
}

//+------------------------------------------------------------------+
//| Calculate pivot points for stop loss placement                  |
//+------------------------------------------------------------------+
void CalculatePivotPoints()
{
    //--- Get yesterday's OHLC data
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyHigh(TradingSymbol, PivotTimeframe, 1, 1, high) != 1 ||
       CopyLow(TradingSymbol, PivotTimeframe, 1, 1, low) != 1 ||
       CopyClose(TradingSymbol, PivotTimeframe, 1, 1, close) != 1)
        return;
    
    //--- Calculate pivot points
    pivot_point = (high[0] + low[0] + close[0]) / 3.0;
    support1 = 2 * pivot_point - high[0];
    support2 = pivot_point - (high[0] - low[0]);
    resistance1 = 2 * pivot_point - low[0];
    resistance2 = pivot_point + (high[0] - low[0]);
    
    Print("Pivot Point: ", DoubleToString(pivot_point, _Digits));
    Print("Support 1: ", DoubleToString(support1, _Digits));
    Print("Resistance 1: ", DoubleToString(resistance1, _Digits));
}

//+------------------------------------------------------------------+
//| Draw pivot levels on chart                                      |
//+------------------------------------------------------------------+
void DrawPivotLevels()
{
    if(!UsePivotPoints) return;
    
    //--- Remove existing pivot lines
    ObjectsDeleteAll(0, "SabinoPivot_");
    
    //--- Draw pivot point
    CreateHorizontalLine("SabinoPivot_PP", pivot_point, clrYellow, STYLE_SOLID, 2);
    
    //--- Draw support levels
    CreateHorizontalLine("SabinoPivot_S1", support1, clrRed, STYLE_DASH, 1);
    CreateHorizontalLine("SabinoPivot_S2", support2, clrRed, STYLE_DOT, 1);
    
    //--- Draw resistance levels
    CreateHorizontalLine("SabinoPivot_R1", resistance1, clrLime, STYLE_DASH, 1);
    CreateHorizontalLine("SabinoPivot_R2", resistance2, clrLime, STYLE_DOT, 1);
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create horizontal line                                           |
//+------------------------------------------------------------------+
void CreateHorizontalLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width)
{
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetString(0, name, OBJPROP_TEXT, name);
}

//+------------------------------------------------------------------+
//| Update risk calculations                                         |
//+------------------------------------------------------------------+
void UpdateRiskCalculations()
{
    account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    risk_amount = account_balance * (RiskPercentage / 100.0);
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                           |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entry_price, double stop_loss)
{
    if(UseFixedLotSize)
        return FixedLotSize;
    
    double price_difference = MathAbs(entry_price - stop_loss);
    if(price_difference == 0) return 0.01;
    
    double tick_value = SymbolInfoDouble(TradingSymbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(TradingSymbol, SYMBOL_TRADE_TICK_SIZE);
    double point_value = tick_value * (Point() / tick_size);
    
    double lot_size = risk_amount / ((price_difference / Point()) * point_value);
    
    //--- Normalize lot size
    double min_lot = SymbolInfoDouble(TradingSymbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(TradingSymbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(TradingSymbol, SYMBOL_VOLUME_STEP);
    
    lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
    lot_size = MathFloor(lot_size / lot_step) * lot_step;
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Check for trading opportunity                                   |
//+------------------------------------------------------------------+
void CheckTradingOpportunity()
{
    //--- Check if already traded today
    if(trade_executed_today) return;
    
    //--- Check time filter
    if(UseTimeFilter && !IsWithinTradingHours()) return;
    
    //--- This is where you would integrate with NinjaTrader signals
    //--- For now, we'll provide manual execution assistance
    
    //--- Check for existing positions
    if(PositionSelect(TradingSymbol))
        return; // Already in position
    
    //--- Update calculated lot size for current market conditions
    double current_price = SymbolInfoDouble(TradingSymbol, SYMBOL_BID);
    double suggested_sl_buy = UsePivotPoints ? support1 : current_price - 100 * Point();
    double suggested_sl_sell = UsePivotPoints ? resistance1 : current_price + 100 * Point();
    
    calculated_lot_size = CalculatePositionSize(current_price, suggested_sl_buy);
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                   |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime time_struct;
    TimeToStruct(TimeCurrent(), time_struct);
    
    int current_hour = time_struct.hour;
    
    // Assuming broker time, adjust if needed
    return (current_hour >= StartHour && current_hour <= EndHour);
}

//+------------------------------------------------------------------+
//| Manual Buy Function                                             |
//+------------------------------------------------------------------+
bool ExecuteManualBuy()
{
    if(trade_executed_today) return false;
    
    double ask_price = SymbolInfoDouble(TradingSymbol, SYMBOL_ASK);
    double stop_loss = UsePivotPoints ? support1 : ask_price - 100 * Point();
    double take_profit = ask_price + (ask_price - stop_loss) * RiskRewardRatio;
    
    double lot_size = CalculatePositionSize(ask_price, stop_loss);
    
    if(trade.Buy(lot_size, TradingSymbol, ask_price, stop_loss, take_profit, "Sabino Manual Buy"))
    {
        trade_executed_today = true;
        last_trade_date = TimeCurrent();
        
        if(SendAlerts)
            Alert("Buy trade executed: ", TradingSymbol, " Lot: ", DoubleToString(lot_size, 2));
        
        if(PlaySounds)
            PlaySound("trade.wav");
            
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Manual Sell Function                                            |
//+------------------------------------------------------------------+
bool ExecuteManualSell()
{
    if(trade_executed_today) return false;
    
    double bid_price = SymbolInfoDouble(TradingSymbol, SYMBOL_BID);
    double stop_loss = UsePivotPoints ? resistance1 : bid_price + 100 * Point();
    double take_profit = bid_price - (stop_loss - bid_price) * RiskRewardRatio;
    
    double lot_size = CalculatePositionSize(bid_price, stop_loss);
    
    if(trade.Sell(lot_size, TradingSymbol, bid_price, stop_loss, take_profit, "Sabino Manual Sell"))
    {
        trade_executed_today = true;
        last_trade_date = TimeCurrent();
        
        if(SendAlerts)
            Alert("Sell trade executed: ", TradingSymbol, " Lot: ", DoubleToString(lot_size, 2));
        
        if(PlaySounds)
            PlaySound("trade.wav");
            
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Create Trading Panel                                            |
//+------------------------------------------------------------------+
void CreateTradingPanel()
{
    //--- Main panel background
    ObjectCreate(0, "SabinoPanel_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "SabinoPanel_BG", OBJPROP_XDISTANCE, panel_x);
    ObjectSetInteger(0, "SabinoPanel_BG", OBJPROP_YDISTANCE, panel_y);
    ObjectSetInteger(0, "SabinoPanel_BG", OBJPROP_XSIZE, panel_width);
    ObjectSetInteger(0, "SabinoPanel_BG", OBJPROP_YSIZE, panel_height);
    ObjectSetInteger(0, "SabinoPanel_BG", OBJPROP_BGCOLOR, clrDarkSlateGray);
    ObjectSetInteger(0, "SabinoPanel_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "SabinoPanel_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    
    //--- Title
    ObjectCreate(0, "SabinoPanel_Title", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "SabinoPanel_Title", OBJPROP_XDISTANCE, panel_x + 10);
    ObjectSetInteger(0, "SabinoPanel_Title", OBJPROP_YDISTANCE, panel_y + 10);
    ObjectSetString(0, "SabinoPanel_Title", OBJPROP_TEXT, "Sabino Hybrid Strategy");
    ObjectSetInteger(0, "SabinoPanel_Title", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, "SabinoPanel_Title", OBJPROP_FONTSIZE, 10);
    
    //--- Buy Button
    ObjectCreate(0, "SabinoPanel_BuyBtn", OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, "SabinoPanel_BuyBtn", OBJPROP_XDISTANCE, panel_x + 10);
    ObjectSetInteger(0, "SabinoPanel_BuyBtn", OBJPROP_YDISTANCE, panel_y + 40);
    ObjectSetInteger(0, "SabinoPanel_BuyBtn", OBJPROP_XSIZE, 100);
    ObjectSetInteger(0, "SabinoPanel_BuyBtn", OBJPROP_YSIZE, 25);
    ObjectSetString(0, "SabinoPanel_BuyBtn", OBJPROP_TEXT, "Manual BUY");
    ObjectSetInteger(0, "SabinoPanel_BuyBtn", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, "SabinoPanel_BuyBtn", OBJPROP_BGCOLOR, clrGreen);
    
    //--- Sell Button
    ObjectCreate(0, "SabinoPanel_SellBtn", OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, "SabinoPanel_SellBtn", OBJPROP_XDISTANCE, panel_x + 130);
    ObjectSetInteger(0, "SabinoPanel_SellBtn", OBJPROP_YDISTANCE, panel_y + 40);
    ObjectSetInteger(0, "SabinoPanel_SellBtn", OBJPROP_XSIZE, 100);
    ObjectSetInteger(0, "SabinoPanel_SellBtn", OBJPROP_YSIZE, 25);
    ObjectSetString(0, "SabinoPanel_SellBtn", OBJPROP_TEXT, "Manual SELL");
    ObjectSetInteger(0, "SabinoPanel_SellBtn", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, "SabinoPanel_SellBtn", OBJPROP_BGCOLOR, clrRed);
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Trading Panel                                            |
//+------------------------------------------------------------------+
void UpdateTradingPanel()
{
    if(!ShowTradePanel) return;
    
    //--- Risk info
    string risk_text = "Risk: $" + DoubleToString(risk_amount, 2) + " (" + DoubleToString(RiskPercentage, 2) + "%)";
    
    if(ObjectFind(0, "SabinoPanel_RiskInfo") < 0)
    {
        ObjectCreate(0, "SabinoPanel_RiskInfo", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "SabinoPanel_RiskInfo", OBJPROP_XDISTANCE, panel_x + 10);
        ObjectSetInteger(0, "SabinoPanel_RiskInfo", OBJPROP_YDISTANCE, panel_y + 75);
        ObjectSetInteger(0, "SabinoPanel_RiskInfo", OBJPROP_COLOR, clrYellow);
        ObjectSetInteger(0, "SabinoPanel_RiskInfo", OBJPROP_FONTSIZE, 8);
    }
    ObjectSetString(0, "SabinoPanel_RiskInfo", OBJPROP_TEXT, risk_text);
    
    //--- Position size info
    string size_text = "Calc. Size: " + DoubleToString(calculated_lot_size, 2);
    
    if(ObjectFind(0, "SabinoPanel_SizeInfo") < 0)
    {
        ObjectCreate(0, "SabinoPanel_SizeInfo", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "SabinoPanel_SizeInfo", OBJPROP_XDISTANCE, panel_x + 10);
        ObjectSetInteger(0, "SabinoPanel_SizeInfo", OBJPROP_YDISTANCE, panel_y + 95);
        ObjectSetInteger(0, "SabinoPanel_SizeInfo", OBJPROP_COLOR, clrAqua);
        ObjectSetInteger(0, "SabinoPanel_SizeInfo", OBJPROP_FONTSIZE, 8);
    }
    ObjectSetString(0, "SabinoPanel_SizeInfo", OBJPROP_TEXT, size_text);
    
    //--- Trading status
    string status_text = trade_executed_today ? "Trade Done Today" : "Ready to Trade";
    color status_color = trade_executed_today ? clrRed : clrLime;
    
    if(ObjectFind(0, "SabinoPanel_Status") < 0)
    {
        ObjectCreate(0, "SabinoPanel_Status", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "SabinoPanel_Status", OBJPROP_XDISTANCE, panel_x + 10);
        ObjectSetInteger(0, "SabinoPanel_Status", OBJPROP_YDISTANCE, panel_y + 115);
        ObjectSetInteger(0, "SabinoPanel_Status", OBJPROP_FONTSIZE, 8);
    }
    ObjectSetString(0, "SabinoPanel_Status", OBJPROP_TEXT, status_text);
    ObjectSetInteger(0, "SabinoPanel_Status", OBJPROP_COLOR, status_color);
}

//+------------------------------------------------------------------+
//| Chart event function                                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(sparam == "SabinoPanel_BuyBtn")
        {
            ExecuteManualBuy();
            ObjectSetInteger(0, "SabinoPanel_BuyBtn", OBJPROP_STATE, false);
        }
        else if(sparam == "SabinoPanel_SellBtn")
        {
            ExecuteManualSell();
            ObjectSetInteger(0, "SabinoPanel_SellBtn", OBJPROP_STATE, false);
        }
        ChartRedraw();
    }
}

//+------------------------------------------------------------------+