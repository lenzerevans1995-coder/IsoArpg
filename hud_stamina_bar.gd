@tool
extends Control
class_name HUDStaminaBar

# Beveled stamina bar with golden gradient fill, glossy top sheen, and a
# pulsing leading-edge glow when partially depleted.

@export_range(0.0, 1.0) var value: float = 1.0 :
	set(v):
		value = clamp(v, 0.0, 1.0)
		queue_redraw()

const COL_OUT_DARK   := Color(0.05, 0.05, 0.06)
const COL_RIM_BRONZE := Color(0.32, 0.22, 0.10)
const COL_RIM_GOLD   := Color(0.62, 0.48, 0.22)
const COL_BG_DEEP    := Color(0.08, 0.07, 0.05)
const COL_BG_MID     := Color(0.14, 0.11, 0.06)
const COL_FILL_HI    := Color(1.00, 0.92, 0.40)
const COL_FILL_MID   := Color(0.95, 0.72, 0.20)
const COL_FILL_LO    := Color(0.62, 0.42, 0.06)
const COL_GLOSS      := Color(1.00, 0.95, 0.65, 0.45)
const COL_GLOW       := Color(1.00, 0.85, 0.40, 0.85)

func _ready() -> void:
	if not Engine.is_editor_hint():
		set_process(true)

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	var w: int = int(size.x)
	var h: int = int(size.y)
	# Outer dark frame.
	draw_rect(Rect2(0, 0, w, h), COL_OUT_DARK, true)
	# Bronze rim (1 px) with brighter top, darker bottom.
	draw_rect(Rect2(1, 1, w - 2, 1), COL_RIM_GOLD, true)
	draw_rect(Rect2(1, h - 2, w - 2, 1), COL_RIM_BRONZE, true)
	draw_rect(Rect2(1, 1, 1, h - 2), COL_RIM_GOLD, true)
	draw_rect(Rect2(w - 2, 1, 1, h - 2), COL_RIM_BRONZE, true)
	# Dark cavity behind the fill.
	draw_rect(Rect2(2, 2, w - 4, h - 4), COL_BG_DEEP, true)
	draw_rect(Rect2(2, 2, w - 4, max(1, (h - 4) / 2)), COL_BG_MID, true)
	# Fill — golden vertical gradient, clipped horizontally by `value`.
	var fill_w: int = int(round(float(w - 4) * value))
	if fill_w > 0:
		var fh: int = h - 4
		var top_h: int = maxi(1, fh / 3)
		var mid_h: int = maxi(1, fh / 3)
		var bot_h: int = fh - top_h - mid_h
		draw_rect(Rect2(2, 2, fill_w, top_h), COL_FILL_HI, true)
		draw_rect(Rect2(2, 2 + top_h, fill_w, mid_h), COL_FILL_MID, true)
		draw_rect(Rect2(2, 2 + top_h + mid_h, fill_w, bot_h), COL_FILL_LO, true)
		# Glossy top sheen (1 px).
		draw_rect(Rect2(2, 2, fill_w, 1), COL_GLOSS, true)
		# Pulsing leading-edge glow (skipped at 0% / 100%).
		if value > 0.001 and value < 0.999:
			var pulse: float = sin(float(Time.get_ticks_msec()) * 0.005) * 0.5 + 0.5
			var glow_col := Color(COL_GLOW.r, COL_GLOW.g, COL_GLOW.b, COL_GLOW.a * (0.55 + 0.45 * pulse))
			var gw: int = 2 + int(pulse * 1.5)
			draw_rect(Rect2(2 + fill_w - gw, 2, gw, fh), glow_col, true)
	# Tick marks every 25%.
	for i in range(1, 4):
		var tx: int = 2 + int(float(w - 4) * (float(i) / 4.0))
		draw_rect(Rect2(tx, 2, 1, h - 4), Color(0, 0, 0, 0.35), true)
