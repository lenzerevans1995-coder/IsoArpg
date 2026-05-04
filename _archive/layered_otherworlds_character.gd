extends Node2D
class_name LayeredOtherworldsCharacter

# Live-layered character built from PVGames OtherWorlds character pieces.
# Keeps all 7 layers loaded simultaneously so equipment swaps are O(1)
# (just reassigns one layer's texture).

const CATALOG_PATH := "res://data/character_pieces_catalog.json"
const PIECES_ROOT := "res://assets/character_pieces"
# Some kits ship as the 21x21 monster format (Goblin) instead of the 50x50
# CharacterPieces format. Map them to a different catalog.
const KIT_CATALOG_OVERRIDE := {
	"goblin": "res://data/monster_anim_catalog.json",
}

# Render order: bottom -> top. Shadow first, weapons on top.
const SLOT_ORDER := ["Shadow", "Base", "Bottom", "Top", "Head", "Hair", "FacialHair", "Accessories", "Weapons"]
# Per-kit override: some asset packs (Backer) need Head rendered above Hair.
const SLOT_ORDER_OVERRIDE := {
	"backer_female": ["Shadow", "Base", "Bottom", "Top", "Hair", "Head", "FacialHair", "Accessories", "Weapons"],
	"backer_male":   ["Shadow", "Base", "Bottom", "Top", "Hair", "Head", "FacialHair", "Accessories", "Weapons"],
}
const SHADER_PATH := "res://shaders/monster_painterly.gdshader"
const SWATCH_PATH := "res://data/swatch_palette.json"

# Catalog directions: [S, W, E, N, SW, NW, SE, NE].
# Maps player_layered.gd's 0..7 (E=0, CCW with y-down) to catalog index.
const DIR_TO_CATALOG := [2, 6, 0, 4, 1, 5, 3, 7]

@export var kit: String = "female"
@export var display_size: float = 128.0
@export var fps: float = 6.0
@export var foot_anchor_y: float = 0.15

var _layers: Dictionary = {}             # slot_name -> Sprite2D
var _layer_colors: Dictionary = {}       # slot_name -> Color (modulate)
var _selection: Dictionary = {}          # slot_name -> variant ("OtherWorlds_3" or "")
var _catalog: Dictionary = {}
var _grid: int = 50
var _frame_size: int = 0
var _direction: int = 2                  # player-style index (E=0..NE=7)
var _current_anim: String = "Idle 1"
var _anim_def: Dictionary = {}
var _frame: float = 0.0
var _ping_dir: int = 1
var _playing: bool = true
var _looping: bool = true
var _finished_cb: Callable = Callable()
var _palette_tex: Texture2D = null
var _shader_pixel_size: float = 1.3
var _shader_palette_mix: float = 0.0

func _ready() -> void:
	y_sort_enabled = true
	_load_catalog()
	_palette_tex = _build_palette_texture()
	for slot in SLOT_ORDER:
		var s := Sprite2D.new()
		s.centered = true
		s.region_enabled = true
		s.visible = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		s.material = _build_painterly_material()
		add_child(s)
		_layers[slot] = s
		_layer_colors[slot] = Color.WHITE
	play_anim(_current_anim, true)

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

func set_shader_pixel_size(v: float) -> void:
	_shader_pixel_size = v
	for slot in _layers:
		var spr: Sprite2D = _layers[slot]
		if spr.material is ShaderMaterial:
			(spr.material as ShaderMaterial).set_shader_parameter("pixel_size", v)

func set_shader_palette_mix(v: float) -> void:
	_shader_palette_mix = v
	for slot in _layers:
		var spr: Sprite2D = _layers[slot]
		if spr.material is ShaderMaterial:
			(spr.material as ShaderMaterial).set_shader_parameter("palette_mix", v)

func _load_catalog() -> void:
	var path: String = KIT_CATALOG_OVERRIDE.get(kit, CATALOG_PATH)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("layered_ow: missing %s" % path)
		return
	_catalog = JSON.parse_string(f.get_as_text())
	_grid = int(_catalog.get("grid", 50))
	_frame_size = int(_catalog.get("frame_size", 80))

func set_slot(slot: String, variant: String) -> void:
	# variant == "" clears the slot.
	_selection[slot] = variant
	var spr: Sprite2D = _layers.get(slot)
	if spr == null:
		push_warning("layered_ow: unknown slot %s" % slot)
		return
	if variant == "":
		spr.texture = null
		spr.visible = false
		return
	var path := _piece_path(slot, variant)
	var tex: Texture2D = _load_texture_robust(path)
	if tex == null:
		push_warning("layered_ow: missing %s" % path)
		print("[layered_ow] FAILED slot=", slot, " variant=", variant, " path=", path)
		spr.visible = false
		return
	print("[layered_ow] loaded slot=", slot, " variant=", variant, " size=", tex.get_size())
	spr.texture = tex
	if tex:
		var fs := int(tex.get_width() / _grid)
		spr.scale = Vector2.ONE * (display_size / float(fs))
		spr.offset = Vector2(0, -float(fs) * (0.5 - foot_anchor_y))
	spr.modulate = _layer_colors[slot]
	spr.visible = true
	_update_region(slot)

# Shared across every LayeredOtherworldsCharacter instance (player + creator
# preview + any spawned NPCs). Without this each character was decoding its
# own 8000² PNG into VRAM separately — heavy memory churn.
static var _texture_cache: Dictionary = {}

func _load_texture_robust(path: String) -> Texture2D:
	# Try the resource pipeline first; fall back to runtime Image loading for
	# PNGs that haven't been imported by the editor yet (e.g. just baked).
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	if tex == null:
		var fs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path) or FileAccess.file_exists(fs_path):
			var img := Image.new()
			var err := img.load(path if FileAccess.file_exists(path) else fs_path)
			if err == OK:
				tex = ImageTexture.create_from_image(img)
	if tex:
		_texture_cache[path] = tex
	return tex

func set_slot_color(slot: String, c: Color) -> void:
	_layer_colors[slot] = c
	if _layers.has(slot):
		(_layers[slot] as Sprite2D).modulate = c

func reload_catalog() -> void:
	# Call after changing `kit` if the new kit may use a different catalog.
	_load_catalog()
	_reorder_layers_for_kit()
	if _anim_def and _catalog.has("animations"):
		var anims: Dictionary = _catalog.get("animations", {})
		if anims.has(_current_anim):
			_anim_def = anims[_current_anim]
		else:
			# Fall back to whatever idle the new catalog defines.
			for fallback in ["Idle", "Idle 1", "idle"]:
				if anims.has(fallback):
					_current_anim = fallback
					_anim_def = anims[fallback]
					break

func _reorder_layers_for_kit() -> void:
	var order: Array = SLOT_ORDER_OVERRIDE.get(kit, SLOT_ORDER)
	# Move each Sprite2D to the right child position so draw order matches.
	for i in range(order.size()):
		var slot: String = order[i]
		if _layers.has(slot):
			move_child(_layers[slot], i)

func _piece_path(slot: String, variant: String) -> String:
	# Shadow lives at slot root with no variant subfolder.
	if slot == "Shadow" or variant == "":
		return "%s/%s/%s/Spritesheet.png" % [PIECES_ROOT, kit, slot]
	return "%s/%s/%s/%s/Spritesheet.png" % [PIECES_ROOT, kit, slot, variant]

func play_anim(name: String, looping: bool = true, finished_cb: Callable = Callable()) -> void:
	var anims: Dictionary = _catalog.get("animations", {})
	if not anims.has(name):
		push_warning("layered_ow: unknown anim %s" % name)
		return
	_current_anim = name
	_anim_def = anims[name]
	_looping = looping
	_finished_cb = finished_cb
	_playing = true
	_frame = 0.0
	_ping_dir = 1
	_finished_cb = finished_cb
	_playing = true
	for slot in _layers:
		_update_region(slot)

func set_direction(player_dir: int) -> void:
	_direction = clamp(player_dir, 0, 7)
	for slot in _layers:
		_update_region(slot)

func _process(delta: float) -> void:
	if not _playing or _anim_def.is_empty():
		return
	var per_dir: int = int(_anim_def.get("per_dir", 1))
	if per_dir <= 1:
		return
	_frame += delta * fps * float(_ping_dir)
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
	for slot in _layers:
		_update_region(slot)

func _update_region(slot: String) -> void:
	var spr: Sprite2D = _layers.get(slot)
	if spr == null or spr.texture == null:
		return
	var per_dir: int = int(_anim_def.get("per_dir", 1))
	var start: int = int(_anim_def.get("start", 0))
	var cat_dir: int = DIR_TO_CATALOG[_direction]
	var idx: int = start + cat_dir * per_dir + int(floor(_frame))
	var col: int = idx % _grid
	var row: int = idx / _grid
	var tex_w: int = spr.texture.get_width()
	var fs: int = int(tex_w / _grid)
	spr.region_rect = Rect2(col * fs, row * fs, fs, fs)
	if spr.material is ShaderMaterial:
		var tw: float = float(tex_w)
		var th: float = float(spr.texture.get_height())
		var u_min := Vector2(float(col * fs) / tw, float(row * fs) / th)
		var u_max := Vector2(float((col + 1) * fs) / tw, float((row + 1) * fs) / th)
		var mat: ShaderMaterial = spr.material
		mat.set_shader_parameter("region_uv_min", u_min)
		mat.set_shader_parameter("region_uv_max", u_max)
