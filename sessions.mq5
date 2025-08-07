
﻿ //+------------------------------------------------------------------+
//|                                              Market_Sessions.mq5 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                                 https://mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2018, MetaQuotes Software Corp."
#property link "https://mql5.com"
#property version "1.00"
#property description "Market Sessions indicator"
#property description "Highlights the Forex Market Sessions"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots 4
//--- plot Sidney
#property indicator_label1 "Sidney"
#property indicator_type1 DRAW_FILLING
#property indicator_color1 clrOrange, clrOrange
#property indicator_style1 STYLE_SOLID
#property indicator_width1 1
//--- plot Tokio
#property indicator_label2 "Tokio"
#property indicator_type2 DRAW_FILLING
#property indicator_color2 clrOrangeRed, clrOrangeRed
#property indicator_style2 STYLE_SOLID
#property indicator_width2 1
//--- plot London
#property indicator_label3 "London"
#property indicator_type3 DRAW_FILLING
#property indicator_color3 clrMediumSeaGreen, clrMediumSeaGreen
#property indicator_style3 STYLE_SOLID
#property indicator_width3 1
//--- plot NewYork
#property indicator_label4 "NewYork"
#property indicator_type4 DRAW_FILLING
#property indicator_color4 clrSkyBlue, clrSkyBlue
#property indicator_style4 STYLE_SOLID
#property indicator_width4 1
    //--- enums
    enum ENUM_INPUT_YES_NO {
      INPUT_YES = 1, // Yes
      INPUT_NO = 0   // No
    };
//---
enum ENUM_SESSIONS
{
  SESSION_SIDNEY,
  SESSION_TOKIO,
  SESSION_LONDON,
  SESSION_NEW_YORK
};
//--- input parameters
input uint InpStartSidney = 0;          // Sidney session begin
input uint InpEndSidney = 9;            // Sidney session end
input color InpColorSidney = clrOrange; // Sidney session color

input uint InpStartTokio = 2;             // Tokio session begin
input uint InpEndTokio = 11;              // Tokio session end
input color InpColorTokio = clrOrangeRed; // Tokio session color

input uint InpStartLondon = 10;                 // London session begin
input uint InpEndLondon = 19;                   // London session end
input color InpColorLondon = clrMediumSeaGreen; // London session color

input uint InpStartNewYork = 15;          // NewYork session begin
input uint InpEndNewYork = 0;             // NewYork session end
input color InpColorNewYork = clrSkyBlue; // NewYork session color

input uchar InpWidth = 60;                         // Session field height
input ENUM_INPUT_YES_NO InpShowLabels = INPUT_YES; // Show session labels
input string InpFontName = "Calibri";              // Font name
input uchar InpFontSize = 8;                       // Font size
input color InpFontColor = clrNavy;                // Font color
input ENUM_INPUT_YES_NO InpShowVLines = INPUT_YES; // Show start-session lines
//--- indicator buffers
double BufferSidney1[];
double BufferSidney2[];
double BufferTokio1[];
double BufferTokio2[];
double BufferLondon1[];
double BufferLondon2[];
double BufferNewYork1[];
double BufferNewYork2[];
//--- global variables
string prefix;
int start_sidney;
int end_sidney;
int start_tokio;
int end_tokio;
int start_london;
int end_london;
int start_new_york;
int end_new_york;
int width;
int font_size;
bool prev_fgnd;
//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
  //--- timer
  EventSetTimer(90);
  //--- set global variables
  prefix = MQLInfoString(MQL_PROGRAM_NAME) + "_";
  start_sidney = int(InpStartSidney >= 24 ? 0 : InpStartSidney);
  end_sidney = int(InpEndSidney >= 24 ? 0 : InpEndSidney);
  start_tokio = int(InpStartTokio >= 24 ? 0 : InpStartTokio);
  end_tokio = int(InpEndTokio >= 24 ? 0 : InpEndTokio);
  start_london = int(InpStartLondon >= 24 ? 0 : InpStartLondon);
  end_london = int(InpEndLondon >= 24 ? 0 : InpEndLondon);
  start_new_york = int(InpStartNewYork >= 24 ? 0 : InpStartNewYork);
  end_new_york = int(InpEndNewYork >= 24 ? 0 : InpEndNewYork);
  width = int(InpWidth < 1 ? 1 : InpWidth);
  font_size = int(InpFontSize < 5 ? 5 : InpFontSize);
  if (Period() > PERIOD_H1)
  {
    Alert("This indicator works only on H1 charts and lower");
    ChartSetSymbolPeriod(0, NULL, PERIOD_H1);
  }
  prev_fgnd = ChartGetInteger(0, CHART_FOREGROUND);
  ChartSetInteger(0, CHART_FOREGROUND, false);
  ChartRedraw();
  //--- indicator buffers mapping
  SetIndexBuffer(0, BufferSidney1, INDICATOR_DATA);
  SetIndexBuffer(1, BufferSidney2, INDICATOR_DATA);
  SetIndexBuffer(2, BufferTokio1, INDICATOR_DATA);
  SetIndexBuffer(3, BufferTokio2, INDICATOR_DATA);
  SetIndexBuffer(4, BufferLondon1, INDICATOR_DATA);
  SetIndexBuffer(5, BufferLondon2, INDICATOR_DATA);
  SetIndexBuffer(6, BufferNewYork1, INDICATOR_DATA);
  SetIndexBuffer(7, BufferNewYork2, INDICATOR_DATA);
  //--- setting indicator parameters
  IndicatorSetString(INDICATOR_SHORTNAME, "Market Sessions");
  IndicatorSetInteger(INDICATOR_DIGITS, Digits());
  //--- setting plot buffer parameters
  PlotIndexSetString(0, PLOT_LABEL, "Sidney session;  from " + (string)start_sidney + " to " + (string)end_sidney);
  PlotIndexSetString(1, PLOT_LABEL, "Tokio session;  from " + (string)start_tokio + " to " + (string)end_tokio);
  PlotIndexSetString(2, PLOT_LABEL, "London session;  from " + (string)start_london + " to " + (string)end_london);
  PlotIndexSetString(3, PLOT_LABEL, "NewYork session;  from " + (string)start_new_york + " to " + (string)end_new_york);
  PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
  PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
  PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
  PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
  PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, InpColorSidney);
  PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, InpColorSidney);
  PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0, InpColorTokio);
  PlotIndexSetInteger(1, PLOT_LINE_COLOR, 1, InpColorTokio);
  PlotIndexSetInteger(2, PLOT_LINE_COLOR, 0, InpColorLondon);
  PlotIndexSetInteger(2, PLOT_LINE_COLOR, 1, InpColorLondon);
  PlotIndexSetInteger(3, PLOT_LINE_COLOR, 0, InpColorNewYork);
  PlotIndexSetInteger(3, PLOT_LINE_COLOR, 1, InpColorNewYork);
  //--- setting buffer arrays as timeseries
  ArraySetAsSeries(BufferSidney1, true);
  ArraySetAsSeries(BufferSidney2, true);
  ArraySetAsSeries(BufferTokio1, true);
  ArraySetAsSeries(BufferTokio2, true);
  ArraySetAsSeries(BufferLondon1, true);
  ArraySetAsSeries(BufferLondon2, true);
  ArraySetAsSeries(BufferNewYork1, true);
  ArraySetAsSeries(BufferNewYork2, true);
  //--- get timeframe
  Time(NULL, PERIOD_D1, 1);
  //---
  return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  //--- set last foreground flag
  ChartSetInteger(0, CHART_FOREGROUND, prev_fgnd);
  //--- delete objects
  ObjectsDeleteAll(0, prefix);
  ChartRedraw();
  //---
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
  //--- Set buffer arrays as time series
  ArraySetAsSeries(high, true);
  ArraySetAsSeries(low, true);
  ArraySetAsSeries(close, true);
  ArraySetAsSeries(time, true);
  //--- Check the number of available bars
  if (rates_total < 24)
    return 0;
  if (Time(NULL, PERIOD_D1, 1) == 0)
    return 0;
  //--- Check and calculate the number of bars to process
  int limit = rates_total - prev_calculated;
  if (limit > 1)
  {
    limit = rates_total - 1;
    ArrayInitialize(BufferSidney1, 0);
    ArrayInitialize(BufferSidney2, 0);
    ArrayInitialize(BufferTokio1, 0);
    ArrayInitialize(BufferTokio2, 0);
    ArrayInitialize(BufferLondon1, 0);
    ArrayInitialize(BufferLondon2, 0);
    ArrayInitialize(BufferNewYork1, 0);
    ArrayInitialize(BufferNewYork2, 0);
  }

  //--- Indicator calculation
  for (int i = limit; i >= 0 && !IsStopped(); i--)
  {
    Initialize(i);
    if (IsTradeTime(time[i], start_sidney, 0, end_sidney, 0))
      Calculations(i, time, start_sidney, BufferSidney1, BufferSidney2, SESSION_SIDNEY);
    if (IsTradeTime(time[i], start_tokio, 0, end_tokio, 0))
      Calculations(i, time, start_tokio, BufferTokio1, BufferTokio2, SESSION_TOKIO);
    if (IsTradeTime(time[i], start_london, 0, end_london, 0))
      Calculations(i, time, start_london, BufferLondon1, BufferLondon2, SESSION_LONDON);
    if (IsTradeTime(time[i], start_new_york, 0, end_new_york, 0))
      Calculations(i, time, start_new_york, BufferNewYork1, BufferNewYork2, SESSION_NEW_YORK);
  }

  //--- return value of prev_calculated for next call
  return (rates_total);
}
//+------------------------------------------------------------------+
//| Custom indicator timer function                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
  Time(NULL, PERIOD_D1, 1);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Initialize(const int shift)
{
  BufferLondon1[shift] = BufferLondon2[shift] = BufferNewYork1[shift] = BufferNewYork2[shift] = BufferSidney1[shift] = BufferSidney2[shift] = BufferTokio1[shift] = BufferTokio2[shift] = 0;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Calculations(const int shift, const datetime &time[], const int hour_start, double &buffer1[], double &buffer2[], ENUM_SESSIONS session)
{
  int bar = BarShift(NULL, PERIOD_D1, time[shift]);
  if (bar == WRONG_VALUE)
    return;
  double p1 = High(NULL, PERIOD_D1, bar);
  if (p1 == 0)
    return;
  buffer1[shift] = p1 - ((width + 4) * (int)session) * Point();
  buffer2[shift] = buffer1[shift] - width * Point();
  if (TimeHour(time[shift]) == hour_start && TimeMinute(time[shift]) == 0)
  {
    if (InpShowLabels)
    {
      string text = " NewYork";
      string end = "NY";
      string tooltip = "NewYork session time:\nfrom " + IntegerToString(start_new_york, 2, '0') + ":00 to " + IntegerToString(end_new_york, 2, '0') + ":00";
      if (session == SESSION_SIDNEY)
      {
        text = " Sidney";
        end = "SD";
        tooltip = "Sidney session time:\nfrom " + IntegerToString(start_sidney, 2, '0') + ":00 to " + IntegerToString(end_sidney, 2, '0') + ":00";
      }
      else if (session == SESSION_TOKIO)
      {
        text = " Tokio";
        end = "TK";
        tooltip = "Tokio session time:\nfrom " + IntegerToString(start_tokio, 2, '0') + ":00 to " + IntegerToString(end_tokio, 2, '0') + ":00";
      }
      else if (session == SESSION_LONDON)
      {
        text = " London";
        end = "LD";
        tooltip = "London session time:\nfrom " + IntegerToString(start_london, 2, '0') + ":00 to " + IntegerToString(end_london, 2, '0') + ":00";
      }
      string name = prefix + TimeToString(time[shift]) + end;
      DrawLabel(name, text, tooltip, time[shift], buffer1[shift], InpFontColor);
    }
    if (InpShowVLines)
    {
      color clr = InpColorNewYork;
      string text = " NewYork";
      string end = "NY_VL";
      string tooltip = " NewYork session time from " + IntegerToString(start_new_york, 2, '0') + ":00 to " + IntegerToString(end_new_york, 2, '0') + ":00";
      if (session == SESSION_SIDNEY)
      {
        clr = InpColorSidney;
        text = " Sidney";
        end = "SD_VL";
        tooltip = " Sidney session time from " + IntegerToString(start_sidney, 2, '0') + ":00 to " + IntegerToString(end_sidney, 2, '0') + ":00";
      }
      else if (session == SESSION_TOKIO)
      {
        clr = InpColorTokio;
        text = " Tokio";
        end = "TK_VL";
        tooltip = " Tokio session time from " + IntegerToString(start_tokio, 2, '0') + ":00 to " + IntegerToString(end_tokio, 2, '0') + ":00";
      }
      else if (session == SESSION_LONDON)
      {
        clr = InpColorLondon;
        text = " London";
        end = "LD_VL";
        tooltip = " London session time from " + IntegerToString(start_london, 2, '0') + ":00 to " + IntegerToString(end_london, 2, '0') + ":00";
      }
      string name = prefix + TimeToString(time[shift]) + end;
      DrawLine(name, text, tooltip, time[shift], clr);
    }
  }
}
//+------------------------------------------------------------------+
//| returns a flag for trade permission by time                      |
//+------------------------------------------------------------------+
bool IsTradeTime(const datetime time_current, const int hour_begin = 0, const int minutes_begin = 0, const int hour_end = 0, const int minutes_end = 0)
{
  MqlDateTime tmb, tme;
  datetime tradetime_begin;
  datetime tradetime_end;
  int current_serv_hour;
  TimeToStruct(time_current, tmb);
  current_serv_hour = tmb.hour;
  TimeToStruct(time_current, tme);
  tmb.hour = hour_begin;
  tmb.min = minutes_begin;
  tme.hour = hour_end;
  tme.min = minutes_end;
  tradetime_begin = StructToTime(tmb);
  tradetime_end = StructToTime(tme);
  if (tradetime_begin >= tradetime_end)
  {
    if (current_serv_hour >= hour_end)
      tradetime_end += 24 * PeriodSeconds(PERIOD_H1);
    else
      tradetime_begin -= 24 * PeriodSeconds(PERIOD_H1);
  }
  return (time_current >= tradetime_begin && time_current <= tradetime_end);
}
//+------------------------------------------------------------------+
//| Returns bar shift by time                                        |
//| https://www.mql5.com/ru/forum/743/page11#comment_7010041         |
//+------------------------------------------------------------------+
int BarShift(const string symbol_name, const ENUM_TIMEFRAMES timeframe, const datetime time, bool exact = false)
{
  int res = Bars(symbol_name, timeframe, time + 1, UINT_MAX);
  if (exact)
    if ((timeframe != PERIOD_MN1 || time > TimeCurrent()) && res == Bars(symbol_name, timeframe, time - PeriodSeconds(timeframe) + 1, UINT_MAX))
      return (WRONG_VALUE);
  return res;
}
//+------------------------------------------------------------------+
//| Returns High                                                     |
//+------------------------------------------------------------------+
double High(const string symbol_name, const ENUM_TIMEFRAMES timeframe, const int shift)
{
  double array[];
  ArraySetAsSeries(array, true);
  return (CopyHigh(symbol_name, timeframe, shift, 1, array) == 1 ? array[0] : 0);
}
//+------------------------------------------------------------------+
//| Returns Time                                                     |
//+------------------------------------------------------------------+
datetime Time(const string symbol_name, const ENUM_TIMEFRAMES timeframe, const int shift)
{
  datetime array[];
  ArraySetAsSeries(array, true);
  return (CopyTime(symbol_name, timeframe, shift, 1, array) == 1 ? array[0] : 0);
}
//+------------------------------------------------------------------+
//| Returns the hour of the specified time                           |
//+------------------------------------------------------------------+
int TimeHour(const datetime time)
{
  MqlDateTime tm;
  if (!TimeToStruct(time, tm))
    return WRONG_VALUE;
  return tm.hour;
}
//+------------------------------------------------------------------+
//| Returns the minute of the specified time                         |
//+------------------------------------------------------------------+
int TimeMinute(const datetime time)
{
  MqlDateTime tm;
  if (!TimeToStruct(time, tm))
    return WRONG_VALUE;
  return tm.min;
}
//+------------------------------------------------------------------+
//| Draw label                                                       |
//+------------------------------------------------------------------+
void DrawLabel(const string name, const string text, const string tooltip, const datetime time, const double price, const color text_color)
{
  if (ObjectFind(0, name) < 0)
  {
    ObjectCreate(0, name, OBJ_TEXT, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
    ObjectSetString(0, name, OBJPROP_FONT, InpFontName);
  }
  ObjectSetInteger(0, name, OBJPROP_TIME, 0, time);
  ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price - (width / 2) * Point());
  ObjectSetString(0, name, OBJPROP_TEXT, text);
  ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}
//+------------------------------------------------------------------+
//| Draw line                                                        |
//+------------------------------------------------------------------+
void DrawLine(const string name, const string text, const string tooltip, const datetime time, const color line_color)
{
  if (ObjectFind(0, name) < 0)
  {
    ObjectCreate(0, name, OBJ_VLINE, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, name, OBJPROP_RAY, false);
  }
  ObjectSetInteger(0, name, OBJPROP_TIME, time);
  ObjectSetString(0, name, OBJPROP_TEXT, text);
  ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}
//+------------------------------------------------------------------+
