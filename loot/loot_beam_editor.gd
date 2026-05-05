@tool
extends Node2D

# Visual placement scene for the rarity beam over a coin pile.
# Open this scene in the editor and tweak `beam_offset_y` /
# `beam_height` / `beam_width` in the inspector — the gold + beam
# render live and the printed values can be copy-pasted back into
# loot_drop.gd. Saves you eyeballing it through gameplay.

const COIN_PATH := "res://assets/drops/gold_drop/coins_drop.png"
const TILE_PATH := "res://assets/forest/environment/Ground A1_S.png"

@export var beam_offset_y: float = 0.0 :
	set(v):
		beam_offset_y = v
		_refresh()
@export var beam_offset_x: float = 0.0 :
	set(v):
		beam_offset_x = v
		_refresh()
@export var beam_width: float = 6.0 :
	set(v):
		beam_width = v
		_refresh()
@export var beam_height: float = 90.0 :
	set(v):
		beam_height = v
		_refresh()
@export_range(0, 4) var rarity: int = 0 :
	set(v):
		rarity = v
		_refresh()
@export var print_values: bool = false :
	set(v):
		if v:
			print("[loot_beam_editor]")
			print("  offset = Vector2(", beam_offset_x, ", ", beam_offset_y, ")")
			print("  size   = Vector2(", beam_width, ", ", beam_height, ")")

const _RarityVisuals := preload("res://loot/rarity_visuals.gd")

var _tile: Sprite2D
var _gold: Sprite2D
var _beam: Node2D

func _ready() -> void:
	_tile = Sprite2D.new()
	_tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tile.centered = true
	_tile.offset = Vector2(0, -42)
	if ResourceLoader.exists(TILE_PATH):
		_tile.texture = load(TILE_PATH)
	_tile.z_index = -2
	add_child(_tile)
	_gold = Sprite2D.new()
	_gold.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_gold.centered = true
	_gold.offset = Vector2.ZERO
	if ResourceLoader.exists(COIN_PATH):
		_gold.texture = load(COIN_PATH)
	_gold.z_index = 30
	add_child(_gold)
	_beam = _BeamDrawer.new()
	_beam.z_index = 29
	add_child(_beam)
	_refresh()

func _refresh() -> void:
	if _beam == null:
		return
	(_beam as _BeamDrawer).beam_color = _RarityVisuals.color_for(clampi(rarity, 0, 4))
	(_beam as _BeamDrawer).beam_width = beam_width
	(_beam as _BeamDrawer).beam_height = beam_height
	_beam.position = Vector2(beam_offset_x, beam_offset_y)
	_beam.queue_redraw()

class _BeamDrawer extends Node2D:
	var beam_color: Color = Color(1, 1, 1, 1)
	var beam_width: float = 6.0
	var beam_height: float = 90.0
	func _draw() -> void:
		var w := beam_width
		var h := beam_height
		var glow_col: Color = beam_color
		glow_col.a = 0.18
		draw_rect(Rect2(-w * 1.5, -h, w * 3.0, h), glow_col, true)
		var mid_col: Color = beam_color
		mid_col.a = 0.45
		draw_rect(Rect2(-w * 0.85, -h, w * 1.7, h), mid_col, true)
		var core_col: Color = beam_color
		core_col.a = 0.95
		draw_rect(Rect2(-w * 0.5, -h, w, h), core_col, true)
