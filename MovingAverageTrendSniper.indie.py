# indie:lang_version = 5
# This source code is subject to the terms of the Mozilla Public License 2.0 at https://mozilla.org/MPL/2.0/
# Original "Moving Average Trend Sniper [ChartPrime]" (Pine v5) (c) ChartPrime. Indie port under the same license.
# Moving Average Trend Sniper (MATS) - port to Indie for Exness Terminal / TakeProfit.
#
# Differences from the Pine original, forced by the Indie runtime:
#   - Indie fills have no gradient, so the glow band is a flat, faint fill on each side of the line.
#   - EMAs are computed by hand with the Pine formula (seeded with the first value, na inputs skipped)
#     so the line matches the original instead of depending on the platform's EMA seeding.
#   - Default colors are two blues (red-green color blind safe); the original used blue / orange.

from math import nan, isnan
from indie import indicator, param, plot, color, MainContext, MutSeriesF
from indie.algorithms import Sma, Tr, Change, Highest, Lowest


def sign(x: float) -> float:
    result = 0.0
    if x > 0:
        result = 1.0
    elif x < 0:
        result = -1.0
    return result


def ema_step(prev: float, src: float, length: int) -> float:
    # Pine ta.ema recursion: alpha * src + (1 - alpha) * prev, seeded with the first value
    alpha = 2.0 / (length + 1.0)
    result = prev
    if not isnan(src):
        if isnan(prev):
            result = src
        else:
            result = alpha * src + (1.0 - alpha) * prev
    return result


@indicator('Moving Average Trend Sniper [ChartPrime]', overlay_main_pane=True)
@param.int('length', default=30, min=2, title='Length')
@param.color('up_color', default=color.rgba(100, 181, 246, 1.0), title='Up Color')
@param.color('down_color', default=color.rgba(92, 107, 192, 1.0), title='Down Color')
@param.bool('enable_glow', default=True, title='Enable Glow')
@plot.line('glow3', title='MATS Glow 3', line_width=4)
@plot.line('glow2', title='MATS Glow 2', line_width=3)
@plot.line('glow1', title='MATS Glow 1', line_width=2)
@plot.line('center', title='Moving Average Trend Sniper', line_width=1)
@plot.line('top', title='Glow Top', color=color.TRANSPARENT)
@plot.line('bottom', title='Glow Bottom', color=color.TRANSPARENT)
@plot.fill('top', 'center', title='Upper Glow')
@plot.fill('center', 'bottom', title='Lower Glow')
class Main(MainContext):
    def __init__(self):
        # Var rolls back on intrabar updates, matching Pine's [1] history
        self._tr_ema = self.new_var(nan)
        self._smooth = self.new_var(nan)
        self._ma_atr = self.new_var(nan)
        self._slow_atr = self.new_var(nan)
        self._result = self.new_var(nan)

    def calc(self, length, up_color, down_color, enable_glow):
        self.close.request_size(12)

        # ---- ema(ta.tr): Pine's custom EMA whose alpha shrinks as 2 / (count + 1) ----
        count = self.bar_index + 1
        true_range = Tr.new()[0]
        prev_tr_ema = self._tr_ema.get()
        if isnan(prev_tr_ema):
            prev_tr_ema = 0.0
        tr_ema = (1.0 - 2.0 / (count + 1.0)) * prev_tr_ema + 2.0 / (count + 1.0) * true_range
        self._tr_ema.set(tr_ema)

        # ---- tra(): high while the 10 bar slope points up, low otherwise, smoothed over 2 bars ----
        # the original converts the slope to an angle in degrees; atan keeps the sign, so slope > 0 is the same test
        slope = nan
        if self.bar_index >= 10 and not isnan(tr_ema) and tr_ema != 0:
            slope = (self.close[0] - self.close[10]) / (tr_ema * 10.0)
        picked = self.low[0]
        if not isnan(slope) and slope > 0:
            picked = self.high[0]
        source = Sma.new(MutSeriesF.new(picked), 2)[0]

        # ---- mats(source, length) ----
        higher_high = max(sign(Change.new(Highest.new(self.high, length), 1)[0]), 0.0)
        lower_low = max(sign(Change.new(Lowest.new(self.low, length), 1)[0] * -1.0), 0.0)
        extended = 0.0
        if higher_high > 0 or lower_low > 0:
            extended = 1.0
        time_constant = Sma.new(MutSeriesF.new(extended), length)[0]
        time_constant = time_constant * time_constant

        prev_smooth = self._smooth.get()
        smooth = prev_smooth + time_constant * (source - prev_smooth)
        if isnan(smooth):
            smooth = source
        self._smooth.set(smooth)

        wilders_period = length * 4 - 1
        prev_for_atr = prev_smooth
        if isnan(prev_for_atr):
            prev_for_atr = 0.0
        atr = abs(prev_for_atr - smooth)
        ma_atr = ema_step(self._ma_atr.get(), atr, wilders_period)
        self._ma_atr.set(ma_atr)
        slow_atr = ema_step(self._slow_atr.get(), ma_atr, wilders_period)
        self._slow_atr.set(slow_atr)
        delta_fast_atr = slow_atr * length * 0.4

        prev_result = self._result.get()
        prev_or_zero = prev_result
        if isnan(prev_or_zero):
            prev_or_zero = 0.0
        result = 0.0
        if smooth > prev_or_zero:
            if smooth - delta_fast_atr < prev_result:
                result = prev_result
            else:
                result = smooth - delta_fast_atr
        else:
            if smooth + delta_fast_atr > prev_result:
                result = prev_result
            else:
                result = smooth + delta_fast_atr
        self._result.set(result)

        # ---- display ----
        colour = down_color
        if Sma.new(self.close, 2)[0] > result:
            colour = up_color
        atr_10 = tr_ema / 2.0
        top = nan
        bottom = nan
        if enable_glow:
            top = result + atr_10
            bottom = result - atr_10

        return (plot.Line(result, color=colour(0.1)),
                plot.Line(result, color=colour(0.2)),
                plot.Line(result, color=colour(0.3)),
                plot.Line(result, color=colour),
                top,
                bottom,
                plot.Fill(color=colour(0.15)),
                plot.Fill(color=colour(0.15)))
