extends Node2D
class_name Dungeon

# Procedural dungeon proto. Generates 7-11 rooms + 1 boss room connected
# by 2-3 cell wide corridors, painted on top of a fully-black backdrop
# so empty space outside the rooms reads as void (not traversable).
#
# Tile choices come straight from the user's spec:
#   walls       Wall A1 (placeholder)
#   ground      Ground D1
#   stone divider / corner / partial   Stone A9 / A10 / A9
#   minerals    Stone A16, A21
#   rocks       Stone A1, A2
#   misc props  Misc A1 bones, A2 1pot, A3 3pot, A8 1barrel, A9 3barrel
#   chest       Chest A3 closed (Chest A4 open swap is gameplay-side)

const ENV := "res://assets/forest/environment"
const SUFFIX := "_S"   # default rotation; matches procedural world's bias
const TILE_W := 128
const TILE_H := 64
const SPRITE_Y := -82
const ROOMS_MIN := 7
const ROOMS_MAX := 11
const ROOM_SIZE_MIN := Vector2i(5, 5)
const ROOM_SIZE_MAX := Vector2i(9, 9)
const BOSS_ROOM_SIZE := Vector2i(11, 11)
const CORRIDOR_WIDTH := 5
const PROP_DENSITY := 0.04

const ROOM_TILES_W := 80   # tile-grid width the dungeon spans
const ROOM_TILES_H := 80

var floor_cells: Dictionary = {}    # cell -> true (walkable)
var wall_cells: Dictionary = {}     # cell -> true (wall sprite present)
var rooms: Array = []               # Array[Rect2i]
var boss_room: Rect2i
var spawn_cell: Vector2i
# Props (rocks / bones / chests) by cell so save/load can restore them.
# Each entry: { "cell": Vector2i, "family": String, "z": int }.
var _props_records: Array = []
# User-toggled wall transparency, keyed by cell. The generator no longer
# applies transparency by default — toggle it on per-wall in the editor.
var transparent_walls: Dictionary = {}
# Map cell -> wall sprites placed there, so the editor can repaint /
# delete / toggle transparency on a per-cell basis.
var _wall_sprites: Dictionary = {}

const DRAFT_PATH := "user://draft_Dungeon.json"
const FIXED_SEED := 1337

var _rng := RandomNumberGenerator.new()

# ---- Public API -------------------------------------------------------

func build(seed_value: int = 0) -> void:
	# If a saved draft_Dungeon exists, load that and skip procedural gen.
	# Otherwise generate ONCE from a fixed seed so the layout is the same
	# every time the player enters (the user can then iterate on it).
	if _load_draft():
		_spawn_skeletons()
		return
	_rng.seed = seed_value if seed_value != 0 else FIXED_SEED
	_clear()
	_generate_layout()
	_paint_floors()
	_paint_walls()
	_scatter_props()
	_place_chest()
	_spawn_skeletons()

const _SkeletonScript := preload("res://skeleton.gd")
var skeletons: Array = []

func _spawn_skeletons() -> void:
	for s in skeletons:
		if is_instance_valid(s):
			s.queue_free()
	skeletons.clear()
	var main := get_tree().root.get_node_or_null("Main")
	var player_target: Node2D = main.player if main else null
	# GUARANTEE every elite type appears at least once across the
	# dungeon — pick distinct rooms for each. Common mobs fill the
	# remaining slots so warriors / archers / wizards are everywhere
	# but the player can find each elite somewhere in the run.
	var elite_kinds := [
		_SkeletonScript.Kind.BRUTE,
		_SkeletonScript.Kind.DARK_KNIGHT,
		_SkeletonScript.Kind.BERSERKER,
		_SkeletonScript.Kind.DARK_ARCHER,
		_SkeletonScript.Kind.NECROMANCER,
	]
	# Shuffle a copy of `rooms` so each elite lands in a different one.
	var room_pool: Array = rooms.duplicate()
	# Fisher-Yates shuffle using our own RNG.
	for i in range(room_pool.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp = room_pool[i]
		room_pool[i] = room_pool[j]
		room_pool[j] = tmp
	var elite_rooms: Dictionary = {}
	for idx in range(min(elite_kinds.size(), room_pool.size())):
		elite_rooms[room_pool[idx]] = elite_kinds[idx]
	# Spawn pack per room: 1 elite if assigned + 2-3 commons.
	for r in rooms:
		if elite_rooms.has(r):
			_spawn_skel_in_rect(r, elite_rooms[r], player_target)
		var pack_size: int = _rng.randi_range(2, 3)
		for i in range(pack_size):
			var roll: float = _rng.randf()
			var kid: int
			if roll < 0.50:
				kid = _SkeletonScript.Kind.WARRIOR
			elif roll < 0.80:
				kid = _SkeletonScript.Kind.ARCHER
			else:
				kid = _SkeletonScript.Kind.WIZARD
			_spawn_skel_in_rect(r, kid, player_target)
	# Boss room: Deathlord + 2 Warrior escorts (always).
	if boss_room.size != Vector2i.ZERO:
		_spawn_skel_in_rect(boss_room, _SkeletonScript.Kind.DEATHLORD, player_target)
		for i in range(2):
			_spawn_skel_in_rect(boss_room, _SkeletonScript.Kind.WARRIOR, player_target)

func _spawn_skel_in_rect(rect: Rect2i, kind_id: int, player_target: Node2D) -> void:
	# Drop the skeleton on a random interior cell that isn't a wall.
	for tries in range(20):
		var cx: int = _rng.randi_range(rect.position.x + 1, rect.position.x + rect.size.x - 2)
		var cy: int = _rng.randi_range(rect.position.y + 1, rect.position.y + rect.size.y - 2)
		var cell := Vector2i(cx, cy)
		if not floor_cells.has(cell):
			continue
		if wall_cells.has(cell):
			continue
		var s: Node2D = _SkeletonScript.make(kind_id, player_target)
		s.position = _grid_to_screen(cell)
		# Lock the skeleton to the room it spawned in. Common mobs +
		# elites stay in their assigned room; the boss stays in the
		# boss room. AI idles when the player isn't in this rect.
		s.home_rect = rect
		add_child(s)
		skeletons.append(s)
		return

func player_spawn_world_pos() -> Vector2:
	return _grid_to_screen(spawn_cell)

# ---- Layout -----------------------------------------------------------

func _clear() -> void:
	for child in get_children():
		child.queue_free()
	floor_cells.clear()
	wall_cells.clear()
	rooms.clear()
	# Black backdrop covering the entire dungeon footprint.
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	# Convert grid bounds to a generous screen-space rect.
	bg.size = Vector2(ROOM_TILES_W * TILE_W, ROOM_TILES_H * TILE_H)
	bg.position = -bg.size * 0.5
	bg.z_index = -1000
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func _generate_layout() -> void:
	var n_rooms: int = _rng.randi_range(ROOMS_MIN, ROOMS_MAX)
	# Try to place each room in random non-overlapping spots within the grid.
	var attempts: int = 200
	while rooms.size() < n_rooms and attempts > 0:
		attempts -= 1
		var sz := Vector2i(
			_rng.randi_range(ROOM_SIZE_MIN.x, ROOM_SIZE_MAX.x),
			_rng.randi_range(ROOM_SIZE_MIN.y, ROOM_SIZE_MAX.y))
		var pos := Vector2i(
			_rng.randi_range(2, ROOM_TILES_W - sz.x - 2) - ROOM_TILES_W / 2,
			_rng.randi_range(2, ROOM_TILES_H - sz.y - 2) - ROOM_TILES_H / 2)
		var rect := Rect2i(pos, sz)
		if _room_overlaps(rect, 2):
			continue
		rooms.append(rect)
	# Boss room: bigger, placed last with larger padding.
	for tries in range(80):
		var pos := Vector2i(
			_rng.randi_range(2, ROOM_TILES_W - BOSS_ROOM_SIZE.x - 2) - ROOM_TILES_W / 2,
			_rng.randi_range(2, ROOM_TILES_H - BOSS_ROOM_SIZE.y - 2) - ROOM_TILES_H / 2)
		var rect := Rect2i(pos, BOSS_ROOM_SIZE)
		if not _room_overlaps(rect, 3):
			boss_room = rect
			break
	if boss_room.size == Vector2i.ZERO:
		boss_room = Rect2i(rooms[0].position, BOSS_ROOM_SIZE)
	# Carve floors for all rooms.
	for r in rooms:
		_carve_room(r)
	_carve_room(boss_room)
	# Connect rooms with 2-3 wide L-corridors. Chain them in placement order
	# then connect boss to the closest non-boss room.
	for i in range(rooms.size() - 1):
		_carve_corridor(rooms[i], rooms[i + 1])
	if rooms.size() > 0:
		_carve_corridor(rooms.back(), boss_room)
	# Spawn at the centre of the first non-boss room.
	if rooms.size() > 0:
		spawn_cell = rooms[0].position + rooms[0].size / 2

func _room_overlaps(rect: Rect2i, pad: int) -> bool:
	var grown := Rect2i(rect.position - Vector2i(pad, pad),
			rect.size + Vector2i(pad * 2, pad * 2))
	for r in rooms:
		if grown.intersects(r):
			return true
	if boss_room.size != Vector2i.ZERO and grown.intersects(boss_room):
		return true
	return false

func _carve_room(rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			floor_cells[Vector2i(x, y)] = true

func _carve_corridor(a: Rect2i, b: Rect2i) -> void:
	var ac := a.position + a.size / 2
	var bc := b.position + b.size / 2
	# L-shape: travel x first then y. CORRIDOR_WIDTH cells thick.
	var w: int = max(2, CORRIDOR_WIDTH)
	var x0: int = mini(ac.x, bc.x)
	var x1: int = maxi(ac.x, bc.x)
	for x in range(x0, x1 + 1):
		for off in range(-(w / 2), (w / 2) + 1):
			floor_cells[Vector2i(x, ac.y + off)] = true
	var y0: int = mini(ac.y, bc.y)
	var y1: int = maxi(ac.y, bc.y)
	for y in range(y0, y1 + 1):
		for off in range(-(w / 2), (w / 2) + 1):
			floor_cells[Vector2i(bc.x + off, y)] = true

# ---- Painting ---------------------------------------------------------

func _paint_floors() -> void:
	# Two-layer floor: Ground A1 base + Ground E1 top overlay (cobble /
	# detail pass) so the surface reads richer than a flat dirt tile.
	var base_tex: Texture2D = _load_tile("Ground A1")
	var top_tex: Texture2D = _load_tile("Ground E1")
	for cell in floor_cells.keys():
		if base_tex != null:
			var b := _make_sprite(base_tex, cell)
			b.z_index = -3
			add_child(b)
		if top_tex != null:
			var t := _make_sprite(top_tex, cell)
			t.z_index = -2
			add_child(t)

func _paint_walls() -> void:
	# Place walls on the EDGE FLOOR CELLS (cells that ARE floor but have
	# at least one cardinal void neighbour). Stamping the wall on top of
	# the floor cell makes the wall visually connect to the floor with
	# no gap, instead of floating one cell out in the void.
	# Side selection per cardinal void neighbour:
	#   void to N (no floor north)  → Wall A1_N (back/north face)
	#   void to E                   → Wall A1_E (back/east face)
	#   void to S                   → Wall A1_S (front/south face)
	#   void to W                   → Wall A1_W (front/west face)
	# All four walls use the Wall A1 family — inner stone walls are off
	# for now per your call. Corners just stack the two relevant variants.
	for cell in floor_cells.keys():
		var sides: Array = []
		if not floor_cells.has(cell + Vector2i(0, -1)): sides.append("_N")
		if not floor_cells.has(cell + Vector2i(1, 0)):  sides.append("_E")
		if not floor_cells.has(cell + Vector2i(0, 1)):  sides.append("_S")
		if not floor_cells.has(cell + Vector2i(-1, 0)): sides.append("_W")
		if sides.is_empty():
			continue
		# CORNER ONLY when TWO adjacent cardinal sides are missing.
		# Single-side-missing cells are straight walls — never corners.
		# This produces the L_______L pattern: just the four outer
		# corners, straight pieces in between.
		var corner_suf: String = ""
		if sides.size() >= 2:
			if sides.has("_N") and sides.has("_E"):     corner_suf = "_N"
			elif sides.has("_N") and sides.has("_W"):   corner_suf = "_W"
			elif sides.has("_S") and sides.has("_E"):   corner_suf = "_E"
			elif sides.has("_S") and sides.has("_W"):   corner_suf = "_S"
		# CORNERS: when a corner is detected we ALWAYS render just the
		# corner piece — never stack straight Wall A1 sprites on top.
		# (Previously the fallback ran when the texture failed to load,
		# producing visible doubles. Now the cell is fully claimed by
		# the corner case even if the corner texture is missing.)
		if corner_suf != "":
			var cpath := "%s/Wall A2%s.png" % [ENV, corner_suf]
			var ctex: Texture2D = load(cpath) if ResourceLoader.exists(cpath) else null
			if ctex != null:
				var cs := _make_sprite(ctex, cell)
				# Opaque corners (_N / _W back-side) render in front of
				# transparent walls (z=100) so the solid corner stays
				# clearly readable at the intersection.
				var is_t: bool = (corner_suf == "_S" or corner_suf == "_E")
				cs.z_index = 100 if is_t else 110
				add_child(cs)
				_track_wall_sprite(cell, cs, corner_suf)
			wall_cells[cell] = true
			continue
		# Straight wall(s) — one sprite per missing cardinal side. Both
		# opaque and transparent walls render, but opaque sit at a
		# HIGHER z_index so at corner intersections the solid wall
		# draws on top of the translucent wall instead of being covered
		# by it.
		for suf in sides:
			var path := "%s/Wall A1%s.png" % [ENV, suf]
			var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
			if tex == null:
				continue
			var s := _make_sprite(tex, cell)
			var is_transparent_side: bool = (suf == "_S" or suf == "_E")
			s.z_index = 100 if is_transparent_side else 110
			add_child(s)
			_track_wall_sprite(cell, s, suf)
		wall_cells[cell] = true

func _track_wall_sprite(cell: Vector2i, s: Sprite2D, suffix: String = "") -> void:
	if not _wall_sprites.has(cell):
		_wall_sprites[cell] = []
	_wall_sprites[cell].append(s)
	# Opaque walls render at full white. Transparent walls (auto-flagged
	# for _S / _E suffixes, or explicitly toggled) get a darker tint
	# AND reduced alpha so they read as a translucent silhouette the
	# player can stand under without losing detail.
	var auto_transparent: bool = (suffix == "_S" or suffix == "_E")
	var trans: bool = bool(transparent_walls.get(cell, false)) or auto_transparent
	if trans:
		# Higher alpha (0.78) reduces compounding when multiple wall
		# sprites overlap on screen — two stacked at 0.55 ended up
		# almost opaque-dark, two stacked at 0.78 stays readable.
		s.modulate = Color(0.45, 0.45, 0.50, 0.78)
		transparent_walls[cell] = true

# Generation no longer applies transparency. The editor toggles it
# per-cell via toggle_wall_transparent() which calls this with the
# current state for that cell.
func _apply_front_wall_alpha(_s: Sprite2D, _suffix: String) -> void:
	pass

# Toggle wall transparency on a single cell. Sprites already placed
# there have their modulate updated immediately. Persists in
# transparent_walls so save/load and re-apply pick it up.
func toggle_wall_transparent(cell: Vector2i) -> bool:
	if not wall_cells.has(cell):
		return false
	var on: bool = not bool(transparent_walls.get(cell, false))
	transparent_walls[cell] = on
	var col := Color(0.45, 0.45, 0.50, 0.78) if on else Color(1, 1, 1, 1)
	for spr in _wall_sprites.get(cell, []):
		if is_instance_valid(spr):
			(spr as Sprite2D).modulate = col
	return on

# Peel ONE sprite at the given cell (the visually topmost one). Right-
# click in the editor calls this so each click chips away a single
# layer instead of nuking the entire cell at once.
# Removal order (highest z_index first): props → walls → floor top → floor base.
func delete_cell(cell: Vector2i) -> bool:
	var top: Sprite2D = null
	var top_z: int = -2147483648
	for child in get_children():
		if not (child is Sprite2D):
			continue
		if not child.has_meta("cell"):
			continue
		if Vector2i(child.get_meta("cell")) != cell:
			continue
		var spr := child as Sprite2D
		if spr.z_index > top_z:
			top_z = spr.z_index
			top = spr
	if top == null:
		return false
	# Update tracking dicts so subsequent peels know what's left.
	if _wall_sprites.has(cell):
		var lst: Array = _wall_sprites[cell]
		lst.erase(top)
		if lst.is_empty():
			_wall_sprites.erase(cell)
			wall_cells.erase(cell)
			transparent_walls.erase(cell)
	top.queue_free()
	# If the floor-base sprite is the only thing left and it's also gone,
	# clear the floor flag so that cell becomes void / impassable.
	var any_left: bool = false
	for child in get_children():
		if child == top:
			continue
		if child is Sprite2D and child.has_meta("cell") \
				and Vector2i(child.get_meta("cell")) == cell:
			any_left = true
			break
	if not any_left:
		floor_cells.erase(cell)
	return true

func _scatter_props() -> void:
	# Inline placement (no record-keeping helper). Each prop appended to
	# _props_records so save_draft can persist it; no double sprites.
	var families := ["Stone A1", "Stone A2", "Stone A16", "Stone A21",
			"Misc A1", "Misc A2", "Misc A3", "Misc A8", "Misc A9"]
	for r in rooms:
		for x in range(r.position.x + 1, r.position.x + r.size.x - 1):
			for y in range(r.position.y + 1, r.position.y + r.size.y - 1):
				if _rng.randf() > PROP_DENSITY:
					continue
				var fam: String = families[_rng.randi_range(0, families.size() - 1)]
				var tex: Texture2D = _load_tile(fam)
				if tex == null:
					continue
				var cell := Vector2i(x, y)
				var s := _make_sprite(tex, cell)
				s.z_index = 50
				add_child(s)
				_props_records.append({"cell": cell, "family": fam, "z": 50})

func _place_chest() -> void:
	if boss_room.size == Vector2i.ZERO:
		return
	var cell := boss_room.position + boss_room.size / 2
	var tex: Texture2D = _load_tile("Chest A3")
	if tex == null:
		return
	var s := _make_sprite(tex, cell)
	s.z_index = 60
	add_child(s)
	_props_records.append({"cell": cell, "family": "Chest A3", "z": 60})

# ---- Helpers ----------------------------------------------------------

func _load_tile(family: String) -> Texture2D:
	var path := "%s/%s%s.png" % [ENV, family, SUFFIX]
	if ResourceLoader.exists(path):
		return load(path)
	# Fall back to first matching directional variant if the south one
	# isn't present for that family.
	for suf in ["_E", "_N", "_W"]:
		var p := "%s/%s%s.png" % [ENV, family, suf]
		if ResourceLoader.exists(p):
			return load(p)
	return null

func _make_sprite(tex: Texture2D, cell: Vector2i) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.offset = Vector2(0, SPRITE_Y)
	s.position = _grid_to_screen(cell)
	s.set_meta("cell", cell)
	return s

func _grid_to_screen(g: Vector2i) -> Vector2:
	return Vector2((g.x - g.y) * (TILE_W * 0.5), (g.x + g.y) * (TILE_H * 0.5))

func save_draft() -> void:
	var floors: Array = []
	for c in floor_cells.keys():
		floors.append([int(c.x), int(c.y)])
	var walls: Array = []
	for c in wall_cells.keys():
		walls.append([int(c.x), int(c.y), bool(transparent_walls.get(c, false))])
	var props: Array = []
	for p in _props_records:
		var c: Vector2i = p["cell"]
		props.append({"x": int(c.x), "y": int(c.y),
				"family": String(p["family"]), "z": int(p["z"])})
	var data := {
		"version": 1,
		"spawn": [int(spawn_cell.x), int(spawn_cell.y)],
		"floors": floors,
		"walls": walls,
		"props": props,
	}
	var f := FileAccess.open(DRAFT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()

func _load_draft() -> bool:
	if not FileAccess.file_exists(DRAFT_PATH):
		return false
	var f := FileAccess.open(DRAFT_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not data is Dictionary:
		return false
	_clear()
	floor_cells.clear()
	wall_cells.clear()
	transparent_walls.clear()
	_wall_sprites.clear()
	if data.has("spawn"):
		spawn_cell = Vector2i(int(data.spawn[0]), int(data.spawn[1]))
	if data.has("floors"):
		for fc in data.floors:
			floor_cells[Vector2i(int(fc[0]), int(fc[1]))] = true
	if data.has("walls"):
		for w in data.walls:
			var c := Vector2i(int(w[0]), int(w[1]))
			if w.size() >= 3 and bool(w[2]):
				transparent_walls[c] = true
	_paint_floors()
	_paint_walls()
	if data.has("props"):
		for p in data.props:
			var cell := Vector2i(int(p.get("x", 0)), int(p.get("y", 0)))
			var fam := String(p.get("family", ""))
			var tex: Texture2D = _load_tile(fam)
			if tex == null:
				continue
			var z: int = int(p.get("z", 50))
			var s := _make_sprite(tex, cell)
			s.z_index = z
			add_child(s)
			_props_records.append({"cell": cell, "family": fam, "z": z})
	return true

func is_walkable_world(world_pos: Vector2) -> bool:
	# Convert a world position back to a grid cell and check if it's a
	# carved floor. Used by the player movement check while in dungeon
	# mode so the void around rooms is impassable.
	var tw := TILE_W * 0.5
	var th := TILE_H * 0.5
	var gx := int(floor((world_pos.x / tw + world_pos.y / th) * 0.5))
	var gy := int(floor((world_pos.y / th - world_pos.x / tw) * 0.5))
	return floor_cells.has(Vector2i(gx, gy))
