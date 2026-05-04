extends Node2D
class_name ThunderFX

# One-shot thunder-strike VFX from the W2_Thunder spritesheet.
# 5 cols × 3 rows of 192×192 cells = 15 frames played in order.
# Pixelised through the same shader the hit popup uses for a chunky look.

const SHEET_PATH := "res://assets/effects/tests/2021 Wave 2 - Elemental Pack/PNG format - 192x192 cells/W2_Thunder.png"
const PIX_SHADER_PATH := "res://pixelize.gdshader"
const COLS := 5
const ROWS := 3
const CELL := 192
const FPS := 24.0

static var _sheet: Texture2D = null
static var _shader: Shader = null

static func _load_assets() -> void:
	if _sheet == null and ResourceLoader.exists(SHEET_PATH):
		_sheet = load(SHEET_PATH)
	if _shader == null and ResourceLoader.exists(PIX_SHADER_PATH):
		_shader = load(PIX_SHADER_PATH)

static func spawn(parent: Node, world_pos: Vector2, scale_mult: float = 0.6) -> void:
	if parent == null:
		return
	_load_assets()
	if _sheet == null:
		return
	var fx := ThunderFX.new()
	fx.scale = Vector2(scale_mult, scale_mult)
	parent.add_child(fx)
	fx.global_position = world_pos
	fx._kick()

var _sprite: Sprite2D
var _frame_t: float = 0.0
var _total_frames: int = COLS * ROWS

func _kick() -> void:
	z_index = 920
	_sprite = Sprite2D.new()
	_sprite.texture = ThunderFX._sheet
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(0, 0, CELL, CELL)
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ThunderFX._shader:
		var mat := ShaderMaterial.new()
		mat.shader = ThunderFX._shader
		mat.set_shader_parameter("pixel_block", 1.1)
		mat.set_shader_parameter("region_size", Vector2(CELL, CELL))
		_sprite.material = mat
	# Lift slightly so the strike lands on the enemy's torso, not feet.
	_sprite.position = Vector2(0, -48)
	add_child(_sprite)

func _process(delta: float) -> void:
	_frame_t += delta * FPS
	var idx: int = int(floor(_frame_t))
	if idx >= _total_frames:
		queue_free()
		return
	var col: int = idx % COLS
	var row: int = idx / COLS
	_sprite.region_rect = Rect2(col * CELL, row * CELL, CELL, CELL)
