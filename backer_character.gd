extends Node2D
class_name BackerCharacter

# Renders PVGames BackerReward characters (FemaleArcher, MaleMusketeer, etc.).
# Format spec from "PVGames Character Sheet Information.docx":
#   - Each character ships 4 PNGs per slot: Sprite_1..Sprite_4.png
#   - Each PNG is 3840x4000 = 24 cols x 25 rows at 160 px/frame
#   - Each anim has a CARDINAL range (4 dirs S,W,E,N) and a DIAGONAL range
#     (4 dirs SW,NW,SE,NE), defined in backer_anim_catalog.json by sheet#

const CATALOG_PATH := "res://backer_anim_catalog.json"
const ROOT := "res://assets/backer_characters"

# Standard layering: skin first, then clothing, then weapons / accessories.
const SLOT_ORDER_DEFAULT := [
	"Base", "Bottom", "Top", "Back", "Head", "Hair", "FacialHair", "Hat",
	"Bow", "Crossbow", "Shield", "Sword", "Mace", "Dagger", "Staff",
	"Pistol", "Rifle", "Pickaxe", "Instrument", "Weapon",
]
# Maps player_dir (0=E..NE=7) to (is_diag, row_within_half).
# Cardinal rows: S=0, W=1, E=2, N=3. Diagonal rows: SW=0, NW=1, SE=2, NE=3.
const DIR_TABLE := [
	[false, 2],  # E -> cardinal row 2
	[true,  2],  # SE -> diag row 2
	[false, 0],  # S -> cardinal row 0
	[true,  0],  # SW -> diag row 0
	[false, 1],  # W -> cardinal row 1
	[true,  1],  # NW -> diag row 1
	[false, 3],  # N -> cardinal row 3
	[true,  3],  # NE -> diag row 3
]

@export var character_name: String = "Female_Archer"
@export var display_size: float = 256.0
@export var fps: float = 6.0
@export var foot_anchor_y: float = 0.18

var _catalog: Dictionary = {}
var _grid: int = 24
var _rows: int = 25
var _frame_size: int = 160

# slot_name -> {textures: Array[Texture2D] of 4 sheets, sprite: Sprite2D}
var _slots: Dictionary = {}
var _slot_order: Array = []
var _direction: int = 2
var _current_anim: String = "Idle 1"
var _anim_def: Dictionary = {}
var _frame: float = 0.0
var _playing: bool = true
var _looping: bool = true
var _finished_cb: Callable = Callable()

func _ready() -> void:
	y_sort_enabled = true
	_load_catalog()
	_build_slots_for_character()
	play_anim(_current_anim, true)

func _load_catalog() -> void:
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		push_error("backer: missing %s" % CATALOG_PATH)
		return
	_catalog = JSON.parse_string(f.get_as_text())
	_grid = int(_catalog.get("grid", 24))
	_rows = int(_catalog.get("rows", 25))
	_frame_size = int(_catalog.get("frame_size", 160))

func _build_slots_for_character() -> void:
	# Discover slots by listing the character's folder and load 4 sheets each.
	var dir_path := "%s/%s" % [ROOT, character_name]
	var d := DirAccess.open(dir_path)
	if d == null:
		push_warning("backer: missing %s" % dir_path)
		return
	var slots_found: Array[String] = []
	d.list_dir_begin()
	while true:
		var entry := d.get_next()
		if entry == "":
			break
		if d.current_is_dir() and not entry.begins_with("."):
			slots_found.append(entry)
	d.list_dir_end()
	# Render in SLOT_ORDER_DEFAULT order; unknown slots go last.
	var ordered: Array[String] = []
	for s in SLOT_ORDER_DEFAULT:
		for f in slots_found:
			if f.ends_with("_" + s):
				ordered.append(f)
				break
	for f in slots_found:
		if not (f in ordered):
			ordered.append(f)
	_slot_order = ordered
	for slot_folder in _slot_order:
		var sheets: Array[Texture2D] = []
		for n in [1, 2, 3, 4]:
			var p := "%s/%s/%s/Sprite_%d.png" % [ROOT, character_name, slot_folder, n]
			var tex := _load_robust(p)
			sheets.append(tex)
		var spr := Sprite2D.new()
		spr.centered = true
		spr.region_enabled = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(spr)
		_slots[slot_folder] = {"textures": sheets, "sprite": spr}

func _load_robust(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path)
		if t:
			return t
	var fs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(fs_path):
		var img := Image.new()
		var err := img.load(path if FileAccess.file_exists(path) else fs_path)
		if err == OK:
			return ImageTexture.create_from_image(img)
	return null

func play_anim(name: String, looping: bool = true, finished_cb: Callable = Callable()) -> void:
	var anims: Dictionary = _catalog.get("animations", {})
	if not anims.has(name):
		push_warning("backer: unknown anim %s" % name)
		return
	_current_anim = name
	_anim_def = anims[name]
	_frame = 0.0
	_looping = looping
	_finished_cb = finished_cb
	_playing = true
	_update_all_slots()

func set_direction(player_dir: int) -> void:
	_direction = clamp(player_dir, 0, 7)
	_update_all_slots()

func _process(delta: float) -> void:
	if not _playing or _anim_def.is_empty():
		return
	var per_dir: int = int(_anim_def.get("total", 8)) / 8
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
	_update_all_slots()

func _update_all_slots() -> void:
	if _anim_def.is_empty():
		return
	var sheet_num: int = int(_anim_def.get("sheet", 1))
	var dir_entry: Array = DIR_TABLE[_direction]
	var is_diag: bool = bool(dir_entry[0])
	var dir_row: int = int(dir_entry[1])
	var per_dir: int = int(_anim_def.get("total", 8)) / 8
	var range_start: int = int(_anim_def.get("diag" if is_diag else "card", 0))
	var idx: int = range_start + dir_row * per_dir + int(floor(_frame))
	var col: int = idx % _grid
	var row: int = idx / _grid
	for slot in _slots:
		var s: Dictionary = _slots[slot]
		var sheets: Array = s["textures"]
		if sheet_num - 1 >= sheets.size():
			continue
		var tex: Texture2D = sheets[sheet_num - 1]
		var spr: Sprite2D = s["sprite"]
		if tex == null:
			spr.visible = false
			continue
		spr.visible = true
		spr.texture = tex
		var fs: int = int(tex.get_width() / _grid)
		spr.scale = Vector2.ONE * (display_size / float(fs))
		spr.offset = Vector2(0, -float(fs) * (0.5 - foot_anchor_y))
		spr.region_rect = Rect2(col * fs, row * fs, fs, fs)
