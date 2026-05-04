extends Node2D
class_name AttackEffect

# One-shot Fantasy-tileset attack overlay (slash trail / magic burst).
# Layout: 1920x1024 sheet, 15 cols x 8 rows at 128 px per cell.
# Rows = direction (0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE).

const COLS := 15
const ROWS := 8
const CELL := 128
const FPS := 22.0

@export var effect_set: String = "Slash1"
@export var anim_name: String = "Attack1"
@export var direction: int = 2
# Add to row index when sampling (in case a particular effect set's rows are
# offset from the body convention). 0 = match body 1:1.
@export var row_offset: int = 0

var _sprite: Sprite2D
var _frame: float = 0.0

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.region_enabled = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)
	_load_sheet()

func _load_sheet() -> void:
	var path := "res://assets/effects/%s/%s.png" % [effect_set, anim_name]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		var img := Image.new()
		var fs := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path) or FileAccess.file_exists(fs):
			if img.load(path if FileAccess.file_exists(path) else fs) == OK:
				tex = ImageTexture.create_from_image(img)
	if tex == null:
		push_warning("attack_effect: missing %s" % path)
		queue_free()
		return
	_sprite.texture = tex
	_update_region()

func _process(delta: float) -> void:
	_frame += delta * FPS
	if _frame >= float(COLS):
		queue_free()
		return
	_update_region()

func _update_region() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var col: int = int(floor(_frame))
	var row: int = posmod(direction + row_offset, ROWS)
	_sprite.region_rect = Rect2(col * CELL, row * CELL, CELL, CELL)
