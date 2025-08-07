//+------------------------------------------------------------------+
//|                                                   Key Levels.mq5 |
//|                                      SpacemanBTC Key Level V13.1 |
//|                           Converted from Pine Script to MQL5     |
//+------------------------------------------------------------------+
#property copyright "SpacemanBTC IDWM"
#property link ""
#property version "13.1"
#property indicator_chart_window
#property indicator_plots 0

//--- Input parameters
enum ENUM_DISPLAY_STYLE
{
  STANDARD = 0,      // Standard
  RIGHT_ANCHORED = 1 // Right Anchored
};

enum ENUM_TEXT_SIZE
{
  TEXT_SMALL = 0,  // Small
  TEXT_MEDIUM = 1, // Medium
  TEXT_LARGE = 2   // Large
};

enum ENUM_LINE_WIDTH
{
  LINE_SMALL = 0,  // Small
  LINE_MEDIUM = 1, // Medium
  LINE_LARGE = 2   // Large
};

enum ENUM_LINE_STYLE_CUSTOM
{
  LINE_SOLID_CUSTOM = 0,  // Solid
  LINE_DASHED_CUSTOM = 1, // Dashed
  LINE_DOTTED_CUSTOM = 2  // Dotted
};

//--- Display Settings
sinput string DisplayGroup = "=== Display Settings ===";    // Display Settings
input ENUM_DISPLAY_STYLE displayStyle = STANDARD;           // Display Style
input bool mergebool = true;                                // Merge Levels?
input int distanceright = 30;                               // Distance (5-500)
input int radistance = 250;                                 // Anchor Distance (5-500)
input ENUM_TEXT_SIZE labelsize = TEXT_MEDIUM;               // Text Size
input ENUM_LINE_WIDTH linesize = LINE_SMALL;                // Line Width
input ENUM_LINE_STYLE_CUSTOM linestyle = LINE_SOLID_CUSTOM; // Line Style

//--- Global Settings
sinput string GlobalGroup = "=== Global Settings ==="; // Global Settings
input bool GlobalTextType = false;                     // Global Text ShortHand
input bool globalcoloring = false;                     // Global Coloring
input color GlobalColor = clrWhite;                    // Global Color

//--- 4H Settings
sinput string IntraGroup = "=== 4H Settings ==="; // 4H Settings
input bool is_intra_enabled = false;              // Open
input bool is_intrarange_enabled = false;         // Prev H/L
input bool is_intram_enabled = false;             // Prev Mid
input bool IntraTextType = false;                 // ShortHand
input color IntraColor = clrOrange;               // 4H Color

//--- Daily Settings
sinput string DailyGroup = "=== Daily Settings ==="; // Daily Settings
input bool is_daily_enabled = true;                  // Open
input bool is_dailyrange_enabled = false;            // Prev H/L
input bool is_dailym_enabled = false;                // Prev Mid
input bool DailyTextType = false;                    // ShortHand
input color DailyColor = 0x08bcd4;                   // Daily Color

//--- Monday Range Settings
sinput string MondayGroup = "=== Monday Range Settings ==="; // Monday Range Settings
input bool is_monday_enabled = true;                         // Range
input bool is_monday_mid = true;                             // Mid
input bool MondayTextType = false;                           // ShortHand
input color MondayColor = clrWhite;                          // Monday Color

//--- Weekly Settings
sinput string WeeklyGroup = "=== Weekly Settings ==="; // Weekly Settings
input bool is_weekly_enabled = true;                   // Open
input bool is_weeklyrange_enabled = true;              // Prev H/L
input bool is_weekly_mid = true;                       // Prev Mid
input bool WeeklyTextType = false;                     // ShortHand
input color WeeklyColor = 0xfffcbc;                    // Weekly Color

//--- Monthly Settings
sinput string MonthlyGroup = "=== Monthly Settings ==="; // Monthly Settings
input bool is_monthly_enabled = true;                    // Open
input bool is_monthlyrange_enabled = true;               // Prev H/L
input bool is_monthly_mid = true;                        // Prev Mid
input bool MonthlyTextType = false;                      // ShortHand
input color MonthlyColor = 0x08d48c;                     // Monthly Color

//--- Quarterly Settings
sinput string QuarterlyGroup = "=== Quarterly Settings ==="; // Quarterly Settings
input bool is_quarterly_enabled = true;                      // Open
input bool is_quarterlyrange_enabled = false;                // Prev H/L
input bool is_quarterly_mid = true;                          // Prev Mid
input bool QuarterlyTextType = false;                        // ShortHand
input color quarterlyColor = clrRed;                         // Quarterly Color

//--- Yearly Settings
sinput string YearlyGroup = "=== Yearly Settings ==="; // Yearly Settings
input bool is_yearly_enabled = true;                   // Open
input bool is_yearlyrange_enabled = false;             // Current H/L
input bool is_yearly_mid = true;                       // Mid
input bool YearlyTextType = false;                     // ShortHand
input color YearlyColor = clrRed;                      // Yearly Color

//--- FX Sessions Settings
sinput string SessionsGroup = "=== FX Sessions Settings ==="; // FX Sessions Settings
input bool is_londonrange_enabled = false;                    // London Range
input bool is_usrange_enabled = false;                        // New York Range
input bool is_asiarange_enabled = false;                      // Asia Range
input bool SessionTextType = false;                           // ShortHand
input int LondonStart = 8;                                    // London Start Hour
input int LondonEnd = 16;                                     // London End Hour
input int USStart = 14;                                       // US Start Hour
input int USEnd = 21;                                         // US End Hour
input int AsiaStart = 0;                                      // Asia Start Hour
input int AsiaEnd = 9;                                        // Asia End Hour
input color LondonColor = clrWhite;                           // London Color
input color USColor = clrWhite;                               // US Color
input color AsiaColor = clrWhite;                             // Asia Color

//--- Global variables
datetime daily_time, dailyh_time, dailyl_time;
double daily_open, dailyh_open, dailyl_open;
double cdailyh_open, cdailyl_open;

datetime weekly_time, weeklyh_time, weeklyl_time;
double weekly_open, weeklyh_open, weeklyl_open;

datetime monthly_time, monthlyh_time, monthlyl_time;
double monthly_open, monthlyh_open, monthlyl_open;

datetime quarterly_time, quarterlyh_time, quarterlyl_time;
double quarterly_open, quarterlyh_open, quarterlyl_open;

datetime yearly_time, yearlyh_time, yearlyl_time;
double yearly_open, yearlyh_open, yearlyl_open;

datetime intra_time, intrah_time, intral_time;
double intra_open, intrah_open, intral_open;

datetime monday_time;
double monday_high, monday_low;
bool untested_monday = false;

// Session variables
double flondonhigh, flondonlow, flondonopen;
double fushigh, fuslow, fusopen;
double fasiahigh, fasialow, fasiaopen;
datetime londontime, ustime, asiatime;

// Text variables
string pdhtext, pdltext, dotext, pdmtext;
string pwhtext, pwltext, wotext, pwmtext;
string pmhtext, pmltext, motext, pmmtext;
string pqhtext, pqltext, qotext, pqmtext;
string cyhtext, cyltext, yotext, cymtext;
string pihtext, piltext, iotext, pimtext;
string pmonhtext, pmonltext, pmonmtext;
string lhtext, lltext, lotext;
string ushtext, usltext, usotext;
string asiahtext, asialtext, asiaotext;

// Drawing variables
int DEFAULT_LINE_WIDTH;
int DEFAULT_EXTEND_RIGHT;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
  //--- Set line width
  switch (linesize)
  {
  case LINE_SMALL:
    DEFAULT_LINE_WIDTH = 1;
    break;
  case LINE_MEDIUM:
    DEFAULT_LINE_WIDTH = 2;
    break;
  case LINE_LARGE:
    DEFAULT_LINE_WIDTH = 3;
    break;
  }

  DEFAULT_EXTEND_RIGHT = distanceright;

  //--- Initialize text labels
  InitializeTextLabels();

  //--- Delete all objects on init
  ObjectsDeleteAll(0, "KeyLevel_");

  return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  //--- Delete all objects created by indicator
  ObjectsDeleteAll(0, "KeyLevel_");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
  //--- Only calculate on last bar
  if (rates_total < 2)
    return (0);

  //--- Get timeframe data
  GetTimeframeData();

  //--- Update session data
  UpdateSessionData();

  //--- Update Monday range
  UpdateMondayRange();

  //--- Draw all levels
  DrawLevels();

  return (rates_total);
}

//+------------------------------------------------------------------+
//| Initialize text labels                                           |
//+------------------------------------------------------------------+
void InitializeTextLabels()
{
  // Daily text labels
  pdhtext = (GlobalTextType || DailyTextType) ? "PDH" : "Prev Day High";
  pdltext = (GlobalTextType || DailyTextType) ? "PDL" : "Prev Day Low";
  dotext = (GlobalTextType || DailyTextType) ? "DO" : "Daily Open";
  pdmtext = (GlobalTextType || DailyTextType) ? "PDM" : "Prev Day Mid";

  // Weekly text labels
  pwhtext = (GlobalTextType || WeeklyTextType) ? "PWH" : "Prev Week High";
  pwltext = (GlobalTextType || WeeklyTextType) ? "PWL" : "Prev Week Low";
  wotext = (GlobalTextType || WeeklyTextType) ? "WO" : "Weekly Open";
  pwmtext = (GlobalTextType || WeeklyTextType) ? "PWM" : "Prev Week Mid";

  // Monthly text labels
  pmhtext = (GlobalTextType || MonthlyTextType) ? "PMH" : "Prev Month High";
  pmltext = (GlobalTextType || MonthlyTextType) ? "PML" : "Prev Month Low";
  motext = (GlobalTextType || MonthlyTextType) ? "MO" : "Monthly Open";
  pmmtext = (GlobalTextType || MonthlyTextType) ? "PMM" : "Prev Month Mid";

  // Quarterly text labels
  pqhtext = (GlobalTextType || QuarterlyTextType) ? "PQH" : "Prev Quarter High";
  pqltext = (GlobalTextType || QuarterlyTextType) ? "PQL" : "Prev Quarter Low";
  qotext = (GlobalTextType || QuarterlyTextType) ? "QO" : "Quarterly Open";
  pqmtext = (GlobalTextType || QuarterlyTextType) ? "PQM" : "Prev Quarter Mid";

  // Yearly text labels
  cyhtext = (GlobalTextType || YearlyTextType) ? "CYH" : "Current Year High";
  cyltext = (GlobalTextType || YearlyTextType) ? "CYL" : "Current Year Low";
  yotext = (GlobalTextType || YearlyTextType) ? "YO" : "Yearly Open";
  cymtext = (GlobalTextType || YearlyTextType) ? "CYM" : "Current Year Mid";

  // 4H text labels
  pihtext = (GlobalTextType || IntraTextType) ? "P-4H-H" : "Prev 4H High";
  piltext = (GlobalTextType || IntraTextType) ? "P-4H-L" : "Prev 4H Low";
  iotext = (GlobalTextType || IntraTextType) ? "4H-O" : "4H Open";
  pimtext = (GlobalTextType || IntraTextType) ? "P-4H-M" : "Prev 4H Mid";

  // Monday text labels
  pmonhtext = (GlobalTextType || MondayTextType) ? "MDAY-H" : "Monday High";
  pmonltext = (GlobalTextType || MondayTextType) ? "MDAY-L" : "Monday Low";
  pmonmtext = (GlobalTextType || MondayTextType) ? "MDAY-M" : "Monday Mid";

  // Session text labels
  lhtext = (GlobalTextType || SessionTextType) ? "Lon-H" : "London High";
  lltext = (GlobalTextType || SessionTextType) ? "Lon-L" : "London Low";
  lotext = (GlobalTextType || SessionTextType) ? "Lon-O" : "London Open";

  ushtext = (GlobalTextType || SessionTextType) ? "NY-H" : "New York High";
  usltext = (GlobalTextType || SessionTextType) ? "NY-L" : "New York Low";
  usotext = (GlobalTextType || SessionTextType) ? "NY-O" : "New York Open";

  asiahtext = (GlobalTextType || SessionTextType) ? "AS-H" : "Asia High";
  asialtext = (GlobalTextType || SessionTextType) ? "AS-L" : "Asia Low";
  asiaotext = (GlobalTextType || SessionTextType) ? "AS-O" : "Asia Open";
}

//+------------------------------------------------------------------+
//| Get timeframe data                                               |
//+------------------------------------------------------------------+
void GetTimeframeData()
{
  // Get Daily data
  daily_time = iTime(Symbol(), PERIOD_D1, 0);
  daily_open = iOpen(Symbol(), PERIOD_D1, 0);
  dailyh_time = iTime(Symbol(), PERIOD_D1, 1);
  dailyh_open = iHigh(Symbol(), PERIOD_D1, 1);
  dailyl_time = iTime(Symbol(), PERIOD_D1, 1);
  dailyl_open = iLow(Symbol(), PERIOD_D1, 1);
  cdailyh_open = iHigh(Symbol(), PERIOD_D1, 0);
  cdailyl_open = iLow(Symbol(), PERIOD_D1, 0);

  // Get Weekly data
  weekly_time = iTime(Symbol(), PERIOD_W1, 0);
  weekly_open = iOpen(Symbol(), PERIOD_W1, 0);
  weeklyh_time = iTime(Symbol(), PERIOD_W1, 1);
  weeklyh_open = iHigh(Symbol(), PERIOD_W1, 1);
  weeklyl_time = iTime(Symbol(), PERIOD_W1, 1);
  weeklyl_open = iLow(Symbol(), PERIOD_W1, 1);

  // Get Monthly data
  monthly_time = iTime(Symbol(), PERIOD_MN1, 0);
  monthly_open = iOpen(Symbol(), PERIOD_MN1, 0);
  monthlyh_time = iTime(Symbol(), PERIOD_MN1, 1);
  monthlyh_open = iHigh(Symbol(), PERIOD_MN1, 1);
  monthlyl_time = iTime(Symbol(), PERIOD_MN1, 1);
  monthlyl_open = iLow(Symbol(), PERIOD_MN1, 1);

  // Get Quarterly data (approximate using 3 months)
  quarterly_time = GetQuarterlyTime(0);
  quarterly_open = GetQuarterlyOpen(0);
  quarterlyh_time = GetQuarterlyTime(1);
  quarterlyh_open = GetQuarterlyHigh(1);
  quarterlyl_time = GetQuarterlyTime(1);
  quarterlyl_open = GetQuarterlyLow(1);

  // Get Yearly data
  yearly_time = GetYearlyTime(0);
  yearly_open = GetYearlyOpen(0);
  yearlyh_time = GetYearlyTime(0);
  yearlyh_open = GetYearlyHigh(0);
  yearlyl_time = GetYearlyTime(0);
  yearlyl_open = GetYearlyLow(0);

  // Get 4H data
  intra_time = iTime(Symbol(), PERIOD_H4, 0);
  intra_open = iOpen(Symbol(), PERIOD_H4, 0);
  intrah_time = iTime(Symbol(), PERIOD_H4, 1);
  intrah_open = iHigh(Symbol(), PERIOD_H4, 1);
  intral_time = iTime(Symbol(), PERIOD_H4, 1);
  intral_open = iLow(Symbol(), PERIOD_H4, 1);
}

//+------------------------------------------------------------------+
//| Update session data                                              |
//+------------------------------------------------------------------+
void UpdateSessionData()
{
  MqlDateTime dt;
  TimeToStruct(TimeCurrent(), dt);

  static double session_high_london = 0, session_low_london = DBL_MAX;
  static double session_high_us = 0, session_low_us = DBL_MAX;
  static double session_high_asia = 0, session_low_asia = DBL_MAX;
  static double session_open_london = 0, session_open_us = 0, session_open_asia = 0;
  static bool in_london = false, in_us = false, in_asia = false;

  double current_high = iHigh(Symbol(), Period(), 0);
  double current_low = iLow(Symbol(), Period(), 0);
  double current_open = iOpen(Symbol(), Period(), 0);
  datetime current_time = iTime(Symbol(), Period(), 0);

  // London session
  bool london_active = (dt.hour >= LondonStart && dt.hour < LondonEnd);
  if (london_active && !in_london)
  {
    session_high_london = current_high;
    session_low_london = current_low;
    session_open_london = current_open;
    londontime = current_time;
    in_london = true;
  }
  else if (london_active && in_london)
  {
    if (current_high > session_high_london)
      session_high_london = current_high;
    if (current_low < session_low_london)
      session_low_london = current_low;
  }
  else if (!london_active && in_london)
  {
    flondonhigh = session_high_london;
    flondonlow = session_low_london;
    flondonopen = session_open_london;
    in_london = false;
  }

  // US session
  bool us_active = (dt.hour >= USStart && dt.hour < USEnd);
  if (us_active && !in_us)
  {
    session_high_us = current_high;
    session_low_us = current_low;
    session_open_us = current_open;
    ustime = current_time;
    in_us = true;
  }
  else if (us_active && in_us)
  {
    if (current_high > session_high_us)
      session_high_us = current_high;
    if (current_low < session_low_us)
      session_low_us = current_low;
  }
  else if (!us_active && in_us)
  {
    fushigh = session_high_us;
    fuslow = session_low_us;
    fusopen = session_open_us;
    in_us = false;
  }

  // Asia session
  bool asia_active = (dt.hour >= AsiaStart && dt.hour < AsiaEnd);
  if (asia_active && !in_asia)
  {
    session_high_asia = current_high;
    session_low_asia = current_low;
    session_open_asia = current_open;
    asiatime = current_time;
    in_asia = true;
  }
  else if (asia_active && in_asia)
  {
    if (current_high > session_high_asia)
      session_high_asia = current_high;
    if (current_low < session_low_asia)
      session_low_asia = current_low;
  }
  else if (!asia_active && in_asia)
  {
    fasiahigh = session_high_asia;
    fasialow = session_low_asia;
    fasiaopen = session_open_asia;
    in_asia = false;
  }
}

//+------------------------------------------------------------------+
//| Update Monday range                                              |
//+------------------------------------------------------------------+
void UpdateMondayRange()
{
  MqlDateTime dt;
  TimeToStruct(weekly_time, dt);

  static datetime last_weekly_time = 0;

  if (weekly_time != last_weekly_time)
  {
    untested_monday = false;
    last_weekly_time = weekly_time;
  }

  if (is_monday_enabled && !untested_monday)
  {
    untested_monday = true;
    monday_time = daily_time;
    monday_high = cdailyh_open;
    monday_low = cdailyl_open;
  }
}

//+------------------------------------------------------------------+
//| Draw all levels                                                  |
//+------------------------------------------------------------------+
void DrawLevels()
{
  // Delete existing objects
  ObjectsDeleteAll(0, "KeyLevel_");

  int bars_total = Bars(Symbol(), Period());
  datetime limit_right;

  datetime current_time = iTime(Symbol(), Period(), 0);
  datetime prev_time = iTime(Symbol(), Period(), 1);

  if (displayStyle == RIGHT_ANCHORED)
    limit_right = current_time + (current_time - prev_time) * radistance;
  else
    limit_right = current_time + (current_time - prev_time) * DEFAULT_EXTEND_RIGHT;

  // Draw 4H levels
  if (is_intra_enabled)
    DrawLevel("4H_Open", intra_time, limit_right, intra_open, iotext, GetColor(IntraColor));

  if (is_intrarange_enabled)
  {
    DrawLevel("4H_High", intrah_time, limit_right, intrah_open, pihtext, GetColor(IntraColor));
    DrawLevel("4H_Low", intral_time, limit_right, intral_open, piltext, GetColor(IntraColor));
  }

  if (is_intram_enabled)
  {
    double intram_open = (intral_open + intrah_open) / 2;
    DrawLevel("4H_Mid", intrah_time, limit_right, intram_open, pimtext, GetColor(IntraColor));
  }

  // Draw Daily levels
  if (is_daily_enabled)
    DrawLevel("Daily_Open", daily_time, limit_right, daily_open, dotext, GetColor(DailyColor));

  if (is_dailyrange_enabled)
  {
    DrawLevel("Daily_High", dailyh_time, limit_right, dailyh_open, pdhtext, GetColor(DailyColor));
    DrawLevel("Daily_Low", dailyl_time, limit_right, dailyl_open, pdltext, GetColor(DailyColor));
  }

  if (is_dailym_enabled)
  {
    double dailym_open = (dailyl_open + dailyh_open) / 2;
    DrawLevel("Daily_Mid", dailyh_time, limit_right, dailym_open, pdmtext, GetColor(DailyColor));
  }

  // Draw Monday levels
  if (is_monday_enabled)
  {
    DrawLevel("Monday_High", monday_time, limit_right, monday_high, pmonhtext, GetColor(MondayColor));
    DrawLevel("Monday_Low", monday_time, limit_right, monday_low, pmonltext, GetColor(MondayColor));
  }

  if (is_monday_mid)
  {
    double mondaym_open = (monday_high + monday_low) / 2;
    DrawLevel("Monday_Mid", monday_time, limit_right, mondaym_open, pmonmtext, GetColor(MondayColor));
  }

  // Draw Weekly levels
  if (is_weekly_enabled)
    DrawLevel("Weekly_Open", weekly_time, limit_right, weekly_open, wotext, GetColor(WeeklyColor));

  if (is_weeklyrange_enabled)
  {
    DrawLevel("Weekly_High", weeklyh_time, limit_right, weeklyh_open, pwhtext, GetColor(WeeklyColor));
    DrawLevel("Weekly_Low", weeklyl_time, limit_right, weeklyl_open, pwltext, GetColor(WeeklyColor));
  }

  if (is_weekly_mid)
  {
    double weeklym_open = (weeklyl_open + weeklyh_open) / 2;
    DrawLevel("Weekly_Mid", weeklyh_time, limit_right, weeklym_open, pwmtext, GetColor(WeeklyColor));
  }

  // Draw Monthly levels
  if (is_monthly_enabled)
    DrawLevel("Monthly_Open", monthly_time, limit_right, monthly_open, motext, GetColor(MonthlyColor));

  if (is_monthlyrange_enabled)
  {
    DrawLevel("Monthly_High", monthlyh_time, limit_right, monthlyh_open, pmhtext, GetColor(MonthlyColor));
    DrawLevel("Monthly_Low", monthlyl_time, limit_right, monthlyl_open, pmltext, GetColor(MonthlyColor));
  }

  if (is_monthly_mid)
  {
    double monthlym_open = (monthlyl_open + monthlyh_open) / 2;
    DrawLevel("Monthly_Mid", monthlyh_time, limit_right, monthlym_open, pmmtext, GetColor(MonthlyColor));
  }

  // Draw Quarterly levels
  if (is_quarterly_enabled)
    DrawLevel("Quarterly_Open", quarterly_time, limit_right, quarterly_open, qotext, GetColor(quarterlyColor));

  if (is_quarterlyrange_enabled)
  {
    DrawLevel("Quarterly_High", quarterlyh_time, limit_right, quarterlyh_open, pqhtext, GetColor(quarterlyColor));
    DrawLevel("Quarterly_Low", quarterlyl_time, limit_right, quarterlyl_open, pqltext, GetColor(quarterlyColor));
  }

  if (is_quarterly_mid)
  {
    double quarterlym_open = (quarterlyl_open + quarterlyh_open) / 2;
    DrawLevel("Quarterly_Mid", quarterlyh_time, limit_right, quarterlym_open, pqmtext, GetColor(quarterlyColor));
  }

  // Draw Yearly levels
  if (is_yearly_enabled)
    DrawLevel("Yearly_Open", yearly_time, limit_right, yearly_open, yotext, GetColor(YearlyColor));

  if (is_yearlyrange_enabled)
  {
    DrawLevel("Yearly_High", yearlyh_time, limit_right, yearlyh_open, cyhtext, GetColor(YearlyColor));
    DrawLevel("Yearly_Low", yearlyl_time, limit_right, yearlyl_open, cyltext, GetColor(YearlyColor));
  }

  if (is_yearly_mid)
  {
    double yearlym_open = (yearlyl_open + yearlyh_open) / 2;
    DrawLevel("Yearly_Mid", yearlyh_time, limit_right, yearlym_open, cymtext, GetColor(YearlyColor));
  }

  // Draw Session levels
  if (is_londonrange_enabled && flondonhigh > 0)
  {
    DrawLevel("London_High", londontime, limit_right, flondonhigh, lhtext, GetColor(LondonColor));
    DrawLevel("London_Low", londontime, limit_right, flondonlow, lltext, GetColor(LondonColor));
    DrawLevel("London_Open", londontime, limit_right, flondonopen, lotext, GetColor(LondonColor));
  }

  if (is_usrange_enabled && fushigh > 0)
  {
    DrawLevel("US_High", ustime, limit_right, fushigh, ushtext, GetColor(USColor));
    DrawLevel("US_Low", ustime, limit_right, fuslow, usltext, GetColor(USColor));
    DrawLevel("US_Open", ustime, limit_right, fusopen, usotext, GetColor(USColor));
  }

  if (is_asiarange_enabled && fasiahigh > 0)
  {
    DrawLevel("Asia_High", asiatime, limit_right, fasiahigh, asiahtext, GetColor(AsiaColor));
    DrawLevel("Asia_Low", asiatime, limit_right, fasialow, asialtext, GetColor(AsiaColor));
    DrawLevel("Asia_Open", asiatime, limit_right, fasiaopen, asiaotext, GetColor(AsiaColor));
  }
}

//+------------------------------------------------------------------+
//| Draw a single level                                              |
//+------------------------------------------------------------------+
void DrawLevel(string name, datetime time_start, datetime time_end, double price, string text, color clr)
{
  string line_name = "KeyLevel_Line_" + name;
  string label_name = "KeyLevel_Label_" + name;

  // Draw trend line
  ObjectCreate(0, line_name, OBJ_TREND, 0, time_start, price, time_end, price);
  ObjectSetInteger(0, line_name, OBJPROP_COLOR, clr);
  ObjectSetInteger(0, line_name, OBJPROP_WIDTH, DEFAULT_LINE_WIDTH);
  ObjectSetInteger(0, line_name, OBJPROP_STYLE, GetLineStyle());
  ObjectSetInteger(0, line_name, OBJPROP_RAY_RIGHT, false);
  ObjectSetInteger(0, line_name, OBJPROP_BACK, true);

  // Draw label
  ObjectCreate(0, label_name, OBJ_TEXT, 0, time_end, price);
  ObjectSetString(0, label_name, OBJPROP_TEXT, text);
  ObjectSetInteger(0, label_name, OBJPROP_COLOR, clr);
  ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, GetFontSize());
  ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, ANCHOR_LEFT);
}

//+------------------------------------------------------------------+
//| Get color based on global coloring setting                      |
//+------------------------------------------------------------------+
color GetColor(color original_color)
{
  return globalcoloring ? GlobalColor : original_color;
}

//+------------------------------------------------------------------+
//| Get line style                                                   |
//+------------------------------------------------------------------+
int GetLineStyle()
{
  switch (linestyle)
  {
  case LINE_SOLID_CUSTOM:
    return STYLE_SOLID;
  case LINE_DASHED_CUSTOM:
    return STYLE_DASH;
  case LINE_DOTTED_CUSTOM:
    return STYLE_DOT;
  default:
    return STYLE_SOLID;
  }
}

//+------------------------------------------------------------------+
//| Get font size                                                    |
//+------------------------------------------------------------------+
int GetFontSize()
{
  switch (labelsize)
  {
  case TEXT_SMALL:
    return 8;
  case TEXT_MEDIUM:
    return 10;
  case TEXT_LARGE:
    return 12;
  default:
    return 10;
  }
}

//+------------------------------------------------------------------+
//| Get quarterly time                                               |
//+------------------------------------------------------------------+
datetime GetQuarterlyTime(int shift)
{
  MqlDateTime dt;
  TimeToStruct(TimeCurrent(), dt);

  // Calculate quarter start
  int quarter = (dt.mon - 1) / 3;
  dt.mon = quarter * 3 + 1;
  dt.day = 1;
  dt.hour = 0;
  dt.min = 0;
  dt.sec = 0;

  if (shift > 0)
  {
    if (quarter == 0)
    {
      dt.year--;
      dt.mon = 10; // October (Q4 of previous year)
    }
    else
    {
      dt.mon = (quarter - 1) * 3 + 1;
    }
  }

  return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Get quarterly open                                               |
//+------------------------------------------------------------------+
double GetQuarterlyOpen(int shift)
{
  datetime q_time = GetQuarterlyTime(shift);
  int q_shift = iBarShift(Symbol(), PERIOD_D1, q_time);
  return iOpen(Symbol(), PERIOD_D1, q_shift);
}

//+------------------------------------------------------------------+
//| Get quarterly high                                               |
//+------------------------------------------------------------------+
double GetQuarterlyHigh(int shift)
{
  datetime q_start = GetQuarterlyTime(shift);
  datetime q_end = GetQuarterlyTime(shift - 1);

  double high_val = 0;
  int start_shift = iBarShift(Symbol(), PERIOD_D1, q_start);
  int end_shift = iBarShift(Symbol(), PERIOD_D1, q_end);

  for (int i = end_shift; i <= start_shift; i++)
  {
    double h = iHigh(Symbol(), PERIOD_D1, i);
    if (h > high_val)
      high_val = h;
  }

  return high_val;
}

//+------------------------------------------------------------------+
//| Get quarterly low                                                |
//+------------------------------------------------------------------+
double GetQuarterlyLow(int shift)
{
  datetime q_start = GetQuarterlyTime(shift);
  datetime q_end = GetQuarterlyTime(shift - 1);

  double low_val = DBL_MAX;
  int start_shift = iBarShift(Symbol(), PERIOD_D1, q_start);
  int end_shift = iBarShift(Symbol(), PERIOD_D1, q_end);

  for (int i = end_shift; i <= start_shift; i++)
  {
    double l = iLow(Symbol(), PERIOD_D1, i);
    if (l < low_val)
      low_val = l;
  }

  return low_val;
}

//+------------------------------------------------------------------+
//| Get yearly time                                                  |
//+------------------------------------------------------------------+
datetime GetYearlyTime(int shift)
{
  MqlDateTime dt;
  TimeToStruct(TimeCurrent(), dt);

  dt.year -= shift;
  dt.mon = 1;
  dt.day = 1;
  dt.hour = 0;
  dt.min = 0;
  dt.sec = 0;

  return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Get yearly open                                                  |
//+------------------------------------------------------------------+
double GetYearlyOpen(int shift)
{
  datetime y_time = GetYearlyTime(shift);
  int y_shift = iBarShift(Symbol(), PERIOD_D1, y_time);
  return iOpen(Symbol(), PERIOD_D1, y_shift);
}

//+------------------------------------------------------------------+
//| Get yearly high                                                  |
//+------------------------------------------------------------------+
double GetYearlyHigh(int shift)
{
  datetime y_start = GetYearlyTime(shift);
  datetime y_end = (shift == 0) ? TimeCurrent() : GetYearlyTime(shift - 1);

  double high_val = 0;
  int start_shift = iBarShift(Symbol(), PERIOD_D1, y_start);
  int end_shift = iBarShift(Symbol(), PERIOD_D1, y_end);

  for (int i = end_shift; i <= start_shift; i++)
  {
    double h = iHigh(Symbol(), PERIOD_D1, i);
    if (h > high_val)
      high_val = h;
  }

  return high_val;
}

//+------------------------------------------------------------------+
//| Get yearly low                                                   |
//+------------------------------------------------------------------+
double GetYearlyLow(int shift)
{
  datetime y_start = GetYearlyTime(shift);
  datetime y_end = (shift == 0) ? TimeCurrent() : GetYearlyTime(shift - 1);

  double low_val = DBL_MAX;
  int start_shift = iBarShift(Symbol(), PERIOD_D1, y_start);
  int end_shift = iBarShift(Symbol(), PERIOD_D1, y_end);

  for (int i = end_shift; i <= start_shift; i++)
  {
    double l = iLow(Symbol(), PERIOD_D1, i);
    if (l < low_val)
      low_val = l;
  }

  return low_val;
}
