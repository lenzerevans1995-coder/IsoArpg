extends Node2D
class_name IceSpikeFX

# Ice-spike VFX. If the EffekseerForGodot4 plugin is installed it plays
# MGC_3D_IceSpike_Projectile.efkefc directly via EffekseerEmitter2D —
# the original animation curves, exactly as authored. Otherwise we fall
# back to the manual 4×4 sprite-sheet replay of IceSpike_1.png.

const EFKEFC_IMPACT_PATH := "res://assets/effects/tests/MGC_IceSpikes_MZ_V1.2/MZ/MGC_IceSpike_Complete.efkefc"
const EFKEFC_MISSILE_PATH := "res://assets/effects/tests/MGC_IceSpikes_MZ_V1.2/MZ/MGC_IceSpike_Projectile.efkefc"
const EFKEFC_PATH := EFKEFC_IMPACT_PATH
const TEX_DIR := "res://assets/effects/tests/MGC_IceSpikes_MZ_V1.2/MZ/Texture/MGC_IceSpike_2021W1"
const SPIKE_TEX_PATH := TEX_DIR + "/IceSpike_1.png"
const STARGLOW_TEX_PATH := TEX_DIR + "/StarGlow_.png"
const PIX_SHADER_PATH := "res://shaders/pixelize.gdshader"

const COLOR_ICE := Color(0.65, 0.92, 1.2, 1.0)
const SPIKE_COLS := 4
const SPIKE_ROWS := 4
const SPIKE_CELL := 256
const SPIKE_TOTAL_FRAMES := 16
const SPIKE_FPS := 28.0

static var _spike_tex: Texture2D = null
static var _starglow_tex: Texture2D = null
static var _shader: Shader = null
static var _efkefc_impact: Resource = null
static var _efkefc_missile: Resource = null
static var _has_effekseer: bool = false
static var _checked_effekseer: bool = false

static func _check_effekseer() -> void:
	if _checked_effekseer:
		return
	_checked_effekseer = true
	# The plugin registers EffekseerEmitter2D as a class; ClassDB will
	# answer true once the GDExtension is loaded.
	_has_effekseer = ClassDB.class_exists("EffekseerEmitter2D")

static func _load_assets() -> void:
	_check_effekseer()
	if _has_effekseer:
		if _efkefc_impact == null and ResourceLoader.exists(EFKEFC_IMPACT_PATH):
			_efkefc_impact = load(EFKEFC_IMPACT_PATH)
		if _efkefc_missile == null and ResourceLoader.exists(EFKEFC_MISSILE_PATH):
			_efkefc_missile = load(EFKEFC_MISSILE_PATH)
	if _spike_tex == null and ResourceLoader.exists(SPIKE_TEX_PATH):
		_spike_tex = load(SPIKE_TEX_PATH)
	if _starglow_tex == null and ResourceLoader.exists(STARGLOW_TEX_PATH):
		_starglow_tex = load(STARGLOW_TEX_PATH)
	if _shader == null and ResourceLoader.exists(PIX_SHADER_PATH):
		_shader = load(PIX_SHADER_PATH)

static func spawn(parent: Node, world_pos: Vector2) -> void:
	if parent == null:
		return
	_load_assets()
	var fx := IceSpikeFX.new()
	fx._mode = "impact"
	parent.add_child(fx)
	fx.global_position = world_pos
	fx._kick()

# Trail / missile emitter that follows a moving projectile (the arrow).
# Returns the spawned FX node so the caller can call queue_free() once
# the arrow lands or expires.
static func spawn_missile(parent: Node, world_pos: Vector2, target_pos: Vector2 = Vector2.ZERO, target_node: Node2D = null) -> Node2D:
	if parent == null:
		return null
	_load_assets()
	var fx := IceSpikeFX.new()
	fx._mode = "missile"
	fx._target_pos = target_pos
	fx._target_node = target_node
	parent.add_child(fx)
	fx.global_position = world_pos
	fx._kick()
	return fx

# Spawn an impact at a moving enemy. Re-targets each frame so it tracks
# even if the enemy keeps walking.
static func spawn_at(parent: Node, target_node: Node2D) -> Node2D:
	if parent == null or target_node == null:
		return null
	_load_assets()
	var fx := IceSpikeFX.new()
	fx._mode = "impact"
	fx._target_node = target_node
	parent.add_child(fx)
	fx.global_position = target_node.global_position
	fx._kick()
	return fx

var _spike_sprite: Sprite2D = null
var _frame_t: float = 0.0
var _mode: String = "impact"   # "impact" or "missile"
var _target_pos: Vector2 = Vector2.ZERO
var _target_node: Node2D = null
var _emitter = null   # the EffekseerEmitter2D so we can poke target_position each frame

func _safe_free() -> void:
	# Used as a timer-driven backstop. Avoids dangling-lambda errors that
	# happen when autofree disposes of the emitter before the timer
	# captures a stale reference.
	if is_instance_valid(self):
		queue_free()

func _kick() -> void:
	z_index = 925
	# 1) Effekseer path: if the plugin loaded, instantiate the emitter
	# for the requested mode (impact spike vs in-flight missile) and
	# play the .efkefc directly. The impact frees on effect_finished;
	# the missile keeps emitting until the caller frees the FX node.
	var efkefc: Resource = IceSpikeFX._efkefc_missile if _mode == "missile" else IceSpikeFX._efkefc_impact
	if IceSpikeFX._has_effekseer and efkefc:
		var em = ClassDB.instantiate("EffekseerEmitter2D")
		if em:
			em.set("effect", efkefc)
			em.set("autoplay", true)
			em.set("autofree", true)
			em.set("scale", Vector2(8.0, 8.0))
			em.set("z_index", 1000)
			em.set("z_as_relative", false)
			em.set("y_sort_enabled", false)
			# Faster overall playback so the projectile reaches the
			# target quickly instead of crawling.
			em.set("speed", 2.0)
			# Make the emitter independent of the parent transform so
			# camera/canvas oddities don't kill it on certain screen
			# regions.
			em.set("top_level", true)
			# Initial target hint — also re-poked each frame in _process
			# so it tracks moving enemies.
			var initial_target: Vector2 = _target_pos
			if _target_node and is_instance_valid(_target_node):
				initial_target = _target_node.global_position
			if initial_target != Vector2.ZERO:
				em.set("target_position", initial_target - global_position)
			_emitter = em
			add_child(em)
			if em.has_method("play"):
				em.call("play")
			get_tree().create_timer(3.0).timeout.connect(_safe_free)
			return
	# 2) Fallback: manual 4×4 sheet replay + StarGlow halo flash.
	if IceSpikeFX._starglow_tex:
		var glow := Sprite2D.new()
		glow.texture = IceSpikeFX._starglow_tex
		glow.modulate = COLOR_ICE
		glow.modulate.a = 0.85
		glow.scale = Vector2(0.1, 0.1)
		glow.z_index = -1
		glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		glow.position = Vector2(0, -32)
		add_child(glow)
		var glow_tw := create_tween()
		glow_tw.set_parallel(true)
		glow_tw.tween_property(glow, "scale", Vector2(0.65, 0.65), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		glow_tw.tween_property(glow, "modulate:a", 0.0, 0.45).set_delay(0.15)
	if IceSpikeFX._spike_tex == null:
		get_tree().create_timer(0.5).timeout.connect(queue_free)
		return
	var spike := Sprite2D.new()
	spike.texture = IceSpikeFX._spike_tex
	spike.region_enabled = true
	spike.region_rect = Rect2(0, 0, SPIKE_CELL, SPIKE_CELL)
	spike.centered = true
	spike.modulate = COLOR_ICE
	spike.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if IceSpikeFX._shader:
		var mat := ShaderMaterial.new()
		mat.shader = IceSpikeFX._shader
		mat.set_shader_parameter("pixel_block", 1.1)
		mat.set_shader_parameter("region_size", Vector2(SPIKE_CELL, SPIKE_CELL))
		spike.material = mat
	var target_h: float = 110.0
	var target_scale: float = target_h / float(SPIKE_CELL)
	spike.scale = Vector2(target_scale, target_scale)
	spike.position = Vector2(0, -32)
	add_child(spike)
	_spike_sprite = spike

func _process(delta: float) -> void:
	# Track a moving enemy if one was passed in. For impact mode, anchor
	# the FX node onto the target's position so the spike stays on top
	# of them. For missile mode, only update target_position so the
	# projectile keeps homing.
	if _target_node and is_instance_valid(_target_node) and _emitter and is_instance_valid(_emitter):
		var t_pos: Vector2 = (_target_node as Node2D).global_position
		if _mode == "impact":
			global_position = t_pos
			# target_position is local — at the emitter origin (zero).
			_emitter.set("target_position", Vector2.ZERO)
		else:
			_emitter.set("target_position", t_pos - global_position)
	if _spike_sprite == null:
		return
	_frame_t += delta * SPIKE_FPS
	var idx: int = int(floor(_frame_t))
	if idx >= SPIKE_TOTAL_FRAMES:
		_spike_sprite.modulate.a = max(0.0, _spike_sprite.modulate.a - delta * 4.0)
		if _spike_sprite.modulate.a <= 0.01:
			_spike_sprite.queue_free()
			_spike_sprite = null
			get_tree().create_timer(0.05).timeout.connect(queue_free)
		return
	var col: int = idx % SPIKE_COLS
	var row: int = idx / SPIKE_COLS
	_spike_sprite.region_rect = Rect2(col * SPIKE_CELL, row * SPIKE_CELL, SPIKE_CELL, SPIKE_CELL)
