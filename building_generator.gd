extends RefCounted
class_name BuildingGenerator

# Generates a rectangular PVGames building. Pieces are iso-projected on a
# 64x64 diamond floor. Layout uses y-sort: every sprite's `position.y` is its
# iso ground baseline, and the texture is drawn upward via Sprite2D.offset.
#
# Iso math (1:1 dimetric, matches the PVGames 32-grid guide):
#     screen.x = (col - row) * 32
#     screen.y = (col + row) * 32
#
# A wall placed at iso (col,row) has its bottom 64 px footprint sitting on the
# floor diamond at that cell, and rises (piece_h - 64) px above it.
# Wall variants Wall_Large_1..4 have asymmetric content:
#   _1, _2  — content shifted LEFT  (used for edges where the wall's HIGH end
#             is on the screen-LEFT — i.e. iso edges that run upper-left to
#             lower-right: the N→E and S→E sides)
#   _3, _4  — content shifted RIGHT (HIGH end on the screen-RIGHT — i.e. iso
#             edges that run upper-right to lower-left: the W→N and W→S sides)

# Match main.gd's world tile grid (TILE_W=128, TILE_H=64). PVGames pieces are
# authored at 64x64 1:1 dimetric, so we scale them x=2,y=1 so the floor
# diamond inscribed in the 64x64 PNG displays as a 128x64 iso diamond aligned
# with the rest of the world.
const HALF_W := 64
const HALF_H := 32
const PIECE_SCALE := Vector2(2.0, 1.0)
const ASSETS := "res://assets/shader_assets"

# Per-edge wall variant pools (random pick from each pool for variety).
const WALL_VARIANTS_LEFT := ["Wall_Large_1", "Wall_Large_2"]
const WALL_VARIANTS_RIGHT := ["Wall_Large_3", "Wall_Large_4"]

static func generate(parent: Node2D, origin: Vector2, w: int, h: int,
		pack: String = "building_stone_1", door_col: int = -1) -> Node2D:
	var root := Node2D.new()
	root.position = origin
	root.y_sort_enabled = true
	root.add_to_group("placed_shader_asset")
	parent.add_child(root)
	var pack_root := "%s/%s" % [ASSETS, pack]

	# 1) Floors at every iso (ix, iy).
	for iy in range(h):
		for ix in range(w):
			_place(root, pack_root, "Floor_Lower", ix, iy)

	# 2) Walls.
	# BACK walls sit one cell OUTSIDE the building (north + west sides).
	# FRONT walls (SE + SW) layer onto the SE and SW floor edges (last col
	# and last row of the floor grid) so they cap the visible front edges.
	# N→E back edge (iso row -1)
	for ix in range(w):
		_place(root, pack_root, _pick(WALL_VARIANTS_LEFT), ix, -1)
	# W→N back edge (iso col -1)
	for iy in range(h):
		_place(root, pack_root, _pick(WALL_VARIANTS_RIGHT), -1, iy)
	# SW front edge — layered on the south-most floor row (iy = h-1).
	# Skip the W and S corners (col 0 and col w-1) — they get corner posts.
	for ix in range(1, w - 1):
		if ix == door_col:
			continue
		_place(root, pack_root, _pick(WALL_VARIANTS_LEFT), ix, h - 1)
	# SE front edge — layered on the east-most floor column (ix = w-1).
	# Skip the E and S corners (row 0 and row h-1) — corner posts handle them.
	for iy in range(1, h - 1):
		_place(root, pack_root, _pick(WALL_VARIANTS_RIGHT), w - 1, iy)

	# 3) Corner posts. North + east + west use Wall_Large_6, south uses _5.
	_place(root, pack_root, "Wall_Large_6", -1, -1)        # N corner (outside)
	_place(root, pack_root, "Wall_Large_6", w - 1, 0)      # E corner (on floor)
	_place(root, pack_root, "Wall_Large_6", 0, h - 1)      # W corner (on floor)
	_place(root, pack_root, "Wall_Large_5", w - 1, h - 1)  # S corner (on floor)

	return root

# Iso-correct placement: position.y = the iso ground baseline (matches floor
# center vertically), and the texture is offset upward to draw above it.
static func _place(parent: Node, pack_root: String, piece: String,
		ix: int, iy: int) -> Sprite2D:
	var path := "%s/%s.png" % [pack_root, piece]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		var fs := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path) or FileAccess.file_exists(fs):
			var img := Image.new()
			if img.load(path if FileAccess.file_exists(path) else fs) == OK:
				tex = ImageTexture.create_from_image(img)
	if tex == null:
		return null
	var piece_h := tex.get_height()
	# Iso math matches main.gd grid_to_screen: x=(col-row)*64, y=(col+row)*32.
	# position.y = grid_to_screen.y of this cell; offset pulls the texture
	# up so the floor diamond center sits exactly on that point (same anchor
	# the world's ground tiles use).
	var screen_x: float = (ix - iy) * HALF_W
	# Sub-pixel y nudge based on iso row so SW pieces draw in front of NE
	# pieces at the same screen.y (taller wall/cliff pieces hit this same
	# tiebreak issue, not just floor tiles).
	var screen_y: float = (ix + iy) * HALF_H + float(iy) * 0.001
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.scale = PIECE_SCALE
	s.position = Vector2(screen_x, screen_y)
	# Floor footprint = bottom 64 px of the unscaled texture; we want its
	# diamond center (texture y=32 of footprint) at position.y. Footprint
	# starts at texture y = piece_h - 64, so footprint center = piece_h - 32.
	# Texture top-left in screen = position.y + offset.y, and we want that
	# + (piece_h - 32) to equal position.y → offset.y = -(piece_h - 32).
	s.offset = Vector2(0, -(piece_h - 32))
	parent.add_child(s)
	return s

static func _pick(pool: Array) -> String:
	return String(pool[randi() % pool.size()])
