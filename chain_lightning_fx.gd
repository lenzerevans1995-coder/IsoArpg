extends Node2D
class_name ChainLightningFX

# Chain-lightning AoE: spawns a W2_Aoe_Lv2 burst on the first target,
# then jumps to the nearest goblin within CHAIN_RANGE up to MAX_JUMPS
# times. Each jump spawns its own anim and damages.

const SHEET_PATH := "res://assets/effects/tests/2021 Wave 2 - Elemental Pack/PNG format - 192x192 cells/W2_Aoe_Lv2.png"
const PIX_SHADER_PATH := "res://shaders/pixelize.gdshader"
const COLS := 5
const ROWS := 4
const CELL := 192
const FPS := 28.0
const TOTAL_FRAMES := COLS * ROWS

const MAX_JUMPS := 4              # first target + 3 chains
const CHAIN_RANGE := 220.0        # px between hops
const HOP_DELAY := 0.18           # seconds between successive zaps
const DAMAGE_FIRST := 22
const DAMAGE_FALLOFF := 0.75      # each subsequent hop deals 75% of last

static var _sheet: Texture2D = null
static var _shader: Shader = null

static func _load_sheet() -> void:
	if _sheet == null and ResourceLoader.exists(SHEET_PATH):
		_sheet = load(SHEET_PATH)
	if _shader == null and ResourceLoader.exists(PIX_SHADER_PATH):
		_shader = load(PIX_SHADER_PATH)

static func cast(parent: Node, first_target: Node2D, all_enemies: Array, on_damage: Callable = Callable()) -> void:
	if parent == null or first_target == null or not is_instance_valid(first_target):
		return
	_load_sheet()
	if _sheet == null:
		return
	# Build the chain: greedy nearest-neighbour walk, no revisits.
	var chain: Array[Node2D] = [first_target]
	var alive: Array = []
	for e in all_enemies:
		if e != null and is_instance_valid(e) and not (e.get("dead") if "dead" in e else false):
			alive.append(e)
	var current: Node2D = first_target
	while chain.size() < MAX_JUMPS:
		var best: Node2D = null
		var best_d: float = CHAIN_RANGE
		for e in alive:
			if chain.has(e):
				continue
			var d: float = current.global_position.distance_to(e.global_position)
			if d < best_d:
				best_d = d
				best = e
		if best == null:
			break
		chain.append(best)
		current = best
	# Spawn each hop with a delay; each carries diminishing damage.
	var delay: float = 0.0
	var dmg: float = float(DAMAGE_FIRST)
	for i in range(chain.size()):
		var node := chain[i]
		var damage: int = int(dmg)
		var fx_parent: Node = parent
		_schedule_hop(parent, node, damage, on_damage, delay)
		delay += HOP_DELAY
		dmg *= DAMAGE_FALLOFF

static func _schedule_hop(parent: Node, target: Node2D, damage: int, on_damage: Callable, delay: float) -> void:
	var fx_script := load("res://chain_lightning_fx.gd") as Script
	var fx = fx_script.new()
	fx._target = target
	fx._delay = delay
	fx._dmg = damage
	fx._on_damage = on_damage
	parent.add_child(fx)

# ---- Per-instance ----------------------------------------------------------

var _target: Node2D = null
var _delay: float = 0.0
var _dmg: int = 0
var _on_damage: Callable = Callable()
var _sprite: Sprite2D = null
var _frame_t: float = 0.0
var _started: bool = false

func _ready() -> void:
	z_index = 1100
	z_as_relative = false
	top_level = true   # ignore parent transform; effect lives in world space

func _process(delta: float) -> void:
	if not _started:
		_delay -= delta
		if _delay <= 0.0:
			_start()
		return
	if _target and is_instance_valid(_target):
		global_position = _target.global_position + Vector2(0, -32)
	_frame_t += delta * FPS
	var idx: int = int(floor(_frame_t))
	if idx >= TOTAL_FRAMES:
		queue_free()
		return
	if _sprite:
		var col: int = idx % COLS
		var row: int = idx / COLS
		_sprite.region_rect = Rect2(col * CELL, row * CELL, CELL, CELL)

func _start() -> void:
	_started = true
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return
	_sprite = Sprite2D.new()
	_sprite.texture = ChainLightningFX._sheet
	_sprite.centered = true
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(0, 0, CELL, CELL)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(0.6, 0.6)
	_sprite.position = Vector2(0, 0)
	# Pixelise shader for the chunky-pixel cartoon look matching the
	# rest of the project.
	if ChainLightningFX._shader:
		var mat := ShaderMaterial.new()
		mat.shader = ChainLightningFX._shader
		mat.set_shader_parameter("pixel_block", 1.1)
		mat.set_shader_parameter("region_size", Vector2(CELL, CELL))
		_sprite.material = mat
	add_child(_sprite)
	# Fire damage now (visual lands at start of the anim).
	if _target.has_method("take_damage"):
		_target.call("take_damage", _dmg, Color(0.45, 0.85, 1.6))
	if _on_damage.is_valid():
		_on_damage.call(_target, _dmg)
