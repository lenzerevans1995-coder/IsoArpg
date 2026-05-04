@tool
extends Control
class_name HUDBelt

# Diablo 2 skill action bar: 16 slots in two banks of 8 with a small gap
# in the middle, set into a chiselled stone/iron panel. Keybinds F1-F8 on
# the left bank, F9-F16 on the right.

@export var slot_count: int = 16 :
	set(v):
		slot_count = max(2, v)
		queue_redraw()

@export var slot_size: int = 38 :
	set(v):
		slot_size = max(8, v)
		queue_redraw()

@export var slot_gap: int = 3 :
	set(v):
		slot_gap = max(0, v)
		queue_redraw()

@export var bank_gap: int = 14 :       # gap between the two banks of 8
	set(v):
		bank_gap = max(0, v)
		queue_redraw()

# Granite/slate palette matching the carved stone HP holder.
const COL_STONE_DARK   := Color(0.10, 0.11, 0.12)
const COL_STONE_MID    := Color(0.22, 0.24, 0.25)
const COL_STONE_LIGHT  := Color(0.40, 0.42, 0.42)
const COL_BRONZE_DARK  := Color(0.18, 0.20, 0.22)
const COL_BRONZE_MID   := Color(0.32, 0.34, 0.36)
const COL_GOLD         := Color(0.55, 0.55, 0.52)   # light stone (replaces gold)
const COL_GOLD_HI      := Color(0.78, 0.76, 0.70)   # warm-grey highlight
const COL_VOID         := Color(0.05, 0.06, 0.07)

func _draw() -> void:
	var w: int = int(size.x)
	var h: int = int(size.y)
	# Drop shadow.
	draw_rect(Rect2(2, 4, w, h), Color(0, 0, 0, 0.55), true)
	# Outer dark stone edge.
	draw_rect(Rect2(0, 0, w, h), COL_STONE_DARK, true)
	# Stone body — three-tone stepped bevel: dark top, mid middle, light bottom.
	draw_rect(Rect2(2, 2, w - 4, h - 4), COL_STONE_MID, true)
	# Top stone highlight (1 px).
	draw_rect(Rect2(2, 2, w - 4, 1), COL_STONE_LIGHT, true)
	# Bottom stone shadow.
	draw_rect(Rect2(2, h - 3, w - 4, 1), COL_STONE_DARK, true)
	# Bronze inner trim.
	draw_rect(Rect2(4, 4, w - 8, h - 8), COL_BRONZE_DARK, true)
	draw_rect(Rect2(5, 5, w - 10, 1), COL_BRONZE_MID, true)
	draw_rect(Rect2(5, 5, 1, h - 10), COL_BRONZE_MID, true)
	draw_rect(Rect2(5, h - 6, w - 10, 1), Color(0.18, 0.12, 0.06), true)
	# Recessed inner panel.
	draw_rect(Rect2(6, 6, w - 12, h - 12), COL_STONE_DARK, true)

	# Layout: optional split into two banks (D2 style) when bank_gap > 0,
	# otherwise a single centred row of `slot_count` slots.
	var slot_y: int = (h - slot_size) / 2
	if bank_gap > 0 and slot_count >= 2:
		var per_bank: int = slot_count / 2
		var bank_w: int = per_bank * slot_size + (per_bank - 1) * slot_gap
		var total_w: int = bank_w * 2 + bank_gap
		var origin_x: int = (w - total_w) / 2
		for i in range(slot_count):
			var bank_idx: int = i / per_bank
			var idx_in_bank: int = i % per_bank
			var sx: int = origin_x + bank_idx * (bank_w + bank_gap) + idx_in_bank * (slot_size + slot_gap)
			_draw_slot(sx, slot_y)
	else:
		var total_w: int = slot_count * slot_size + (slot_count - 1) * slot_gap
		var origin_x: int = (w - total_w) / 2
		for i in range(slot_count):
			var sx: int = origin_x + i * (slot_size + slot_gap)
			_draw_slot(sx, slot_y)

func _draw_slot(x: int, y: int) -> void:
	# Outer dark recess (sunken into the panel).
	draw_rect(Rect2(x - 2, y - 2, slot_size + 4, slot_size + 4), COL_STONE_DARK, true)
	# Bronze rim.
	draw_rect(Rect2(x - 1, y - 1, slot_size + 2, slot_size + 2), COL_BRONZE_MID, true)
	# Gold pinstripe.
	draw_rect(Rect2(x, y, slot_size, slot_size), COL_GOLD, true)
	# Inner dark.
	draw_rect(Rect2(x + 1, y + 1, slot_size - 2, slot_size - 2), COL_STONE_DARK, true)
	# Cavity.
	draw_rect(Rect2(x + 2, y + 2, slot_size - 4, slot_size - 4), COL_VOID, true)
	# Faint inner top sheen.
	draw_rect(Rect2(x + 2, y + 2, slot_size - 4, max(2, (slot_size - 4) / 5)), Color(1, 1, 1, 0.06), true)
	# Gold corner accents.
	var ts: int = 4
	_corner_tri(x, y, ts, 0)
	_corner_tri(x + slot_size, y, ts, 1)
	_corner_tri(x, y + slot_size, ts, 2)
	_corner_tri(x + slot_size, y + slot_size, ts, 3)

func _corner_tri(x: int, y: int, ts: int, corner: int) -> void:
	var pts := PackedVector2Array()
	match corner:
		0:  pts = PackedVector2Array([Vector2(x, y), Vector2(x + ts, y), Vector2(x, y + ts)])
		1:  pts = PackedVector2Array([Vector2(x, y), Vector2(x - ts, y), Vector2(x, y + ts)])
		2:  pts = PackedVector2Array([Vector2(x, y), Vector2(x + ts, y), Vector2(x, y - ts)])
		_:  pts = PackedVector2Array([Vector2(x, y), Vector2(x - ts, y), Vector2(x, y - ts)])
	draw_colored_polygon(pts, COL_GOLD)
