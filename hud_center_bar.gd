@tool
extends Control
class_name HUDCenterBar

# Centre HUD panel — matches the orb rim recipe (dark → bronze → gold →
# dark → cavity) so the bar reads as part of the same stone-set as the
# HP/MP orbs. Decorative grooves are gated behind the `draw_dividers`
# meta flag (default off).

# Same palette as hud_orb.gd's rim (don't drift from it).
const COL_RIM_DARK    := Color(0.10, 0.11, 0.12)   # outer dark + crevice
const COL_RIM_BRONZE  := Color(0.30, 0.32, 0.34)   # mid stone
const COL_RIM_GOLD    := Color(0.55, 0.55, 0.52)   # light stone
const COL_RIM_GOLD_HI := Color(0.78, 0.76, 0.70)   # warm-grey highlight
const COL_VOID        := Color(0.05, 0.06, 0.07)   # cavity black
const COL_SHEEN       := Color(1, 1, 1, 0.05)
const COL_SHADOW      := Color(0, 0, 0, 0.5)

func _draw() -> void:
	var w: int = int(size.x)
	var h: int = int(size.y)
	if w <= 14 or h <= 14:
		return

	# 1) Drop shadow.
	draw_rect(Rect2(2, 4, w, h), COL_SHADOW, true)
	# 2) Outer dark rim — full panel.
	draw_rect(Rect2(0, 0, w, h), COL_RIM_DARK, true)
	# 3) Bronze rim (inset 2 px), same thickness as orb's bronze ring.
	draw_rect(Rect2(2, 2, w - 4, h - 4), COL_RIM_BRONZE, true)
	# 4) Gold pinstripe (inset 4 px) — the orb's gold ring.
	draw_rect(Rect2(4, 4, w - 8, h - 8), COL_RIM_GOLD, true)
	# 5) Inner dark band (inset 5 px) — orb's inner dark cavity edge.
	draw_rect(Rect2(5, 5, w - 10, h - 10), COL_RIM_DARK, true)
	# 6) Cavity void (inset 7 px) — orb's central void colour.
	draw_rect(Rect2(7, 7, w - 14, h - 14), COL_VOID, true)
	# 7) Subtle inner top sheen (matches the glass crescent on the orb).
	draw_rect(Rect2(7, 7, w - 14, max(2, (h - 14) / 6)), COL_SHEEN, true)
	# 8) Four corner rivet studs — same recipe as the orb's cardinal rivets:
	#    4 px dark base + 3 px gold-hi + 1 px white spec.
	var pad: int = 5
	_rivet(pad, pad)
	_rivet(w - pad, pad)
	_rivet(pad, h - pad)
	_rivet(w - pad, h - pad)

	# 9) Optional vertical dividers — only if explicitly opted-in.
	if get_meta("draw_dividers", false):
		var x1: int = w / 4
		var x2: int = (w * 3) / 4
		draw_rect(Rect2(x1, 8, 1, h - 16), COL_RIM_DARK, true)
		draw_rect(Rect2(x1 + 1, 8, 1, h - 16), COL_RIM_GOLD, true)
		draw_rect(Rect2(x2, 8, 1, h - 16), COL_RIM_DARK, true)
		draw_rect(Rect2(x2 + 1, 8, 1, h - 16), COL_RIM_GOLD, true)

func _rivet(cx: int, cy: int) -> void:
	# Mirrors the orb's rivet recipe exactly.
	draw_rect(Rect2(cx - 2, cy - 2, 4, 4), COL_RIM_DARK, true)
	draw_rect(Rect2(cx - 1, cy - 1, 3, 3), COL_RIM_GOLD_HI, true)
	draw_rect(Rect2(cx - 1, cy - 1, 1, 1), Color(1, 1, 1, 0.85), true)
