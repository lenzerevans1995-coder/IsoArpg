extends Node2D
class_name BossMonster

# Renders Medieval Bosses (PVGames). Each boss ships per-anim PNGs:
#   <Name>_idle.png        cardinal  (4 dirs S,W,E,N x N frames)
#   <Name>_idle_diag.png   diagonal  (4 dirs SW,NW,SE,NE x N frames)
#   <Name>_walking.png + _walking_diag.png
#   <Name>_ko.png + _ko_diag.png
# Frames are 512x512 (8192/16) for the standard tier; the cell size is
# detected at load time from sheet_height / 4 (4 directions per file).

const BOSSES_ROOT := "res://assets/bosses"

# Player-style direction (E=0,SE=1,S=2,SW=3,W=4,NW=5,N=6,NE=7) ->
# (file_kind, row) where file_kind is "card" (S,W,E,N rows 0..3) or
# "diag" (SW,NW,SE,NE rows 0..3).
const DIR_TO_FILE_ROW := [
	["card", 2],  # E -> wait E is index 2 in S,W,E,N
	["diag", 2],  # SE -> SW,NW,SE,NE row 2
	["card", 0],  # S
	["diag", 0],  # SW
	["card", 1],  # W
	["diag", 1],  # NW
	["card", 3],  # N
	["diag", 3],  # NE
]

@export var boss_name: String = "Medieval_Bosses_Gollageth"
@export var display_size: float = 256.0
@export var fps: float = 8.0
@export var foot_anchor_y: float = 0.18
@export var wander: bool = false
@export var wander_speed: float = 70.0
@export var wander_radius: float = 320.0
@export var attack_preview_interval: float = 6.0   # seconds between preview attacks

var _sprite: Sprite2D
var _anim: String = "idle"   # idle | walking | ko
var _direction: int = 2
var _frame: float = 0.0
var _per_dir: int = 1
var _cell: int = 512
var _texs: Dictionary = {}    # "<anim>_<kind>" -> Texture2D

func _ready() -> void:
	y_sort_enabled = true
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.region_enabled = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)
	_load_textures()
	# Default to whichever idle the boss ships (lite tier has "idle", extended
	# has "idle1"). Falls back to the first available anim.
	var start := "idle" if "idle" in available_anims else (
		"idle1" if "idle1" in available_anims else (
		available_anims[0] if available_anims.size() > 0 else ""))
	if start != "":
		play_anim(start)

const KNOWN_ANIMS := [
	"idle", "idle1", "idle2", "walking", "running", "ko",
	"kneel", "sitting1", "sitting2", "sleeping", "collapse", "dead", "default",
]
var available_anims: Array[String] = []
var _wander_origin: Vector2 = Vector2.INF
var _wander_target: Vector2 = Vector2.ZERO
var _wander_pause: float = 0.0
var _attack_timer: float = 0.0
var _attack_busy: float = 0.0       # >0 while playing the preview-attack anim

func _load_textures() -> void:
	for anim in KNOWN_ANIMS:
		var any_loaded := false
		for kind in ["card", "diag"]:
			var suffix: String = "_" + anim + ("_diag" if kind == "diag" else "")
			var path: String = "%s/%s/%s%s.png" % [BOSSES_ROOT, boss_name, boss_name, suffix]
			var tex := _load_runtime(path)
			if tex:
				_texs["%s_%s" % [anim, kind]] = tex
				any_loaded = true
		if any_loaded:
			available_anims.append(anim)

func _load_runtime(path: String) -> Texture2D:
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

func play_anim(name: String) -> void:
	if _anim == name and _per_dir > 1:
		return
	_anim = name
	_frame = 0.0
	_update_region()

func set_direction(player_dir: int) -> void:
	_direction = clamp(player_dir, 0, 7)
	_update_region()

func _process(delta: float) -> void:
	if wander:
		_wander_tick(delta)
	if _per_dir <= 1:
		return
	_frame += delta * fps
	if _frame >= float(_per_dir):
		_frame = fmod(_frame, float(_per_dir))
	_update_region()

func _wander_tick(delta: float) -> void:
	if _wander_origin == Vector2.INF:
		_wander_origin = position
		_pick_wander_target()
	# Attack preview: every attack_preview_interval, lock motion and play
	# whichever "active" anim the boss has — running > kneel > idle2.
	if _attack_busy > 0.0:
		_attack_busy = max(0.0, _attack_busy - delta)
		if _attack_busy <= 0.0:
			play_anim(_pick_walking())
		return
	_attack_timer += delta
	if _attack_timer >= attack_preview_interval:
		_attack_timer = 0.0
		var attack_anim := _pick_attack_anim()
		if attack_anim != "":
			play_anim(attack_anim)
			_attack_busy = 1.6
			return
	# Walk toward target.
	if _wander_pause > 0.0:
		_wander_pause -= delta
		play_anim(_pick_idle())
		return
	var to_t: Vector2 = _wander_target - position
	if to_t.length() < 6.0:
		_wander_pause = randf_range(0.6, 1.6)
		_pick_wander_target()
		play_anim(_pick_idle())
		return
	var step: Vector2 = to_t.normalized() * wander_speed * delta
	position += step
	var ang := atan2(step.y, step.x)
	if ang < 0.0:
		ang += TAU
	set_direction(int(round(ang / (TAU / 8.0))) % 8)
	play_anim(_pick_walking())

func _pick_wander_target() -> void:
	var ang := randf() * TAU
	var dist := randf_range(wander_radius * 0.3, wander_radius)
	_wander_target = _wander_origin + Vector2(cos(ang), sin(ang)) * dist

func _pick_idle() -> String:
	for n in ["idle", "idle1", "idle2", "default"]:
		if n in available_anims:
			return n
	return _anim

func _pick_walking() -> String:
	for n in ["walking", "running"]:
		if n in available_anims:
			return n
	return _pick_idle()

func _pick_attack_anim() -> String:
	# Bosses don't ship a true _attack iso anim; closest "active" frames are
	# running (charge), kneel (slam), or idle2 (windup). Tier-1 bosses
	# (Gollageth/Hive) only have idle/walking/ko, so they fall back to ko
	# briefly as a "stagger" preview.
	for n in ["running", "kneel", "idle2", "ko"]:
		if n in available_anims:
			return n
	return ""

func _update_region() -> void:
	var entry: Array = DIR_TO_FILE_ROW[_direction]
	var kind: String = entry[0]
	var row: int = entry[1]
	var key := "%s_%s" % [_anim, kind]
	var tex: Texture2D = _texs.get(key)
	if tex == null:
		_sprite.texture = null
		return
	# Detect cell size & frame count from sheet dimensions (4 dirs vertically).
	var th: int = tex.get_height()
	_cell = th / 4
	_per_dir = max(1, tex.get_width() / _cell)
	_sprite.texture = tex
	_sprite.scale = Vector2.ONE * (display_size / float(_cell))
	_sprite.offset = Vector2(0, -float(_cell) * (0.5 - foot_anchor_y))
	var col: int = int(floor(_frame)) % _per_dir
	_sprite.region_rect = Rect2(col * _cell, row * _cell, _cell, _cell)
