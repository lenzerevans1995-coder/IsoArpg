extends Node2D
class_name Arrow

# Animated arrow projectile. Renders the per-frame PNGs from
# assets/.../Projectiles - 2D HD Character pack 1/Arrows/Arrow/, rotated
# to its travel direction. Hits the first goblin within hit_radius.

const FRAMES_DIR := "res://assets/charachters/Sprites/Players/Projectiles - 2D HD Character pack 1/Projectiles - 2D HD Character pack 1/Arrows/Arrow"
const FRAMES_FPS := 24.0
const SPEED := 720.0
const LIFETIME := 1.4
const HIT_RADIUS := 24.0
# Fallbacks if a goblin somehow lacks the per-instance body shape props
# (older spawns or non-Goblin enemies). Goblins now expose
# `body_offset` and `body_radius` directly.
const FALLBACK_BODY_OFFSET := Vector2(0, -32)
const FALLBACK_BODY_OFFSET_BOSS := Vector2(0, -56)
const FALLBACK_BODY_RADIUS := 32.0
const FALLBACK_BODY_RADIUS_BOSS := 56.0

@export var damage: int = 14
# Kept for backwards-compat with old call-sites; no longer triggers any
# FX. The Effekseer shot effect is spawned by the player skill, not here.
@export var is_ice: bool = false
@export var aim_target_pos: Vector2 = Vector2.ZERO

var direction: Vector2 = Vector2.RIGHT
var _frames: Array[Texture2D] = []
var _frame_t: float = 0.0
var _life: float = 0.0
var _sprite: Sprite2D
var _hit_set: Dictionary = {}

static var _frames_cache: Array[Texture2D] = []

static func _load_frames() -> Array[Texture2D]:
	if _frames_cache.size() > 0:
		return _frames_cache
	var d := DirAccess.open(FRAMES_DIR)
	if d == null:
		return _frames_cache
	var names: Array = []
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn.ends_with(".png"):
			names.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	names.sort()
	for n in names:
		var t: Texture2D = load("%s/%s" % [FRAMES_DIR, n])
		if t != null:
			_frames_cache.append(t)
	return _frames_cache

func _ready() -> void:
	_frames = _load_frames()
	_sprite = Sprite2D.new()
	_sprite.centered = true
	if not _frames.is_empty():
		_sprite.texture = _frames[0]
	# Anchor the rotation pivot at the arrow's TIP (texture pixel
	# (295, 10)) so the tip always starts exactly at the spawn point and
	# the trail extends BEHIND it. Texture canvas is 512×26 with center
	# at (256, 13); offset = canvas_center - art_tip = (-39, 3).
	_sprite.offset = Vector2(-39.0, 3.0)
	add_child(_sprite)
	# Rotate the sprite (not the parent Node2D) so positional collision
	# in _process stays in plain world space and only the visual swings.
	_sprite.rotation = direction.angle()
	z_index = 600

func _process(delta: float) -> void:
	_life += delta
	if _life >= LIFETIME:
		queue_free()
		return
	_frame_t += delta * FRAMES_FPS
	if not _frames.is_empty():
		_sprite.texture = _frames[int(_frame_t) % _frames.size()]
	# Move.
	position += direction * SPEED * delta
	var main := get_tree().root.get_node_or_null("Main")
	# Enemy-fired arrows — only target the player, ignore other enemies.
	if has_meta("from_enemy") and main and main.player:
		var p2d: Node2D = main.player
		var p_off: Vector2 = p2d.body_offset if "body_offset" in p2d else Vector2(0, -90)
		var p_r: float = p2d.body_radius if "body_radius" in p2d else 26.0
		if position.distance_to(p2d.global_position + p_off) < HIT_RADIUS + p_r:
			if main.has_method("take_player_damage"):
				main.take_player_damage(damage)
			queue_free()
			return
		# Don't fall through to the friendly hit loops.
		return
	if main and "goblins" in main:
		for g in main.goblins:
			if g == null or not is_instance_valid(g) or g.dead or _hit_set.has(g):
				continue
			# Factor in the goblin's body radius (boss is bigger). Without
			# this the boss could "swallow" arrows that passed close but
			# never hit the centre point, leaving hits unregistered.
			# Read body offset / radius from the goblin's per-instance
			# shape props (set on the BodyArea CollisionShape2D). Falls
			# back to the old constants if the spawn predates the shape.
			var is_boss: bool = "is_boss" in g and g.is_boss
			var body_offset: Vector2
			if "body_offset" in g:
				body_offset = g.body_offset
			else:
				body_offset = FALLBACK_BODY_OFFSET_BOSS if is_boss else FALLBACK_BODY_OFFSET
			var body_r: float
			if "body_radius" in g:
				body_r = g.body_radius * (1.6 if is_boss else 1.0)
			else:
				body_r = FALLBACK_BODY_RADIUS_BOSS if is_boss else FALLBACK_BODY_RADIUS
			var body_pos: Vector2 = g.global_position + body_offset
			if position.distance_to(body_pos) < HIT_RADIUS + body_r:
				_hit_set[g] = true
				if g.has_method("take_damage"):
					var flash_col: Color = Color(0.55, 0.95, 1.4)
					g.take_damage(damage, flash_col)
				if main.has_method("_spawn_damage_number"):
					main._spawn_damage_number(g.global_position + Vector2(0, -32), damage)
				queue_free()
				return
	# Skeletons (dungeon mode) — same body-radius hit test as goblins.
	if main and "in_dungeon" in main and main.in_dungeon \
			and "dungeon" in main and main.dungeon \
			and "skeletons" in main.dungeon:
		for sk in main.dungeon.skeletons:
			if sk == null or not is_instance_valid(sk) or sk.dead or _hit_set.has(sk):
				continue
			var s_off: Vector2 = sk.body_offset if "body_offset" in sk else Vector2(0, -90)
			var s_r: float = sk.body_radius if "body_radius" in sk else 26.0
			var s_pos: Vector2 = sk.global_position + s_off
			if position.distance_to(s_pos) < HIT_RADIUS + s_r:
				_hit_set[sk] = true
				if sk.has_method("take_damage"):
					sk.take_damage(damage, Color(0.55, 0.95, 1.4))
				if main.has_method("_spawn_damage_number"):
					main._spawn_damage_number(sk.global_position + Vector2(0, -32), damage)
				queue_free()
				return
	# No goblin hit — see if the arrow passed over a destructible prop
	# (tree / scattered stone / tall grass). The arrow flies at body
	# height (~110 px above the foot), so checking the cell directly
	# under the arrow misses ground-anchored props. Scan a small
	# neighbourhood of the body-corrected ground cell.
	# Match the arrow against any registered destructible by GROUND-
	# projected distance. The arrow flies at body height (~110 px above
	# its foot); the prop sprite's global_position is at its cell foot.
	# We subtract the body offset from the arrow once, then compare to
	# each sprite's foot directly. Cell-conversion math at body height
	# was unreliable, this avoids it.
	if main and main.has_method("damage_destructible") and "destructibles" in main:
		var ground_pos: Vector2 = position + Vector2(0, 110)
		const DESTRUCTIBLE_HIT_RADIUS := 56.0
		var hr2: float = DESTRUCTIBLE_HIT_RADIUS * DESTRUCTIBLE_HIT_RADIUS
		for cell_key in main.destructibles.keys():
			if _hit_set.has(cell_key):
				continue
			var entry: Variant = main.destructibles[cell_key]
			if not (entry is Dictionary):
				continue
			var spr: Variant = entry.get("sprite", null)
			if spr == null or not is_instance_valid(spr) or not (spr is Node2D):
				continue
			var d2: float = (spr as Node2D).global_position.distance_squared_to(ground_pos)
			if d2 < hr2:
				_hit_set[cell_key] = true
				main.damage_destructible(cell_key, 1)
				queue_free()
				return
