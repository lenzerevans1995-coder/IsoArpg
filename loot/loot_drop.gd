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
# Beam base sits at the icon's anchor (0, 0) so the pillar visually
# rises straight out of the dropped item. Was 83 when coins were the
# floor sprite; the icon sprite is centered so the offset is now 0.
const BEAM_OFFSET_Y := 0.0

# Rarity colors come from rarity_visuals.gd (which reads
# data/swatch_palette.json — the project's 81-swatch palette).
# Local enum kept so callers can write LootDrop.Rarity.RARE etc.
enum Rarity { COMMON, MAGIC, RARE, UNIQUE, LEGENDARY }
const _RarityVisuals := preload("res://loot/rarity_visuals.gd")

static var _coin_tex: Texture2D = null

var _gold_sprite: Sprite2D
# The beam is a Node2D with a custom _draw — keeps it at the same
# anchor as the gold sprite without needing a separate asset.
var _beam_node: Node2D

# ---- Spawn helpers ---------------------------------------------------

# Drops gold at `world_pos` parented to `parent`. `item_id` carries the
# rolled loot's identity so future pickup logic can grant the right
# inventory slot without re-rolling. Returns the new LootDrop.
static func spawn(parent: Node, world_pos: Vector2, rarity: int = Rarity.COMMON, item_id: String = "") -> Node2D:
	var script: Script = load("res://loot/loot_drop.gd")
	var d: Node2D = script.new()
	d.position = world_pos
	d.set("item_id", item_id)
	d.call("_build_for", rarity)
	parent.add_child(d)
	return d

# Pickup helper: returns the rolled identity of the drop and queues
# the visual for free. Caller is responsible for granting the item +
# applying it to the player's loadout.
func pickup() -> Dictionary:
	var data := {"item_id": item_id, "rarity": _rarity}
	queue_free()
	return data

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
# Rolled item this drop represents. Future pickup logic reads this to
# grant the right inventory slot. Empty = generic gold-only drop.
var item_id: String = ""
var _hover_radius: float = 64.0

func _build_for(rarity: int) -> void:
	_rarity = rarity
	add_to_group("loot_drop")
	# Item icon on the floor — uses the baked ground sprite if it exists,
	# else falls back to the inventory icon. Coins are gone — drops now
	# show the actual rolled item.
	_gold_sprite = Sprite2D.new()
	_gold_sprite.centered = true
	_gold_sprite.offset = Vector2.ZERO
	_gold_sprite.z_index = 30
	_gold_sprite.scale = Vector2(COIN_SCALE, COIN_SCALE)
	_gold_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var icon_tex: Texture2D = _icon_for_item(item_id)
	if icon_tex != null:
		_gold_sprite.texture = icon_tex
		# Rarity-coloured outline so loot reads against the floor at a
		# glance. Width scales with rarity (1.5px common -> 3px legendary).
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/outline.gdshader")
		mat.set_shader_parameter("outline_color", _RarityVisuals.color_for(rarity))
		var w: float = 1.5 + 0.4 * float(rarity)   # 1.5..3.1 across 5 tiers
		mat.set_shader_parameter("outline_width", w)
		mat.set_shader_parameter("texture_size", Vector2(icon_tex.get_width(), icon_tex.get_height()))
		_gold_sprite.material = mat
	add_child(_gold_sprite)
	# Beam — vertical rarity-coloured pillar above the icon.
	_beam_node = _BeamNode.new()
	(_beam_node as _BeamNode).beam_color = _RarityVisuals.color_for(rarity)
	_beam_node.position = Vector2(0, BEAM_OFFSET_Y)
	_beam_node.z_index = 29
	add_child(_beam_node)
	# Clickable area so the player can pick up by clicking the icon as
	# well as pressing E. Area2D wraps the visual; the size is tuned to
	# the 128x128 baked icon centered on the foot.
	var area := Area2D.new()
	area.input_pickable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(64, 64)
	shape.shape = rect
	shape.position = Vector2(0, -32)
	area.add_child(shape)
	area.input_event.connect(_on_area_input_event)
	add_child(area)

# Resolve item_id -> baked icon texture. Tries the ground (death-pose)
# sprite first since that's authored to read on the floor; falls back
# to the inventory icon if ground bake doesn't exist for this item.
static func _icon_for_item(iid: String) -> Texture2D:
	if iid == "":
		return null
	for dir in ["ground", "icons"]:
		var p: String = "res://assets/generated/%s/%s.png" % [dir, iid]
		if ResourceLoader.exists(p):
			var t: Texture2D = load(p)
			if t != null and t.get_width() > 0:
				return t
	return null

func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Left-click on the icon picks it up. Mirrors the E-key path in main.gd.
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var main := get_tree().root.get_node_or_null("Main")
			if main and main.has_method("_pickup_drop"):
				main._pickup_drop(self)

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
		(_beam_node as _BeamNode).beam_color = _RarityVisuals.color_for(_rarity)
		(_beam_node as _BeamNode).modulate = Color(1.4, 1.4, 1.4) if hover else Color(1, 1, 1, 1)
		_beam_node.queue_redraw()
