//+------------------------------------------------------------------+
//|                           ORBPlusVolumeConfirmation-kasutufx.mq5 |
//|                                                         kasutufx |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "kasutufx"
#property link "https://www.mql5.com"
#property version "1.00"

enum ENUM_SL_METHOD
{
  SL_ORB_HALF_RANGE
};

//--- Input parameters
input double min_lot_size = 0.01;
input int magic_number = 12345;
input double volume_multiplier = 1.065;
input ENUM_SL_METHOD sl_method = SL_ORB_HALF_RANGE;
input double sl_tolerance_price = 0.0003;
input int orb_start_hour = 5;
input int orb_start_minute = 0;
input int orb_end_hour = 5;
input int orb_end_minute = 30;
input int trade_window_limit_hour = 9;
input double profit_multiplier = 6.0;
input bool use_ema_confirmation = true;
input bool use_cvd_confirmation = true;
input int cvd_lookback_periods = 10;
input bool use_cmi_filter = true;
input int cmi_period = 14;
input double cmi_threshold = 70.0;
input bool draw_indicators = true;
input bool draw_ema_lines = true;
input bool draw_cmi_histogram = true;
input bool draw_cvd_line = true;

//+------------------------------------------------------------------+
//| Choppy Market Index Analyzer Class                              |
//+------------------------------------------------------------------+
class CCMIAnalyzer
{
private:
  double m_cmi_values[];

public:
  CCMIAnalyzer()
  {
    ArrayResize(m_cmi_values, cmi_period + 5);
  }

  bool IsMarketChoppy()
  {
    if (!CalculateCMI())
      return false;

    double current_cmi = m_cmi_values[0];
    bool is_choppy = current_cmi > cmi_threshold;

    if (is_choppy)
      Print("Market choppy - CMI: ", DoubleToString(current_cmi, 2), " > ", cmi_threshold);
    else
      Print("Market trending - CMI: ", DoubleToString(current_cmi, 2));

    return is_choppy;
  }

  double GetCurrentCMI()
  {
    if (!CalculateCMI())
      return 0.0;
    return m_cmi_values[0];
  }

private:
  bool CalculateCMI()
  {
    double highs[], lows[], closes[];
    int bars_needed = cmi_period + 5;

    ArrayResize(highs, bars_needed);
    ArrayResize(lows, bars_needed);
    ArrayResize(closes, bars_needed);

    if (CopyHigh(Symbol(), PERIOD_M5, 0, bars_needed, highs) <= 0 ||
        CopyLow(Symbol(), PERIOD_M5, 0, bars_needed, lows) <= 0 ||
        CopyClose(Symbol(), PERIOD_M5, 0, bars_needed, closes) <= 0)
      return false;

    for (int i = 0; i < bars_needed - cmi_period; i++)
    {
      m_cmi_values[i] = CalculateCMIValue(highs, lows, closes, i, cmi_period);
    }

    return true;
  }

  double CalculateCMIValue(const double &highs[], const double &lows[], const double &closes[], int start_idx, int period)
  {
    double sum_abs_moves = 0.0;

    for (int i = start_idx; i < start_idx + period - 1; i++)
    {
      sum_abs_moves += MathAbs(closes[i] - closes[i + 1]);
    }

    double highest_high = highs[ArrayMaximum(highs, start_idx, period)];
    double lowest_low = lows[ArrayMinimum(lows, start_idx, period)];
    double net_movement = highest_high - lowest_low;

    if (net_movement == 0.0)
      return 100.0;

    double cmi = (sum_abs_moves / net_movement) * 100.0;
    return MathMin(cmi, 100.0);
  }
};

//+------------------------------------------------------------------+
//| EMA Analyzer Class                                               |
//+------------------------------------------------------------------+
class CEMAAnalyzer
{
private:
  int m_ema50_handle, m_ema200_handle;

public:
  CEMAAnalyzer()
  {
    m_ema50_handle = iMA(Symbol(), PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
    m_ema200_handle = iMA(Symbol(), PERIOD_M5, 200, 0, MODE_EMA, PRICE_CLOSE);
  }

  ~CEMAAnalyzer()
  {
    if (m_ema50_handle != INVALID_HANDLE)
      IndicatorRelease(m_ema50_handle);
    if (m_ema200_handle != INVALID_HANDLE)
      IndicatorRelease(m_ema200_handle);
  }

  bool IsBullishCrossing()
  {
    if (!IsValidHandles())
      return false;

    double ema50[2], ema200[2];
    if (!CopyEMAValues(ema50, ema200))
      return false;

    bool bullish_cross = (ema50[1] > ema200[1]) && (ema50[0] <= ema200[0]);

    if (bullish_cross)
      Print("EMA Bull cross: 50 > 200");

    return bullish_cross;
  }

  bool IsBearishCrossing()
  {
    if (!IsValidHandles())
      return false;

    double ema50[2], ema200[2];
    if (!CopyEMAValues(ema50, ema200))
      return false;

    bool bearish_cross = (ema50[1] < ema200[1]) && (ema50[0] >= ema200[0]);

    if (bearish_cross)
      Print("EMA Bear cross: 50 < 200");

    return bearish_cross;
  }

  bool IsBullishAlignment()
  {
    if (!IsValidHandles())
      return false;

    double ema50[1], ema200[1];
    if (CopyBuffer(m_ema50_handle, 0, 1, 1, ema50) <= 0 ||
        CopyBuffer(m_ema200_handle, 0, 1, 1, ema200) <= 0)
      return false;

    return ema50[0] > ema200[0];
  }

  bool GetCurrentEMAValues(double &ema50_value, double &ema200_value)
  {
    if (!IsValidHandles())
      return false;

    double ema50[1], ema200[1];
    if (CopyBuffer(m_ema50_handle, 0, 1, 1, ema50) <= 0 ||
        CopyBuffer(m_ema200_handle, 0, 1, 1, ema200) <= 0)
      return false;

    ema50_value = ema50[0];
    ema200_value = ema200[0];
    return true;
  }

private:
  bool IsValidHandles()
  {
    return (m_ema50_handle != INVALID_HANDLE && m_ema200_handle != INVALID_HANDLE);
  }

  bool CopyEMAValues(double &ema50[], double &ema200[])
  {
    return (CopyBuffer(m_ema50_handle, 0, 0, 2, ema50) > 0 &&
            CopyBuffer(m_ema200_handle, 0, 0, 2, ema200) > 0);
  }
};

//+------------------------------------------------------------------+
//| CVD Analyzer Class                                               |
//+------------------------------------------------------------------+
class CCVDAnalyzer
{
private:
  double m_cvd_values[];
  double m_price_values[];

public:
  CCVDAnalyzer()
  {
    ArrayResize(m_cvd_values, cvd_lookback_periods + 5);
    ArrayResize(m_price_values, cvd_lookback_periods + 5);
  }

  bool UpdateCVD()
  {
    long volumes[];
    double closes[], highs[], lows[];
    int bars_needed = cvd_lookback_periods + 5;

    ArrayResize(volumes, bars_needed);
    ArrayResize(closes, bars_needed);
    ArrayResize(highs, bars_needed);
    ArrayResize(lows, bars_needed);

    if (CopyTickVolume(Symbol(), PERIOD_M5, 1, bars_needed, volumes) <= 0 ||
        CopyClose(Symbol(), PERIOD_M5, 1, bars_needed, closes) <= 0 ||
        CopyHigh(Symbol(), PERIOD_M5, 1, bars_needed, highs) <= 0 ||
        CopyLow(Symbol(), PERIOD_M5, 1, bars_needed, lows) <= 0)
      return false;

    double cumulative_delta = 0;
    for (int i = 0; i < bars_needed; i++)
    {
      double midpoint = (highs[i] + lows[i]) / 2.0;
      double delta = (closes[i] > midpoint) ? volumes[i] : -volumes[i];
      cumulative_delta += delta;

      m_cvd_values[i] = cumulative_delta;
      m_price_values[i] = closes[i];
    }

    return true;
  }

  bool IsBullishDivergence()
  {
    if (!UpdateCVD())
      return false;

    int recent_idx = cvd_lookback_periods;
    double recent_price_low = m_price_values[recent_idx];
    double recent_cvd_at_price_low = m_cvd_values[recent_idx];
    double prev_price_low = recent_price_low;
    double prev_cvd_at_price_low = recent_cvd_at_price_low;

    for (int i = recent_idx - cvd_lookback_periods; i < recent_idx; i++)
    {
      if (m_price_values[i] < prev_price_low)
      {
        prev_price_low = m_price_values[i];
        prev_cvd_at_price_low = m_cvd_values[i];
      }
    }

    bool divergence = (recent_price_low < prev_price_low) &&
                      (recent_cvd_at_price_low > prev_cvd_at_price_low);

    if (divergence)
      Print("CVD Bull divergence detected");

    return divergence;
  }

  bool IsBearishDivergence()
  {
    if (!UpdateCVD())
      return false;

    int recent_idx = cvd_lookback_periods;
    double recent_price_high = m_price_values[recent_idx];
    double recent_cvd_at_price_high = m_cvd_values[recent_idx];
    double prev_price_high = recent_price_high;
    double prev_cvd_at_price_high = recent_cvd_at_price_high;

    for (int i = recent_idx - cvd_lookback_periods; i < recent_idx; i++)
    {
      if (m_price_values[i] > prev_price_high)
      {
        prev_price_high = m_price_values[i];
        prev_cvd_at_price_high = m_cvd_values[i];
      }
    }

    bool divergence = (recent_price_high > prev_price_high) &&
                      (recent_cvd_at_price_high < prev_cvd_at_price_high);

    if (divergence)
      Print("CVD Bear divergence detected");

    return divergence;
  }

  double GetCurrentCVD()
  {
    if (!UpdateCVD())
      return 0.0;
    return m_cvd_values[0];
  }
};

//+------------------------------------------------------------------+
//| Time Manager Class                                               |
//+------------------------------------------------------------------+
class CTimeManager
{
private:
  datetime m_last_reset_time;

public:
  CTimeManager() : m_last_reset_time(0) {}

  datetime GetNYTime() { return TimeGMT() - 5 * 3600; }

  bool IsORBWindow(const MqlDateTime &ny_struct)
  {
    return (ny_struct.hour > orb_end_hour) ||
           (ny_struct.hour == orb_end_hour && ny_struct.min >= orb_end_minute);
  }

  bool IsTradingWindow(const MqlDateTime &ny_struct)
  {
    return IsORBWindow(ny_struct) && (ny_struct.hour < trade_window_limit_hour);
  }

  bool ShouldReset(const MqlDateTime &ny_struct)
  {
    if ((ny_struct.hour == 17 && ny_struct.min == 0) ||
        (ny_struct.hour == orb_start_hour && ny_struct.min == orb_start_minute))
    {
      datetime current_date = (GetNYTime() / 86400) * 86400;
      if (m_last_reset_time != current_date)
      {
        m_last_reset_time = current_date;
        return true;
      }
    }
    return false;
  }
};

//+------------------------------------------------------------------+
//| ORB Calculator Class                                             |
//+------------------------------------------------------------------+
class CORBCalculator
{
private:
  double m_orb_high, m_orb_low, m_tp3_bull, m_tp3_bear;
  bool m_calculated;

public:
  CORBCalculator() : m_orb_high(0), m_orb_low(0), m_tp3_bull(0), m_tp3_bear(0), m_calculated(false) {}

  void Reset()
  {
    m_orb_high = m_orb_low = m_tp3_bull = m_tp3_bear = 0;
    m_calculated = false;
  }

  bool Calculate()
  {
    datetime gmt_start = GetGMTSessionTime(orb_start_hour, orb_start_minute);
    datetime gmt_end = GetGMTSessionTime(orb_end_hour, orb_end_minute);

    int bars = Bars(Symbol(), PERIOD_M5, gmt_start, gmt_end);
    if (bars < 1)
      return false;

    double high_prices[], low_prices[];
    if (!CopyPriceData(gmt_start, bars, high_prices, low_prices))
      return false;

    m_orb_high = high_prices[ArrayMaximum(high_prices)];
    m_orb_low = low_prices[ArrayMinimum(low_prices)];

    double range = m_orb_high - m_orb_low;
    m_tp3_bull = m_orb_high + range * profit_multiplier;
    m_tp3_bear = m_orb_low - range * profit_multiplier;

    m_calculated = true;
    Print("ORB: ", m_orb_high, "-", m_orb_low, " | TP3: ", m_tp3_bull, "/", m_tp3_bear);
    return true;
  }

  double GetHigh() const { return m_orb_high; }
  double GetLow() const { return m_orb_low; }
  double GetTP3Bull() const { return m_tp3_bull; }
  double GetTP3Bear() const { return m_tp3_bear; }
  bool IsCalculated() const { return m_calculated; }

private:
  datetime GetGMTSessionTime(int hour, int minute)
  {
    MqlDateTime ny_struct;
    TimeToStruct(CTimeManager().GetNYTime(), ny_struct);
    ny_struct.hour = hour;
    ny_struct.min = minute;
    ny_struct.sec = 0;
    return StructToTime(ny_struct) + 5 * 3600;
  }

  bool CopyPriceData(datetime start_time, int bars, double &high_prices[], double &low_prices[])
  {
    ArrayResize(high_prices, bars);
    ArrayResize(low_prices, bars);
    return (CopyHigh(Symbol(), PERIOD_M5, start_time, bars, high_prices) > 0 &&
            CopyLow(Symbol(), PERIOD_M5, start_time, bars, low_prices) > 0);
  }
};

//+------------------------------------------------------------------+
//| Volume Analyzer Class                                            |
//+------------------------------------------------------------------+
class CVolumeAnalyzer
{
public:
  bool IsVolumeConfirmed()
  {
    long volumes[];
    ArrayResize(volumes, 1);
    if (CopyTickVolume(Symbol(), PERIOD_M5, 1, 1, volumes) <= 0)
      return false;

    double avg_volume = GetVolumeAverage();
    bool confirmed = (volumes[0] > avg_volume * volume_multiplier);

    if (!confirmed)
      Print("Vol insufficient: ", volumes[0], " | Req: ", avg_volume * volume_multiplier);
    else
      Print("Vol OK: ", volumes[0]);

    return confirmed;
  }

private:
  double GetVolumeAverage()
  {
    long volumes[20];
    int copied = CopyTickVolume(Symbol(), PERIOD_M5, 1, 20, volumes);
    if (copied <= 0)
      return 0;

    long total = 0;
    for (int i = 0; i < copied; i++)
      total += volumes[i];
    return (double)total / copied;
  }
};

//+------------------------------------------------------------------+
//| Position Manager Class                                           |
//+------------------------------------------------------------------+
class CPositionManager
{
private:
  bool m_active, m_is_long, m_tp3_reached, m_safety_applied;
  ulong m_ticket;
  double m_entry_price, m_volume;

public:
  CPositionManager() { Reset(); }

  void Reset()
  {
    m_active = m_is_long = m_tp3_reached = m_safety_applied = false;
    m_ticket = 0;
    m_entry_price = m_volume = 0;
  }

  bool IsActive() const { return m_active; }
  bool IsLong() const { return m_is_long; }
  double GetEntryPrice() const { return m_entry_price; }

  bool OpenPosition(bool is_long, double orb_high, double orb_low, double tp3_level)
  {
    if (m_active)
      return false;

    MqlTradeRequest req = {};
    MqlTradeResult res = {};

    double price = is_long ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double sl = CalculateSL(is_long, orb_high, orb_low);

    req.action = TRADE_ACTION_DEAL;
    req.symbol = Symbol();
    req.volume = CalculateLotSize();
    req.type = is_long ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    req.price = price;
    req.sl = sl;
    req.tp = tp3_level;
    req.magic = magic_number;
    req.comment = is_long ? "ORB Long" : "ORB Short";
    req.deviation = 3;
    req.type_filling = ORDER_FILLING_FOK;

    if (OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
    {
      m_active = true;
      m_is_long = is_long;
      m_ticket = res.deal;
      m_entry_price = price;
      m_volume = req.volume;

      Print((is_long ? "LONG" : "SHORT"), " opened | Entry: ", price, " | SL: ", sl, " | TP: ", tp3_level);
      return true;
    }

    Print("Order failed: ", res.retcode);
    return false;
  }

  bool CheckTP3(double tp3_bull, double tp3_bear)
  {
    if (m_tp3_reached)
      return false;

    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_LAST);

    if (!m_safety_applied && ShouldApplySafety(current_price))
    {
      MoveSLToProfit();
    }

    bool tp3_hit = (m_is_long && current_price >= tp3_bull) ||
                   (!m_is_long && current_price <= tp3_bear);

    if (tp3_hit)
    {
      m_tp3_reached = true;
      double pnl = CalculatePnL(current_price);
      Print("TP3 reached | P&L: $", DoubleToString(pnl, 2));
      return true;
    }

    return false;
  }

  bool CheckIfClosed()
  {
    if (!m_active)
      return false;

    for (int i = 0; i < PositionsTotal(); i++)
    {
      if (PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == magic_number)
        return false;
    }

    Print("Position closed");
    Reset();
    return true;
  }

  void CloseAll()
  {
    double total_pnl = 0;
    int closed = 0;

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
      if (PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == magic_number)
      {
        double close_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                            SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);

        total_pnl += CalculatePnL(close_price);

        MqlTradeRequest req = {};
        MqlTradeResult res = {};

        req.action = TRADE_ACTION_DEAL;
        req.symbol = PositionGetString(POSITION_SYMBOL);
        req.volume = PositionGetDouble(POSITION_VOLUME);
        req.price = close_price;
        req.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        req.position = PositionGetTicket(i);
        req.magic = magic_number;
        req.deviation = 3;
        req.type_filling = ORDER_FILLING_FOK;

        if (OrderSend(req, res))
          closed++;
      }
    }

    if (closed > 0)
    {
      Print("Closed ", closed, " positions | P&L: $", DoubleToString(total_pnl, 2));
      Reset();
    }
  }

private:
  double CalculateSL(bool is_long, double orb_high, double orb_low)
  {
    double midpoint = (orb_high + orb_low) / 2.0;
    return is_long ? midpoint - sl_tolerance_price : midpoint + sl_tolerance_price;
  }

  double CalculateLotSize()
  {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double lot = MathMax(min_lot_size, balance / 10000.0);
    double step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    return MathRound(lot / step) * step;
  }

  double CalculatePnL(double close_price)
  {
    if (m_entry_price == 0)
      return 0;

    double price_diff = m_is_long ? close_price - m_entry_price : m_entry_price - close_price;
    double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);

    return (price_diff / tick_size) * tick_value * m_volume;
  }

  bool ShouldApplySafety(double current_price)
  {
    double current_pnl = CalculatePnL(current_price);
    double current_sl = GetCurrentSL();
    if (current_sl <= 0)
      return false;

    double initial_risk = MathAbs(m_entry_price - current_sl);
    double risk_usd = (initial_risk / SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE)) *
                      SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE) * m_volume;

    return current_pnl >= (risk_usd * 1.5);
  }

  void MoveSLToProfit()
  {
    double current_sl = GetCurrentSL();
    if (current_sl <= 0)
      return;

    double initial_risk = MathAbs(m_entry_price - current_sl);
    double new_sl = m_is_long ? m_entry_price + (initial_risk * 0.1) : m_entry_price - (initial_risk * 0.1);

    if (ModifySL(new_sl))
    {
      m_safety_applied = true;
      Print("SL moved to profit lock: ", new_sl);
    }
  }

  double GetCurrentSL()
  {
    for (int i = 0; i < PositionsTotal(); i++)
    {
      if (PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == magic_number)
        return PositionGetDouble(POSITION_SL);
    }
    return 0;
  }

  bool ModifySL(double new_sl)
  {
    for (int i = 0; i < PositionsTotal(); i++)
    {
      if (PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == magic_number)
      {
        MqlTradeRequest req = {};
        MqlTradeResult res = {};

        req.action = TRADE_ACTION_SLTP;
        req.symbol = PositionGetString(POSITION_SYMBOL);
        req.position = PositionGetTicket(i);
        req.sl = new_sl;
        req.tp = PositionGetDouble(POSITION_TP);

        return OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE;
      }
    }
    return false;
  }
};

//+------------------------------------------------------------------+
//| Chart Info Panel Class                                           |
//+------------------------------------------------------------------+
class CInfoPanel
{
private:
  string m_panel_objects[15];
  int m_total_objects;

public:
  CInfoPanel()
  {
    m_total_objects = 0;
    InitializePanelObjects();
  }

  ~CInfoPanel()
  {
    DeletePanel();
  }

  void UpdatePanel(const CORBCalculator &orb_calc, const CVolumeAnalyzer &vol_analyzer,
                   const CEMAAnalyzer &ema_analyzer, const CCVDAnalyzer &cvd_analyzer,
                   const CCMIAnalyzer &cmi_analyzer, bool pos_mgr_active, bool pos_mgr_is_long, 
                   double pos_mgr_entry_price, bool trading_window_active, bool breakout_triggered)
  {
    DeletePanel();

    int y_offset = 20;
    int line_height = 18;
    color text_color = clrWhite;

    // Header
    CreateLabel("InfoPanel_Header", "=== ORB EA Status ===", 10, y_offset, clrYellow, 10);
    y_offset += line_height + 5;

    // Time and Session Info
    datetime ny_time = TimeGMT() - 5 * 3600;
    MqlDateTime ny_struct;
    TimeToStruct(ny_time, ny_struct);

    string time_info = StringFormat("NY Time: %02d:%02d", ny_struct.hour, ny_struct.min);
    CreateLabel("InfoPanel_Time", time_info, 10, y_offset, text_color, 8);
    y_offset += line_height;

    string session_status = trading_window_active ? "Trading Window: ACTIVE" : "Trading Window: CLOSED";
    color session_color = trading_window_active ? clrLime : clrGray;
    CreateLabel("InfoPanel_Session", session_status, 10, y_offset, session_color, 8);
    y_offset += line_height;

    // ORB Status
    if (orb_calc.IsCalculated())
    {
      string orb_info = StringFormat("ORB: %.5f - %.5f", orb_calc.GetHigh(), orb_calc.GetLow());
      CreateLabel("InfoPanel_ORB", orb_info, 10, y_offset, clrCyan, 8);
    }
    else
    {
      CreateLabel("InfoPanel_ORB", "ORB: Not Calculated", 10, y_offset, clrGray, 8);
    }
    y_offset += line_height;

    // Position Status
    if (pos_mgr_active)
    {
      string pos_type = pos_mgr_is_long ? "LONG" : "SHORT";
      string pos_info = StringFormat("Position: %s @ %.5f", pos_type, pos_mgr_entry_price);
      CreateLabel("InfoPanel_Position", pos_info, 10, y_offset, clrYellow, 8);
    }
    else
    {
      CreateLabel("InfoPanel_Position", "Position: None", 10, y_offset, clrGray, 8);
    }
    y_offset += line_height + 5;

    // Confirmation Status Header
    CreateLabel("InfoPanel_ConfHeader", "--- Confirmations ---", 10, y_offset, clrOrange, 9);
    y_offset += line_height;

    // Volume Confirmation
    long volumes[1];
    bool vol_ok = false;
    if (CopyTickVolume(Symbol(), PERIOD_M5, 1, 1, volumes) > 0)
    {
      long vol_avg[20];
      if (CopyTickVolume(Symbol(), PERIOD_M5, 1, 20, vol_avg) > 0)
      {
        long total = 0;
        for (int i = 0; i < 20; i++)
          total += vol_avg[i];
        double avg = (double)total / 20.0;
        vol_ok = (volumes[0] > avg * volume_multiplier);
      }
    }

    string vol_status = vol_ok ? "Volume: OK" : "Volume: LOW";
    color vol_color = vol_ok ? clrLime : clrRed;
    CreateLabel("InfoPanel_Volume", vol_status, 10, y_offset, vol_color, 8);
    y_offset += line_height;

    // CMI Filter
    if (use_cmi_filter)
    {
      string cmi_status = "CMI: MONITORING";
      color cmi_color = clrGray;
      CreateLabel("InfoPanel_CMI", cmi_status, 10, y_offset, cmi_color, 8);
    }
    else
    {
      CreateLabel("InfoPanel_CMI", "CMI: DISABLED", 10, y_offset, clrGray, 8);
    }
    y_offset += line_height;

    // EMA Confirmation
    if (use_ema_confirmation)
    {
      string ema_status = "EMA: MONITORING";
      color ema_color = clrGray;
      CreateLabel("InfoPanel_EMA", ema_status, 10, y_offset, ema_color, 8);
    }
    else
    {
      CreateLabel("InfoPanel_EMA", "EMA: DISABLED", 10, y_offset, clrGray, 8);
    }
    y_offset += line_height;

    // CVD Confirmation
    if (use_cvd_confirmation)
    {
      string cvd_status = "CVD: MONITORING";
      color cvd_color = clrGray;
      CreateLabel("InfoPanel_CVD", cvd_status, 10, y_offset, cvd_color, 8);
    }
    else
    {
      CreateLabel("InfoPanel_CVD", "CVD: DISABLED", 10, y_offset, clrGray, 8);
    }
    y_offset += line_height + 5;

    // Overall Status
    string overall_status;
    color overall_color;

    if (!trading_window_active)
    {
      overall_status = "Status: WAITING FOR SESSION";
      overall_color = clrGray;
    }
    else if (!orb_calc.IsCalculated())
    {
      overall_status = "Status: WAITING FOR ORB";
      overall_color = clrOrange;
    }
    else if (pos_mgr_active)
    {
      overall_status = "Status: POSITION ACTIVE";
      overall_color = clrYellow;
    }
    else if (breakout_triggered)
    {
      overall_status = "Status: BREAKOUT TRIGGERED";
      overall_color = clrMagenta;
    }
    else
    {
      overall_status = "Status: MONITORING";
      overall_color = clrCyan;
    }

    CreateLabel("InfoPanel_Status", overall_status, 10, y_offset, overall_color, 9);
    ChartRedraw();
  }

private:
  void InitializePanelObjects()
  {
    m_panel_objects[0] = "InfoPanel_Header";
    m_panel_objects[1] = "InfoPanel_Time";
    m_panel_objects[2] = "InfoPanel_Session";
    m_panel_objects[3] = "InfoPanel_ORB";
    m_panel_objects[4] = "InfoPanel_Position";
    m_panel_objects[5] = "InfoPanel_ConfHeader";
    m_panel_objects[6] = "InfoPanel_Volume";
    m_panel_objects[7] = "InfoPanel_CMI";
    m_panel_objects[8] = "InfoPanel_EMA";
    m_panel_objects[9] = "InfoPanel_CVD";
    m_panel_objects[10] = "InfoPanel_Status";
    m_total_objects = 11;
  }

  void CreateLabel(string name, string text, int x, int y, color clr, int font_size)
  {
    ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
    ObjectSetString(0, name, OBJPROP_FONT, "Arial");
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
  }

  void DeletePanel()
  {
    for (int i = 0; i < m_total_objects; i++)
    {
      ObjectDelete(0, m_panel_objects[i]);
    }
  }
};

//+------------------------------------------------------------------+
//| Chart Manager Class                                              |
//+------------------------------------------------------------------+
class CChartManager
{
private:
  string m_line_names[20];
  datetime m_last_indicator_update;

public:
  CChartManager() : m_last_indicator_update(0)
  {
    InitializeLineNames();
  }

  void InitializeLineNames()
  {
    m_line_names[0] = "ORB_High";
    m_line_names[1] = "ORB_Low";
    m_line_names[2] = "TP3_Bull";
    m_line_names[3] = "TP3_Bear";
    m_line_names[4] = "Session_Start";
    m_line_names[5] = "Session_End";
    m_line_names[6] = "EMA50_Line";
    m_line_names[7] = "EMA200_Line";
    m_line_names[8] = "CMI_Level";
    m_line_names[9] = "CMI_Threshold";
    m_line_names[10] = "CVD_Line";
    m_line_names[11] = "CVD_Zero";
  }

  void DrawORBLines(double high, double low)
  {
    CreateHLine(m_line_names[0], high, clrRed, "ORB High: ");
    CreateHLine(m_line_names[1], low, clrRed, "ORB Low: ");
  }

  void DrawTP3Line(bool is_long, double tp3_price)
  {
    string name = is_long ? m_line_names[2] : m_line_names[3];
    color clr = is_long ? clrLime : clrOrange;
    string label = is_long ? "Bull TP3: " : "Bear TP3: ";
    CreateHLine(name, tp3_price, clr, label);
  }

  void DrawSessionLines()
  {
    CreateVLine(m_line_names[4], clrBlue, StringFormat("Start (%02d:%02d)", orb_start_hour, orb_start_minute));
    CreateVLine(m_line_names[5], clrBlue, "End (17:00)");
  }

  void DrawIndicators(CEMAAnalyzer &ema_analyzer, CCMIAnalyzer &cmi_analyzer, CCVDAnalyzer &cvd_analyzer)
  {
    if (!draw_indicators)
      return;

    datetime current_time = TimeCurrent();
    if (current_time - m_last_indicator_update < 5)
      return;
    m_last_indicator_update = current_time;

    if (draw_ema_lines)
    {
      DrawEMALines(ema_analyzer);
    }

    if (draw_cmi_histogram)
    {
      DrawCMIIndicator(cmi_analyzer);
    }

    if (draw_cvd_line)
    {
      DrawCVDIndicator(cvd_analyzer);
    }
  }

  void RemoveTP3Lines()
  {
    ObjectDelete(0, m_line_names[2]);
    ObjectDelete(0, m_line_names[3]);
  }

  void DeleteAll()
  {
    for (int i = 0; i < ArraySize(m_line_names); i++)
      ObjectDelete(0, m_line_names[i]);

    ObjectDelete(0, "CMI_Display");
    ObjectDelete(0, "CVD_Display");
  }

  void DeleteInfoPanel()
  {
    string info_objects[] = {"InfoPanel_Header", "InfoPanel_Time", "InfoPanel_Session",
                             "InfoPanel_ORB", "InfoPanel_Position", "InfoPanel_ConfHeader",
                             "InfoPanel_Volume", "InfoPanel_CMI", "InfoPanel_EMA",
                             "InfoPanel_CVD", "InfoPanel_Status"};

    for (int i = 0; i < ArraySize(info_objects); i++)
      ObjectDelete(0, info_objects[i]);

    ObjectDelete(0, "CMI_Display");
    ObjectDelete(0, "CVD_Display");
  }

private:
  void DrawEMALines(CEMAAnalyzer &ema_analyzer)
  {
    double ema50_value, ema200_value;

    if (ema_analyzer.GetCurrentEMAValues(ema50_value, ema200_value))
    {
      CreateHLine(m_line_names[6], ema50_value, clrOrange, "EMA 50: ");
      CreateHLine(m_line_names[7], ema200_value, clrMagenta, "EMA 200: ");
    }
  }

  void DrawCMIIndicator(CCMIAnalyzer &cmi_analyzer)
  {
    double current_cmi = cmi_analyzer.GetCurrentCMI();

    if (current_cmi > 0)
    {
      string cmi_text = StringFormat("CMI: %.1f %s", current_cmi,
                                     (current_cmi > cmi_threshold) ? "(CHOPPY)" : "(TRENDING)");
      color cmi_color = (current_cmi > cmi_threshold) ? clrRed : clrLime;

      CreateTextLabel("CMI_Display", cmi_text, 200, 50, cmi_color, 9);
    }
  }

  void DrawCVDIndicator(CCVDAnalyzer &cvd_analyzer)
  {
    double current_cvd = cvd_analyzer.GetCurrentCVD();

    string cvd_text = StringFormat("CVD: %.0f", current_cvd);
    color cvd_color = (current_cvd > 0) ? clrLime : clrRed;

    CreateTextLabel("CVD_Display", cvd_text, 200, 80, cvd_color, 9);
  }

  void CreateTextLabel(string name, string text, int x, int y, color clr, int font_size)
  {
    ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
    ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
  }

  void CreateHLine(string name, double price, color clr, string text)
  {
    ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
    ObjectSetString(0, name, OBJPROP_TEXT, text + DoubleToString(price, 5));
  }

  void CreateVLine(string name, color clr, string text)
  {
    ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_VLINE, 0, TimeCurrent(), 0);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
  }
};

//+------------------------------------------------------------------+
//| Main ORB Strategy Class                                          |
//+------------------------------------------------------------------+
class CORBStrategy
{
private:
  CTimeManager m_time_mgr;
  CORBCalculator m_orb_calc;
  CVolumeAnalyzer m_vol_analyzer;
  CEMAAnalyzer m_ema_analyzer;
  CCVDAnalyzer m_cvd_analyzer;
  CCMIAnalyzer m_cmi_analyzer;
  CChartManager m_chart_mgr;
  CPositionManager m_pos_mgr;
  CInfoPanel m_info_panel;

  bool m_trading_window_active;
  bool m_breakout_triggered;
  double m_current_bar_close;
  datetime m_last_time;

public:
  CORBStrategy() : m_trading_window_active(false), m_breakout_triggered(false),
                   m_current_bar_close(0), m_last_time(0) {}

  void OnTick()
  {
    bool new_candle = CheckNewCandle();

    datetime ny_time = m_time_mgr.GetNYTime();
    MqlDateTime ny_struct;
    TimeToStruct(ny_time, ny_struct);

    if (m_time_mgr.ShouldReset(ny_struct))
    {
      ResetDaily();
      return;
    }

    ProcessTimeEvents(ny_struct);

    m_trading_window_active = m_time_mgr.IsTradingWindow(ny_struct);

    if (m_trading_window_active && m_orb_calc.IsCalculated() && !m_pos_mgr.IsActive() && new_candle)
    {
      CheckBreakout();
    }

    if (m_pos_mgr.IsActive())
    {
      if (m_pos_mgr.CheckTP3(m_orb_calc.GetTP3Bull(), m_orb_calc.GetTP3Bear()))
      {
        m_pos_mgr.CloseAll();
        m_chart_mgr.RemoveTP3Lines();
        m_breakout_triggered = false;
      }
      m_pos_mgr.CheckIfClosed();
    }

    if (ny_struct.hour == 17 && ny_struct.min == 0)
    {
      m_pos_mgr.CloseAll();
    }

    // Update info panel every tick
    m_info_panel.UpdatePanel(m_orb_calc, m_vol_analyzer, m_ema_analyzer,
                             m_cvd_analyzer, m_cmi_analyzer, m_pos_mgr.IsActive(), 
                             m_pos_mgr.IsLong(), m_pos_mgr.GetEntryPrice(),
                             m_trading_window_active, m_breakout_triggered);

    // Draw indicators on chart
    m_chart_mgr.DrawIndicators(m_ema_analyzer, m_cmi_analyzer, m_cvd_analyzer);
  }

private:
  bool CheckNewCandle()
  {
    datetime current_time = iTime(Symbol(), PERIOD_M5, 0);
    if (current_time != m_last_time)
    {
      m_last_time = current_time;
      m_current_bar_close = iClose(Symbol(), PERIOD_M5, 1);
      Print("New M5: ", m_current_bar_close);
      return true;
    }
    return false;
  }

  void ProcessTimeEvents(const MqlDateTime &ny_struct)
  {
    if (ny_struct.hour == orb_end_hour && ny_struct.min == orb_end_minute && !m_orb_calc.IsCalculated())
    {
      if (m_orb_calc.Calculate())
      {
        m_chart_mgr.DrawORBLines(m_orb_calc.GetHigh(), m_orb_calc.GetLow());
      }
    }

    if (ny_struct.hour == orb_start_hour && ny_struct.min == orb_start_minute)
    {
      m_chart_mgr.DrawSessionLines();
    }
  }

  void CheckBreakout()
  {
    if (m_breakout_triggered)
      return;

    bool bull_breakout = m_current_bar_close > m_orb_calc.GetHigh();
    bool bear_breakout = m_current_bar_close < m_orb_calc.GetLow();

    if (bull_breakout || bear_breakout)
    {
      if (!m_vol_analyzer.IsVolumeConfirmed())
        return;

      if (use_cmi_filter)
      {
        if (m_cmi_analyzer.IsMarketChoppy())
        {
          Print("Trade avoided - market is choppy");
          return;
        }
      }

      if (use_ema_confirmation)
      {
        bool ema_confirmed = false;
        if (bull_breakout)
        {
          ema_confirmed = m_ema_analyzer.IsBullishAlignment() || m_ema_analyzer.IsBullishCrossing();
          if (!ema_confirmed)
          {
            Print("EMA not confirmed for bull breakout");
            return;
          }
        }
        else if (bear_breakout)
        {
          ema_confirmed = !m_ema_analyzer.IsBullishAlignment() || m_ema_analyzer.IsBearishCrossing();
          if (!ema_confirmed)
          {
            Print("EMA not confirmed for bear breakout");
            return;
          }
        }
      }

      if (use_cvd_confirmation)
      {
        bool cvd_confirmed = false;
        if (bull_breakout)
        {
          cvd_confirmed = m_cvd_analyzer.IsBullishDivergence();
          if (!cvd_confirmed)
          {
            Print("CVD not confirmed for bull breakout");
            return;
          }
        }
        else if (bear_breakout)
        {
          cvd_confirmed = m_cvd_analyzer.IsBearishDivergence();
          if (!cvd_confirmed)
          {
            Print("CVD not confirmed for bear breakout");
            return;
          }
        }
      }

      ExecuteBreakout(bull_breakout);
    }
  }

  void ExecuteBreakout(bool is_bullish)
  {
    m_breakout_triggered = true;

    double tp3_level = is_bullish ? m_orb_calc.GetTP3Bull() : m_orb_calc.GetTP3Bear();

    if (m_pos_mgr.OpenPosition(is_bullish, m_orb_calc.GetHigh(), m_orb_calc.GetLow(), tp3_level))
    {
      m_chart_mgr.DrawTP3Line(is_bullish, tp3_level);
      Print((is_bullish ? "BULL" : "BEAR"), " breakout executed");
    }
  }

  void ResetDaily()
  {
    m_orb_calc.Reset();
    m_pos_mgr.Reset();
    m_chart_mgr.DeleteAll();
    m_chart_mgr.DeleteInfoPanel();
    m_trading_window_active = false;
    m_breakout_triggered = false;
    m_current_bar_close = 0;
    Print("Daily reset");
  }
};

//+------------------------------------------------------------------+
//| Global Strategy Instance                                         |
//+------------------------------------------------------------------+
CORBStrategy g_strategy;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  int start_total = orb_start_hour * 60 + orb_start_minute;
  int end_total = orb_end_hour * 60 + orb_end_minute;

  if (end_total <= start_total)
  {
    Print("ERROR: ORB end must be after start!");
    return INIT_PARAMETERS_INCORRECT;
  }

  Print("ORB EA Init | Window: ", orb_start_hour, ":", StringFormat("%02d", orb_start_minute),
        " to ", orb_end_hour, ":", StringFormat("%02d", orb_end_minute), " NY (",
        end_total - start_total, " min)");

  Print("Confirmations: EMA=", (use_ema_confirmation ? "ON" : "OFF"),
        " | CVD=", (use_cvd_confirmation ? "ON" : "OFF"),
        " | CVD Lookback=", cvd_lookback_periods,
        " | CMI Filter=", (use_cmi_filter ? "ON" : "OFF"),
        " | CMI Threshold=", cmi_threshold);

  Print("Chart Drawing: Indicators=", (draw_indicators ? "ON" : "OFF"),
        " | EMA Lines=", (draw_ema_lines ? "ON" : "OFF"),
        " | CMI=", (draw_cmi_histogram ? "ON" : "OFF"),
        " | CVD=", (draw_cvd_line ? "ON" : "OFF"));

  return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  string info_objects[] = {"InfoPanel_Header", "InfoPanel_Time", "InfoPanel_Session",
                           "InfoPanel_ORB", "InfoPanel_Position", "InfoPanel_ConfHeader",
                           "InfoPanel_Volume", "InfoPanel_CMI", "InfoPanel_EMA",
                           "InfoPanel_CVD", "InfoPanel_Status"};

  for (int i = 0; i < ArraySize(info_objects); i++)
    ObjectDelete(0, info_objects[i]);

  ObjectDelete(0, "CMI_Display");
  ObjectDelete(0, "CVD_Display");

  Print("ORB EA Removed");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
  g_strategy.OnTick();
}
