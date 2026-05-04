@tool
extends Control
class_name HUDOrb

# Diablo-style HP / MP orb with animated liquid inside a glass globe.
# The fluid surface ripples (two-octave sine), and there's a single clean
# crescent-arc reflection on the upper-left of the glass — no stacked
# concentric grey discs. All draws are integer-snapped for pixel-art.

@export_enum("hp", "mp") var kind: String = "hp" :
	set(v):
		kind = v
		queue_redraw()

@export_range(0.0, 1.0) var value: float = 1.0 :
	set(v):
		value = clamp(v, 0.0, 1.0)
		queue_redraw()

# When false, the drawn stone rim + rivet studs are skipped — used when an
# external sculpted frame (e.g. the angel statue) covers the orb periphery.
@export var show_rim: bool = true :
	set(v):
		show_rim = v
		queue_redraw()

const COL_RIM_DARK    := Color(0.10, 0.11, 0.12)   # deepest stone crevice
const COL_RIM_BRONZE  := Color(0.30, 0.32, 0.34)   # mid stone
const COL_RIM_GOLD    := Color(0.55, 0.55, 0.52)   # light stone (was gold)
const COL_RIM_GOLD_HI := Color(0.78, 0.76, 0.70)   # warm-grey highlight
const COL_VOID        := Color(0.05, 0.06, 0.07)

# Fluid colour stops — uniform body with subtle highlight at top + soft
# darkening at the bottom (potion / liquid look, not blood-fading-to-black).
const HP_TOP := Color(1.00, 0.42, 0.38)   # surface highlight tint
const HP_MID := Color(0.92, 0.20, 0.20)   # main body
const HP_LOW := Color(0.85, 0.16, 0.16)   # body deeper
const HP_BOT := Color(0.70, 0.10, 0.10)   # soft bottom shade
const MP_TOP := Color(0.78, 0.95, 1.00)
const MP_MID := Color(0.32, 0.60, 1.00)
const MP_LOW := Color(0.26, 0.52, 0.95)
const MP_BOT := Color(0.18, 0.38, 0.85)

func _ready() -> void:
	# Skip the per-frame redraw in the editor — _draw runs on property
	# changes anyway, and we don't want the surface ripple animating.
	if not Engine.is_editor_hint():
		set_process(true)

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	var w: int = int(size.x)
	var h: int = int(size.y)
	var cx: int = w / 2
	var cy: int = h / 2
	var R: int = mini(w, h) / 2

	var top_col: Color = HP_TOP if kind == "hp" else MP_TOP
	var mid_col: Color = HP_MID if kind == "hp" else MP_MID
	var low_col: Color = HP_LOW if kind == "hp" else MP_LOW
	var bot_col: Color = HP_BOT if kind == "hp" else MP_BOT

	# Drop shadow + frame stack: dark → bronze → gold pinstripe → dark edge.
	# Skipped when an external statue frame covers the orb periphery.
	var inner_R: int
	if show_rim:
		_fill_disc(cx + 2, cy + 4, R, Color(0, 0, 0, 0.5))
		_fill_disc(cx, cy, R, COL_RIM_DARK)
		_fill_disc(cx, cy, R - 2, COL_RIM_BRONZE)
		_fill_disc(cx, cy, R - 4, COL_RIM_GOLD)
		_fill_disc(cx, cy, R - 5, COL_RIM_DARK)
		inner_R = R - 7
	else:
		inner_R = R
	# Empty cavity behind the fluid.
	_fill_disc(cx, cy, inner_R, COL_VOID)

	# --- Liquid: per-column with wavy surface and smooth depth gradient -----
	# Pre-compute the depth-gradient lookup once per draw (one entry per row
	# of the orb). Colour depends on ABSOLUTE y position in the orb so the
	# bottom of the orb is always the darkest tone regardless of fill level.
	var grad: PackedColorArray = PackedColorArray()
	var orb_height: int = inner_R * 2 + 1
	grad.resize(orb_height)
	# Weighted gradient: thin highlight zone at top, large uniform body in
	# the middle, soft darken zone at the bottom — looks like a coloured
	# liquid, not a blood smear that fades to black.
	for i in range(orb_height):
		var dt: float = float(i) / float(orb_height - 1)
		var c: Color
		if dt < 0.18:
			c = top_col.lerp(mid_col, dt / 0.18)        # surface highlight → body
		elif dt < 0.78:
			c = mid_col.lerp(low_col, (dt - 0.18) / 0.60)  # body, slight gradient
		else:
			c = low_col.lerp(bot_col, (dt - 0.78) / 0.22)  # subtle bottom shade
		grad[i] = c

	var t_now: float = float(Time.get_ticks_msec()) * 0.001
	var base_top: float = float(cy + inner_R) - float(inner_R * 2) * value
	var orb_top_y: int = cy - inner_R
	for x in range(-inner_R, inner_R + 1):
		var col_half_h: int = int(sqrt(float(inner_R * inner_R - x * x)))
		var col_top: int = cy - col_half_h
		var col_bot: int = cy + col_half_h
		var wave: float = (
			sin(float(x) * 0.35 + t_now * 2.4) * 1.3
			+ sin(float(x) * 0.18 - t_now * 1.6) * 0.7
		)
		var surface_y: int = int(round(base_top + wave))
		var fluid_top: int = maxi(col_top, surface_y)
		if fluid_top > col_bot:
			continue
		var draw_x: int = cx + x
		# Per-pixel down the column — smooth gradient by table lookup.
		for y in range(fluid_top, col_bot + 1):
			var idx: int = clampi(y - orb_top_y, 0, orb_height - 1)
			draw_rect(Rect2(draw_x, y, 1, 1), grad[idx], true)
		# Bright meniscus right at the surface (only when partially full).
		if value > 0.001 and value < 0.999:
			var sheen := top_col.lerp(Color(1, 1, 1), 0.55)
			sheen.a = 0.7
			draw_rect(Rect2(draw_x, fluid_top, 1, 1), sheen, true)

	# --- Glass crescent (upper-RIGHT, matching D2's screen-right key light) -
	_draw_glass_arc(cx, cy, inner_R - 1, inner_R - 5, -PI * 0.42, PI * 0.08, Color(1, 1, 1, 0.22))
	_draw_glass_arc(cx, cy, inner_R - 2, inner_R - 4, -PI * 0.36, PI * 0.02, Color(1, 1, 1, 0.18))

	# Hot spec dot in the upper-right of the orb.
	var spec_x: int = cx + (inner_R * 4) / 10
	var spec_y: int = cy - (inner_R * 5) / 10
	_fill_disc(spec_x, spec_y, maxi(2, inner_R / 14), Color(1, 1, 1, 0.85))

	# Four gold rivets at cardinal points around the rim — only when the
	# drawn rim is visible.
	if show_rim:
		var ang_list: PackedFloat32Array = PackedFloat32Array([-PI * 0.5, 0.0, PI * 0.5, PI])
		for ang in ang_list:
			var px: int = cx + int(cos(ang) * float(R - 2))
			var py: int = cy + int(sin(ang) * float(R - 2))
			_fill_disc(px, py, 4, COL_RIM_DARK)
			_fill_disc(px, py, 3, COL_RIM_GOLD_HI)
			_fill_disc(px - 1, py - 1, 1, Color(1, 1, 1, 0.85))

# Annular crescent slice from start_ang to end_ang, between inner_r and outer_r.
func _draw_glass_arc(cx: int, cy: int, outer_r: int, inner_r: int,
		start_ang: float, end_ang: float, col: Color) -> void:
	if outer_r <= inner_r:
		return
	var steps: int = 16
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var a: float = lerpf(start_ang, end_ang, t)
		pts.append(Vector2(float(cx) + cos(a) * float(outer_r), float(cy) + sin(a) * float(outer_r)))
	for i in range(steps + 1):
		var t: float = 1.0 - float(i) / float(steps)
		var a: float = lerpf(start_ang, end_ang, t)
		pts.append(Vector2(float(cx) + cos(a) * float(inner_r), float(cy) + sin(a) * float(inner_r)))
	draw_colored_polygon(pts, col)

# Pixel-art filled disc — integer scanlines.
func _fill_disc(cx: int, cy: int, r: int, col: Color) -> void:
	if r <= 0:
		return
	for y in range(-r, r + 1):
		var half_w: int = int(sqrt(float(r * r - y * y)))
		draw_rect(Rect2(cx - half_w, cy + y, half_w * 2 + 1, 1), col, true)
