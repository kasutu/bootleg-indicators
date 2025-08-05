//+------------------------------------------------------------------+
//|                           ORBPlusVolumeConfirmation-kasutufx.mq5 |
//|                                                         kasutufx |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "kasutufx"
#property link "https://www.mql5.com"
#property version "1.00"

// Stop Loss calculation methods
enum ENUM_SL_METHOD
{
  SL_ORB_HALF_RANGE // Half ORB range with pip tolerance
};

//--- input parameters
input double min_lot_size = 0.01;
input int magic_number = 12345;
input double volume_multiplier = 1.5;
input ENUM_SL_METHOD sl_method = SL_ORB_HALF_RANGE; // Stop Loss calculation method
input double sl_tolerance_price = 0.0003;           // Additional price tolerance for SL (in price units)

//--- global variables
double orb_high = 0;
double orb_low = 0;
bool orb_calculated = false;
bool trading_window_active = false;
bool breakout_triggered = false; // Prevent multiple trades on same breakout
double current_bar_close = 0.0;  // Track current completed bar close for breakout confirmation
datetime last_reset_time = 0;
datetime last_bar_time = 0; // Track last processed bar time

input double breakout_buffer_price = 0.0002; // Buffer price beyond ORB level for execution

// TP levels variables
double tp3_bull = 0;
double tp3_bear = 0;
bool position_active = false;
bool is_long_position = false;

// TP progression tracking
bool tp3_reached = false;
bool breakeven_applied = false; // Track if SL has been moved to break even
ulong current_position_ticket = 0;
double entry_price = 0.0;
double position_volume = 0.0;

// Line objects for visualization
string orb_high_line = "ORB_High";
string orb_low_line = "ORB_Low";
string tp3_bull_line = "TP3_Bull";
string tp3_bear_line = "TP3_Bear";
string session_start_line = "Session_Start";
string session_end_line = "Session_End";

//+------------------------------------------------------------------+
//| Get NY time with proper timezone handling                        |
//+------------------------------------------------------------------+
datetime GetNYTime()
{
  // Get GMT time first
  datetime gmt_time = TimeGMT();

  // NY is UTC-5 (EST) or UTC-4 (EDT during daylight saving time)
  // For simplicity, using EST offset (UTC-5).
  // In production, implement proper DST logic based on dates
  datetime ny_time = gmt_time - 5 * 3600; // EST: GMT - 5 hours

  return ny_time;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  Print("ORB Strategy EA Initialized");
  return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  DeleteChartObjects();
  Print("ORB EA Removed");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
  // Candle close detection - only process on new candle formation
  static datetime lastTime = 0;
  bool new_candle = false;

  if (iTime(Symbol(), PERIOD_M5, 0) != lastTime)
  {
    lastTime = iTime(Symbol(), PERIOD_M5, 0);
    new_candle = true;

    // Get the close price of the last completed candle
    double currentClosePrice = iClose(Symbol(), PERIOD_M5, 1);
    current_bar_close = currentClosePrice;

    Print("New M5 candle: ", currentClosePrice);
  }

  // Get NY time
  datetime ny_time = GetNYTime();
  MqlDateTime ny_struct;
  TimeToStruct(ny_time, ny_struct);

  int ny_hour = ny_struct.hour;
  int ny_min = ny_struct.min;

  // Reset daily variables after market close (5:00 PM NY) - only once per day
  if (ny_hour == 17 && ny_min == 0)
  {
    datetime current_date = (ny_time / 86400) * 86400; // Get date component only

    if (last_reset_time != current_date)
    {
      ResetDailyVariables();
      last_reset_time = current_date;
    }
  }

  // Also reset variables at start of new trading day (5:00 AM NY) if not already reset
  if (ny_hour == 5 && ny_min == 0)
  {
    datetime current_date = (ny_time / 86400) * 86400; // Get date component only

    if (last_reset_time != current_date)
    {
      ResetDailyVariables();
      last_reset_time = current_date;
      Print("Daily reset at session start");
    }
  }

  // Calculate ORB at 5:15 AM NY (15-minute range completion)
  if (ny_hour == 5 && ny_min == 15 && !orb_calculated)
  {
    CalculateORB();
  }

  // Draw session start line at 5:00 AM NY (only once per day)
  if (ny_hour == 5 && ny_min == 0)
  {
    DrawSessionStartLine();
  }

  // Draw session end line at 5:00 PM NY (only once per day)
  if (ny_hour == 17 && ny_min == 0)
  {
    DrawSessionEndLine();
  }

  // Reset session flags for next day
  if (ny_hour == 17 && ny_min == 0)
  {
    ObjectDelete(0, session_start_line);
    ObjectDelete(0, session_end_line);
  }

  // Trading window: 15 minutes after session start (5:20 AM NY)
  trading_window_active = (ny_hour == 5 && ny_min >= 20) || (ny_hour > 5 && ny_hour < 9);

  // Check for breakout during trading window - on candle close
  if (trading_window_active && orb_calculated && !position_active && new_candle)
  {
    CheckCandleCloseBreakout(); // Check for breakout on candle close
  }
  else if (trading_window_active && orb_calculated && position_active)
  {
    // EA is monitoring existing position
  }
  else if (trading_window_active && !orb_calculated)
  {
    // Uncomment for debugging: Print("Trading window active but ORB not calculated yet");
  }

  // Check for TP progression if position is active
  if (position_active)
  {
    CheckTP3();
    CheckPositionStatus(); // Check if position was closed by SL or other reasons
  }

  // Close positions at 5:00 PM NY (market close)
  if (ny_hour == 17 && ny_min == 0)
  {
    CloseAllPositions();
  }
}

//+------------------------------------------------------------------+
//| Reset daily variables                                            |
//+------------------------------------------------------------------+
void ResetDailyVariables()
{
  DeleteChartObjects();

  orb_calculated = trading_window_active = tp3_reached = position_active = is_long_position = breakout_triggered = breakeven_applied = false;
  current_position_ticket = 0;
  orb_high = orb_low = tp3_bull = tp3_bear = entry_price = position_volume = current_bar_close = 0.0;
  last_bar_time = 0;

  Print("Daily reset at market close");
}

//+------------------------------------------------------------------+
//| Calculate Opening Range Breakout                                 |
//+------------------------------------------------------------------+
void CalculateORB()
{
  // Get current GMT time and calculate NY time
  datetime gmt_time = TimeGMT();
  datetime ny_time = GetNYTime();

  MqlDateTime ny_struct;
  TimeToStruct(ny_time, ny_struct);

  // Calculate 5:00 AM NY time for today
  ny_struct.hour = 5;
  ny_struct.min = 0;
  ny_struct.sec = 0;
  datetime ny_session_start = StructToTime(ny_struct);

  // Calculate 5:20 AM NY time for today
  ny_struct.min = 20;
  datetime ny_session_end = StructToTime(ny_struct);

  // Convert NY times to GMT for data retrieval
  datetime gmt_session_start = ny_session_start + 5 * 3600; // Add 5 hours to get GMT
  datetime gmt_session_end = ny_session_end + 5 * 3600;     // Add 5 hours to get GMT

  Print("Calculating ORB for NY time: ", TimeToString(ny_session_start, TIME_DATE | TIME_MINUTES), " to ", TimeToString(ny_session_end, TIME_DATE | TIME_MINUTES));
  Print("GMT equivalent: ", TimeToString(gmt_session_start, TIME_DATE | TIME_MINUTES), " to ", TimeToString(gmt_session_end, TIME_DATE | TIME_MINUTES));

  // Get bars from the specific 20-minute ORB period using GMT times
  int bars = Bars(Symbol(), PERIOD_M5, gmt_session_start, gmt_session_end);
  if (bars < 4) // Need at least 4 bars for 20-minute range on M5
  {
    Print("Not enough bars for ORB calculation: ", bars, " bars found");
    return;
  }

  double high_prices[];
  double low_prices[];
  long volumes[];

  ArrayResize(high_prices, bars);
  ArrayResize(low_prices, bars);
  ArrayResize(volumes, bars);

  if (CopyHigh(Symbol(), PERIOD_M5, gmt_session_start, bars, high_prices) <= 0 ||
      CopyLow(Symbol(), PERIOD_M5, gmt_session_start, bars, low_prices) <= 0 ||
      CopyTickVolume(Symbol(), PERIOD_M5, gmt_session_start, bars, volumes) <= 0)
  {
    Print("Error copying price/volume data for ORB period");
    return;
  }

  orb_high = high_prices[ArrayMaximum(high_prices)];
  orb_low = low_prices[ArrayMinimum(low_prices)];

  orb_calculated = true;

  // Calculate TP3 level only (6x ORB range)
  double orb_range = orb_high - orb_low;
  tp3_bull = orb_high + orb_range * 6;
  tp3_bear = orb_low - orb_range * 6;

  Print("ORB: ", orb_high, " - ", orb_low, " | TP3: ", tp3_bull, " / ", tp3_bear);

  // Draw only the ORB lines initially
  DrawORBLines();
}

//+------------------------------------------------------------------+
//| Helper function to create horizontal line on chart              |
//+------------------------------------------------------------------+
void CreateHorizontalLine(string name, double price, color line_color, int style, string text)
{
  ObjectDelete(0, name);
  ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
  ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
  ObjectSetInteger(0, name, OBJPROP_STYLE, style);
  ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
  ObjectSetString(0, name, OBJPROP_TEXT, text + DoubleToString(price, 5));
}

//+------------------------------------------------------------------+
//| Helper function to create vertical line on chart                |
//+------------------------------------------------------------------+
void CreateVerticalLine(string name, color line_color, int style, string text)
{
  ObjectDelete(0, name);
  ObjectCreate(0, name, OBJ_VLINE, 0, TimeCurrent(), 0);
  ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
  ObjectSetInteger(0, name, OBJPROP_STYLE, style);
  ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
  ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Helper function to delete chart objects                         |
//+------------------------------------------------------------------+
void DeleteChartObjects()
{
  string objects[] = {orb_high_line, orb_low_line, tp3_bull_line, tp3_bear_line, session_start_line, session_end_line};
  for (int i = 0; i < ArraySize(objects); i++)
  {
    ObjectDelete(0, objects[i]);
  }
}

//+------------------------------------------------------------------+
//| Draw only ORB lines on chart                                     |
//+------------------------------------------------------------------+
void DrawORBLines()
{
  CreateHorizontalLine(orb_high_line, orb_high, clrRed, STYLE_SOLID, "ORB High: ");
  CreateHorizontalLine(orb_low_line, orb_low, clrRed, STYLE_SOLID, "ORB Low: ");
  Print("ORB lines drawn");
}

//+------------------------------------------------------------------+
//| Draw session start vertical line at 5:00 AM NY                  |
//+------------------------------------------------------------------+
void DrawSessionStartLine()
{
  // delete the old session start line if it exists
  ObjectDelete(0, session_start_line);

  // Create a new session start line
  CreateVerticalLine(session_start_line, clrBlue, STYLE_SOLID, "ORB Session Start (5:00 AM NY)");
  Print("Session start line drawn");
}

//+------------------------------------------------------------------+
//| Draw session end vertical line at 5:00 PM NY                    |
//+------------------------------------------------------------------+
void DrawSessionEndLine()
{
  CreateVerticalLine(session_end_line, clrBlue, STYLE_DASH, "Session End (5:00 PM NY)");
  Print("Session end line drawn");
}

//+------------------------------------------------------------------+
//| Draw TP3 line for position direction                             |
//+------------------------------------------------------------------+
void DrawTP3LineForPosition(bool is_long)
{
  string line_name = is_long ? tp3_bull_line : tp3_bear_line;
  double price_level = is_long ? tp3_bull : tp3_bear;
  color line_color = is_long ? clrLime : clrOrange;
  string label_prefix = is_long ? "Bull TP3: " : "Bear TP3: ";
  string direction = is_long ? "Bullish" : "Bearish";

  Print(direction, " TP3 line drawn");
}

//+------------------------------------------------------------------+
//| Remove TP3 line from chart                                       |
//+------------------------------------------------------------------+
void RemoveTP3Line()
{
  ObjectDelete(0, tp3_bull_line);
  ObjectDelete(0, tp3_bear_line);
  Print("TP3 line removed");
}

//+------------------------------------------------------------------+
//| Calculate simple stop loss at midpoint between ORB high and low |
//+------------------------------------------------------------------+
double CalculateSimpleSL(bool is_long, double entry_price_param)
{
  double sl = 0;

  // Calculate the exact midpoint price between ORB high and low
  double midpoint_price = (orb_high + orb_low) / 2.0;

  // Add price tolerance directly
  double tolerance = sl_tolerance_price;

  switch (sl_method)
  {
  case SL_ORB_HALF_RANGE:
  {
    if (is_long)
    {
      // For longs: SL at midpoint minus tolerance
      sl = midpoint_price - tolerance;
    }
    else
    {
      // For shorts: SL at midpoint plus tolerance
      sl = midpoint_price + tolerance;
    }
  }
  break;

  default:
    // Fallback to same logic
    sl = is_long ? midpoint_price - tolerance : midpoint_price + tolerance;
    break;
  }

  return sl;
}

//+------------------------------------------------------------------+
//| Helper function to handle breakout trade execution              |
//+------------------------------------------------------------------+
void ExecuteBreakoutTrade(bool is_bullish, double current_price, double level)
{
  string direction = is_bullish ? "BULLISH" : "BEARISH";
  string level_name = is_bullish ? "ORB High" : "ORB Low";

  Print(direction, " breakout at ", current_price);

  if (is_bullish)
    OpenLongPosition();
  else
    OpenShortPosition();
}

//+------------------------------------------------------------------+
//| Calculate current 20-period volume SMA                          |
//+------------------------------------------------------------------+
double CalculateCurrentVolumeAverage()
{
  // Calculate average volume like Pine Script: ta.sma(volume, 20)
  // Get the last 20 completed bars for SMA calculation - on M5 timeframe
  long avg_volumes[];
  int avg_bars = 20;
  ArrayResize(avg_volumes, avg_bars);

  // Get exactly 20 completed bars starting from bar 1 (most recent completed bar)
  int copied = CopyTickVolume(Symbol(), PERIOD_M5, 1, avg_bars, avg_volumes);

  if (copied != avg_bars)
  {
    Print("Warning: Only copied ", copied, " bars instead of ", avg_bars, " for volume SMA");
    if (copied <= 0)
    {
      Print("Error copying volume data for SMA calculation");
      return 0.0;
    }
    // Adjust avg_bars to actual copied bars
    avg_bars = copied;
  }

  // Calculate simple moving average of the 20 bars
  long total_volume = 0;
  for (int i = 0; i < avg_bars; i++)
  {
    total_volume += avg_volumes[i];
  }

  double current_avg_volume = (double)total_volume / (double)avg_bars;

  // Debug output every 20th calculation to monitor the rolling average
  static int debug_counter = 0;
  debug_counter++;
  if (debug_counter % 20 == 0)
  {
    Print("Volume SMA: ", (long)current_avg_volume);
  }

  return current_avg_volume;
}

//+------------------------------------------------------------------+
//| Check for breakout based on candle close prices                 |
//+------------------------------------------------------------------+
void CheckCandleCloseBreakout()
{
  // Don't proceed if breakout already triggered
  if (breakout_triggered)
    return;

  // Use the close price of the last completed candle
  double candle_close = current_bar_close;

  // Calculate buffer levels (direct price buffer beyond ORB levels)
  double buffer = breakout_buffer_price;

  double bull_trigger_level = orb_high + buffer;
  double bear_trigger_level = orb_low - buffer;

  // Check for candle close breakout above ORB High + buffer
  if (candle_close > bull_trigger_level)
  {
    Print("BULL breakout: ", candle_close, " > ", bull_trigger_level);

    // Check volume and execute if confirmed
    CheckVolumeAndExecute(true, candle_close);
  }
  // Check for candle close breakout below ORB Low - buffer
  else if (candle_close < bear_trigger_level)
  {
    Print("BEAR breakout: ", candle_close, " < ", bear_trigger_level);

    // Check volume and execute if confirmed
    CheckVolumeAndExecute(false, candle_close);
  }
}

//+------------------------------------------------------------------+
//| Check for real-time breakout and execute immediately            |
//+------------------------------------------------------------------+
void CheckRealtimeBreakout()
{
  // Don't proceed if breakout already triggered
  if (breakout_triggered)
    return;

  // Get current prices
  double current_bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
  double current_ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

  // Calculate buffer levels (direct price buffer beyond ORB levels)
  double buffer = breakout_buffer_price;

  double bull_trigger_level = orb_high + buffer;
  double bear_trigger_level = orb_low - buffer;

  // Check for real-time breakout above ORB High + buffer
  if (current_bid > bull_trigger_level)
  {
    datetime ny_time = GetNYTime();
    Print("BULLISH BREAKOUT detected (NY: ", TimeToString(ny_time, TIME_DATE | TIME_MINUTES), "): Price ", current_bid, " broke above trigger level: ", bull_trigger_level);

    // Check volume and execute if confirmed
    CheckVolumeAndExecute(true, current_bid);
  }
  // Check for real-time breakout below ORB Low - buffer
  else if (current_ask < bear_trigger_level)
  {
    datetime ny_time = GetNYTime();
    Print("BEARISH BREAKOUT detected (NY: ", TimeToString(ny_time, TIME_DATE | TIME_MINUTES), "): Price ", current_ask, " broke below trigger level: ", bear_trigger_level);

    // Check volume and execute if confirmed
    CheckVolumeAndExecute(false, current_ask);
  }
}

//+------------------------------------------------------------------+
//| Check volume and execute trade immediately                      |
//+------------------------------------------------------------------+
void CheckVolumeAndExecute(bool is_long_trade, double trigger_price)
{
  // Get the most recent completed M5 bar for volume confirmation
  long volumes[];
  datetime times[];
  ArrayResize(volumes, 1);
  ArrayResize(times, 1);

  // Get the last completed bar for volume confirmation
  if (CopyTickVolume(Symbol(), PERIOD_M5, 1, 1, volumes) <= 0 ||
      CopyTime(Symbol(), PERIOD_M5, 1, 1, times) <= 0)
  {
    Print("Error getting volume data - trade cancelled");
    return;
  }

  // Calculate current 20-period volume average
  double current_avg_volume = CalculateCurrentVolumeAverage();
  if (current_avg_volume <= 0)
  {
    Print("Error calculating volume average - trade cancelled");
    return;
  }

  // Check if current volume meets the required threshold
  long current_volume = volumes[0];
  bool volume_confirmed = (current_volume > current_avg_volume);

  if (!volume_confirmed)
  {
    Print("volume not enough: ", current_volume, " | Required Volume: ", current_avg_volume);
    return;
  }

  Print("Volume OK: ", current_volume, " | Executing trade");
  breakout_triggered = true;

  if (is_long_trade)
  {
    Print("BULL executed at ", trigger_price);
    ExecuteBreakoutTrade(true, trigger_price, orb_high);
  }
  else
  {
    Print("BEAR executed at ", trigger_price);
    ExecuteBreakoutTrade(false, trigger_price, orb_low);
  }
}

//+------------------------------------------------------------------+
//| Legacy function - no longer used with real-time execution      |
//+------------------------------------------------------------------+
void CheckBreakoutBarBased()
{
  // This function is no longer used - trades execute immediately in CheckRealtimeBreakout()
  // Keeping for potential future use or debugging
  return;
}

//+------------------------------------------------------------------+
//| Calculate P&L in USD                                             |
//+------------------------------------------------------------------+
double CalculatePnLUSD(double close_price)
{
  if (current_position_ticket == 0 || entry_price == 0)
    return 0;

  double price_diff = 0;

  if (is_long_position)
  {
    price_diff = close_price - entry_price;
  }
  else
  {
    price_diff = entry_price - close_price;
  }

  // Convert to USD
  double contract_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_CONTRACT_SIZE);
  double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
  double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);

  double pnl_usd = (price_diff / tick_size) * tick_value * position_volume;

  return pnl_usd;
}

//+------------------------------------------------------------------+
//| Calculate risk in USD between two price levels                   |
//+------------------------------------------------------------------+
double CalculateRiskUSD(double entry_price_param, double sl_price)
{
  if (entry_price_param == 0 || sl_price == 0)
    return 0;

  double price_diff = MathAbs(entry_price_param - sl_price);

  // Convert to USD using the same method as P&L calculation
  double contract_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_CONTRACT_SIZE);
  double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
  double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);

  double risk_usd = (price_diff / tick_size) * tick_value * position_volume;

  return risk_usd;
}

//+------------------------------------------------------------------+
//| Helper function to handle TP3 reached event                     |
//+------------------------------------------------------------------+
void HandleTP3Reached(bool is_long, double current_price, double tp3_level)
{
  tp3_reached = true;
  double pnl_usd = CalculatePnLUSD(current_price);
  string direction = is_long ? "Long" : "Short";

  Print("TP3 reached: ", direction, " P&L: $", DoubleToString(pnl_usd, 2));

  CloseAllPositions();
  position_active = false;
  breakout_triggered = false; // Allow new breakouts after TP3
  RemoveTP3Line();

  Print("Position closed at TP3 - Profit: $", DoubleToString(pnl_usd, 2));
}

//+------------------------------------------------------------------+
//| Move stop loss to break even (triggered when P&L = 2x risk)     |
//+------------------------------------------------------------------+
void MoveStopLossToBreakEven()
{
  if (!position_active || current_position_ticket == 0 || breakeven_applied)
    return;

  // Find the position by magic number
  for (int i = 0; i < PositionsTotal(); i++)
  {
    if (PositionGetTicket(i) > 0)
    {
      if (PositionGetInteger(POSITION_MAGIC) == magic_number)
      {
        MqlTradeRequest request = {};
        MqlTradeResult result = {};

        // Set up the modification request
        request.action = TRADE_ACTION_SLTP;
        request.symbol = PositionGetString(POSITION_SYMBOL);
        request.position = PositionGetTicket(i);
        request.sl = entry_price;                    // Move SL to entry price (break even)
        request.tp = PositionGetDouble(POSITION_TP); // Keep current TP

        // Send the modification request
        if (OrderSend(request, result))
        {
          if (result.retcode == TRADE_RETCODE_DONE)
          {
            breakeven_applied = true;
            string direction = is_long_position ? "Long" : "Short";
            Print("SUCCESS: SL moved to break even for ", direction, " position. Entry: ", entry_price);
          }
          else
          {
            Print("ERROR: Failed to move SL to break even. Return code: ", result.retcode);
          }
        }
        else
        {
          Print("ERROR: OrderSend failed when moving SL to break even. Error: ", GetLastError());
        }
        break;
      }
    }
  }
}

//+------------------------------------------------------------------+
//| Check if position still exists (SL hit detection)               |
//+------------------------------------------------------------------+
void CheckPositionStatus()
{
  if (!position_active || current_position_ticket == 0)
    return;

  // Check if our position still exists
  bool position_exists = false;

  for (int i = 0; i < PositionsTotal(); i++)
  {
    if (PositionGetTicket(i) > 0)
    {
      if (PositionGetInteger(POSITION_MAGIC) == magic_number)
      {
        position_exists = true;
        break;
      }
    }
  }

  // If position no longer exists, it was closed (likely by SL or TP)
  if (!position_exists)
  {
    string direction = is_long_position ? "Long" : "Short";
    Print("Position closed: ", direction, " (SL hit)");

    // Reset all position tracking variables
    position_active = false;
    is_long_position = false;
    tp3_reached = false;
    breakeven_applied = false;
    current_position_ticket = 0;
    entry_price = 0.0;
    position_volume = 0.0;
    breakout_triggered = false; // Allow new trades

    // Remove TP3 line
    RemoveTP3Line();

    Print("EA reset - ready for new trades");
  }
}

//+------------------------------------------------------------------+
//| Check for TP3 and break-even conditions                         |
//+------------------------------------------------------------------+
void CheckTP3()
{
  if (tp3_reached)
    return;

  double current_price = SymbolInfoDouble(Symbol(), SYMBOL_LAST);

  // Check for break-even condition first (when current P&L reaches 2x the initial risk)
  // Risk = distance from entry to stop loss in USD
  // Trigger break-even when current profit = 2x initial risk
  if (!breakeven_applied && position_active)
  {
    // Get current price for P&L calculation
    double current_pnl = CalculatePnLUSD(current_price);

    // Calculate initial risk (entry to SL distance in USD)
    double initial_risk = 0;

    // Get the current stop loss from the position
    double current_sl = 0;
    for (int i = 0; i < PositionsTotal(); i++)
    {
      if (PositionGetTicket(i) > 0)
      {
        if (PositionGetInteger(POSITION_MAGIC) == magic_number)
        {
          current_sl = PositionGetDouble(POSITION_SL);
          break;
        }
      }
    }

    if (current_sl > 0)
    {
      // Calculate initial risk in USD
      initial_risk = CalculateRiskUSD(entry_price, current_sl);

      // Check if current profit is >= 2x the initial risk
      if (current_pnl >= (initial_risk * 2.0))
      {
        string direction = is_long_position ? "Long" : "Short";
        Print("Break-even trigger: ", direction, " P&L: $", DoubleToString(current_pnl, 2),
              " >= 2x Risk: $", DoubleToString(initial_risk * 2.0, 2));
        MoveStopLossToBreakEven();
      }
    }
  }

  // Check for TP3 reached
  if (is_long_position && current_price >= tp3_bull)
  {
    HandleTP3Reached(true, current_price, tp3_bull);
  }
  else if (!is_long_position && current_price <= tp3_bear)
  {
    HandleTP3Reached(false, current_price, tp3_bear);
  }
}

//+------------------------------------------------------------------+
//| Helper function to log SL calculation details                   |
//+------------------------------------------------------------------+
void LogSLDetails(bool is_long, double entry_price_param, double sl)
{
  string direction = is_long ? "LONG" : "SHORT";
  double orb_range = orb_high - orb_low;
  Print("=== ", direction, " POSITION OPENED ===");
  Print("Entry: ", entry_price_param, " | SL: ", sl, " | TP3: ", is_long ? tp3_bull : tp3_bear);
  Print("ORB Range: ", DoubleToString(orb_range, 5), " | Half Range + Tolerance: ", DoubleToString((orb_range / 2.0) + sl_tolerance_price, 5));
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size based on account balance             |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
  double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
  double lot_size = account_balance / 10000.0; // 1 lot per $10,000 balance

  // Ensure minimum lot size
  lot_size = MathMax(min_lot_size, lot_size);

  // Round to valid lot size step
  double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
  lot_size = MathRound(lot_size / lot_step) * lot_step;

  Print("Balance: $", account_balance, " | Lot: ", lot_size);
  return lot_size;
}

//+------------------------------------------------------------------+
//| Open Long Position                                               |
//+------------------------------------------------------------------+
void OpenLongPosition()
{
  OpenPosition(true);
}

//+------------------------------------------------------------------+
//| Open Short Position                                              |
//+------------------------------------------------------------------+
void OpenShortPosition()
{
  OpenPosition(false);
}

//+------------------------------------------------------------------+
//| Open Position (Main Function)                                   |
//+------------------------------------------------------------------+
void OpenPosition(bool is_long)
{
  if (position_active)
  {
    Print("Position already active - skipping trade");
    return;
  }

  MqlTradeRequest request = {};
  MqlTradeResult result = {};

  // Calculate dynamic lot size based on account balance
  double lot_size = CalculateLotSize();

  // Set trade parameters
  request.action = TRADE_ACTION_DEAL;
  request.symbol = Symbol();
  request.volume = lot_size;
  request.type = is_long ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
  request.price = is_long ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
  request.magic = magic_number;
  request.comment = is_long ? "ORB Long" : "ORB Short";
  request.deviation = 3;
  request.type_filling = ORDER_FILLING_FOK;

  // Calculate stop loss using simplified method
  double sl_price = CalculateSimpleSL(is_long, request.price);
  request.sl = sl_price;

  // Set TP3 as take profit
  request.tp = is_long ? tp3_bull : tp3_bear;

  Print("Opening ", (is_long ? "LONG" : "SHORT"), " | Entry: ", request.price, " | SL: ", request.sl, " | TP: ", request.tp);

  // Send the order
  if (OrderSend(request, result))
  {
    if (result.retcode == TRADE_RETCODE_DONE)
    {
      Print("SUCCESS: ", (is_long ? "LONG" : "SHORT"), " opened | Ticket: ", result.deal);

      // Update position tracking
      position_active = true;
      is_long_position = is_long;
      current_position_ticket = result.deal;
      entry_price = request.price;
      position_volume = request.volume;

      // Draw TP3 line for the position direction
      DrawTP3LineForPosition(is_long);

      Print("Position tracking updated");
    }
    else
    {
      Print("ERROR: Order execution failed. Return code: ", result.retcode);
      Print("Error description: ", GetRetcodeDescription(result.retcode));
    }
  }
  else
  {
    Print("ERROR: OrderSend failed. Error code: ", GetLastError());
  }
}

//+------------------------------------------------------------------+
//| Get return code description                                      |
//+------------------------------------------------------------------+
string GetRetcodeDescription(uint retcode)
{
  switch (retcode)
  {
  case TRADE_RETCODE_REQUOTE:
    return "Requote";
  case TRADE_RETCODE_REJECT:
    return "Request rejected";
  case TRADE_RETCODE_CANCEL:
    return "Request canceled by trader";
  case TRADE_RETCODE_PLACED:
    return "Order placed";
  case TRADE_RETCODE_DONE:
    return "Request completed";
  case TRADE_RETCODE_DONE_PARTIAL:
    return "Request partially completed";
  case TRADE_RETCODE_ERROR:
    return "Request processing error";
  case TRADE_RETCODE_TIMEOUT:
    return "Request canceled by timeout";
  case TRADE_RETCODE_INVALID:
    return "Invalid request";
  case TRADE_RETCODE_INVALID_VOLUME:
    return "Invalid volume in request";
  case TRADE_RETCODE_INVALID_PRICE:
    return "Invalid price in request";
  case TRADE_RETCODE_INVALID_STOPS:
    return "Invalid stops in request";
  case TRADE_RETCODE_TRADE_DISABLED:
    return "Trade is disabled";
  case TRADE_RETCODE_MARKET_CLOSED:
    return "Market is closed";
  case TRADE_RETCODE_NO_MONEY:
    return "No money to complete request";
  case TRADE_RETCODE_PRICE_CHANGED:
    return "Price changed";
  case TRADE_RETCODE_PRICE_OFF:
    return "Off quotes";
  case TRADE_RETCODE_INVALID_EXPIRATION:
    return "Invalid order expiration date";
  case TRADE_RETCODE_ORDER_CHANGED:
    return "Order state changed";
  case TRADE_RETCODE_TOO_MANY_REQUESTS:
    return "Too many requests";
  case TRADE_RETCODE_NO_CHANGES:
    return "No changes in request";
  case TRADE_RETCODE_SERVER_DISABLES_AT:
    return "Autotrading disabled by server";
  case TRADE_RETCODE_CLIENT_DISABLES_AT:
    return "Autotrading disabled by client terminal";
  case TRADE_RETCODE_LOCKED:
    return "Request locked for processing";
  case TRADE_RETCODE_FROZEN:
    return "Order or position frozen";
  case TRADE_RETCODE_INVALID_FILL:
    return "Invalid order filling type";
  case TRADE_RETCODE_CONNECTION:
    return "No connection with trade server";
  case TRADE_RETCODE_ONLY_REAL:
    return "Operation is allowed only for live accounts";
  case TRADE_RETCODE_LIMIT_ORDERS:
    return "Number of pending orders has reached the limit";
  case TRADE_RETCODE_LIMIT_VOLUME:
    return "Volume of orders and positions has reached the limit";
  default:
    return "Unknown error";
  }
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
  int positions_closed = 0;
  double total_pnl = 0;

  for (int i = PositionsTotal() - 1; i >= 0; i--)
  {
    if (PositionGetTicket(i) > 0)
    {
      if (PositionGetInteger(POSITION_MAGIC) == magic_number)
      {
        // Calculate P&L before closing
        double close_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_BID) : SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_ASK);

        double position_pnl = CalculatePnLUSD(close_price);
        total_pnl += position_pnl;

        MqlTradeRequest request = {};
        MqlTradeResult result = {};

        request.action = TRADE_ACTION_DEAL;
        request.symbol = PositionGetString(POSITION_SYMBOL);
        request.volume = PositionGetDouble(POSITION_VOLUME);
        request.price = close_price;
        request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        request.position = PositionGetTicket(i);
        request.magic = magic_number;
        request.comment = "ORB Close";
        request.deviation = 3;
        request.type_filling = ORDER_FILLING_FOK;

        if (OrderSend(request, result))
        {
          positions_closed++;
          Print("Position ", PositionGetTicket(i), " closed. P&L: $", DoubleToString(position_pnl, 2), " USD");
        }
        else
        {
          Print("Failed to close position ", PositionGetTicket(i), " Error: ", GetLastError());
        }
      }
    }
  }

  if (positions_closed > 0)
  {
    Print("Positions closed: ", positions_closed, " | Total P&L: $", DoubleToString(total_pnl, 2));

    if (total_pnl > 0)
      Print("PROFIT: Made $", DoubleToString(total_pnl, 2), " USD");
    else if (total_pnl < 0)
      Print("LOSS: Lost $", DoubleToString(-total_pnl, 2), " USD");
    else
      Print("BREAKEVEN: No profit or loss");
  }

  // Reset position tracking flags when positions are closed
  if (positions_closed > 0)
  {
    position_active = false;
    is_long_position = false;
    tp3_reached = false;
    breakeven_applied = false;
    current_position_ticket = 0;
    entry_price = 0.0;
    position_volume = 0.0;

    // Allow trading again after position is closed (reset flags)
    breakout_triggered = false;
    Print("Trading flags reset - EA can trade again after position close");

    // Remove TP3 line when positions are closed
    RemoveTP3Line();
  }
}