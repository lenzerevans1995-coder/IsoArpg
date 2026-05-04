extends Node2D
class_name LayeredCharacter

# Stacked-sprite character driver. Each "layer" is a Sprite2D pointing at a
# different equipment sheet; all layers share the same (direction_row, frame_col)
# pair so swapping a Chest or Head texture instantly re-skins the same anim.
#
# Sheets live next to the standalone Unity character creator (already pre-rendered
# at HD: 1920x1024 = 15 cols x 8 rows of 128x128 frames, rows are clockwise from
# facing-right matching player.gd's _vec_to_dir).
const SHEETS_ROOT := "res://assets/charachters/Stand-alone Character creator - 2D Fantasy V1-0-3/Character creator - 2D Fantasy_Data/StreamingAssets/spritesheets/"
const FRAME_W := 128
const FRAME_H := 128
const COLS := 15
const ROWS := 8
const DEFAULT_FPS := 12.0

# Layer order: back -> front. Each entry is the loadout key.
const LAYERS := [
	"shadow",
	"mount",
	"body",
	"legs",
	"shoes",
	"chest",
	"belt",
	"bag",
	"hands",
	"head",
	"offhand",
	"mainhand",
	"vfx",
]

# Some slots don't have every anim file; if a sheet is missing the layer hides
# for that anim. Cache holds null for verified-missing so we don't disk-thrash.
static var _tex_cache: Dictionary = {}

@export var sprite_offset: Vector2 = Vector2(0, -26)

var _sprites: Dictionary = {}        # layer_name -> Sprite2D
var _equip: Dictionary = {}          # layer_name -> sheet folder name (e.g. "Chest3"); "" = empty
var _tints: Dictionary = {}          # layer_name -> Color (modulate)
var _anim: String = "Idle"
var _fps: float = DEFAULT_FPS
var _direction: int = 2              # facing south by default
var _anim_time: float = 0.0
var _frame: int = 0
var _looping: bool = true
var _finished_cb: Callable = Callable()

func _ready() -> void:
	for layer_name in LAYERS:
		var s := Sprite2D.new()
		s.name = layer_name
		s.centered = true
		s.region_enabled = true
		s.region_rect = Rect2(0, 0, FRAME_W, FRAME_H)
		s.offset = sprite_offset
		s.visible = false
		s.modulate = _tints.get(layer_name, Color.WHITE)
		add_child(s)
		_sprites[layer_name] = s
		if not _equip.has(layer_name):
			_equip[layer_name] = ""
	# Apply any equip()/play_anim() calls that arrived before _ready().
	_refresh_all_layers()

func equip(layer_name: String, folder: String) -> void:
	if not (layer_name in LAYERS):
		push_warning("LayeredCharacter: unknown layer %s" % layer_name)
		return
	_equip[layer_name] = folder
	if _sprites.has(layer_name):
		_refresh_layer(layer_name)

func clear_layer(layer_name: String) -> void:
	equip(layer_name, "")

func set_tint(layer_name: String, color: Color) -> void:
	_tints[layer_name] = color
	if _sprites.has(layer_name):
		_sprites[layer_name].modulate = color

func get_tint(layer_name: String) -> Color:
	return _tints.get(layer_name, Color.WHITE)

func get_equipped(layer_name: String) -> String:
	return _equip.get(layer_name, "")

func play_anim(anim_name: String, fps: float = -1.0, looping: bool = true, finished_cb: Callable = Callable()) -> void:
	_anim = anim_name
	_fps = fps if fps > 0.0 else DEFAULT_FPS
	_looping = looping
	_finished_cb = finished_cb
	_anim_time = 0.0
	_frame = 0
	_refresh_all_layers()

func set_direction(dir: int) -> void:
	_direction = clamp(dir, 0, ROWS - 1)
	_apply_region_to_all()

func get_direction() -> int:
	return _direction

func _process(delta: float) -> void:
	_anim_time += delta
	var f: int = int(_anim_time * _fps)
	if _looping:
		f = f % COLS
	else:
		if f >= COLS:
			f = COLS - 1
			if not _finished_cb.is_null():
				var cb := _finished_cb
				_finished_cb = Callable()
				cb.call()
	if f != _frame:
		_frame = f
		_apply_region_to_all()

func _refresh_all_layers() -> void:
	for layer_name in LAYERS:
		if _sprites.has(layer_name):
			_refresh_layer(layer_name)

func _refresh_layer(layer_name: String) -> void:
	if not _sprites.has(layer_name):
		return
	var s: Sprite2D = _sprites[layer_name]
	var folder: String = String(_equip.get(layer_name, ""))
	if folder == "":
		s.visible = false
		s.texture = null
		return
	var tex: Texture2D = _load_sheet(folder, _anim)
	if tex == null:
		# Fall back to Idle if this slot lacks the requested anim (e.g. Effect1
		# only has Attack1).
		tex = _load_sheet(folder, "Idle")
	if tex == null:
		s.visible = false
		s.texture = null
		return
	s.texture = tex
	s.visible = true
	s.region_rect = Rect2(_frame * FRAME_W, _direction * FRAME_H, FRAME_W, FRAME_H)

func _apply_region_to_all() -> void:
	var rect := Rect2(_frame * FRAME_W, _direction * FRAME_H, FRAME_W, FRAME_H)
	for layer_name in LAYERS:
		var s: Sprite2D = _sprites[layer_name]
		if s.texture != null:
			s.region_rect = rect

static func _load_sheet(folder: String, anim_name: String) -> Texture2D:
	var path := SHEETS_ROOT + folder + "/" + anim_name + ".png"
	if _tex_cache.has(path):
		return _tex_cache[path]
	if not ResourceLoader.exists(path):
		_tex_cache[path] = null
		return null
	var tex: Texture2D = load(path)
	_tex_cache[path] = tex
	return tex
