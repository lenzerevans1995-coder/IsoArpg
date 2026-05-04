extends Node
class_name TerrainLift

# Owns the per-cell physics terrain rules (paint_lift, role lift, storey,
# blocking) and the pixel-perfect slope sampling. main.gd delegates here
# so its file stays focused on world streaming + character spawning, and
# the editor can talk to a single object instead of pawing through main.

const TileRules := preload("res://tile_rules.gd")

# 3 stair-steps × 32 px = 96 px climb from south to north of a slope tile,
# matching the visible 3-segment art on G17 et al.
const SLOPE_RISE_PER_TILE := 96

var main: Node = null   # main.gd reference for grid math + constants

# Per-cell terrain state.
var tile_storey: Dictionary = {}        # legacy storey count, max-of-stack
var tile_role_lift: Dictionary = {}     # max LIFT_PX from any painted role
var tile_paint_lift: Dictionary = {}    # max y_lift from painted tiles
var tile_blocked: Dictionary = {}       # blocking refcount

# Pixel-perfect slope state.
var _tile_height_maps: Dictionary = {}  # tex_path -> PackedInt32Array
var _tile_alpha_masks: Dictionary = {}  # tex_path -> Image (kept for pixel-
                                        # perfect wall collision so a hole or
                                        # transparent window is passable)
var _painted_pixels: Dictionary = {}    # cell -> Array[{tex_path, y_lift}]

# ---- height map cache --------------------------------------------------------

func _height_map_for(tex_path: String) -> PackedInt32Array:
	if _tile_height_maps.has(tex_path):
		return _tile_height_maps[tex_path]
	var tex: Texture2D = load(tex_path) if ResourceLoader.exists(tex_path) else null
	if tex == null:
		_tile_height_maps[tex_path] = PackedInt32Array()
		return _tile_height_maps[tex_path]
	var img: Image = tex.get_image()
	if img == null:
		_tile_height_maps[tex_path] = PackedInt32Array()
		return _tile_height_maps[tex_path]
	# Stash the image so wall-collision can do per-pixel alpha (windows,
	# arches and other holes in a wall sprite stay passable).
	_tile_alpha_masks[tex_path] = img
	var w: int = img.get_width()
	var h: int = img.get_height()
	var result := PackedInt32Array()
	result.resize(w)
	for x in range(w):
		result[x] = -1
		for y in range(h):
			if img.get_pixel(x, y).a > 0.1:
				result[x] = y
				break
	_tile_height_maps[tex_path] = result
	return result

# ---- registration (editor calls these on every paint / peel) -----------------

func register_painted_pixel_tile(cell: Vector2i, tex_path: String, y_lift: int) -> void:
	if tex_path == "":
		return
	# Filter by ROLE rather than path — G18-G21 cave walls live in
	# assets/forest/environment/, not the elevation/ folder, so a path
	# check would silently skip them. Skip GROUND / OVERLAY because flat
	# tiles don't need pixel-perfect physics.
	var role: int = TileRules.role_for_path(tex_path)
	if role == TileRules.Role.GROUND or role == TileRules.Role.OVERLAY:
		return
	if not _painted_pixels.has(cell):
		_painted_pixels[cell] = []
	_painted_pixels[cell].append({
		"tex_path": tex_path,
		"y_lift": y_lift,
		"role": role,
		"layer": 1,   # default; the editor calls set_painted_layer to override
	})
	_height_map_for(tex_path)
	# For BLOCKING painted tiles (cave walls etc.) also seed main.blocked
	# at the placement cell AND the cell visually-south on screen — the
	# wall sprite's visible base extends DOWN past the cell origin into
	# the cell that converts to (c+1, r) / (c, r+1) on screen. Without
	# this the player walks under the wall along the row that holds its
	# visual base, even though the foot is "below" the texture.
	if main and TileRules.BLOCKING.get(role, false):
		if main.blocked != null:
			main.blocked[cell] = true
			main.blocked[Vector2i(cell.x + 1, cell.y)] = true
			main.blocked[Vector2i(cell.x, cell.y + 1)] = true
			main.blocked[Vector2i(cell.x + 1, cell.y + 1)] = true

var _trees: Dictionary = {}             # cell -> tex_path. Trunk-only block.
const TREE_TRUNK_HEIGHT_PX := 48        # bottom of texture treated as the
                                        # blocking trunk; foliage above is
                                        # purely decorative.

func register_tree(cell: Vector2i, tex_path: String) -> void:
	if tex_path == "":
		return
	_trees[cell] = tex_path
	_height_map_for(tex_path)   # also caches alpha mask

func unregister_tree(cell: Vector2i) -> void:
	_trees.erase(cell)

func set_painted_layer(cell: Vector2i, tex_path: String, y_lift: int, layer: int) -> void:
	if not _painted_pixels.has(cell):
		return
	for entry in _painted_pixels[cell]:
		if entry is Dictionary and entry.get("tex_path", "") == tex_path and int(entry.get("y_lift", 0)) == y_lift:
			entry["layer"] = layer
			return

# Pixel-level wall collision: returns true if any blocking-role painted
# tile in the 3x3 around `pos` has an opaque pixel under the player's
# column. So a thin cliff/wall sprite blocks only the strip its art
# actually covers, not the whole cell.
func is_blocked_at_pos(pos: Vector2) -> bool:
	# "Visible pixel wins": across all painted sprites whose opaque texel
	# covers the player's screen pixel, only the FRONTMOST one (highest
	# y-sort key) decides whether the player is blocked. So a wall hidden
	# behind a tree (the tree's opaque pixels are drawn on top) doesn't
	# block where the tree is, and a wall whose pixels render above other
	# sprites does block.
	var center_cell: Vector2i = main._screen_to_grid(pos)
	var best_sort: float = -INF
	var best_role: int = TileRules.Role.GROUND
	for dx in range(-5, 6):
		for dy in range(-5, 6):
			var cell := center_cell + Vector2i(dx, dy)
			if not _painted_pixels.has(cell):
				continue
			var center: Vector2 = main.grid_to_screen(cell)
			# Sort key: layer dominates (so layer-2 paints win over layer-1
			# regardless of iso position), then SW-priority y nudge.
			for entry in _painted_pixels[cell]:
				var sort_key: float = float(int(entry.get("layer", 1))) * 1.0e6 + center.y + float(cell.y) * 0.001
				var img: Image = _tile_alpha_masks.get(entry.tex_path, null)
				if img == null:
					_height_map_for(entry.tex_path)
					img = _tile_alpha_masks.get(entry.tex_path, null)
					if img == null:
						continue
				var sprite_w: int = img.get_width()
				var sprite_h: int = img.get_height()
				# Use real texture dimensions instead of the old hard-coded
				# 256/128 — rocks and other props use smaller assets and
				# the foot pixel was being tested at the wrong row.
				var tlx: float = center.x - float(sprite_w) * 0.5
				var tly: float = center.y - float(sprite_h) * 0.5 + float(main.SPRITE_Y_OFFSET) - float(int(entry.get("y_lift", 0)))
				var rel_x: int = int(round(pos.x - tlx))
				var rel_y: int = int(round(pos.y - tly))
				if rel_x < 0 or rel_x >= sprite_w:
					continue
				if rel_y < 0 or rel_y >= sprite_h:
					continue
				if img.get_pixel(rel_x, rel_y).a <= 0.1:
					continue
				if sort_key > best_sort:
					best_sort = sort_key
					best_role = int(entry.get("role", 0))
	if TileRules.BLOCKING.get(best_role, false):
		return true
	# Trees: only the trunk (bottom TREE_TRUNK_HEIGHT_PX of the texture)
	# blocks, so the player can walk behind and under the foliage.
	for dx2 in range(-2, 3):
		for dy2 in range(-2, 3):
			var t_cell := center_cell + Vector2i(dx2, dy2)
			if not _trees.has(t_cell):
				continue
			var tex_path: String = _trees[t_cell]
			var img: Image = _tile_alpha_masks.get(tex_path, null)
			if img == null:
				continue
			var t_center: Vector2 = main.grid_to_screen(t_cell)
			var sprite_w: int = img.get_width()
			var sprite_h: int = img.get_height()
			# Sprites use centered=true with offset (0, SPRITE_Y_OFFSET).
			# Texture top-left in world = (centre - w/2, centre - h/2 + off).
			# The old code hardcoded h/2 = 128 (256-tall assets only); for
			# 128-tall trees this misaligned the alpha check by 64 px and
			# the trunk pixels were never tested.
			var tlx: float = t_center.x - float(sprite_w) * 0.5
			var tly: float = t_center.y - float(sprite_h) * 0.5 + float(main.SPRITE_Y_OFFSET)
			var rel_x: int = int(round(pos.x - tlx))
			var rel_y: int = int(round(pos.y - tly))
			if rel_x < 0 or rel_x >= sprite_w:
				continue
			if rel_y < sprite_h - TREE_TRUNK_HEIGHT_PX or rel_y >= sprite_h:
				continue
			if img.get_pixel(rel_x, rel_y).a > 0.1:
				return true
	return false

func unregister_painted_pixel_tile(cell: Vector2i, tex_path: String, y_lift: int) -> void:
	if not _painted_pixels.has(cell):
		return
	var arr: Array = _painted_pixels[cell]
	for i in range(arr.size() - 1, -1, -1):
		var e = arr[i]
		if e is Dictionary and e.tex_path == tex_path and int(e.y_lift) == y_lift:
			arr.remove_at(i)
			break
	if arr.is_empty():
		_painted_pixels.erase(cell)

func set_tile_paint_lift(cell: Vector2i, lift_px: int, added: bool) -> void:
	if lift_px <= 0:
		return
	if added:
		tile_paint_lift[cell] = max(int(tile_paint_lift.get(cell, 0)), lift_px)
	else:
		if int(tile_paint_lift.get(cell, 0)) <= lift_px:
			tile_paint_lift.erase(cell)

func set_tile_role(cell: Vector2i, role: int, added: bool) -> void:
	var storey: int = TileRules.STOREY_HEIGHT.get(role, 0)
	var lift_px: int = TileRules.LIFT_PX.get(role, 0)
	if storey > 0:
		if added:
			tile_storey[cell] = max(int(tile_storey.get(cell, 0)), storey)
		else:
			if int(tile_storey.get(cell, 0)) <= storey:
				tile_storey.erase(cell)
	if lift_px > 0:
		if added:
			tile_role_lift[cell] = max(int(tile_role_lift.get(cell, 0)), lift_px)
		else:
			if int(tile_role_lift.get(cell, 0)) <= lift_px:
				tile_role_lift.erase(cell)
	if TileRules.BLOCKING.get(role, false):
		# Refcount only — no cell-level main.blocked write. Wall collision
		# is now pixel-perfect via is_blocked_at_pos, so the player can
		# squeeze around a thin cliff strip instead of being stopped at
		# the whole 128x64 cell footprint.
		var n: int = int(tile_blocked.get(cell, 0)) + (1 if added else -1)
		if n <= 0:
			tile_blocked.erase(cell)
		else:
			tile_blocked[cell] = n

# ---- queries (player physics calls these) -----------------------------------

func _cell_floor_lift(cell: Vector2i) -> float:
	var rl: float = float(int(tile_role_lift.get(cell, 0)))
	var sl: float = float(int(tile_storey.get(cell, 0))) * float(main.HILL_LIFT)
	var pl: float = float(int(tile_paint_lift.get(cell, 0)))
	# Slope cells contribute their TOP so adjacent flat cells using bilinear
	# corner-min interp see the slope's high end at the shared corner.
	var slope_top: float = 0.0
	if _painted_pixels.has(cell):
		var max_yl: int = 0
		for entry in _painted_pixels[cell]:
			max_yl = max(max_yl, int(entry.y_lift))
		slope_top = float(max_yl) + float(SLOPE_RISE_PER_TILE)
	return max(slope_top, max(rl, max(sl, pl)))

func _corner_lift(cell: Vector2i, dx: int, dy: int) -> float:
	var l: float = _cell_floor_lift(cell)
	l = min(l, _cell_floor_lift(cell + Vector2i(dx, 0)))
	l = min(l, _cell_floor_lift(cell + Vector2i(0, dy)))
	l = min(l, _cell_floor_lift(cell + Vector2i(dx, dy)))
	return l

func _has_floor_neighbour(cell: Vector2i) -> bool:
	for off in [Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1),
			Vector2i(-1,0), Vector2i(1,0),
			Vector2i(-1,1), Vector2i(0,1), Vector2i(1,1)]:
		if _cell_floor_lift(cell + off) > 0.0:
			return true
	return false

# Slope-cell pixel-perfect lift: ramp from y_lift at south edge to
# y_lift + SLOPE_RISE_PER_TILE at north edge. Returns -INF if the player
# isn't on a registered slope cell.
func _pixel_lift_at(pos: Vector2) -> float:
	var cell: Vector2i = main._screen_to_grid(pos)
	if not _painted_pixels.has(cell):
		return -INF
	var stack: Array = _painted_pixels[cell]
	if stack.is_empty():
		return -INF
	var base_y_lift: int = 0
	for entry in stack:
		base_y_lift = max(base_y_lift, int(entry.y_lift))
	var center: Vector2 = main.grid_to_screen(cell)
	var d: Vector2 = pos - center
	var v: float = clamp((d.y / 64.0 - d.x / 128.0) * 0.5, -0.5, 0.5)
	var t: float = 0.5 - v
	return float(base_y_lift) + float(SLOPE_RISE_PER_TILE) * t

# Public lift queries used by player physics.
func cell_lift_at(pos: Vector2) -> float:
	# Slope cells (registered elevation tiles) ramp linearly across the cell.
	var px_lift: float = _pixel_lift_at(pos)
	if px_lift != -INF:
		return px_lift
	# Otherwise: each cell holds its OWN floor lift as a hard square — every
	# point in an S2 cell reads exactly 64 px, no bilinear corner gradient
	# blending into neighbours. The player's velocity-bounded lift tracker
	# in player_layered.gd handles the visual smoothing across cell
	# boundaries, so we don't need to fake gradients here.
	var cell: Vector2i = main._screen_to_grid(pos)
	var here: float = _cell_floor_lift(cell)
	if here > 0.0:
		return here
	return float(main.HILL_LIFT) if main.is_hill_interior(cell) else 0.0

func cell_lift(cell: Vector2i) -> float:
	return cell_lift_at(main.grid_to_screen(cell))
