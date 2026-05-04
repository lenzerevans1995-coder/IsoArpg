extends Node2D
class_name EditorOverlay

# Editor-mode overlay drawn over the paint backdrop:
#   - isometric diamond grid lines (one diamond per cell)
#   - filled highlight diamond on the cell currently under the cursor
#
# The owning editor.gd calls update_view() each frame with the current camera
# focus + hover cell. We redraw lazily via queue_redraw().

const TILE_W := 128
const TILE_H := 64
const TILE_HW := TILE_W * 0.5
const TILE_HH := TILE_H * 0.5

# How many cells to draw around the camera focus. 30 covers a typical 1.5x
# zoomed-out viewport with margin; bump if grid pops in at the edges.
@export var grid_radius: int = 30

const COL_GRID       := Color(0.42, 0.46, 0.52, 0.55)
const COL_GRID_AXIS  := Color(0.62, 0.55, 0.30, 0.85)
const COL_HOVER_FILL := Color(1.0, 0.95, 0.55, 0.30)
const COL_HOVER_EDGE := Color(1.0, 0.95, 0.55, 0.95)
const COL_AREA_FILL  := Color(0.30, 0.95, 1.0, 0.32)
const COL_AREA_EDGE  := Color(0.10, 1.00, 0.95, 1.0)
const AREA_EDGE_W    := 4.0   # thicker outline so the marquee reads at a glance

var _center_world: Vector2 = Vector2.ZERO
var _hover_cell: Vector2i = Vector2i.ZERO
var _hover_visible: bool = false
var _area_rect: Rect2i = Rect2i(0, 0, 0, 0)
var _area_visible: bool = false

func update_view(camera_world: Vector2, hover: Vector2i, hover_show: bool) -> void:
	# Only redraw if anything actually changed — _draw is cheap but we run this
	# every frame from the editor _process.
	var changed := false
	if not _center_world.is_equal_approx(camera_world):
		_center_world = camera_world
		changed = true
	if hover != _hover_cell:
		_hover_cell = hover
		changed = true
	if hover_show != _hover_visible:
		_hover_visible = hover_show
		changed = true
	if changed:
		queue_redraw()

func set_area(rect: Rect2i, show: bool) -> void:
	if rect != _area_rect or show != _area_visible:
		_area_rect = rect
		_area_visible = show
		queue_redraw()

func _diamond(cell: Vector2i) -> PackedVector2Array:
	var cx: float = float(cell.x - cell.y) * TILE_HW
	var cy: float = float(cell.x + cell.y) * TILE_HH
	return PackedVector2Array([
		Vector2(cx, cy - TILE_HH),
		Vector2(cx + TILE_HW, cy),
		Vector2(cx, cy + TILE_HH),
		Vector2(cx - TILE_HW, cy),
	])

func _draw() -> void:
	# Convert camera world position to grid coords (matches main._screen_to_grid).
	var cx: float = (_center_world.x / TILE_HW + _center_world.y / TILE_HH) * 0.5
	var cy: float = (_center_world.y / TILE_HH - _center_world.x / TILE_HW) * 0.5
	var center_cell := Vector2i(int(round(cx)), int(round(cy)))

	# Draw each cell's 4 diamond edges. Adjacent cells share edges, so we
	# get 2x overdraw — fine for ~3,600 cells, no perf concern at this scale.
	for dy in range(-grid_radius, grid_radius + 1):
		for dx in range(-grid_radius, grid_radius + 1):
			var c := Vector2i(center_cell.x + dx, center_cell.y + dy)
			var pts := _diamond(c)
			# Highlight the world-origin axes so it's easy to find (0,0).
			var col := COL_GRID_AXIS if (c.x == 0 or c.y == 0) else COL_GRID
			for i in range(4):
				draw_line(pts[i], pts[(i + 1) % 4], col, 1.0)

	# Area selection: light cyan fill on each cell + a 2-px outline around
	# the rect's full iso silhouette. Drawn under the hover highlight so the
	# cursor cell still pops on top.
	if _area_visible and _area_rect.size.x > 0 and _area_rect.size.y > 0:
		for ay in range(_area_rect.position.y, _area_rect.position.y + _area_rect.size.y):
			for ax in range(_area_rect.position.x, _area_rect.position.x + _area_rect.size.x):
				var c := Vector2i(ax, ay)
				draw_colored_polygon(_diamond(c), COL_AREA_FILL)
		# Outline the iso silhouette by drawing the four extremes of the rect.
		var nw := _diamond(_area_rect.position)
		var ne := _diamond(Vector2i(_area_rect.position.x + _area_rect.size.x - 1, _area_rect.position.y))
		var se := _diamond(Vector2i(_area_rect.position.x + _area_rect.size.x - 1, _area_rect.position.y + _area_rect.size.y - 1))
		var sw := _diamond(Vector2i(_area_rect.position.x, _area_rect.position.y + _area_rect.size.y - 1))
		draw_line(nw[0], ne[1], COL_AREA_EDGE, AREA_EDGE_W)
		draw_line(ne[1], se[2], COL_AREA_EDGE, AREA_EDGE_W)
		draw_line(se[2], sw[3], COL_AREA_EDGE, AREA_EDGE_W)
		draw_line(sw[3], nw[0], COL_AREA_EDGE, AREA_EDGE_W)
	if _hover_visible:
		var hp := _diamond(_hover_cell)
		draw_colored_polygon(hp, COL_HOVER_FILL)
		for i in range(4):
			draw_line(hp[i], hp[(i + 1) % 4], COL_HOVER_EDGE, 2.0)
