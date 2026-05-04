@tool
extends Control
class_name FighterBar

# Composite FighterBar (HP top row + tag bottom row + 2 mana secondaries).
# Designed to be assembled in the Godot editor — every visual layer is a
# child node you can select, resize, and re-slice via the inspector.
#
# The script only handles: clipping fills to value, and laying out the
# secondaries so they fill the bottom row to the right of the tag area.
# Everything else (textures, slice margins, colours) is editor-driven.

# --- Editor-tweakable layout knobs -----------------------------------------

@export var bottom_tag_end_x: int = 18 :
	set(v):
		bottom_tag_end_x = v
		_apply_layout()

@export var top_band_height: int = 6 :
	set(v):
		top_band_height = v
		_apply_layout()

@export var secondary_gap: int = 2 :
	set(v):
		secondary_gap = v
		_apply_layout()

@export_range(0.0, 1.0) var hp_value: float = 1.0 :
	set(v):
		hp_value = clamp(v, 0.0, 1.0)
		_apply_hp()

@export_range(0.0, 1.0) var mana_a_value: float = 1.0 :
	set(v):
		mana_a_value = clamp(v, 0.0, 1.0)
		_apply_secondary(0)

@export_range(0.0, 1.0) var mana_b_value: float = 1.0 :
	set(v):
		mana_b_value = clamp(v, 0.0, 1.0)
		_apply_secondary(1)

# Cached node refs.
@onready var _bg: NinePatchRect = $Background
@onready var _top_clip: Control = $TopFillClip
@onready var _top_fill: NinePatchRect = $TopFillClip/Fill
@onready var _tag_clip: Control = $TagFillClip
@onready var _tag_fill: NinePatchRect = $TagFillClip/Fill
@onready var _sec_a: Control = $SecondaryA
@onready var _sec_a_clip: Control = $SecondaryA/FillClip
@onready var _sec_b: Control = $SecondaryB
@onready var _sec_b_clip: Control = $SecondaryB/FillClip

func _ready() -> void:
	resized.connect(_apply_layout)
	_apply_layout()
	_apply_hp()
	_apply_secondary(0)
	_apply_secondary(1)

# Public API ----------------------------------------------------------------

func set_hp(v: float, m: float) -> void:
	hp_value = clamp(v / max(m, 1.0), 0.0, 1.0)

func set_secondary(idx: int, v: float, m: float) -> void:
	var t: float = clamp(v / max(m, 1.0), 0.0, 1.0)
	if idx == 0: mana_a_value = t
	elif idx == 1: mana_b_value = t

# Layout --------------------------------------------------------------------

func _apply_layout() -> void:
	if not is_inside_tree():
		return
	var w: float = size.x
	var h: float = size.y
	# Top fill band — full width, height = top_band_height (caps the top row).
	if _top_clip:
		_top_clip.position = Vector2(0, 0)
		_top_clip.size = Vector2(w, top_band_height)
	if _top_fill:
		_top_fill.size = Vector2(w, h)               # full bar; clip cuts to top band
		_top_fill.position = Vector2.ZERO
	# Tag fill — bottom-band region of the left "tag", fixed pixel width.
	if _tag_clip:
		_tag_clip.position = Vector2(0, top_band_height)
		_tag_clip.size = Vector2(bottom_tag_end_x, h - top_band_height)
	if _tag_fill:
		_tag_fill.size = Vector2(w, h)
		_tag_fill.position = Vector2(0, -top_band_height)
	# Secondaries — split remaining bottom-row space after the tag.
	var sec_origin_x: float = float(bottom_tag_end_x + 1)
	var remaining_w: float = max(0.0, w - sec_origin_x)
	var sec_w: float = max(0.0, (remaining_w - secondary_gap) * 0.5)
	var sec_h: float = h - top_band_height + 1.0     # rows 5-9 of the bar
	var sec_y: float = top_band_height - 1.0
	if _sec_a:
		_sec_a.position = Vector2(sec_origin_x, sec_y)
		_sec_a.size = Vector2(sec_w, sec_h)
	if _sec_b:
		_sec_b.position = Vector2(sec_origin_x + sec_w + secondary_gap, sec_y)
		_sec_b.size = Vector2(sec_w, sec_h)
	_apply_hp()
	_apply_secondary(0)
	_apply_secondary(1)

func _apply_hp() -> void:
	if _top_clip:
		_top_clip.size.x = size.x * hp_value
	if _tag_clip:
		_tag_clip.size.x = float(bottom_tag_end_x) * hp_value

func _apply_secondary(idx: int) -> void:
	var node: Control = _sec_a_clip if idx == 0 else _sec_b_clip
	var v: float = mana_a_value if idx == 0 else mana_b_value
	if node and is_instance_valid(node):
		var full_w: float = float(node.get_meta("_full_w", 0.0))
		if full_w <= 0.0:
			full_w = node.size.x
			node.set_meta("_full_w", full_w)
		# Re-cache full_w when the secondary parent is resized.
		var parent_w: float = (node.get_parent() as Control).size.x - 4.0
		if parent_w > 0.0 and abs(parent_w - full_w) > 0.5:
			full_w = parent_w
			node.set_meta("_full_w", full_w)
		node.size.x = full_w * v
