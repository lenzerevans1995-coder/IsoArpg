extends Node2D
class_name CompositeCharacter

# In-game player renderer that uses a SINGLE pre-baked composite spritesheet
# instead of stacking 9 live layers. Same animation API as
# LayeredOtherworldsCharacter — just much cheaper (one texture, one Sprite2D).

const CATALOG_PATH := "res://data/character_pieces_catalog.json"
const SHADER_PATH := "res://shaders/monster_painterly.gdshader"
const SWATCH_PATH := "res://data/swatch_palette.json"
const KIT_CATALOG_OVERRIDE := {
	"goblin": "res://data/monster_anim_catalog.json",
}
const DIR_TO_CATALOG := [2, 6, 0, 4, 1, 5, 3, 7]   # E,SE,S,SW,W,NW,N,NE -> S,W,E,N,SW,NW,SE,NE

@export var display_size: float = 96.0
@export var fps: float = 6.0
@export var foot_anchor_y: float = 0.15

var kit: String = "female"
var SLOT_ORDER: Array = []   # exposed for player_otherworlds compatibility (no-op here)

var _sprite: Sprite2D
var _catalog: Dictionary = {}
var _grid: int = 50
var _frame_size: int = 0
var _direction: int = 2
var _current_anim: String = ""
var _anim_def: Dictionary = {}
var _frame: float = 0.0
var _looping: bool = true
var _playing: bool = true
var _finished_cb: Callable = Callable()
var _palette_tex: Texture2D = null
var _shader_pixel_size: float = 1.3
var _shader_palette_mix: float = 0.0

func _ready() -> void:
	y_sort_enabled = true
	_palette_tex = _build_palette_texture()
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.region_enabled = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_sprite.material = _build_painterly_material()
	add_child(_sprite)
	_load_catalog()

func _build_painterly_material() -> ShaderMaterial:
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("pixel_size", _shader_pixel_size)
	mat.set_shader_parameter("palette_levels", 9)
	mat.set_shader_parameter("saturation", 1.0)
	mat.set_shader_parameter("contrast", 1.0)
	mat.set_shader_parameter("brightness", 0.0)
	mat.set_shader_parameter("outline_strength", 0.0)
	mat.set_shader_parameter("alpha_cutoff", 0.35)
	mat.set_shader_parameter("warm_tint", Vector3(1, 1, 1))
	mat.set_shader_parameter("palette_mix", _shader_palette_mix)
	mat.set_shader_parameter("glow_strength", 0.0)
	if _palette_tex:
		mat.set_shader_parameter("palette_tex", _palette_tex)
		mat.set_shader_parameter("palette_size", _palette_tex.get_width())
	return mat

func _build_palette_texture() -> Texture2D:
	var f := FileAccess.open(SWATCH_PATH, FileAccess.READ)
	if f == null:
		return null
	var swatches: Array = JSON.parse_string(f.get_as_text())
	if swatches.is_empty():
		return null
	var img := Image.create(swatches.size(), 1, false, Image.FORMAT_RGBA8)
	for i in range(swatches.size()):
		img.set_pixel(i, 0, Color(String(swatches[i])))
	return ImageTexture.create_from_image(img)

func _load_catalog() -> void:
	var path: String = KIT_CATALOG_OVERRIDE.get(kit, CATALOG_PATH)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	_catalog = JSON.parse_string(f.get_as_text())
	_grid = int(_catalog.get("grid", 50))

func reload_catalog() -> void:
	_load_catalog()

func set_composite_path(path: String) -> void:
	if path == "" or _sprite == null:
		return
	var img := Image.new()
	var fs_path := ProjectSettings.globalize_path(path)
	var err := img.load(path if FileAccess.file_exists(path) else fs_path)
	if err != OK:
		push_warning("composite_character: failed to load %s" % path)
		return
	var tex := ImageTexture.create_from_image(img)
	_sprite.texture = tex
	_frame_size = int(tex.get_width() / _grid)
	_sprite.scale = Vector2.ONE * (display_size / float(_frame_size))
	_sprite.offset = Vector2(0, -float(_frame_size) * (0.5 - foot_anchor_y))
	_update_region()

func play_anim(name: String, looping: bool = true, finished_cb: Callable = Callable()) -> void:
	var anims: Dictionary = _catalog.get("animations", {})
	if not anims.has(name):
		return
	_current_anim = name
	_anim_def = anims[name]
	_frame = 0.0
	_looping = looping
	_finished_cb = finished_cb
	_playing = true
	_update_region()

func set_direction(player_dir: int) -> void:
	_direction = clamp(player_dir, 0, 7)
	_update_region()

func _process(delta: float) -> void:
	if not _playing or _anim_def.is_empty():
		return
	var per_dir: int = int(_anim_def.get("per_dir", 1))
	if per_dir <= 1:
		return
	_frame += delta * fps
	if _frame >= float(per_dir):
		if _looping:
			_frame = fmod(_frame, float(per_dir))
		else:
			_frame = float(per_dir) - 1.0
			_playing = false
			var cb := _finished_cb
			_finished_cb = Callable()
			if cb.is_valid():
				cb.call()
	_update_region()

func _update_region() -> void:
	if _sprite == null or _sprite.texture == null or _frame_size <= 0:
		return
	var per_dir: int = int(_anim_def.get("per_dir", 1))
	var start: int = int(_anim_def.get("start", 0))
	var cat_dir: int = DIR_TO_CATALOG[_direction]
	var idx: int = start + cat_dir * per_dir + int(floor(_frame))
	var col: int = idx % _grid
	var row: int = idx / _grid
	_sprite.region_rect = Rect2(col * _frame_size, row * _frame_size, _frame_size, _frame_size)
	# Push the active cell's UV bounds so the painterly shader's neighbour
	# samples (outline / glow) clamp inside the cell rather than bleeding
	# into adjacent frames.
	if _sprite.material is ShaderMaterial and _sprite.texture:
		var tw: float = float(_sprite.texture.get_width())
		var th: float = float(_sprite.texture.get_height())
		var u_min := Vector2(float(col * _frame_size) / tw, float(row * _frame_size) / th)
		var u_max := Vector2(float((col + 1) * _frame_size) / tw, float((row + 1) * _frame_size) / th)
		var mat: ShaderMaterial = _sprite.material
		mat.set_shader_parameter("region_uv_min", u_min)
		mat.set_shader_parameter("region_uv_max", u_max)

# Slot setters are no-ops at runtime — equipment changes happen by re-baking
# the composite via CompositeBaker, then calling set_composite_path again.
func set_slot(_slot: String, _variant: String) -> void: pass
func set_slot_color(_slot: String, _c: Color) -> void: pass

func set_shader_pixel_size(v: float) -> void:
	_shader_pixel_size = v
	if _sprite and _sprite.material is ShaderMaterial:
		(_sprite.material as ShaderMaterial).set_shader_parameter("pixel_size", v)

func set_shader_palette_mix(v: float) -> void:
	_shader_palette_mix = v
	if _sprite and _sprite.material is ShaderMaterial:
		(_sprite.material as ShaderMaterial).set_shader_parameter("palette_mix", v)
