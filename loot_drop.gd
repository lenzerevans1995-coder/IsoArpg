extends Node2D
class_name LootDrop

# Visual-only loot drop. Two pieces stacked at the same world position:
#   1. an animated gold pile (gold_drop/<dir>/) on the ground
#   2. a vertical "loot beam" sprite recolored by rarity
# No inventory wiring yet — drops linger forever until picked up by a
# future loot system. The beam disappears after a short fade so the
# screen doesn't fill with permanent vertical pillars.

const COIN_PATH := "res://assets/drops/gold_drop/coins_drop.png"
# Coin pile asset is now pre-sized to match other floor assets — render
# at 1:1, no scaling.
const COIN_SCALE := 1.0
# Code-drawn rarity beam — values dialed in via loot_beam_editor.tscn.
const BEAM_WIDTH := 3.5
const BEAM_HEIGHT := 160.0
const BEAM_OFFSET_Y := 83.0

# Rarity tint table — beam asset is yellow, so we recolor via modulate.
# These shift the yellow base toward the rarity colour.
enum Rarity { COMMON, MAGIC, RARE, UNIQUE, LEGENDARY }
const RARITY_COLORS := {
	Rarity.COMMON:    Color(1.0, 1.0, 1.0, 1.0),     # white
	Rarity.MAGIC:     Color(0.50, 0.70, 1.30, 1.0),  # blue
	Rarity.RARE:      Color(1.30, 1.30, 0.50, 1.0),  # gold
	Rarity.UNIQUE:    Color(1.40, 0.80, 0.30, 1.0),  # orange
	Rarity.LEGENDARY: Color(1.30, 0.45, 0.45, 1.0),  # red
}

static var _coin_tex: Texture2D = null

var _gold_sprite: Sprite2D
# The beam is a Node2D with a custom _draw — keeps it at the same
# anchor as the gold sprite without needing a separate asset.
var _beam_node: Node2D

# ---- Spawn helpers ---------------------------------------------------

# Drops gold at `world_pos` parented to `parent`. Random direction +
# rarity tier. Returns the new LootDrop instance for further tweaks.
static func spawn(parent: Node, world_pos: Vector2, rarity: int = Rarity.COMMON) -> Node2D:
	var script: Script = load("res://loot_drop.gd")
	var d: Node2D = script.new()
	d.position = world_pos
	d.call("_build_for", rarity)
	parent.add_child(d)
	return d

# Convenience: pick a random rarity weighted toward common drops.
static func random_rarity(rng: RandomNumberGenerator = null) -> int:
	var roll: float = rng.randf() if rng != null else randf()
	if roll < 0.65: return Rarity.COMMON
	if roll < 0.85: return Rarity.MAGIC
	if roll < 0.95: return Rarity.RARE
	if roll < 0.99: return Rarity.UNIQUE
	return Rarity.LEGENDARY

# ---- Internal --------------------------------------------------------

var _hover_active: bool = false
var _rarity: int = Rarity.COMMON
var _hover_radius: float = 64.0

func _build_for(rarity: int) -> void:
	_rarity = rarity
	add_to_group("loot_drop")
	# STATIC coin pile — single image scaled down to fit on the floor.
	if _coin_tex == null and ResourceLoader.exists(COIN_PATH):
		_coin_tex = load(COIN_PATH)
	_gold_sprite = Sprite2D.new()
	_gold_sprite.centered = true
	# Anchor both the gold pile AND the beam at (0, 0) — the LootDrop's
	# foot dot. Earlier offset (0, -16) was lifting the gold and made
	# the beam read as floating above the pile.
	_gold_sprite.offset = Vector2.ZERO
	_gold_sprite.z_index = 30
	_gold_sprite.scale = Vector2(COIN_SCALE, COIN_SCALE)
	_gold_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _coin_tex != null:
		_gold_sprite.texture = _coin_tex
	# Same chunky pixelize the skill icons use, dialed lower (1.1) so
	# the coin pile keeps its detail but reads as pixel-art on the floor.
	var coin_mat := ShaderMaterial.new()
	coin_mat.shader = preload("res://skill_icon_pixelize.gdshader")
	coin_mat.set_shader_parameter("pixel_size", 1.1)
	_gold_sprite.material = coin_mat
	add_child(_gold_sprite)
	# Beam drawn in code at the same anchor as the gold (offset
	# (0, -16)). A vertical rectangle from the pile's base going up,
	# coloured by rarity. _draw is owned by the beam_node so we can
	# keep it z-behind the gold sprite without splitting transforms.
	_beam_node = _BeamNode.new()
	(_beam_node as _BeamNode).beam_color = RARITY_COLORS.get(rarity, Color(1, 1, 1, 1))
	# Position calibrated in loot_beam_editor.tscn — base of beam sits
	# inside the coin pile so the pillar reads as rising out of it.
	_beam_node.position = Vector2(0, BEAM_OFFSET_Y)
	_beam_node.z_index = 29              # behind the gold sprite
	add_child(_beam_node)

# Inline class — small Node2D that just _draw()s a vertical rarity beam.
# Lives as a sibling under the LootDrop so the offset/anchor matches
# the gold sprite exactly.
class _BeamNode extends Node2D:
	# Width / height carried as instance vars so the inner class doesn't
	# need to reach into the outer script's consts.
	var beam_color: Color = Color(1, 1, 1, 0.85)
	var beam_width: float = 3.5
	var beam_height: float = 160.0
	func _draw() -> void:
		var w: float = beam_width
		var h: float = beam_height
		var glow_col: Color = beam_color
		glow_col.a = 0.18
		draw_rect(Rect2(-w * 1.5, -h, w * 3.0, h), glow_col, true)
		var mid_col: Color = beam_color
		mid_col.a = 0.45
		draw_rect(Rect2(-w * 0.85, -h, w * 1.7, h), mid_col, true)
		var core_col: Color = beam_color
		core_col.a = 0.95
		draw_rect(Rect2(-w * 0.5, -h, w, h), core_col, true)

var _hover_throttle: float = 0.0

func _process(delta: float) -> void:
	# Hover detection throttled to ~10 Hz — many drops on the floor at
	# once was a meaningful per-frame cost when this ran every frame.
	_hover_throttle -= delta
	if _hover_throttle > 0.0:
		return
	_hover_throttle = 0.1
	var mouse: Vector2 = get_global_mouse_position()
	var hover: bool = mouse.distance_squared_to(global_position) < _hover_radius * _hover_radius
	if hover != _hover_active:
		_hover_active = hover
		_apply_hover_visuals(hover)

func _apply_hover_visuals(hover: bool) -> void:
	# Gold pile stays static. The beam brightens slightly on hover.
	if _beam_node and is_instance_valid(_beam_node):
		(_beam_node as _BeamNode).beam_color = RARITY_COLORS.get(_rarity, Color(1, 1, 1, 1))
		(_beam_node as _BeamNode).modulate = Color(1.4, 1.4, 1.4) if hover else Color(1, 1, 1, 1)
		_beam_node.queue_redraw()
