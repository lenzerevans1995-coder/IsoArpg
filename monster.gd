extends Node2D
class_name Monster

# Renders an OtherWorlds_Monsters / PVGames spritesheet using the layout in
# monster_anim_catalog.json and the painterly shader. Supports 8-direction
# animation playback with the catalog's animation lexicon (Loop / Singular /
# PingPong / PingPongSingular / Static).

const CATALOG_PATH := "res://data/monster_anim_catalog.json"
const SHADER_PATH := "res://shaders/monster_painterly.gdshader"
const PRESETS_PATH := "res://data/gear_presets.json"
const SWATCH_PATH := "res://data/swatch_palette.json"
# Slots from the gear presets that read as "skin/armor" colors and translate
# well into a luma ramp for the monster recolor.
const PRESET_SLOTS := ["body", "head", "chest", "legs", "shoes", "hands", "belt"]

# Maps player_layered.gd's 0-7 direction (0=E, CCW from +x with y-down screen,
# i.e. 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE) to the catalog index in
# directions = [S, W, E, N, SW, NW, SE, NE].
const DIR_TO_CATALOG := [2, 6, 0, 4, 1, 5, 3, 7]

@export var spritesheet: Texture2D
@export var display_size: float = 128.0   # world-space height of the rendered sprite
@export var default_anim: String = "Idle"
@export var fps: float = 12.0
# Where the character's feet sit within the frame (0 = bottom edge, 1 = top
# edge). Used to anchor the sprite so y-sort with grass/tufts works.
@export var foot_anchor_y: float = 0.15

# Painterly shader uniforms — tweak per-monster if needed.
@export var wander: bool = false
@export var wander_speed: float = 40.0
@export var wander_radius: float = 256.0

# Combat
@export var hp: int = 30
@export var max_hp: int = 30
@export var damage: int = 8
@export var attack_range: float = 56.0
@export var attack_cooldown: float = 1.0
@export var aggressive: bool = false
@export var chase_speed: float = 90.0

var target: Node2D = null
var _attack_timer: float = 0.0
var _state: int = 0   # 0 idle/wander, 1 chase, 2 attack, 3 dead
# Strafe AI: each spider has a preferred orbit angle around the target so they
# spread out instead of clumping. Resets every few seconds.
var _strafe_angle: float = 0.0
var _strafe_left: float = 0.0
var _strafe_dir: float = 1.0      # +1 or -1, randomized
var _windup_left: float = 0.0     # >0 while telegraphing the attack
# Pack coordination: at most a few spiders can be in the "committed" attack
# zone at once. The rest hold an outer orbit until a slot opens.
@export var max_simultaneous_attackers: int = 2
var _committed: bool = false
# Lunge: occasional long-range pounce. Triggered when not committed and the
# player is just outside attack_range.
var _lunge_left: float = 0.0
var _lunge_cooldown: float = 0.0
var _peer_count_cache: int = 0
var _peer_recheck_left: float = 0.0
@export var lunge_speed: float = 220.0
@export var lunge_chance: float = 0.18    # per cycle when conditions met
var _hit_flash: float = 0.0
var knockback_pending: Vector2 = Vector2.ZERO
var _knockback_left: float = 0.0
var dead: bool = false
var _anim_locked: bool = false   # Singular anims (Attack/GetHit) own the sprite until done.
signal died(monster)

@export var pixel_size: float = 3
@export var palette_levels: int = 9
@export var saturation: float = 1.0
@export var contrast: float = 1.1
@export var outline_strength: float = 0.0
@export var alpha_cutoff: float = 0.35
@export var warm_tint: Color = Color(1.0, 1.0, 1.0)

var _sprite: Sprite2D
var _catalog: Dictionary = {}
var _full_catalog: Dictionary = {}   # raw root dict, keeps "overrides" map
var _frame_size: int = 0
var _grid: int = 21
var _current_anim: String = ""
var _anim_def: Dictionary = {}
var _direction: int = 2          # player-style direction (E=0..NE=7)
var _frame: float = 0.0
var _ping_dir: int = 1
var _finished_cb: Callable = Callable()
var _playing: bool = true
var _wander_origin: Vector2 = Vector2.INF
var _wander_target: Vector2 = Vector2.ZERO
var _wander_pause: float = 0.0
var _is_walking: bool = false

func _ready() -> void:
	_load_catalog()
	y_sort_enabled = true
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.region_enabled = true
	add_child(_sprite)
	if spritesheet:
		set_spritesheet(spritesheet)
	_apply_shader()
	play_anim(default_anim, true)

func set_display_size(size: float) -> void:
	display_size = size
	if _sprite and _frame_size > 0:
		_sprite.scale = Vector2.ONE * (display_size / float(_frame_size))
		_apply_anchor()

func _apply_anchor() -> void:
	if _sprite == null or _frame_size <= 0:
		return
	# Shift the texture up so the foot row sits at the node origin (=y-sort key).
	# offset is in unscaled texture pixels.
	_sprite.offset = Vector2(0, -float(_frame_size) * (0.5 - foot_anchor_y))

func set_spritesheet(tex: Texture2D) -> void:
	# Pick the right catalog (default or per-monster override) based on the
	# sprite's parent folder name in res://assets/shader_sprites/<Name>/.
	if tex:
		var monster_name := tex.resource_path.get_base_dir().get_file()
		_apply_catalog_for(monster_name)
		if _anim_def:
			# Re-resolve the anim against the (possibly different) catalog.
			var anims: Dictionary = _catalog.get("animations", {})
			if anims.has(_current_anim):
				_anim_def = anims[_current_anim]
			else:
				_anim_def = anims.get("Idle", {})
				_current_anim = "Idle"
	spritesheet = tex
	if _sprite == null:
		return
	_sprite.texture = tex
	if tex:
		if tex.get_width() % _grid != 0:
			push_warning("monster.gd: %dx%d not divisible by grid %d for %s" % [tex.get_width(), tex.get_height(), _grid, tex.resource_path])
		_frame_size = int(tex.get_width() / _grid)
		_sprite.scale = Vector2.ONE * (display_size / float(_frame_size))
		_apply_anchor()
		_update_region()

func _load_catalog() -> void:
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		push_error("monster.gd: catalog missing at %s" % CATALOG_PATH)
		return
	_full_catalog = JSON.parse_string(f.get_as_text())
	_apply_catalog_for("")

func _apply_catalog_for(monster_name: String) -> void:
	# Start with the root catalog, then layer in any per-monster override.
	_catalog = _full_catalog.duplicate(true)
	var overrides: Dictionary = _full_catalog.get("overrides", {})
	if monster_name != "" and overrides.has(monster_name):
		var ov: Dictionary = overrides[monster_name]
		for k in ov.keys():
			_catalog[k] = ov[k]
	_grid = int(_catalog.get("grid", 21))

func _apply_shader() -> void:
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("pixel_size", pixel_size)
	mat.set_shader_parameter("palette_levels", palette_levels)
	mat.set_shader_parameter("saturation", saturation)
	mat.set_shader_parameter("contrast", contrast)
	mat.set_shader_parameter("outline_strength", outline_strength)
	mat.set_shader_parameter("alpha_cutoff", alpha_cutoff)
	mat.set_shader_parameter("warm_tint", Vector3(warm_tint.r, warm_tint.g, warm_tint.b))
	var pal_tex := _build_palette_texture()
	if pal_tex:
		mat.set_shader_parameter("palette_tex", pal_tex)
		mat.set_shader_parameter("palette_size", pal_tex.get_width())
	_sprite.material = mat

func _combat_tick(delta: float) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)
	_lunge_cooldown = max(0.0, _lunge_cooldown - delta)
	# Lunge: a short, fast forward dash. Plays out independently of the regular
	# attack windup; ends when timer hits zero.
	if _lunge_left > 0.0:
		var to_lunge: Vector2 = target.position - position
		if to_lunge.length() > 1.0:
			position += to_lunge.normalized() * lunge_speed * delta
		_lunge_left -= delta
		return
	if _anim_locked:
		var to_t: Vector2 = target.position - position
		var ang := atan2(to_t.y, to_t.x)
		if ang < 0.0:
			ang += TAU
		set_direction(int(round(ang / (TAU / 8.0))) % 8)
		return
	# Periodically reroll a preferred orbit angle so spiders spread around
	# the player instead of stacking on one tile.
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe_angle = randf_range(-0.6, 0.6)   # offset from straight-on (+/- ~35deg)
		_strafe_dir = -1.0 if randf() < 0.5 else 1.0
		_strafe_left = randf_range(1.4, 2.6)
	var to_target: Vector2 = target.position - position
	var dist: float = to_target.length()
	# Player-aware retreat: if the player just started swinging and we're
	# already point-blank, back off briefly so we get a chance to dodge.
	if target.get("attacking") and dist < attack_range * 0.95 and randf() < 0.4:
		var back: Vector2 = -to_target.normalized() * chase_speed * delta
		position += back
		_set_walking(true)
		return
	# Pack rotation: only a few spiders commit to point-blank at once. Others
	# hover at outer ring (1.5x attack_range) until the count of attackers drops.
	_peer_recheck_left -= delta
	if _peer_recheck_left <= 0.0:
		_peer_count_cache = _count_attacker_peers()
		_peer_recheck_left = 0.25
	var attacker_count: int = _peer_count_cache
	var slot_open := attacker_count < max_simultaneous_attackers
	var commit_dist := attack_range
	var hold_dist := attack_range * 1.6
	var goal_dist := commit_dist if slot_open or _committed else hold_dist
	_committed = slot_open and dist <= commit_dist + 4.0
	# Lunge from outer ring when not committed and cooldown is up.
	if (not _committed) and _lunge_cooldown <= 0.0 and dist > attack_range * 1.05 \
			and dist < attack_range * 2.4 and randf() < lunge_chance:
		_lunge_left = 0.32
		_lunge_cooldown = randf_range(3.5, 6.0)
		_anim_locked = true
		play_anim("Running" if "Running" in _catalog.get("animations", {}) else "Walking", true)
		get_tree().create_timer(0.32).timeout.connect(func():
			_anim_locked = false
			_apply_attack_damage())
		return
	if dist > goal_dist:
		# Move toward the player but biased along the orbit angle so each spider
		# approaches from a slightly different vector.
		var dir_v: Vector2 = to_target.normalized().rotated(_strafe_angle)
		var step: Vector2 = dir_v * chase_speed * delta
		position += step
		var ang := atan2(to_target.y, to_target.x)   # face the player, not the strafe
		if ang < 0.0:
			ang += TAU
		set_direction(int(round(ang / (TAU / 8.0))) % 8)
		_set_walking(true)
	else:
		# Inside attack range: orbit slightly while waiting for the cooldown so
		# the spider doesn't sit still and feel like a punching bag.
		_set_walking(false)
		var ang := atan2(to_target.y, to_target.x)
		if ang < 0.0:
			ang += TAU
		set_direction(int(round(ang / (TAU / 8.0))) % 8)
		# Always orbit slightly so the spider doesn't sit still.
		var tangent: Vector2 = Vector2(-to_target.y, to_target.x).normalized() * _strafe_dir
		position += tangent * (chase_speed * 0.4) * delta
		if _committed and _attack_timer <= 0.0:
			_attack_timer = attack_cooldown + randf_range(-0.2, 0.4)
			_anim_locked = true
			# Slow the strike playback so its 3 frames span the wind-up
			# instead of snapping back to Idle halfway through.
			var saved_fps := fps
			fps = 6.5   # 3 frames / 6.5 fps = ~0.46s, matches windup
			play_anim("Attack1", true)   # loop so the last pose holds till damage hits
			_windup_left = 0.45
			get_tree().create_timer(_windup_left).timeout.connect(func():
				fps = saved_fps
				_anim_locked = false
				_apply_attack_damage()
				if not dead:
					play_anim("Idle", true))

func _count_attacker_peers() -> int:
	# Cheaply count committed spiders by reading target.main.active_spiders.
	if target == null or not target.get("main"):
		return 0
	var m: Node = target.main
	if not m or not m.get("active_spiders"):
		return 0
	var n := 0
	for s in m.active_spiders:
		if not is_instance_valid(s) or s.dead:
			continue
		if s == self:
			if _committed:
				n += 1
		elif s.get("_committed"):
			n += 1
	return n

func _on_attack_anim_done() -> void:
	_anim_locked = false
	if not dead:
		play_anim("Idle", true)

func _apply_attack_damage() -> void:
	if dead or target == null or not is_instance_valid(target):
		return
	if (target.position - position).length() > attack_range * 1.2:
		return
	if target.has_method("take_damage"):
		target.take_damage(damage)

func take_damage(amount: int) -> void:
	if dead:
		return
	hp -= amount
	_hit_flash = 0.22
	if hp <= 0:
		_die()
	else:
		_anim_locked = true
		play_anim("GetHit", false, func():
			_anim_locked = false
			if not dead:
				play_anim("Idle", true))

func _die() -> void:
	dead = true
	_anim_locked = true
	hp = 0
	play_anim("DeadToDown", false)
	# Fade out and free shortly after the death anim.
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): emit_signal("died", self); queue_free())

func _wander_tick(delta: float) -> void:
	if _wander_origin == Vector2.INF:
		_wander_origin = position
		_pick_wander_target()
	if _wander_pause > 0.0:
		_wander_pause -= delta
		_set_walking(false)
		return
	var to_target: Vector2 = _wander_target - position
	if to_target.length() < 4.0:
		_wander_pause = randf_range(0.6, 2.0)
		_pick_wander_target()
		_set_walking(false)
		return
	var step: Vector2 = to_target.normalized() * wander_speed * delta
	position += step
	var ang := atan2(step.y, step.x)
	if ang < 0.0:
		ang += TAU
	var dir: int = int(round(ang / (TAU / 8.0))) % 8
	set_direction(dir)
	_set_walking(true)

func _pick_wander_target() -> void:
	var ang := randf() * TAU
	var dist := randf_range(wander_radius * 0.3, wander_radius)
	_wander_target = _wander_origin + Vector2(cos(ang), sin(ang)) * dist

func _set_walking(walking: bool) -> void:
	if walking == _is_walking:
		return
	_is_walking = walking
	var anims: Dictionary = _catalog.get("animations", {})
	var name := "Walking" if walking else "Idle"
	if not anims.has(name):
		name = "Idle"
	if name != _current_anim:
		play_anim(name, true)

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

func set_palette_index(idx: int) -> void:
	# idx < 0 disables palette mode and restores normal grading.
	if _sprite == null or not (_sprite.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = _sprite.material
	if idx < 0:
		mat.set_shader_parameter("use_palette", 0.0)
		return
	var f := FileAccess.open(PRESETS_PATH, FileAccess.READ)
	if f == null:
		return
	var presets: Array = JSON.parse_string(f.get_as_text())
	if presets.is_empty():
		return
	var preset: Dictionary = presets[idx % presets.size()]
	var colors: Array[Color] = []
	for slot in PRESET_SLOTS:
		var hex: String = String(preset.get(slot, ""))
		if hex == "" or hex == "#ffffff":
			continue
		colors.append(Color(hex))
	if colors.is_empty():
		mat.set_shader_parameter("use_palette", 0.0)
		return
	colors.sort_custom(func(a: Color, b: Color) -> bool:
		return (a.r * 0.299 + a.g * 0.587 + a.b * 0.114) < (b.r * 0.299 + b.g * 0.587 + b.b * 0.114))
	var n: int = min(colors.size(), 8)
	mat.set_shader_parameter("use_palette", 1.0)
	mat.set_shader_parameter("palette_count", n)
	for i in range(8):
		var c: Color = colors[min(i, n - 1)]
		mat.set_shader_parameter("palette_%d" % i, Vector3(c.r, c.g, c.b))

func set_swatch_row(row: int) -> void:
	# Picks 8 colors from a 9-col row of swatch_palette.json (81 swatches in
	# 9 rows of 9). row < 0 disables palette mode.
	if _sprite == null or not (_sprite.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = _sprite.material
	if row < 0:
		mat.set_shader_parameter("use_palette", 0.0)
		return
	var f := FileAccess.open(SWATCH_PATH, FileAccess.READ)
	if f == null:
		return
	var swatches: Array = JSON.parse_string(f.get_as_text())
	if swatches.size() < (row + 1) * 9:
		return
	var slice: Array[Color] = []
	for i in range(9):
		slice.append(Color(String(swatches[row * 9 + i])))
	slice.sort_custom(func(a: Color, b: Color) -> bool:
		return (a.r * 0.299 + a.g * 0.587 + a.b * 0.114) < (b.r * 0.299 + b.g * 0.587 + b.b * 0.114))
	# Drop the brightest to fit 8 slots; brightest tends to be near-white and
	# would clash with the source's highlights.
	var n: int = min(slice.size() - 1, 8)
	mat.set_shader_parameter("use_palette", 1.0)
	mat.set_shader_parameter("palette_count", n)
	for i in range(8):
		var c: Color = slice[min(i, n - 1)]
		mat.set_shader_parameter("palette_%d" % i, Vector3(c.r, c.g, c.b))

func play_anim(name: String, looping: bool = true, finished_cb: Callable = Callable()) -> void:
	var anims: Dictionary = _catalog.get("animations", {})
	if not anims.has(name):
		push_warning("monster.gd: unknown anim '%s'" % name)
		return
	_current_anim = name
	_anim_def = anims[name]
	_frame = 0.0
	_ping_dir = 1
	_finished_cb = finished_cb
	_playing = true
	_update_region()

func set_direction(player_dir: int) -> void:
	_direction = clamp(player_dir, 0, 7)
	_update_region()

func _process(delta: float) -> void:
	if dead:
		return
	if _hit_flash > 0.0:
		_hit_flash = max(0.0, _hit_flash - delta)
		# Stronger Diablo-style burst: bright white over the sprite, fading to normal.
		var t: float = _hit_flash / 0.22
		_sprite.modulate = Color(2.4, 2.4, 2.4).lerp(Color.WHITE, 1.0 - t)
	# Knockback impulse: short slide in the direction the hit pushed.
	if knockback_pending != Vector2.ZERO and _knockback_left <= 0.0:
		_knockback_left = 0.18
	if _knockback_left > 0.0:
		var step: float = (knockback_pending.length() / 0.18) * delta
		position += knockback_pending.normalized() * step
		_knockback_left -= delta
		if _knockback_left <= 0.0:
			knockback_pending = Vector2.ZERO
	if aggressive and target and is_instance_valid(target):
		_combat_tick(delta)
	elif wander:
		_wander_tick(delta)
	if not _playing or _anim_def.is_empty():
		return
	var per_dir: int = int(_anim_def.get("per_dir", 1))
	if per_dir <= 1:
		return
	var t: String = String(_anim_def.get("type", "Loop"))
	_frame += delta * fps * float(_ping_dir)
	match t:
		"Loop":
			if _frame >= float(per_dir):
				_frame = fmod(_frame, float(per_dir))
		"Singular", "Static":
			if _frame >= float(per_dir) - 1.0:
				_frame = float(per_dir) - 1.0
				_playing = false
				if _finished_cb.is_valid():
					_finished_cb.call()
		"PingPong":
			if _frame >= float(per_dir) - 1.0:
				_frame = float(per_dir) - 1.0
				_ping_dir = -1
			elif _frame <= 0.0:
				_frame = 0.0
				_ping_dir = 1
		"PingPongSingular":
			if _ping_dir == 1 and _frame >= float(per_dir) - 1.0:
				_frame = float(per_dir) - 1.0
				_ping_dir = -1
			elif _ping_dir == -1 and _frame <= 0.0:
				_frame = 0.0
				_playing = false
				if _finished_cb.is_valid():
					_finished_cb.call()
	_update_region()

func _update_region() -> void:
	if _frame_size == 0 or _anim_def.is_empty() or _sprite == null:
		return
	var per_dir: int = int(_anim_def.get("per_dir", 1))
	var start: int = int(_anim_def.get("start", 0))
	var cat_dir: int = DIR_TO_CATALOG[_direction]
	var idx: int = start + cat_dir * per_dir + int(floor(_frame))
	var col: int = idx % _grid
	var row: int = idx / _grid
	_sprite.region_rect = Rect2(col * _frame_size, row * _frame_size, _frame_size, _frame_size)
	if _sprite.material is ShaderMaterial and spritesheet:
		var tw: float = float(spritesheet.get_width())
		var th: float = float(spritesheet.get_height())
		var u_min := Vector2(float(col * _frame_size) / tw, float(row * _frame_size) / th)
		var u_max := Vector2(float((col + 1) * _frame_size) / tw, float((row + 1) * _frame_size) / th)
		var mat: ShaderMaterial = _sprite.material
		mat.set_shader_parameter("region_uv_min", u_min)
		mat.set_shader_parameter("region_uv_max", u_max)
