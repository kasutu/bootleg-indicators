# indie:lang_version = 5
# Auto Range Detector [QuantAlgo] - port of AutoRangeDetector (Pine v6) to Indie for Exness Terminal / TakeProfit.
#
# Differences from the Pine original, forced by the Indie runtime:
#   - No chart background access and no RGB getters on Color, so the contrast correction step is dropped.
#     Colors are used as chosen; pick a Range color that reads on your chart theme.
#   - Marker text color is an input instead of being derived from the marker background.
#   - alertcondition() does not exist. The five signals are exported as hidden plots (1 = fired, 0 = idle)
#     so alerts can be attached to them from the platform's alert dialog.
#   - Drawings are positioned by bar time instead of bar_index.

from math import sqrt, isnan, nan
from indie import indicator, param, plot, color, Color, line_style, MainContext, Algorithm, Context, MutSeriesF, Optional, Var
from indie.algorithms import Atr, Percentile, Highest, Lowest
from indie.drawings import Rectangle, LineSegment, LabelAbs, AbsolutePosition, callout_position



#              ╔════════════════════════════════╗              #
#              ║       UTILITY FUNCTIONS        ║              #
#              ╚════════════════════════════════╝              #

def fade(source: Color, transparency: float) -> Color:
    # Pine-style transparency (0 opaque .. 100 invisible) to Indie alpha
    return source(max(0.0, min(1.0, 1.0 - transparency / 100.0)))


def resolve_size(choice: str) -> int:
    size = 11
    if choice == 'Tiny':
        size = 9
    elif choice == 'Normal':
        size = 13
    elif choice == 'Large':
        size = 16
    return size


def percent_text(value: float) -> str:
    return f'{value:.2f}%'


def preset_bullish(preset: str, custom: Color) -> Color:
    result = custom
    if preset == 'Classic':
        result = color.hex('#00ff00')
    elif preset == 'Aqua':
        result = color.hex('#00d4ff')
    elif preset == 'Cosmic':
        result = color.hex('#49ffce')
    elif preset == 'Cyber':
        result = color.hex('#00cccc')
    elif preset == 'Neon':
        result = color.hex('#ffff00')
    return result


def preset_bearish(preset: str, custom: Color) -> Color:
    result = custom
    if preset == 'Classic':
        result = color.hex('#ff0000')
    elif preset == 'Aqua':
        result = color.hex('#ff8c00')
    elif preset == 'Cosmic':
        result = color.hex('#9932cc')
    elif preset == 'Cyber':
        result = color.hex('#ff6600')
    elif preset == 'Neon':
        result = color.hex('#ff00ff')
    return result


#              ╔════════════════════════════════╗              #
#              ║          SCAN WINDOW           ║              #
#              ╚════════════════════════════════╝              #

class ScanWindow(Algorithm):
    def __init__(self, ctx: Context):
        super().__init__(ctx)

    def calc(self, length: int, atr_value: float, boundary_basis: str, band_percentile: float,
             compression_pct: float, calibration_len: int, atr_length: int, min_rotation: float,
             wick_touch: bool, min_touches: int, touch_tolerance: float, max_drift: float,
             min_containment: float) -> tuple[bool, float, float]:
        ctx = self.ctx
        ctx.close.request_size(length + 2)
        ctx.high.request_size(length + 2)
        ctx.low.request_size(length + 2)

        # Rolling algorithms run on every bar so their windows stay in sync
        pct_top = Percentile.new(ctx.high, length, band_percentile, True)[0]
        pct_bottom = Percentile.new(ctx.low, length, 100.0 - band_percentile, True)[0]
        ext_top = Highest.new(ctx.high, length)[0]
        ext_bottom = Lowest.new(ctx.low, length)[0]
        body_high = MutSeriesF.new(max(ctx.open[0], ctx.close[0]))
        body_low = MutSeriesF.new(min(ctx.open[0], ctx.close[0]))
        body_top = Highest.new(body_high, length)[0]
        body_bottom = Lowest.new(body_low, length)[0]

        top = pct_top
        bottom = pct_bottom
        if boundary_basis == 'Absolute extremes':
            top = ext_top
            bottom = ext_bottom
        elif boundary_basis == 'Body extremes':
            top = body_top
            bottom = body_bottom
        band_height = top - bottom

        context_ok = not isnan(atr_value) and atr_value > 0
        compression = 99.0
        if context_ok and band_height > 0:
            compression = band_height / (atr_value * sqrt(length))
        compression_series = MutSeriesF.new(compression)
        compression_series.request_size(calibration_len + 2)

        if not context_ok or isnan(band_height) or ctx.bar_index <= length + 5:
            return False, top, bottom

        midpoint = (top + bottom) / 2.0
        tolerance = touch_tolerance * atr_value
        crossings = 0
        hits_top = 0
        hits_bottom = 0
        contained = 0
        # Least squares slope of close over the window (x grows with time)
        sum_x = 0.0
        sum_y = 0.0
        sum_xy = 0.0
        sum_xx = 0.0
        for i in range(length):
            c = ctx.close[i]
            if (c > midpoint) != (ctx.close[i + 1] > midpoint):
                crossings += 1
            touched_top = False
            touched_bottom = False
            if wick_touch:
                touched_top = ctx.high[i] >= top - tolerance
                touched_bottom = ctx.low[i] <= bottom + tolerance
            else:
                touched_top = c >= top - tolerance
                touched_bottom = c <= bottom + tolerance
            if touched_top:
                hits_top += 1
            if touched_bottom:
                hits_bottom += 1
            if c <= top and c >= bottom:
                contained += 1
            x = float(length - 1 - i)
            sum_x += x
            sum_y += c
            sum_xy += x * c
            sum_xx += x * x

        denominator = length * sum_xx - sum_x * sum_x
        slope = 0.0
        if denominator != 0:
            slope = (length * sum_xy - sum_x * sum_y) / denominator
        drift = 99.0
        if band_height > 0:
            drift = abs(slope) * length / band_height
        containment = contained / float(length)

        structure_ok = (crossings >= max(3, round(min_rotation * length))
                        and hits_top >= min_touches and hits_bottom >= min_touches
                        and drift <= max_drift and containment >= min_containment)
        if not structure_ok:
            return False, top, bottom

        # Compression rank against its own history (only evaluated when the cheap filters pass)
        span_cap = calibration_len
        if ctx.bar_index >= 1:
            span_cap = max(1, min(calibration_len, ctx.bar_index - atr_length))
        num_leq = 0
        for i in range(1, span_cap + 1):
            if compression_series[i] <= compression_series[0]:
                num_leq += 1
        rank = 100.0 * num_leq / span_cap
        return rank <= compression_pct, top, bottom


#              ╔════════════════════════════════╗              #
#              ║          RANGE ENGINE          ║              #
#              ╚════════════════════════════════╝              #

@indicator('Auto Range Detector [QuantAlgo]', overlay_main_pane=True)
# ════════ Detection ════════
@param.str('scan_scaling', default='Base + 2x + 3x', options=['Base only', 'Base + 2x', 'Base + 2x + 3x'], title='Scan Scaling')
@param.int('base_length', default=20, min=8, max=100, title='Base Scan Length')
@param.str('boundary_basis', default='Percentile band', options=['Percentile band', 'Absolute extremes', 'Body extremes'], title='Boundary Basis')
@param.float('band_percentile', default=90.0, min=70.0, max=100.0, step=1.0, title='Boundary Percentile')
@param.str('signal_timing', default='Bar close', options=['Bar close', 'Live bar'], title='Signal Timing')
@param.int('atr_length', default=200, min=14, max=1000, title='ATR Length')
# ════════ Structure Filters ════════
@param.float('compression_pct', default=40.0, min=5.0, max=95.0, step=5.0, title='Compression Percentile')
@param.int('calibration_len', default=500, min=100, max=2000, title='Calibration Lookback')
@param.float('min_rotation', default=0.18, min=0.05, max=0.60, step=0.01, title='Min Rotation Rate')
@param.str('touch_basis', default='Wick reaches', options=['Wick reaches', 'Close reaches'], title='Touch Definition')
@param.int('min_touches', default=2, min=1, max=10, title='Min Boundary Touches')
@param.float('touch_tolerance', default=0.10, min=0.02, max=1.0, step=0.02, title='Touch Tolerance (ATR)')
@param.float('max_drift', default=0.45, min=0.05, max=2.0, step=0.05, title='Max Drift')
@param.float('min_containment', default=0.70, min=0.40, max=1.0, step=0.05, title='Min Containment')
# ════════ Range Behavior ════════
@param.str('range_anchoring', default='Extend to containment', options=['Scan window only', 'Extend to containment'], title='Range Anchoring')
@param.int('anchor_lookback', default=300, min=20, max=500, title='Anchor Lookback')
@param.int('min_range_bars', default=10, min=2, max=200, title='Minimum Range Bars')
@param.bool('absorb_overshoot', default=True, title='Absorb Overshoot')
@param.float('overshoot_tol', default=0.25, min=0.05, max=1.0, step=0.05, title='Overshoot Tolerance (ATR)')
@param.str('break_confirm', default='Close beyond', options=['Close beyond', 'Wick beyond'], title='Break Confirmation')
@param.float('breakout_buffer', default=0.15, min=0.0, max=2.0, step=0.05, title='Breakout Buffer (ATR)')
@param.bool('merge_deviations', default=True, title='Merge Deviations')
@param.int('deviation_window', default=10, min=1, max=100, title='Deviation Window')
@param.int('cooldown_bars', default=3, min=0, max=100, title='Cooldown Bars')
@param.int('max_range_age', default=0, min=0, max=2000, title='Max Range Age')
# ════════ Visual Settings ════════
@param.str('color_preset', default='Custom', options=['Classic', 'Aqua', 'Cosmic', 'Cyber', 'Neon', 'Custom'], title='Color Preset')
@param.color('bullish_input', default=color.hex('#00ffaa'), title='Bullish Color')
@param.color('bearish_input', default=color.hex('#ff0000'), title='Bearish Color')
@param.color('range_input', default=color.GRAY, title='Range Color')
@param.color('marker_text_color', default=color.BLACK, title='Marker Text Color')
@param.int('gradient_steps', default=4, min=1, max=10, title='Gradient Steps')
@param.int('fill_transparency', default=88, min=50, max=100, title='Fill Transparency')
@param.bool('show_equilibrium', default=True, title='Show Equilibrium Line')
@param.bool('show_quartiles', default=True, title='Show Quartile Levels')
@param.bool('show_range_label', default=True, title='Show Range Labels')
@param.bool('show_breakouts', default=True, title='Show Breakout Markers')
@param.bool('show_deviations', default=True, title='Show Deviation Markers')
@param.str('label_text_size', default='Small', options=['Tiny', 'Small', 'Normal', 'Large'], title='Label Text Size')
# ════════ Alert signals (hidden, 1 = fired) ════════
@plot.line('sig_new_range', title='Range Detected', display_options=plot.LineDisplayOptions(pane=False, status_line=False, price_label=False))
@plot.line('sig_break_up', title='Range Breakout Up', display_options=plot.LineDisplayOptions(pane=False, status_line=False, price_label=False))
@plot.line('sig_break_down', title='Range Breakdown', display_options=plot.LineDisplayOptions(pane=False, status_line=False, price_label=False))
@plot.line('sig_any_break', title='Any Range Break', display_options=plot.LineDisplayOptions(pane=False, status_line=False, price_label=False))
@plot.line('sig_deviation', title='Range Deviation', display_options=plot.LineDisplayOptions(pane=False, status_line=False, price_label=False))
class Main(MainContext):
    def __init__(self, color_preset, bullish_input, bearish_input, range_input, marker_text_color,
                 gradient_steps, fill_transparency, label_text_size):
        self._bullish = preset_bullish(color_preset, bullish_input)
        self._bearish = preset_bearish(color_preset, bearish_input)
        self._range = range_input
        self._marker_text = marker_text_color
        self._steps = max(1, min(10, gradient_steps))
        self._fill_transparency = fill_transparency
        self._font = resolve_size(label_text_size)

        # Engine state. Var rolls back on intrabar updates, matching Pine `var` semantics.
        self._range_top = self.new_var(nan)
        self._range_bottom = self.new_var(nan)
        self._range_left = self.new_var(0)
        self._range_left_time = self.new_var(0.0)
        self._range_opened = self.new_var(0)
        self._range_active = self.new_var(False)
        self._range_confirmed = self.new_var(False)
        self._range_dormant = self.new_var(False)
        self._dormant_since = self.new_var(0)
        self._dormant_dir = self.new_var(0)
        self._deviation_price = self.new_var(nan)
        self._deviation_time = self.new_var(0.0)
        self._cooldown_left = self.new_var(0)

        # Drawings of the range currently tracked (live or dormant)
        self._box = self.new_var(Optional[Rectangle]())
        self._equilibrium = self.new_var(Optional[LineSegment]())
        self._lower_quartile = self.new_var(Optional[LineSegment]())
        self._upper_quartile = self.new_var(Optional[LineSegment]())
        self._tag = self.new_var(Optional[LabelAbs]())
        self._break_marker = self.new_var(Optional[LabelAbs]())
        self._shades: list[Var[Optional[Rectangle]]] = []
        for _ in range(10):
            self._shades.append(self.new_var(Optional[Rectangle]()))

    # ---------- drawing helpers ----------

    def _anchor_span(self, window: int, top: float, bottom: float, tolerance: float,
                     extend: bool, anchor_lookback: int, min_containment: float) -> int:
        span = window
        if extend:
            limit = min(anchor_lookback, self.bar_index)
            allowed = max(2, round((1.0 - min_containment) * window))
            outside = 0
            offset = 0
            while offset < limit and outside <= allowed:
                c = self.close[offset]
                closed_in = c <= top and c >= bottom
                fully_in = closed_in and self.high[offset] <= top + tolerance and self.low[offset] >= bottom - tolerance
                if closed_in:
                    outside = max(0, outside - 1)
                    if fully_in and offset + 1 >= window:
                        span = offset + 1
                else:
                    outside += 1
                offset += 1
        return span

    def _create_drawings(self, left_time: float, top: float, bottom: float,
                         show_equilibrium: bool, show_quartiles: bool, show_range_label: bool) -> None:
        now = self.time[0]
        midpoint = (top + bottom) / 2.0
        quartile_low = bottom + (top - bottom) * 0.25
        quartile_high = bottom + (top - bottom) * 0.75
        for i in range(self._steps):
            self._shades[i].set(Rectangle(AbsolutePosition(left_time, top), AbsolutePosition(now, bottom),
                                          line_color=color.TRANSPARENT, bg_color=color.TRANSPARENT,
                                          middle_line_color=color.TRANSPARENT))
        self._box.set(Rectangle(AbsolutePosition(left_time, top), AbsolutePosition(now, bottom),
                                line_style=line_style.DASHED, line_width=1,
                                line_color=fade(self._range, 65), bg_color=color.TRANSPARENT,
                                middle_line_color=color.TRANSPARENT))
        if show_equilibrium:
            self._equilibrium.set(LineSegment(AbsolutePosition(left_time, midpoint), AbsolutePosition(now, midpoint),
                                              color=fade(self._range, 25), line_style=line_style.DOTTED, line_width=1))
        if show_quartiles:
            self._lower_quartile.set(LineSegment(AbsolutePosition(left_time, quartile_low), AbsolutePosition(now, quartile_low),
                                                 color=fade(self._range, 70), line_style=line_style.DOTTED, line_width=1))
            self._upper_quartile.set(LineSegment(AbsolutePosition(left_time, quartile_high), AbsolutePosition(now, quartile_high),
                                                 color=fade(self._range, 70), line_style=line_style.DOTTED, line_width=1))
        if show_range_label:
            self._tag.set(LabelAbs('', AbsolutePosition(left_time, top), font_size=self._font,
                                   text_color=fade(self._range, 10), bg_color=color.TRANSPARENT,
                                   callout_position=callout_position.TOP_RIGHT))

    def _render(self, left_time: float, right_time: float, top: float, bottom: float,
                border: Color, border_style: line_style, fill: Color, tag_text: str, tag_color: Color) -> None:
        # Shading: horizontal slices that fade from the boundaries toward equilibrium
        if top > bottom:
            slice_height = (top - bottom) / self._steps
            for i in range(self._steps):
                shade_opt = self._shades[i].get()
                if shade_opt is not None:
                    shade = shade_opt.value()
                    center_dist = abs((i + 0.5) / self._steps - 0.5) * 2.0
                    slice_trans = float(int(min(99.0, max(0.0, self._fill_transparency + (1.0 - center_dist) * 10))))
                    shade.point_a = AbsolutePosition(left_time, top - slice_height * i)
                    shade.point_b = AbsolutePosition(right_time, top - slice_height * (i + 1))
                    shade.bg_color = fade(fill, slice_trans)
                    self.chart.draw(shade)

        box_opt = self._box.get()
        if box_opt is not None:
            box = box_opt.value()
            box.point_a = AbsolutePosition(left_time, top)
            box.point_b = AbsolutePosition(right_time, bottom)
            box.line_color = border
            box.line_style = border_style
            self.chart.draw(box)

        midpoint = (top + bottom) / 2.0
        eq_opt = self._equilibrium.get()
        if eq_opt is not None:
            eq = eq_opt.value()
            eq.point_a = AbsolutePosition(left_time, midpoint)
            eq.point_b = AbsolutePosition(right_time, midpoint)
            self.chart.draw(eq)

        lq_opt = self._lower_quartile.get()
        uq_opt = self._upper_quartile.get()
        if lq_opt is not None and uq_opt is not None:
            quartile_low = bottom + (top - bottom) * 0.25
            quartile_high = bottom + (top - bottom) * 0.75
            lq = lq_opt.value()
            uq = uq_opt.value()
            lq.point_a = AbsolutePosition(left_time, quartile_low)
            lq.point_b = AbsolutePosition(right_time, quartile_low)
            uq.point_a = AbsolutePosition(left_time, quartile_high)
            uq.point_b = AbsolutePosition(right_time, quartile_high)
            self.chart.draw(lq)
            self.chart.draw(uq)

        tag_opt = self._tag.get()
        if tag_opt is not None:
            tag = tag_opt.value()
            tag.position = AbsolutePosition((left_time + right_time) / 2.0, top)
            tag.text = tag_text
            tag.text_color = tag_color
            self.chart.draw(tag)

    def _erase_drawings(self) -> None:
        for i in range(10):
            shade_opt = self._shades[i].get()
            if shade_opt is not None:
                self.chart.erase(shade_opt.value())
        box_opt = self._box.get()
        if box_opt is not None:
            self.chart.erase(box_opt.value())
        eq_opt = self._equilibrium.get()
        if eq_opt is not None:
            self.chart.erase(eq_opt.value())
        lq_opt = self._lower_quartile.get()
        if lq_opt is not None:
            self.chart.erase(lq_opt.value())
        uq_opt = self._upper_quartile.get()
        if uq_opt is not None:
            self.chart.erase(uq_opt.value())
        tag_opt = self._tag.get()
        if tag_opt is not None:
            self.chart.erase(tag_opt.value())
        self._forget_drawings()

    def _forget_drawings(self) -> None:
        # Drop references only; whatever is on the chart stays there as history
        for i in range(10):
            self._shades[i].set(None)
        self._box.set(None)
        self._equilibrium.set(None)
        self._lower_quartile.set(None)
        self._upper_quartile.set(None)
        self._tag.set(None)
        self._break_marker.set(None)

    # ---------- main calculation ----------

    def calc(self, scan_scaling, base_length, boundary_basis, band_percentile, signal_timing, atr_length,
             compression_pct, calibration_len, min_rotation, touch_basis, min_touches, touch_tolerance,
             max_drift, min_containment, range_anchoring, anchor_lookback, min_range_bars,
             absorb_overshoot, overshoot_tol, break_confirm, breakout_buffer, merge_deviations,
             deviation_window, cooldown_bars, max_range_age, show_equilibrium, show_quartiles,
             show_range_label, show_breakouts, show_deviations):
        self.close.request_size(anchor_lookback + 2)
        self.high.request_size(anchor_lookback + 2)
        self.low.request_size(anchor_lookback + 2)
        self.time.request_size(anchor_lookback + 2)

        atr_value = Atr.new(atr_length)[0]
        wick_break = break_confirm == 'Wick beyond'
        wick_touch = touch_basis == 'Wick reaches'
        bar_ready = signal_timing == 'Live bar' or self.is_closed_bar

        qualified_a, top_a, bottom_a = ScanWindow.new(base_length, atr_value, boundary_basis, band_percentile,
                                                      compression_pct, calibration_len, atr_length, min_rotation,
                                                      wick_touch, min_touches, touch_tolerance, max_drift, min_containment)
        qualified_b, top_b, bottom_b = ScanWindow.new(base_length * 2, atr_value, boundary_basis, band_percentile,
                                                      compression_pct, calibration_len, atr_length, min_rotation,
                                                      wick_touch, min_touches, touch_tolerance, max_drift, min_containment)
        qualified_c, top_c, bottom_c = ScanWindow.new(base_length * 3, atr_value, boundary_basis, band_percentile,
                                                      compression_pct, calibration_len, atr_length, min_rotation,
                                                      wick_touch, min_touches, touch_tolerance, max_drift, min_containment)

        use_double = scan_scaling != 'Base only' and qualified_b
        use_triple = scan_scaling == 'Base + 2x + 3x' and qualified_c
        qualified = qualified_a or use_double or use_triple

        scan_length = base_length
        scan_top = top_a
        scan_bottom = bottom_a
        if use_triple:
            scan_length = base_length * 3
            scan_top = top_c
            scan_bottom = bottom_c
        elif use_double:
            scan_length = base_length * 2
            scan_top = top_b
            scan_bottom = bottom_b

        # Working copies of the persistent state, written back at the end of the bar
        range_top = self._range_top.get()
        range_bottom = self._range_bottom.get()
        range_left = self._range_left.get()
        range_left_time = self._range_left_time.get()
        range_opened = self._range_opened.get()
        range_active = self._range_active.get()
        range_confirmed = self._range_confirmed.get()
        range_dormant = self._range_dormant.get()
        dormant_since = self._dormant_since.get()
        dormant_dir = self._dormant_dir.get()
        deviation_price = self._deviation_price.get()
        deviation_time = self._deviation_time.get()
        cooldown_left = self._cooldown_left.get()

        signal_new_range = False
        signal_break_up = False
        signal_break_down = False
        signal_deviation = False

        if bar_ready and cooldown_left > 0:
            cooldown_left -= 1

        # ---- range formation ----
        if bar_ready and not range_active and not range_dormant and cooldown_left <= 0 and qualified:
            anchor_bars = self._anchor_span(scan_length, scan_top, scan_bottom, touch_tolerance * atr_value,
                                            range_anchoring == 'Extend to containment', anchor_lookback, min_containment)
            range_left = self.bar_index - anchor_bars + 1
            range_left_time = self.time[anchor_bars - 1]
            range_opened = self.bar_index
            range_top = scan_top
            range_bottom = scan_bottom
            range_active = True
            range_confirmed = False
            self._create_drawings(range_left_time, range_top, range_bottom,
                                  show_equilibrium, show_quartiles, show_range_label)
            signal_new_range = True

        # ---- live range: absorb, break, age ----
        if range_active and bar_ready:
            break_offset = breakout_buffer * atr_value
            absorb_offset = overshoot_tol * atr_value
            if absorb_overshoot and not wick_break and self.close[0] <= range_top and self.close[0] >= range_bottom:
                if self.high[0] > range_top and self.high[0] <= range_top + absorb_offset:
                    range_top = self.high[0]
                if self.low[0] < range_bottom and self.low[0] >= range_bottom - absorb_offset:
                    range_bottom = self.low[0]
            break_up = False
            break_down = False
            if wick_break:
                break_up = self.high[0] > range_top + break_offset
                break_down = self.low[0] < range_bottom - break_offset
            else:
                break_up = self.close[0] > range_top + break_offset
                break_down = self.close[0] < range_bottom - break_offset
            range_aged = max_range_age > 0 and self.bar_index - range_opened + 1 >= max_range_age

            if break_up or break_down or range_aged:
                break_direction = 0
                if break_up:
                    break_direction = 1
                elif break_down:
                    break_direction = -1
                held_bars = self.bar_index - range_left + 1
                if break_direction != 0:
                    held_bars = self.bar_index - range_left
                range_height = 0.0
                if range_bottom != 0:
                    range_height = (range_top - range_bottom) / range_bottom * 100.0
                hold_for_merge = merge_deviations and break_direction != 0 and range_confirmed

                if range_confirmed:
                    retire_base = self._range
                    if break_direction == 1:
                        retire_base = self._bullish
                    elif break_direction == -1:
                        retire_base = self._bearish
                    self._render(range_left_time, self.time[0], range_top, range_bottom,
                                 fade(retire_base, 35), line_style.SOLID, retire_base,
                                 'RANGE   ' + str(held_bars) + ' BARS   ' + percent_text(range_height),
                                 fade(retire_base, 10))
                    if show_breakouts and break_direction != 0:
                        marker_price = self.high[0]
                        marker_text = '▼  Breakout'
                        marker_callout = callout_position.TOP_RIGHT
                        if break_direction == 1:
                            marker_price = self.low[0]
                            marker_text = '▲  Breakout'
                            marker_callout = callout_position.BOTTOM_RIGHT
                        marker = LabelAbs(marker_text, AbsolutePosition(self.time[0], marker_price),
                                          font_size=self._font, text_color=self._marker_text,
                                          bg_color=fade(retire_base, 10), callout_position=marker_callout)
                        self.chart.draw(marker)
                        self._break_marker.set(marker)
                    if break_direction == 1:
                        signal_break_up = True
                    elif break_direction == -1:
                        signal_break_down = True
                else:
                    # Provisional structure failed: clear it without a marker
                    self._erase_drawings()

                if hold_for_merge:
                    range_dormant = True
                    dormant_since = self.bar_index
                    dormant_dir = break_direction
                    deviation_price = self.low[0]
                    if break_direction == 1:
                        deviation_price = self.high[0]
                    deviation_time = self.time[0]
                else:
                    self._forget_drawings()
                range_active = False
                range_confirmed = False
                cooldown_left = cooldown_bars
            else:
                range_confirmed = self.bar_index - range_left + 1 >= min_range_bars

        # ---- dormant range: wait for a close back inside ----
        if range_dormant and bar_ready:
            if dormant_dir == 1 and self.high[0] > deviation_price:
                deviation_price = self.high[0]
                deviation_time = self.time[0]
            if dormant_dir == -1 and self.low[0] < deviation_price:
                deviation_price = self.low[0]
                deviation_time = self.time[0]
            reentered = self.close[0] >= range_bottom
            if dormant_dir == 1:
                reentered = self.close[0] <= range_top
            expired = self.bar_index - dormant_since >= deviation_window

            if reentered and self.bar_index > dormant_since:
                if show_deviations:
                    deviation_base = self._bullish
                    deviation_text = '⤴  Deviation'
                    deviation_callout = callout_position.BOTTOM_RIGHT
                    if dormant_dir == 1:
                        deviation_base = self._bearish
                        deviation_text = '⤵  Deviation'
                        deviation_callout = callout_position.TOP_RIGHT
                    self.chart.draw(LabelAbs(deviation_text, AbsolutePosition(deviation_time, deviation_price),
                                             font_size=self._font, text_color=self._marker_text,
                                             bg_color=fade(deviation_base, 10), callout_position=deviation_callout))
                marker_opt = self._break_marker.get()
                if marker_opt is not None:
                    self.chart.erase(marker_opt.value())
                    self._break_marker.set(None)
                range_active = True
                range_confirmed = True
                range_dormant = False
                dormant_dir = 0
                cooldown_left = 0
                signal_deviation = True
            elif expired:
                range_dormant = False
                dormant_dir = 0
                self._forget_drawings()

        # ---- keep the live range drawn up to the current bar ----
        if range_active:
            live_height = 0.0
            if range_bottom != 0:
                live_height = (range_top - range_bottom) / range_bottom * 100.0
            border = fade(self._range, 65)
            border_style = line_style.DASHED
            state_text = 'FORMING   '
            if range_confirmed:
                border = fade(self._range, 35)
                border_style = line_style.SOLID
                state_text = 'RANGE   '
            self._render(range_left_time, self.time[0], range_top, range_bottom,
                         border, border_style, self._range,
                         state_text + str(self.bar_index - range_left + 1) + ' BARS   ' + percent_text(live_height),
                         fade(self._range, 10))

        self._range_top.set(range_top)
        self._range_bottom.set(range_bottom)
        self._range_left.set(range_left)
        self._range_left_time.set(range_left_time)
        self._range_opened.set(range_opened)
        self._range_active.set(range_active)
        self._range_confirmed.set(range_confirmed)
        self._range_dormant.set(range_dormant)
        self._dormant_since.set(dormant_since)
        self._dormant_dir.set(dormant_dir)
        self._deviation_price.set(deviation_price)
        self._deviation_time.set(deviation_time)
        self._cooldown_left.set(cooldown_left)

        signal_any_break = signal_break_up or signal_break_down
        return (1.0 if signal_new_range else 0.0,
                1.0 if signal_break_up else 0.0,
                1.0 if signal_break_down else 0.0,
                1.0 if signal_any_break else 0.0,
                1.0 if signal_deviation else 0.0)
