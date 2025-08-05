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
input double sl_tolerance_pips = 3.0;               // Additional pip tolerance for SL

//--- global variables
double orb_high = 0;
double orb_low = 0;
double avg_volume = 0; // Changed from start_volume to avg_volume
bool orb_calculated = false;
bool trading_window_active = false;
bool traded_today = false;
bool breakout_triggered = false; // Prevent multiple trades on same breakout
double current_bar_close = 0.0;  // Track current completed bar close for breakout confirmation
int trades_today = 0;            // Count trades taken today
datetime last_reset_time = 0;
datetime last_bar_time = 0; // Track last processed bar time

// TP levels variables
double tp3_bull = 0;
double tp3_bear = 0;
bool position_active = false;
bool is_long_position = false;

// TP progression tracking
bool tp3_reached = false;
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
  // EST is UTC-5, EDT is UTC-4 (adjust based on daylight saving)
  // For simplicity, using EST offset. In production, implement proper DST logic
  return TimeCurrent() - 5 * 3600;
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

  // Trading window: at session start (5am NY)
  trading_window_active = (ny_hour == 5 && ny_min >= 15) || (ny_hour > 5 && ny_hour < 9);

  // Check for breakout during trading window - use bar-based logic
  if (trading_window_active && orb_calculated && !position_active)
  {
    CheckBreakoutBarBased();
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

  orb_calculated = trading_window_active = traded_today = tp3_reached = position_active = is_long_position = breakout_triggered = false;
  trades_today = 0;
  current_position_ticket = 0;
  orb_high = orb_low = avg_volume = tp3_bull = tp3_bear = entry_price = position_volume = current_bar_close = 0.0;
  last_bar_time = 0;

  Print("Daily ORB variables reset at market close (5:00 PM NY)");
}

//+------------------------------------------------------------------+
//| Calculate Opening Range Breakout                                 |
//+------------------------------------------------------------------+
void CalculateORB()
{
  // Get 15-minute range from 5:00-5:15 AM NY (3 bars on M5 timeframe)
  datetime start_time = TimeCurrent() - 15 * 60; // 15 minutes ago

  int bars = Bars(Symbol(), PERIOD_M5, start_time, TimeCurrent());
  if (bars < 3) // Need at least 3 bars for 15-minute range on M5
    return;

  double high_prices[];
  double low_prices[];
  long volumes[];

  ArrayResize(high_prices, bars);
  ArrayResize(low_prices, bars);
  ArrayResize(volumes, bars);

  if (CopyHigh(Symbol(), PERIOD_M5, start_time, bars, high_prices) <= 0 ||
      CopyLow(Symbol(), PERIOD_M5, start_time, bars, low_prices) <= 0 ||
      CopyTickVolume(Symbol(), PERIOD_M5, start_time, bars, volumes) <= 0)
  {
    Print("Error copying price/volume data");
    return;
  }

  orb_high = high_prices[ArrayMaximum(high_prices)];
  orb_low = low_prices[ArrayMinimum(low_prices)];

  orb_calculated = true;

  // Calculate average volume like Pine Script: ta.sma(volume, 20)
  // Get the last 20 bars for SMA calculation (completed bars only) - on M5 timeframe
  long avg_volumes[];
  int avg_bars = 20;
  ArrayResize(avg_volumes, avg_bars);

  if (CopyTickVolume(Symbol(), PERIOD_M5, 1, avg_bars, avg_volumes) > 0) // Start from bar 1 (previous completed bar)
  {
    long total_volume = 0;
    for (int i = 0; i < avg_bars; i++)
    {
      total_volume += avg_volumes[i];
    }
    avg_volume = (double)total_volume / avg_bars;
  }
  else
  {
    Print("Error copying average volume data");
    return;
  }

  // Calculate TP3 level only (6x ORB range)
  double orb_range = orb_high - orb_low;
  tp3_bull = orb_high + orb_range * 6;
  tp3_bear = orb_low - orb_range * 6;

  datetime ny_time = GetNYTime();
  Print("ORB calculated (NY: ", TimeToString(ny_time, TIME_DATE | TIME_MINUTES), ") - High: ", orb_high, " Low: ", orb_low, " Avg Volume: ", avg_volume);
  Print("TP3 Levels - Bull TP3: ", tp3_bull, " Bear TP3: ", tp3_bear);

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
  ChartRedraw(0);
  Print("ORB lines drawn on chart");
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
  ChartRedraw(0);
  Print("Session start line drawn at 5:00 AM NY");
}

//+------------------------------------------------------------------+
//| Draw session end vertical line at 5:00 PM NY                    |
//+------------------------------------------------------------------+
void DrawSessionEndLine()
{
  CreateVerticalLine(session_end_line, clrBlue, STYLE_DASH, "Session End (5:00 PM NY)");
  ChartRedraw(0);
  Print("Session end line drawn at 5:00 PM NY");
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

  CreateHorizontalLine(line_name, price_level, line_color, STYLE_DASH, label_prefix);
  Print(direction, " TP3 line drawn on chart");
  ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Remove TP3 line from chart                                       |
//+------------------------------------------------------------------+
void RemoveTP3Line()
{
  ObjectDelete(0, tp3_bull_line);
  ObjectDelete(0, tp3_bear_line);
  ChartRedraw(0);
  Print("TP3 line removed from chart");
}

//+------------------------------------------------------------------+
//| Calculate simple stop loss using half ORB range with tolerance  |
//+------------------------------------------------------------------+
double CalculateSimpleSL(bool is_long, double entry_price_param)
{
  double sl = 0;
  double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
  double pip_value = point * 10; // Assuming 5-digit broker

  // Calculate half the ORB range
  double orb_range = orb_high - orb_low;
  double half_range = orb_range / 2.0;

  // Add pip tolerance
  double tolerance = sl_tolerance_pips * pip_value;

  switch (sl_method)
  {
  case SL_ORB_HALF_RANGE:
  {
    if (is_long)
    {
      // For longs: SL at entry minus half ORB range minus tolerance
      sl = entry_price_param - half_range - tolerance;
    }
    else
    {
      // For shorts: SL at entry plus half ORB range plus tolerance
      sl = entry_price_param + half_range + tolerance;
    }
  }
  break;

  default:
    // Fallback to same logic
    sl = is_long ? entry_price_param - half_range - tolerance : entry_price_param + half_range + tolerance;
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

  Print(direction, " BREAKOUT detected at price: ", current_price, " (", level_name, ": ", level, ")");

  if (is_bullish)
    OpenLongPosition();
  else
    OpenShortPosition();

  trades_today++;
  Print("Trade #", trades_today, " taken today");

  // Set traded_today flag to prevent multiple trades on same breakout
  traded_today = true;
}

//+------------------------------------------------------------------+
//| Check if completed candle closed above ORB High or below ORB Low with volume |
//+------------------------------------------------------------------+
void CheckBreakoutBarBased()
{
  // Prevent multiple trades on same breakout
  if (breakout_triggered)
    return;

  // Get the most recent completed M5 bar data
  double close_prices[];
  long volumes[];
  datetime times[];

  ArrayResize(close_prices, 1);
  ArrayResize(volumes, 1);
  ArrayResize(times, 1);

  // Get the last completed bar (index 1 = most recent completed bar)
  if (CopyClose(Symbol(), PERIOD_M5, 1, 1, close_prices) <= 0 ||
      CopyTickVolume(Symbol(), PERIOD_M5, 1, 1, volumes) <= 0 ||
      CopyTime(Symbol(), PERIOD_M5, 1, 1, times) <= 0)
    return;

  // Check if we have a new completed bar
  if (times[0] <= last_bar_time)
    return; // No new bar yet

  // Update bar tracking - use current completed bar
  last_bar_time = times[0];
  current_bar_close = close_prices[0]; // Current completed bar close

  // Volume confirmation using current completed bar
  long current_volume = volumes[0];
  bool volume_confirmed = (current_volume > avg_volume * volume_multiplier);

  if (!volume_confirmed)
  {
    // Uncomment for debugging: Print("Volume not confirmed. Current: ", current_volume, " Required: ", (long)(avg_volume * volume_multiplier));
    return;
  }

  // Print volume confirmation for debugging with NY time
  datetime ny_time = GetNYTime();
  Print("Volume CONFIRMED! (NY: ", TimeToString(ny_time, TIME_DATE|TIME_MINUTES), ") Candle closed at: ", current_bar_close, " | Volume: ", current_volume, " vs Required: ", (long)(avg_volume * volume_multiplier));

  // Check if completed candle closed above/below ORB levels
  bool bullish_breakout = (current_bar_close > orb_high) && volume_confirmed;
  bool bearish_breakout = (current_bar_close < orb_low) && volume_confirmed;

  // Execute trades based on completed candle breakouts
  if (bullish_breakout)
  {
    breakout_triggered = true;
    datetime ny_time = GetNYTime();
    Print("BULLISH BREAKOUT (NY: ", TimeToString(ny_time, TIME_DATE|TIME_MINUTES), "): Candle closed at ", current_bar_close, " above ORB High: ", orb_high);
    ExecuteBreakoutTrade(true, current_bar_close, orb_high);
  }
  else if (bearish_breakout)
  {
    breakout_triggered = true;
    datetime ny_time = GetNYTime();
    Print("BEARISH BREAKOUT (NY: ", TimeToString(ny_time, TIME_DATE|TIME_MINUTES), "): Candle closed at ", current_bar_close, " below ORB Low: ", orb_low);
    ExecuteBreakoutTrade(false, current_bar_close, orb_low);
  }
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
//| Helper function to handle TP3 reached event                     |
//+------------------------------------------------------------------+
void HandleTP3Reached(bool is_long, double current_price, double tp3_level)
{
  tp3_reached = true;
  double pnl_usd = CalculatePnLUSD(current_price);
  string direction = is_long ? "Long" : "Short";

  Print("TP3 REACHED for ", direction, " position at price: ", current_price, " (TP3: ", tp3_level, ")");
  Print("Position P&L: $", DoubleToString(pnl_usd, 2), " USD");

  CloseAllPositions();
  position_active = false;
  traded_today = false;       // Allow new trades after TP3 is reached
  breakout_triggered = false; // Allow new breakouts after TP3
  RemoveTP3Line();

  Print("Position closed at TP3 - Trade completed successfully with profit: $", DoubleToString(pnl_usd, 2));
}

//+------------------------------------------------------------------+
//| Check for TP3 and close position                                |
//+------------------------------------------------------------------+
void CheckTP3()
{
  if (tp3_reached)
    return;

  double current_price = SymbolInfoDouble(Symbol(), SYMBOL_LAST);

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
  Print("ORB Range: ", DoubleToString(orb_range, 5), " | Half Range + Tolerance: ", DoubleToString((orb_range / 2.0) + (sl_tolerance_pips * SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 10), 5));
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

  Print("Account Balance: $", account_balance, " | Calculated Lot Size: ", lot_size);
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

  Print("Attempting to open ", (is_long ? "LONG" : "SHORT"), " position:");
  Print("Entry Price: ", request.price);
  Print("Stop Loss: ", request.sl);
  Print("Take Profit: ", request.tp);
  Print("Volume: ", request.volume);

  // Send the order
  if (OrderSend(request, result))
  {
    if (result.retcode == TRADE_RETCODE_DONE)
    {
      Print("SUCCESS: ", (is_long ? "LONG" : "SHORT"), " position opened!");
      Print("Order ticket: ", result.order);
      Print("Deal ticket: ", result.deal);

      // Update position tracking
      position_active = true;
      is_long_position = is_long;
      current_position_ticket = result.deal;
      entry_price = request.price;
      position_volume = request.volume;

      // Draw TP3 line for the position direction
      DrawTP3LineForPosition(is_long);

      Print("Position tracking updated - EA monitoring position");
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
//| Calculate Kelly Criterion Lot Size                              |
//+------------------------------------------------------------------+
double CalculateKellyLotSize(bool is_long)
{
  // Simplified Kelly calculation
  // In practice, you'd need historical win rate and avg win/loss data
  double win_rate = 0.55; // 55% win rate assumption
  double avg_win = 2.0;   // Average win ratio
  double avg_loss = 1.0;  // Average loss ratio

  double kelly_percent = (win_rate * avg_win - (1 - win_rate) * avg_loss) / avg_win;
  kelly_percent = MathMax(0.01, MathMin(0.1, kelly_percent)); // Cap between 1% and 10%

  double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
  double orb_range = orb_high - orb_low;
  double risk_amount = account_balance * kelly_percent;

  double lot_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_CONTRACT_SIZE);
  double pip_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);

  double risk_pips = orb_range / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
  double lot_size = risk_amount / (risk_pips * pip_value);

  // Ensure minimum lot size
  lot_size = MathMax(min_lot_size, lot_size);

  // Round to valid lot size
  double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
  lot_size = MathRound(lot_size / lot_step) * lot_step;

  return lot_size;
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
    Print("ORB positions closed at 5:00 PM NY: ", positions_closed, " positions");
    Print("Total P&L: $", DoubleToString(total_pnl, 2), " USD");

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
    current_position_ticket = 0;
    entry_price = 0.0;
    position_volume = 0.0;

    // Allow trading again after position is closed (reset flags)
    traded_today = false;
    breakout_triggered = false;
    Print("Trading flags reset - EA can trade again after position close");

    // Remove TP3 line when positions are closed
    RemoveTP3Line();
  }
}