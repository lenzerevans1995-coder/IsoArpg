extends Node

# Standalone in-engine paint editor.
#
# The editor lives on its OWN canvas layers, so painted tiles never touch the
# game world:
#   - BackdropLayer (CanvasLayer 5)  : screen-space grey background covering the world.
#   - PaintLayer    (CanvasLayer 10) : world-space (follow_viewport=true) - painted sprites.
#   - UILayer       (CanvasLayer 20) : screen-space - dropdown UI panel.
#
# Toggling the editor on/off shows/hides ALL of these together, so when you
# return to the game the painted tiles are no longer visible.

const FOREST := "res://assets/forest"
const WATER_SHADER := preload("res://water.gdshader")
const FROTH_SHADER := preload("res://ripple_froth.gdshader")

const DUNGEON_CATEGORY := {
	"label": "Dungeon",
	"families": [
		# Floors
		{"name": "Ground A1 (dungeon floor base)", "path": "environment/Ground A1"},
		{"name": "Ground D1 (alt floor)",          "path": "environment/Ground D1"},
		{"name": "Ground E1 (floor top)",          "path": "environment/Ground E1"},
		# Walls
		{"name": "Wall A1 (straight wall)",        "path": "environment/Wall A1"},
		{"name": "Wall A2 (corner wall)",          "path": "environment/Wall A2"},
		# Stone family
		{"name": "Stone A9 (partial wall)",        "path": "environment/Stone A9"},
		{"name": "Stone A10 (corner stone)",       "path": "environment/Stone A10"},
		# Scatter — rocks / minerals
		{"name": "Stone A1 (rock)",                "path": "environment/Stone A1"},
		{"name": "Stone A2 (rock)",                "path": "environment/Stone A2"},
		{"name": "Stone A16 (mineral)",            "path": "environment/Stone A16"},
		{"name": "Stone A21 (mineral)",            "path": "environment/Stone A21"},
		# Misc props
		{"name": "Misc A1 (skele bones)",          "path": "environment/Misc A1"},
		{"name": "Misc A2 (1 pot)",                "path": "environment/Misc A2"},
		{"name": "Misc A3 (3 pot)",                "path": "environment/Misc A3"},
		{"name": "Misc A8 (1 barrel)",             "path": "environment/Misc A8"},
		{"name": "Misc A9 (3 barrels)",            "path": "environment/Misc A9"},
		# Chest
		{"name": "Chest A3 (closed)",              "path": "environment/Chest A3"},
		{"name": "Chest A4 (open)",                "path": "environment/Chest A4"},
		# Trap tile — full-cell spike sprite with a fade-in on placement.
		{"name": "Spikes (trap)",
			"abs_path": "res://assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Environment/spikes_tile.png",
			"no_dirs": true},
	],
}
# Set by main.gd before opening the editor when the player is inside a
# dungeon. Filters _all_categories() down to the Dungeon preset.
var dungeon_mode: bool = false

const CATEGORIES := [
	{
		"label": "Water",
		"families": [
			{"name": "C3 solid",  "path": "ground/water_bed/Ground C3", "is_water": true},
			{"name": "C2 corner", "path": "ground/water_bed/Ground C2", "is_water": true},
			{"name": "C1 edge",   "path": "ground/water_bed/Ground C1", "is_water": true},
		],
	},
	{
		"label": "Edges",
		"families": [
			{"name": "A3 grass corner", "path": "edges/grass_corner/Ground A3"},
			{"name": "A4 grass single", "path": "edges/grass_single/Ground A4"},
		],
	},
	{
		"label": "Path",
		"families": [
			# Body — A1 dirt is what the procedural generator uses for
			# the path centre. Drop these along the trail.
			{"name": "A1 dirt body",        "path": "ground/dirt/Ground A1"},
			# Edge trim where path meets grass — A3 corner + A4 single
			# auto-tile in the procedural pass; here you place them by
			# hand in whichever rotation reads right.
			{"name": "A3 grass corner",     "path": "edges/grass_corner/Ground A3"},
			{"name": "A4 grass single",     "path": "edges/grass_single/Ground A4"},
			# Mud / dirt-path variants (ground/mud_path/Ground I1..I10)
			# for muddier or wagon-rut sections of the trail.
			{"name": "I1 mud rut",          "path": "ground/mud_path/Ground I1"},
			{"name": "I2 mud rut",          "path": "ground/mud_path/Ground I2"},
			{"name": "I3 mud rut",          "path": "ground/mud_path/Ground I3"},
			{"name": "I4 mud rut",          "path": "ground/mud_path/Ground I4"},
			{"name": "I5 mud rut",          "path": "ground/mud_path/Ground I5"},
			{"name": "I6 mud rut",          "path": "ground/mud_path/Ground I6"},
			{"name": "I7 mud rut",          "path": "ground/mud_path/Ground I7"},
			{"name": "I8 mud rut",          "path": "ground/mud_path/Ground I8"},
			{"name": "I9 mud rut",          "path": "ground/mud_path/Ground I9"},
			{"name": "I10 mud rut",         "path": "ground/mud_path/Ground I10"},
		],
	},
	{
		"label": "Ground",
		"families": [
			{"name": "A1 dirt",  "path": "ground/dirt/Ground A1"},
			{"name": "A2 grass", "path": "ground/grass/Ground A2"},
		],
	},
	{
		"label": "Decor",
		"families": [
			{"name": "A6 tuft",     "path": "decor/tufts/Ground A6",    "is_overlay": true},
			{"name": "A22 flower",  "path": "decor/flowers/Ground A22", "is_overlay": true},
			{"name": "B2 tall",     "path": "decor/tall_grass/Flora B2","is_overlay": true},
		],
	},
	{
		"label": "Hills (dirt)",
		"families": [
			{"name": "G1 ridge edge",      "path": "elevation/dirt/Ground G1",  "is_overlay": true},
			{"name": "G2 inside fold",     "path": "elevation/dirt/Ground G2",  "is_overlay": true},
			{"name": "G3 cliff vertical",  "path": "elevation/dirt/Ground G3",  "is_overlay": true},
			{"name": "G4 ridge edge alt",  "path": "elevation/dirt/Ground G4",  "is_overlay": true},
			{"name": "G5 inside fold alt", "path": "elevation/dirt/Ground G5",  "is_overlay": true},
			{"name": "G8 (extra)",         "path": "elevation/dirt/Ground G8",  "is_overlay": true},
			{"name": "G10 (extra)",        "path": "elevation/dirt/Ground G10", "is_overlay": true},
			{"name": "G11 (extra)",        "path": "elevation/dirt/Ground G11", "is_overlay": true},
			{"name": "G16 (extra)",        "path": "elevation/dirt/Ground G16", "is_overlay": true},
			{"name": "G17 (extra)",        "path": "elevation/dirt/Ground G17", "is_overlay": true},
		],
	},
	{
		"label": "Hills (grass)",
		"families": [
			{"name": "G6 ridge grass",    "path": "elevation/grass/Ground G6", "is_overlay": true},
			{"name": "G7 fold grass",     "path": "elevation/grass/Ground G7", "is_overlay": true},
		],
	},
	{
		"label": "Hills (auto)",
		"families": [
			# Single brush that auto-picks G1/G3 + suffix from neighbors. Click
			# cells to paint a hill region; corners and edges resolve themselves.
			{"name": "Hill (auto-fit)", "path": "elevation/dirt/Ground G1", "is_overlay": true, "is_hill_auto": true},
		],
	},
	{
		"label": "Portals",
		"families": [
			{"name": "Portal Idle",
				"path": "res://assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Animations/Props/PortalIdle",
				"is_portal": true},
		],
	},
	{
		"label": "Ripples (animated)",
		"families": [
			{"name": "WR1 small dot",        "path": "decor/water_ripples/Ripple1",  "is_ripple": true},
			{"name": "WR2 NE small",         "path": "decor/water_ripples/Ripple2",  "is_ripple": true},
			{"name": "WR3 NW small",         "path": "decor/water_ripples/Ripple3",  "is_ripple": true},
			{"name": "WR4 NE",               "path": "decor/water_ripples/Ripple4",  "is_ripple": true},
			{"name": "WR5 NW",               "path": "decor/water_ripples/Ripple5",  "is_ripple": true},
			{"name": "WR6 top edge",         "path": "decor/water_ripples/Ripple6",  "is_ripple": true},
			{"name": "WR7 left edge",        "path": "decor/water_ripples/Ripple7",  "is_ripple": true},
			{"name": "WR8 bottom edge",      "path": "decor/water_ripples/Ripple8",  "is_ripple": true},
			{"name": "WR9 right edge",       "path": "decor/water_ripples/Ripple9",  "is_ripple": true},
			{"name": "WR10 NE large",        "path": "decor/water_ripples/Ripple10", "is_ripple": true},
			{"name": "WR11 NW large",        "path": "decor/water_ripples/Ripple11", "is_ripple": true},
			{"name": "WR12 NE diag sweep",   "path": "decor/water_ripples/Ripple12", "is_ripple": true},
			{"name": "WR13 NW diag sweep",   "path": "decor/water_ripples/Ripple13", "is_ripple": true},
		],
	},
]
const SUFFIXES := ["E", "N", "S", "W"]

# Dynamically-scanned families injected into CATEGORIES at runtime so the
# editor picks up every Fantasy Environment piece without us hand-listing them.
const SCAN_ROOTS := [
	{"label": "Environment", "rel": "environment"},
]
var _scanned_categories: Array = []

var main_ref: Node = null
# Per-cell stack of layers, oldest first. Painting always pushes a new layer
# on top instead of replacing - matches how the procedural generator stacks
# dirt (z=-2) + grass (z=-1) + props (z=0).
var painted_base: Dictionary = {}      # Vector2i -> Array of {"tex","is_water","sprite"}
var painted_ripples: Dictionary = {}   # Vector2i -> Array of {"tex","ripple_folder","sprite"}
var brush_tex_path: String = ""
var brush_is_water: bool = false
var brush_is_ripple: bool = false
# Portal / animated prop brush — absolute folder path with frame PNGs.
var brush_is_portal: bool = false
var brush_portal_folder: String = ""
var brush_is_overlay: bool = false   # stacks on top of existing terrain instead of replacing it
var brush_is_hill_auto: bool = false # auto-picks G1/G3 + suffix from neighbor mask
var brush_ripple_folder: String = ""

# Drag-painting state: track which mouse button is currently held and the last
# cell painted so we don't re-process the same cell on every motion event.
var paint_drag_button: int = 0           # 0 = none, MOUSE_BUTTON_LEFT, or MOUSE_BUTTON_RIGHT
var paint_drag_last_cell: Vector2i = Vector2i(99999, 99999)

# Area-select state. Drag with SHIFT held to define a rectangle of cells.
# Once set, F = fill with current brush, X / DELETE = delete paints in area,
# ESC = clear selection. The rect overlay renders on the editor_overlay.
var area_dragging: bool = false
var area_drag_start: Vector2i = Vector2i.ZERO
var area_rect: Rect2i = Rect2i(0, 0, 0, 0)
var area_active: bool = false

# Tool mode: PAINT (left click stamps brush) or SELECT (left drag picks an
# area). Shift+drag also enters area selection in either mode.
enum ToolMode { PAINT, SELECT, PATH }
var tool_mode: int = ToolMode.PAINT

# Tracks cells flagged as part of a hill region by the auto-fit brush.
# Maps cell -> Sprite2D (the current overlay tile). Cells with mask 15 (interior)
# have null sprite — they're flagged as hill but display no overlay.
var hill_cells: Dictionary = {}

var current_category: int = 0
var current_group: int = 0
var current_family: int = 0
var current_variant: int = 0

# Painted layers replace generator output, so they render at the SAME z as
# the equivalent procedural layer (z=-1 for ground/edges, z=2 for ripples).
# Tree-order tiebreak puts the latest-added (painted) sprite on top within
# the same z, and erase_world_cell already cleared whatever was at that cell,
# so this also blends visually with adjacent procedural tiles instead of
# floating above the world.
const PAINT_BASE_Z := -1
const PAINT_RIPPLE_Z := 2

# Pan state (middle-mouse drag).
var panning: bool = false
var pan_last_mouse: Vector2 = Vector2.ZERO

# Hover overlay for grid + cursor highlight; lives under PaintLayer so it
# follows the camera transform.
const EDITOR_OVERLAY_SCRIPT := preload("res://editor_overlay.gd")
var overlay: Node2D = null
var hover_cell: Vector2i = Vector2i.ZERO
var hover_visible: bool = false
# Ghost preview that follows the cursor while painting.
var ghost_sprite: Sprite2D = null
@export var dim_world_alpha: float = 0.45    # how much to dim non-painted world while editor is open
@export var ghost_alpha: float = 0.7         # transparency of the ghost preview tile

# Layer the brush operates on. Painting only touches sprites on the same
# layer; other layers stay untouched even when you click on top of them.
const LAYERS := ["ground", "overlay", "props"]
var current_layer: String = "ground"
# Numeric paint layer (1=back, 6=front). Painted sprites store their layer
# so render order, save/load, and the "visible pixel wins" wall test can
# all use it as the top-priority sort key.
var current_paint_layer: int = 1
const MAX_PAINT_LAYERS := 6
# z-offset applied to the next placement, adjusted with the two side mouse
# buttons (XBUTTON1 = down, XBUTTON2 = up). Lets you slip a tile UNDER or
# ABOVE existing tiles at the same cell without painting/erasing them.
var z_offset: int = 0
# Vertical pixel lift applied to the next placement. Lets you stack on top of
# a tall cliff tile (e.g. G22) at the correct height instead of at ground
# level. Adjusted with [ / ] in steps of LIFT_STEP. Resets to 0 with \.
var y_lift: int = 0
const LIFT_STEP := 64

@onready var backdrop_layer: CanvasLayer = $BackdropLayer
@onready var paint_layer: CanvasLayer = $PaintLayer
@onready var paint_root: Node2D = $PaintLayer/PaintRoot
@onready var ui_layer: CanvasLayer = $UILayer
@onready var panel: Panel = $UILayer/Panel
@onready var category_dd: OptionButton = $UILayer/Panel/Scroll/VBox/CategoryDropdown
@onready var group_dd: OptionButton = $UILayer/Panel/Scroll/VBox/GroupDropdown
@onready var family_dd: OptionButton = $UILayer/Panel/Scroll/VBox/FamilyDropdown
@onready var variant_dd: OptionButton = $UILayer/Panel/Scroll/VBox/VariantDropdown
@onready var l1_paint_btn: Button = $UILayer/Panel/Scroll/VBox/LayerRow/L1Btn
@onready var l2_paint_btn: Button = $UILayer/Panel/Scroll/VBox/LayerRow/L2Btn
@onready var l3_paint_btn: Button = $UILayer/Panel/Scroll/VBox/LayerRow/L3Btn
@onready var l4_paint_btn: Button = $UILayer/Panel/Scroll/VBox/LayerRow/L4Btn
@onready var l5_paint_btn: Button = $UILayer/Panel/Scroll/VBox/LayerRow/L5Btn
@onready var l6_paint_btn: Button = $UILayer/Panel/Scroll/VBox/LayerRow/L6Btn
@onready var paint_mode_btn: Button = $UILayer/Panel/Scroll/VBox/ModeRow/PaintModeBtn
@onready var select_mode_btn: Button = $UILayer/Panel/Scroll/VBox/ModeRow/SelectModeBtn
var _path_mode_btn: Button = null
@onready var fill_btn: Button = $UILayer/Panel/Scroll/VBox/ToolbarRow1/FillBtn
@onready var delete_btn: Button = $UILayer/Panel/Scroll/VBox/ToolbarRow1/DeleteBtn
@onready var clear_sel_btn: Button = $UILayer/Panel/Scroll/VBox/ToolbarRow1/ClearSelBtn
@onready var l0_btn: Button = $UILayer/Panel/Scroll/VBox/LiftRow/L0Btn
@onready var l1_btn: Button = $UILayer/Panel/Scroll/VBox/LiftRow/L1Btn
@onready var l2_btn: Button = $UILayer/Panel/Scroll/VBox/LiftRow/L2Btn
@onready var mark_floor_btn: Button = $UILayer/Panel/Scroll/VBox/RulesRow1/MarkFloorBtn
@onready var mark_slope_btn: Button = $UILayer/Panel/Scroll/VBox/RulesRow1/MarkSlopeBtn
@onready var mark_block_btn: Button = $UILayer/Panel/Scroll/VBox/RulesRow1/MarkBlockBtn
@onready var clear_rules_btn: Button = $UILayer/Panel/Scroll/VBox/RulesRow2/ClearRulesBtn
@onready var s1_btn: Button = $UILayer/Panel/Scroll/VBox/StairsRow/S1Btn
@onready var s2_btn: Button = $UILayer/Panel/Scroll/VBox/StairsRow/S2Btn
@onready var s3_btn: Button = $UILayer/Panel/Scroll/VBox/StairsRow/S3Btn
@onready var s4_btn: Button = $UILayer/Panel/Scroll/VBox/StairsRow/S4Btn
@onready var s5_btn: Button = $UILayer/Panel/Scroll/VBox/StairsRow2/S5Btn
@onready var s6_btn: Button = $UILayer/Panel/Scroll/VBox/StairsRow2/S6Btn
@onready var s7_btn: Button = $UILayer/Panel/Scroll/VBox/StairsRow2/S7Btn
@onready var s8_btn: Button = $UILayer/Panel/Scroll/VBox/StairsRow2/S8Btn
@onready var custom_step_spin: SpinBox = $UILayer/Panel/Scroll/VBox/CustomStepRow/CustomStepSpin
@onready var custom_step_btn: Button = $UILayer/Panel/Scroll/VBox/CustomStepRow/CustomStepBtn

# Each stair step is 32 px tall (4 steps cover one HILL_LIFT storey of 64 px,
# 4 cover one storey-2 plateau of 128 — set per use). Click a step button
# with an area selected to stamp every cell in that area at that step's
# height. Build a staircase by selecting one row of cells, S1; selecting
# the next row up, S2; etc.
const STAIR_RISE := 32
@onready var preview: TextureRect = $UILayer/Panel/Scroll/VBox/PreviewBox/PreviewMargin/Preview
@onready var status_label: Label = $UILayer/Panel/Scroll/VBox/StatusLabel

var _active: bool = false
var _reparented_to_world: bool = false
# Auto-save: re-writes user://arena.json every AUTO_SAVE_INTERVAL seconds
# whenever the editor is active and there have been new paints since the
# last save. The file also seeds the world when BATTLE_WORLD is on.
const ARENA_PATH := "user://arena.json"
const AUTO_SAVE_INTERVAL := 60.0
var _auto_save_timer: float = 0.0
var _dirty_since_save: bool = true
# Auto-loads the latest draft the first time the editor opens this session, so
# work survives across game restarts without having to remember to press F.
var _auto_loaded_draft: bool = false

func _ready() -> void:
	_set_visible(false)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scan_extra_categories()
	_init_dropdowns()
	_refresh_brush()
	# Grid + hover overlay lives on PaintLayer (CanvasLayer 10) so it renders
	# ABOVE every world tile. paint_root was reparented to main.world for
	# pixel-perfect scale on painted tiles — we deliberately don't put the
	# overlay there or it'd sit behind procedural sprites.
	# Toolbar wiring — buttons mirror the keyboard shortcuts so the rules can
	# be applied without having to remember the keybinds.
	l1_paint_btn.pressed.connect(func(): _set_paint_layer(1))
	l2_paint_btn.pressed.connect(func(): _set_paint_layer(2))
	l3_paint_btn.pressed.connect(func(): _set_paint_layer(3))
	l4_paint_btn.pressed.connect(func(): _set_paint_layer(4))
	l5_paint_btn.pressed.connect(func(): _set_paint_layer(5))
	l6_paint_btn.pressed.connect(func(): _set_paint_layer(6))
	paint_mode_btn.pressed.connect(func(): _set_tool_mode(ToolMode.PAINT))
	select_mode_btn.pressed.connect(func(): _set_tool_mode(ToolMode.SELECT))
	# Add a PATH-mode button alongside Paint / Select. Click & drag in
	# PATH mode stamps procedural-style path cells with auto-edges.
	if paint_mode_btn and paint_mode_btn.get_parent():
		var pb := Button.new()
		pb.text = "Path"
		pb.toggle_mode = true
		pb.pressed.connect(func(): _set_tool_mode(ToolMode.PATH))
		paint_mode_btn.get_parent().add_child(pb)
		_path_mode_btn = pb
	fill_btn.pressed.connect(_area_fill)
	delete_btn.pressed.connect(_area_delete)
	clear_sel_btn.pressed.connect(_area_clear_selection)
	l0_btn.pressed.connect(func(): _set_lift_preset(0))
	l1_btn.pressed.connect(func(): _set_lift_preset(1))
	l2_btn.pressed.connect(func(): _set_lift_preset(2))
	mark_floor_btn.pressed.connect(_area_mark_floor)
	mark_slope_btn.pressed.connect(_area_mark_slope)
	mark_block_btn.pressed.connect(_area_mark_block)
	clear_rules_btn.pressed.connect(_area_clear_rules)
	s1_btn.pressed.connect(func(): _area_mark_step(1))
	s2_btn.pressed.connect(func(): _area_mark_step(2))
	s3_btn.pressed.connect(func(): _area_mark_step(3))
	s4_btn.pressed.connect(func(): _area_mark_step(4))
	s5_btn.pressed.connect(func(): _area_mark_step(5))
	s6_btn.pressed.connect(func(): _area_mark_step(6))
	s7_btn.pressed.connect(func(): _area_mark_step(7))
	s8_btn.pressed.connect(func(): _area_mark_step(8))
	custom_step_btn.pressed.connect(func(): _area_mark_step(int(custom_step_spin.value)))
	overlay = EDITOR_OVERLAY_SCRIPT.new()
	overlay.name = "EditorOverlay"
	paint_layer.add_child(overlay)
	# Ghost preview sprite — follows the hovered cell, shows the current brush
	# texture at editor-display alpha. Lives on the paint_layer (above world)
	# so it doesn't get caught by the world-dim modulate.
	ghost_sprite = Sprite2D.new()
	ghost_sprite.centered = true
	ghost_sprite.modulate = Color(1, 1, 1, ghost_alpha)
	ghost_sprite.visible = false
	ghost_sprite.z_index = 100
	paint_layer.add_child(ghost_sprite)

func _notification(what: int) -> void:
	# Save on game quit / window close so the player's last walked position
	# isn't lost between auto-save ticks.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		var arena_active: bool = main_ref != null and "BATTLE_WORLD" in main_ref and main_ref.BATTLE_WORLD
		if arena_active:
			_save_arena()

func _ensure_paint_root_on_world() -> void:
	# Move paint_root from PaintLayer onto main.world so painted tiles use the
	# IDENTICAL canvas transform as procedurally generated tiles. Otherwise the
	# CanvasLayer.follow_viewport pipeline introduces sub-pixel scaling drift,
	# so painted tiles read slightly larger / misaligned next to world tiles.
	if _reparented_to_world:
		return
	if main_ref == null or main_ref.world == null:
		return
	var prev_parent := paint_root.get_parent()
	if prev_parent:
		prev_parent.remove_child(paint_root)
	main_ref.world.add_child(paint_root)
	_reparented_to_world = true

const TILE_RULES := preload("res://tile_rules.gd")

# Ask main.gd to register the rules-derived behaviour for a freshly painted
# (or freshly removed) tile so player physics + collision honour it.
func _apply_rules_for_paint(cell: Vector2i, tex_path: String, added: bool) -> void:
	if main_ref == null or tex_path == "":
		return
	var role: int = TILE_RULES.role_for_path(tex_path)
	if main_ref.has_method("set_tile_role"):
		main_ref.set_tile_role(cell, role, added)
	_dirty_since_save = added or _dirty_since_save

func _process(_delta: float) -> void:
	# Auto-save runs even when the editor isn't open, so player position
	# (and any rule changes) keep persisting while you're walking around
	# the arena.
	_auto_save_timer += _delta
	if _auto_save_timer >= AUTO_SAVE_INTERVAL:
		_auto_save_timer = 0.0
		var arena_active: bool = main_ref != null and "BATTLE_WORLD" in main_ref and main_ref.BATTLE_WORLD
		if arena_active:
			_save_arena()
	if not _active:
		return
	_ensure_paint_root_on_world()
	# Drive grid + hover redraw from the camera focus and current mouse cell.
	if main_ref == null or main_ref.player == null or overlay == null:
		return
	var cam: Camera2D = main_ref.player.get_node_or_null("Camera2D")
	var cam_world: Vector2 = cam.get_screen_center_position() if cam else main_ref.player.position
	var over_panel := _is_pointer_over_panel()
	if not over_panel:
		var world_pos: Vector2 = main_ref.player.get_global_mouse_position()
		hover_cell = _screen_to_grid_diamond(world_pos)
		hover_visible = true
	else:
		hover_visible = false
	overlay.update_view(cam_world, hover_cell, hover_visible)
	# Refresh status every frame so the hover cell + player cell read-out
	# tracks the mouse and player movement live (HUD is hidden in editor mode).
	_update_status()
	# Auto-save the arena draft so the bounded test world survives a crash
	# or restart without manually pressing S.
	_auto_save_timer += _delta
	if _auto_save_timer >= AUTO_SAVE_INTERVAL:
		_auto_save_timer = 0.0
		# Always save on the interval — even if no paints happened the
		# player position likely changed, and a no-op rewrite is cheap.
		_save_arena()
	# Ghost preview follows the hovered iso cell.
	if ghost_sprite:
		ghost_sprite.visible = hover_visible and ghost_sprite.texture != null
		if hover_visible and main_ref:
			ghost_sprite.position = main_ref.grid_to_screen(hover_cell)
			ghost_sprite.offset = Vector2(0, main_ref.SPRITE_Y_OFFSET - y_lift)

# Iso point-in-diamond cell pick. main._screen_to_grid uses floor() which is
# only correct for points exactly at a diamond center; for arbitrary cursor
# positions we want the diamond that VISUALLY contains the cursor, which is
# the round() form (a point inside cell (gx,gy)'s diamond satisfies
# |dgx| < 0.5 AND |dgy| < 0.5 in continuous grid coords).
func _screen_to_grid_diamond(p: Vector2) -> Vector2i:
	var tw: float = main_ref.TILE_W * 0.5
	var th: float = main_ref.TILE_H * 0.5
	var gx: float = (p.x / tw + p.y / th) * 0.5
	var gy: float = (p.y / th - p.x / tw) * 0.5
	return Vector2i(int(round(gx)), int(round(gy)))

func toggle() -> void:
	_active = not _active
	_set_visible(_active)
	# Hide all generator-spawned trees / bushes / shadows while editor is open
	# so the underlying ground is visible for painting tests.
	if main_ref and main_ref.has_method("set_props_visible"):
		main_ref.set_props_visible(not _active)
	# Also hide live characters (player + goblins + spiders + bosses) so
	# the underlying ground reads cleanly while painting. Visibility is
	# the only thing toggled — they keep ticking under the hood.
	if main_ref:
		if "player" in main_ref and is_instance_valid(main_ref.player):
			(main_ref.player as Node2D).visible = not _active
		for grp in ["goblin", "spider", "boss_monster"]:
			for n in main_ref.get_tree().get_nodes_in_group(grp):
				if n is CanvasItem:
					(n as CanvasItem).visible = not _active
	# First time we open the editor in a session, restore the appropriate save:
	#   - BATTLE_WORLD: load the persistent arena.json so iterative work on
	#     the test arena survives across runs.
	#   - infinite world: load the latest draft_N.json (legacy path).
	var arena_active: bool = main_ref != null and "BATTLE_WORLD" in main_ref and main_ref.BATTLE_WORLD
	if _active and not _auto_loaded_draft:
		_auto_loaded_draft = true
		if arena_active:
			_load_arena()
		else:
			_load_latest_draft()
	_update_status()

func is_active() -> bool:
	return _active

func _set_visible(v: bool) -> void:
	# Backdrop is permanently hidden — the editor overlays the live world.
	# Painted tiles live under main.world as siblings of the generator sprites,
	# so they stay visible whether the editor is open or not. Only the grid /
	# hover overlay and the side-panel UI toggle with editor state.
	backdrop_layer.visible = false
	paint_layer.visible = true
	if overlay:
		overlay.visible = v
	ui_layer.visible = v
	# Dim the world while editing so the brush ghost reads clearly against
	# existing tiles. Restored when the editor closes.
	if main_ref and main_ref.world:
		main_ref.world.modulate = Color(1, 1, 1, dim_world_alpha) if v else Color(1, 1, 1, 1)
	# Hide the gameplay HUD (HP / MP / wave info / mode label) while the editor
	# is open — it covers the cells you're trying to paint and there's nothing
	# combat-relevant going on while you're editing.
	if main_ref:
		var game_hud := main_ref.get_node_or_null("HUD")
		if game_hud:
			game_hud.visible = not v
		if "combat_hud" in main_ref and main_ref.combat_hud:
			main_ref.combat_hud.visible = not v
	if ghost_sprite:
		ghost_sprite.visible = v and ghost_sprite.texture != null

# -------------------------------------------------------------- Dropdowns ---

func _scan_extra_categories() -> void:
	# Walk every SCAN_ROOTS folder and build a hierarchical structure:
	#   Category (first word, e.g. "Ground")
	#     └─ Group  (letter prefix of the family code, e.g. "G")
	#          └─ Family (the number, shown as "22" for "Ground G22")
	#               └─ Variant (N/S/E/W from filename suffix)
	# Files without a "<word> <letter><number>" pattern fall back to a single
	# "—" group with the bare stem as family name (e.g. FirePlace.png).
	_scanned_categories.clear()
	for root in SCAN_ROOTS:
		var rel: String = root.rel
		var folder := "%s/%s" % [FOREST, rel]
		var d := DirAccess.open(folder)
		if d == null:
			continue
		# cat -> letter -> family_name -> family_dict
		var by_cat: Dictionary = {}
		d.list_dir_begin()
		var fn: String = d.get_next()
		while fn != "":
			if not d.current_is_dir() and fn.ends_with(".png"):
				var stem := fn.get_basename()
				var family_name := stem
				var has_dir := false
				if stem.length() > 2:
					var tail := stem.substr(stem.length() - 2, 2)
					if tail == "_N" or tail == "_S" or tail == "_E" or tail == "_W":
						family_name = stem.substr(0, stem.length() - 2)
						has_dir = true
				var parts := family_name.split(" ")
				var cat_key: String = parts[0]
				var letter: String = "—"
				var fam_label: String = family_name
				# Special case: "Shadow1", "Shadow2"… have the number glued
				# to the first word, so without help they'd each become their
				# own category. Split the digit suffix off so they all land
				# under one "Shadow" category, with the number as the family.
				if cat_key.begins_with("Shadow") and cat_key.length() > 6:
					var rest := cat_key.substr(6)
					if rest.length() > 0 and rest[0] >= "0" and rest[0] <= "9":
						cat_key = "Shadow"
						fam_label = rest
						letter = "—"
				elif parts.size() >= 2 and parts[1].length() > 0:
					letter = parts[1].substr(0, 1)
					# Strip the redundant cat+letter prefix from fam_label so
					# the dropdown shows just "22" for "Ground G22".
					fam_label = parts[1].substr(1)
					if fam_label == "":
						fam_label = parts[1]
				if not by_cat.has(cat_key):
					by_cat[cat_key] = {}
				if not by_cat[cat_key].has(letter):
					by_cat[cat_key][letter] = {}
				by_cat[cat_key][letter][family_name] = {
					"name": fam_label,
					"path": "%s/%s" % [rel, family_name],
					"is_overlay": true,
					"no_dirs": not has_dir,
				}
			fn = d.get_next()
		d.list_dir_end()
		var cat_keys := by_cat.keys()
		cat_keys.sort()
		for ck in cat_keys:
			var letters: Dictionary = by_cat[ck]
			var letter_keys: Array = letters.keys()
			letter_keys.sort()
			var groups_arr: Array = []
			for lk in letter_keys:
				var fams_dict: Dictionary = letters[lk]
				var fam_keys: Array = fams_dict.keys()
				fam_keys.sort_custom(_natural_compare)
				var fams: Array = []
				for fk in fam_keys:
					fams.append(fams_dict[fk])
				groups_arr.append({"label": lk, "families": fams})
			_scanned_categories.append({
				"label": ck,
				"groups": groups_arr,
			})

# Natural-order compare so "Ground G2" precedes "Ground G10" instead of the
# default lexicographic order putting G10 right after G1. Splits each string
# into runs of digits / non-digits and compares run-by-run with numeric
# comparison on digit runs.
func _natural_compare(a: String, b: String) -> bool:
	var ia := 0
	var ib := 0
	while ia < a.length() and ib < b.length():
		var ca := a[ia]
		var cb := b[ib]
		var a_digit := ca >= "0" and ca <= "9"
		var b_digit := cb >= "0" and cb <= "9"
		if a_digit and b_digit:
			var ja := ia
			while ja < a.length() and a[ja] >= "0" and a[ja] <= "9":
				ja += 1
			var jb := ib
			while jb < b.length() and b[jb] >= "0" and b[jb] <= "9":
				jb += 1
			var na := int(a.substr(ia, ja - ia))
			var nb := int(b.substr(ib, jb - ib))
			if na != nb:
				return na < nb
			ia = ja
			ib = jb
		else:
			if ca != cb:
				return ca < cb
			ia += 1
			ib += 1
	return a.length() < b.length()

# Returns the right parent Node2D for newly-painted sprites. Inside a
# dungeon paints land on main.dungeon (the visible world during dungeon
# mode); otherwise they go on main.world like before.
func _paint_parent() -> Node:
	if main_ref == null:
		return null
	if "in_dungeon" in main_ref and main_ref.in_dungeon \
			and "dungeon" in main_ref and main_ref.dungeon:
		return main_ref.dungeon
	return main_ref.world

func _all_categories() -> Array:
	# In dungeon mode the user only wants the dungeon-relevant tiles, no
	# forest categories. Return the single Dungeon preset.
	if dungeon_mode:
		return [DUNGEON_CATEGORY]
	# CATEGORIES is hand-curated (water/edges/ground/decor/hills/ripples).
	# _scanned_categories is auto-generated from the Fantasy Environment folder
	# at startup so every chest/door/flora/wall/etc. is paint-able without us
	# hand-listing it. Concatenated each call so swaps to either side update.
	var out: Array = []
	for c in CATEGORIES:
		out.append(c)
	for c in _scanned_categories:
		out.append(c)
	return out

# Returns the category at idx in a normalized form: always has a "groups"
# array even for the hand-curated CATEGORIES (which have a flat "families"
# field — those get wrapped in a single anonymous group).
func _norm_category(idx: int) -> Dictionary:
	var raw: Dictionary = _all_categories()[idx]
	if raw.has("groups"):
		return raw
	return {"label": raw.label, "groups": [{"label": "—", "families": raw.families}]}

func _init_dropdowns() -> void:
	category_dd.clear()
	# Only show categories whose label fits the current paint layer.
	for cat in _all_categories():
		if _category_fits_layer(String(cat.label), current_paint_layer):
			category_dd.add_item(cat.label)
	if category_dd.get_item_count() == 0:
		# Fallback: empty layer filter — show everything so the user isn't
		# stuck with no options.
		for cat in _all_categories():
			category_dd.add_item(cat.label)
	if not category_dd.item_selected.is_connected(_on_category_selected):
		category_dd.item_selected.connect(_on_category_selected)
	group_dd.item_selected.connect(_on_group_selected)
	family_dd.item_selected.connect(_on_family_selected)
	variant_dd.item_selected.connect(_on_variant_selected)
	_on_category_selected(0)

func _on_category_selected(idx: int) -> void:
	# Translate the dropdown's visible-item index into the full category
	# list index, since the layer filter hides some entries.
	var visible_count: int = -1
	var all_idx: int = 0
	for i in range(_all_categories().size()):
		if _category_fits_layer(String(_all_categories()[i].label), current_paint_layer):
			visible_count += 1
			if visible_count == idx:
				all_idx = i
				break
	idx = all_idx
	current_category = idx
	current_group = 0
	var cat := _norm_category(idx)
	group_dd.clear()
	for grp in cat.groups:
		group_dd.add_item(grp.label)
	# Hide the Letter dropdown if there's only the synthetic "—" group, so the
	# hand-curated categories (Water/Edges/Hills/etc.) don't show a useless row.
	var single: bool = cat.groups.size() <= 1
	group_dd.visible = not single
	var grp_label_node := $UILayer/Panel/Scroll/VBox/GroupLabel
	if grp_label_node:
		grp_label_node.visible = not single
	_on_group_selected(0)

func _on_group_selected(idx: int) -> void:
	current_group = idx
	current_family = 0
	var cat := _norm_category(current_category)
	family_dd.clear()
	for fam in cat.groups[idx].families:
		family_dd.add_item(fam.name)
	_on_family_selected(0)

func _on_family_selected(idx: int) -> void:
	current_family = idx
	current_variant = 0
	variant_dd.clear()
	for s in SUFFIXES:
		variant_dd.add_item(s)
	_on_variant_selected(0)

func _on_variant_selected(idx: int) -> void:
	current_variant = idx
	_refresh_brush()

func _refresh_brush() -> void:
	var cat := _norm_category(current_category)
	var fam: Dictionary = cat.groups[current_group].families[current_family]
	brush_is_water = bool(fam.get("is_water", false))
	brush_is_ripple = bool(fam.get("is_ripple", false))
	brush_is_portal = bool(fam.get("is_portal", false))
	brush_is_overlay = bool(fam.get("is_overlay", false))
	brush_is_hill_auto = bool(fam.get("is_hill_auto", false))
	var no_dirs: bool = bool(fam.get("no_dirs", false))
	if brush_is_portal:
		# Portal / animated-prop brush: family.path is an absolute folder.
		# Preview shows the first frame, in-world paint plays the loop.
		brush_portal_folder = String(fam.path)
		brush_tex_path = brush_portal_folder + "/0001.png"
		brush_ripple_folder = ""
		variant_dd.disabled = true
	elif brush_is_ripple:
		brush_ripple_folder = fam.path
		brush_tex_path = "%s/%s/0001.png" % [FOREST, fam.path]
		variant_dd.disabled = true
	elif no_dirs:
		# Pieces without N/S/E/W variants. `abs_path` is for tiles
		# outside the forest tree (e.g. spikes_tile in the Fantasy
		# tileset Environment folder); `path` is relative to FOREST.
		brush_ripple_folder = ""
		if fam.has("abs_path"):
			brush_tex_path = String(fam.abs_path)
		else:
			brush_tex_path = "%s/%s.png" % [FOREST, fam.path]
		variant_dd.disabled = true
	else:
		brush_ripple_folder = ""
		brush_tex_path = "%s/%s_%s.png" % [FOREST, fam.path, SUFFIXES[current_variant]]
		variant_dd.disabled = false
	var tex: Texture2D = load(brush_tex_path)
	if preview:
		preview.texture = tex
	if ghost_sprite:
		ghost_sprite.texture = tex
		ghost_sprite.modulate = Color(1, 1, 1, ghost_alpha)
	_update_status()

func _load_ripple_frames(folder_rel: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var folder := "%s/%s" % [FOREST, folder_rel]
	var d := DirAccess.open(folder)
	if d == null:
		return frames
	var names: Array = []
	d.list_dir_begin()
	var fn: String = d.get_next()
	while fn != "":
		if not d.current_is_dir() and fn.ends_with(".png"):
			names.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	names.sort()
	for n in names:
		var t: Texture2D = load("%s/%s" % [folder, n])
		if t != null:
			frames.append(t)
	return frames

# Cache of ripple-centroid offsets per folder so we only scan each animation once.
var _ripple_offset_cache: Dictionary = {}

func _ripple_centroid_offset(folder_rel: String, first_frame: Texture2D) -> Vector2:
	# Returns an extra offset (beyond the standard pivot) that shifts the
	# ripple so its art's CENTROID lands on the cell pivot - i.e. the ripple
	# appears centered on the clicked cell instead of skewed to one quadrant.
	if _ripple_offset_cache.has(folder_rel):
		return _ripple_offset_cache[folder_rel]
	var img: Image = first_frame.get_image()
	if img == null:
		_ripple_offset_cache[folder_rel] = Vector2.ZERO
		return Vector2.ZERO
	var w := img.get_width()
	var h := img.get_height()
	var cx: float = 0.0
	var cy: float = 0.0
	var n: int = 0
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.1:
				cx += float(x)
				cy += float(y)
				n += 1
	var off := Vector2.ZERO
	if n > 0:
		var centroid := Vector2(cx / float(n), cy / float(n))
		var canvas_center := Vector2(float(w) * 0.5, float(h) * 0.5)
		off = canvas_center - centroid
	_ripple_offset_cache[folder_rel] = off
	return off

# -------------------------------------------------------------- Painting ---

func _input(event: InputEvent) -> void:
	if not _active:
		return
	# Middle-mouse-button drag panning. Tracks mouse delta and shifts the
	# player position (the camera is parented to the player) so the view pans.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			pan_last_mouse = event.position
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and panning and main_ref and main_ref.player:
		var delta: Vector2 = event.position - pan_last_mouse
		pan_last_mouse = event.position
		var cam: Camera2D = main_ref.player.get_node_or_null("Camera2D")
		var zoom_v: Vector2 = cam.zoom if cam else Vector2(1, 1)
		# Drag direction matches view: dragging the cursor right pulls the
		# world right, i.e. the camera moves left, i.e. the player moves left.
		main_ref.player.position -= delta / zoom_v
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		# Release of left button ends an area-drag (selection persists for
		# fill / delete / escape).
		if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and area_dragging:
			area_dragging = false
			_update_status()
			return
		# Release of any held button ends drag-paint mode.
		if not event.pressed and event.button_index == paint_drag_button:
			paint_drag_button = 0
			paint_drag_last_cell = Vector2i(99999, 99999)
			return
		if event.pressed:
			if _is_pointer_over_panel():
				return
			# Let scroll-wheel zoom fall through to the player's _unhandled_input.
			if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				return
			if main_ref == null:
				return
			var world_pos: Vector2 = main_ref.player.get_global_mouse_position() if main_ref.player else Vector2.ZERO
			var cell: Vector2i = _screen_to_grid_diamond(world_pos)
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					# SELECT mode OR Shift held → drag selects an area.
					# PATH mode → click & drag stamps procedural path tiles.
					# PAINT mode (default) → drag paints the brush.
					if tool_mode == ToolMode.SELECT or event.shift_pressed:
						area_dragging = true
						area_drag_start = cell
						area_rect = Rect2i(cell, Vector2i(1, 1))
						area_active = true
						_refresh_area_overlay()
						get_viewport().set_input_as_handled()
						return
					if tool_mode == ToolMode.PATH:
						if main_ref and main_ref.has_method("paint_path_at"):
							main_ref.paint_path_at(cell)
						paint_drag_button = MOUSE_BUTTON_LEFT
						paint_drag_last_cell = cell
						get_viewport().set_input_as_handled()
						return
					_paint_cell(cell)
					paint_drag_button = MOUSE_BUTTON_LEFT
					paint_drag_last_cell = cell
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_RIGHT:
					_erase_cell(cell)
					paint_drag_button = MOUSE_BUTTON_RIGHT
					paint_drag_last_cell = cell
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_XBUTTON1:
					# Side button (back) → push next paint DOWN in z-order, OR
					# pull the topmost existing paint at this cell down by one.
					_shift_z(cell, -1)
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_XBUTTON2:
					# Side button (forward) → push next paint UP in z-order.
					_shift_z(cell, +1)
					get_viewport().set_input_as_handled()
	# Drag-paint: if a paint button is held and the cursor enters a new cell,
	# paint/erase that new cell too.
	if event is InputEventMouseMotion and area_dragging and not panning:
		if _is_pointer_over_panel() or main_ref == null:
			return
		var world_pos_a: Vector2 = main_ref.player.get_global_mouse_position()
		var cell_a: Vector2i = _screen_to_grid_diamond(world_pos_a)
		var lo := Vector2i(min(area_drag_start.x, cell_a.x), min(area_drag_start.y, cell_a.y))
		var hi := Vector2i(max(area_drag_start.x, cell_a.x), max(area_drag_start.y, cell_a.y))
		area_rect = Rect2i(lo, hi - lo + Vector2i(1, 1))
		_refresh_area_overlay()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and paint_drag_button != 0 and not panning:
		if _is_pointer_over_panel() or main_ref == null:
			return
		var world_pos2: Vector2 = main_ref.player.get_global_mouse_position()
		var cell2: Vector2i = _screen_to_grid_diamond(world_pos2)
		if cell2 != paint_drag_last_cell:
			paint_drag_last_cell = cell2
			if paint_drag_button == MOUSE_BUTTON_LEFT:
				if tool_mode == ToolMode.PATH:
					if main_ref and main_ref.has_method("paint_path_at"):
						main_ref.paint_path_at(cell2)
				else:
					_paint_cell(cell2)
			elif paint_drag_button == MOUSE_BUTTON_RIGHT:
				_erase_cell(cell2)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_S:
				# Inside a dungeon S saves the dungeon layout to
				# draft_Dungeon.json (not a numbered draft_N.json).
				if main_ref and "in_dungeon" in main_ref and main_ref.in_dungeon \
						and "dungeon" in main_ref and main_ref.dungeon \
						and main_ref.dungeon.has_method("save_draft"):
					main_ref.dungeon.save_draft()
					print("[dungeon] saved to ", main_ref.dungeon.DRAFT_PATH)
				else:
					_save_draft()
				get_viewport().set_input_as_handled()
			KEY_C:
				_clear_painted()
				get_viewport().set_input_as_handled()
			KEY_F:
				_load_latest_draft()
				get_viewport().set_input_as_handled()
			KEY_BRACKETLEFT:
				# [ → drop next placement by one storey (matches HILL_LIFT step).
				y_lift = max(y_lift - LIFT_STEP, -1024)
				_update_status()
				get_viewport().set_input_as_handled()
			KEY_BRACKETRIGHT:
				# ] → raise next placement by one storey, so a tile lands flush
				# on top of a tall cliff piece like G22 instead of at ground.
				y_lift = min(y_lift + LIFT_STEP, 1024)
				_update_status()
				get_viewport().set_input_as_handled()
			KEY_BACKSLASH:
				# \ resets the lift to 0 (back to ground level).
				y_lift = 0
				_update_status()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				# ENTER → fill the selected area with the current brush.
				if area_active:
					_area_fill()
					get_viewport().set_input_as_handled()
			KEY_DELETE, KEY_X:
				# DELETE / X → clear all paints in the selected area.
				if area_active:
					_area_delete()
					get_viewport().set_input_as_handled()
			KEY_L:
				# L → tag every cell in the selection with the current lift
				# value as a *terrain rule* (no new sprite). Player walks on
				# top of the area at that elevation. Useful for marking a
				# painted A1 region as a "floor at storey 2" without painting
				# new sprites just to register the height.
				if area_active and main_ref and main_ref.has_method("set_tile_paint_lift"):
					for cy in range(area_rect.position.y, area_rect.position.y + area_rect.size.y):
						for cx in range(area_rect.position.x, area_rect.position.x + area_rect.size.x):
							main_ref.set_tile_paint_lift(Vector2i(cx, cy), y_lift, true)
					_dirty_since_save = true
					_update_status()
					get_viewport().set_input_as_handled()
			KEY_K:
				# K → clear every rule (storey / paint_lift / blocking) in
				# the selected area. The painted sprites stay; only the
				# terrain semantics reset to flat ground.
				if area_active and main_ref:
					for cy in range(area_rect.position.y, area_rect.position.y + area_rect.size.y):
						for cx in range(area_rect.position.x, area_rect.position.x + area_rect.size.x):
							var c := Vector2i(cx, cy)
							main_ref.tile_storey.erase(c)
							main_ref.tile_paint_lift.erase(c)
							main_ref.tile_blocked.erase(c)
							main_ref.blocked.erase(c)
					_dirty_since_save = true
					_update_status()
					get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				# ESC → drop the area selection.
				if area_active:
					area_active = false
					area_dragging = false
					_refresh_area_overlay()
					_update_status()
					get_viewport().set_input_as_handled()

func _is_pointer_over_panel() -> bool:
	if panel == null or not panel.visible:
		return false
	return panel.get_global_rect().has_point(panel.get_global_mouse_position())

func _paint_cell(cell: Vector2i) -> void:
	# Behaviour depends on brush kind:
	#   ripple    -> animated overlay, never erases
	#   hill_auto -> mark cell as hill region; auto-pick G1/G3 + suffix from
	#                neighbour mask; refresh adjacent hill cells too so their
	#                tiles update (corner becomes edge when a new neighbour joins)
	#   overlay   -> static overlay (decor / hills), stacks on top of dirt
	#   ground    -> replaces whatever the generator put here
	if brush_is_portal:
		_add_animated_prop(cell, brush_portal_folder, 12.0, PAINT_BASE_Z + 4 * 100)
		return
	if brush_is_ripple:
		_add_ripple(cell)
	elif brush_is_hill_auto:
		# Hill brush ONLY stamps the cliff overlay (G1/G3). Whatever ground was
		# there before (procedural dirt + grass, or earlier manual paint) stays
		# beneath it — the user paints A1/A2 manually on cells they want to
		# look dirt-topped or grass-topped. Auto-pasting A1 here was producing
		# alignment mismatches against manually-painted A2.
		hill_cells[cell] = null
		_refresh_hill_tile(cell)
		# Refresh neighbours within 2 cells along each cardinal — the junction
		# detection probes 2-step cells, so painting at C can flip a neighbour
		# at C±d from corner→fold or vice versa.
		for off in [Vector2i(0,-1), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0),
				Vector2i(0,-2), Vector2i(2,0), Vector2i(0,2), Vector2i(-2,0)]:
			if hill_cells.has(cell + off):
				_refresh_hill_tile(cell + off)
	else:
		# Always non-destructive: paint stacks on top of whatever's already at
		# this cell. Use right-click to peel layers; chunk-generator tiles stay
		# alive underneath until their layer is the topmost remaining one.
		_set_base(cell)
	_update_status()

# Hill auto-fit table: 4-bit cardinal mask of neighbouring HILL cells -> tile
# path under res://assets/forest/. mask 15 (interior) and isolated cells (0)
# both render no overlay; the cell still reads as "hill" through the user's
# painted dirt/grass underneath.
#
# 2-neighbour cells (masks 3/6/9/12) split into two cases — the table holds
# both, and _refresh_hill_tile picks G3 (terminal convex corner) vs G5
# (junction inside-fold) by probing whether the two arms continue past their
# first cell. Validated against draft 45's hand-painted layout.
const _HILL_TILE := {
	# Outer convex corners (G3) — terminal end of a single arm.
	"corner_3":  "elevation/dirt/Ground G3_W.png",   # N+E hill, SW open
	"corner_6":  "elevation/dirt/Ground G3_N.png",   # E+S hill, NW open
	"corner_9":  "elevation/dirt/Ground G3_S.png",   # N+W hill, SE open
	"corner_12": "elevation/dirt/Ground G3_E.png",   # S+W hill, NE open
	# Inside folds (G5) — junction where two hill arms meet at this cell.
	"fold_3":    "elevation/dirt/Ground G5_S.png",   # N+E arms continuing
	"fold_6":    "elevation/dirt/Ground G5_W.png",   # E+S arms continuing
	"fold_9":    "elevation/dirt/Ground G5_E.png",   # N+W arms continuing
	"fold_12":   "elevation/dirt/Ground G5_N.png",   # S+W arms continuing
	# Channels (G4) — 1-wide passage with hill on two opposite sides.
	5:  "elevation/dirt/Ground G4_N.png",   # N+S hill (vertical channel)
	10: "elevation/dirt/Ground G4_E.png",   # E+W hill (horizontal channel)
	# Edges (G1) — 3 cardinal hill neighbours
	14: "elevation/dirt/Ground G1_E.png",   # N is the outside  -> N edge
	13: "elevation/dirt/Ground G1_S.png",   # E is the outside  -> E edge
	11: "elevation/dirt/Ground G1_W.png",   # S is the outside  -> S edge
	7:  "elevation/dirt/Ground G1_N.png",   # W is the outside  -> W edge
}

# For each 2-neighbour mask, the two cardinal directions whose cells we probe
# one step further along — if BOTH continue (i.e. they're also hill), this
# cell is an inside-fold junction (G5); otherwise it's a convex tip (G3).
const _CORNER_ARMS := {
	3:  [Vector2i(0, -1), Vector2i(1, 0)],    # N + E
	6:  [Vector2i(1,  0), Vector2i(0, 1)],    # E + S
	9:  [Vector2i(0, -1), Vector2i(-1, 0)],   # N + W
	12: [Vector2i(0,  1), Vector2i(-1, 0)],   # S + W
}

# Lay down a fresh A1 dirt tile under a hill cell. The procedural ground was
# erased just before this call. z = -2 matches the generator's dirt layer.
func _paint_dirt_base(cell: Vector2i) -> void:
	var path := "%s/ground/dirt/Ground A1_E.png" % FOREST
	var tex: Texture2D = load(path)
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.offset = Vector2(0, main_ref.SPRITE_Y_OFFSET)
	s.position = main_ref.grid_to_screen(cell) + Vector2(0, float(cell.y) * 0.001)
	s.z_index = -2
	s.add_to_group("editor_paints")
	_paint_parent().add_child(s)
	if not painted_base.has(cell):
		painted_base[cell] = []
	painted_base[cell].append({"tex": path, "is_water": false, "sprite": s})

func _refresh_hill_tile(cell: Vector2i) -> void:
	if not hill_cells.has(cell):
		return
	# Compute hill-neighbour mask (only counts cells flagged as hill).
	var m: int = 0
	if hill_cells.has(cell + Vector2i(0, -1)): m |= 1
	if hill_cells.has(cell + Vector2i(1,  0)): m |= 2
	if hill_cells.has(cell + Vector2i(0,  1)): m |= 4
	if hill_cells.has(cell + Vector2i(-1, 0)): m |= 8
	# Free any existing overlay sprite for this cell.
	var prev = hill_cells[cell]
	if prev != null and is_instance_valid(prev):
		prev.queue_free()
	hill_cells[cell] = null
	# Resolve the right tile path for this cell's neighbour pattern.
	var tile_rel: String = ""
	if _CORNER_ARMS.has(m):
		# 2-adjacent-neighbour case. Probe one cell beyond each hill neighbour
		# along its own direction: if BOTH arms continue, this is a junction
		# (inside fold, G5). If either arm stops at the first cell, this is a
		# convex tip (outer corner, G3).
		var arms: Array = _CORNER_ARMS[m]
		var d0: Vector2i = arms[0]
		var d1: Vector2i = arms[1]
		var arm0_continues: bool = hill_cells.has(cell + d0 * 2)
		var arm1_continues: bool = hill_cells.has(cell + d1 * 2)
		var key: String = ("fold_%d" if (arm0_continues and arm1_continues) else "corner_%d") % m
		tile_rel = _HILL_TILE[key]
	elif _HILL_TILE.has(m):
		tile_rel = _HILL_TILE[m]
	else:
		# mask 15 (interior) and stragglers (0/1/2/4/8) get no overlay yet.
		return
	var path: String = "%s/%s" % [FOREST, tile_rel]
	var tex: Texture2D = load(path)
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.offset = Vector2(0, main_ref.SPRITE_Y_OFFSET)
	s.position = main_ref.grid_to_screen(cell) + Vector2(0, float(cell.y) * 0.001)
	s.z_index = PAINT_BASE_Z + 1   # above procedural ground, visible over dirt
	s.add_to_group("editor_paints")
	_paint_parent().add_child(s)
	hill_cells[cell] = s
	# Mirror the new sprite into painted_base so save/load round-trips it.
	if not painted_base.has(cell):
		painted_base[cell] = []
	painted_base[cell].append({
		"tex": path,
		"is_water": false,
		"sprite": s,
	})

func _set_base(cell: Vector2i) -> void:
	if brush_tex_path == "":
		return
	var tex: Texture2D = load(brush_tex_path)
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	# In dungeon mode, force y_lift=0 so painted tiles align with the
	# dungeon's generated sprites (which use the bare SPRITE_Y_OFFSET
	# with no lift). Otherwise an inadvertent toolbar lift would push
	# painted tiles upward off the dungeon floor.
	var paint_lift: int = 0 if dungeon_mode else y_lift
	s.offset = Vector2(0, main_ref.SPRITE_Y_OFFSET - paint_lift)
	s.position = main_ref.grid_to_screen(cell) + Vector2(0, float(cell.y) * 0.001)
	# Stack: each new base layer at this cell sits one z above the prior so
	# newest paint renders on top of older paints (grass on top of dirt). The
	# whole stack starts well above the procedural generator's max z so the
	# painted tile is always visible against the live world.
	# Auto-assign the correct layer for this tile group. The toolbar's
	# current_paint_layer is the user's preference, but groups have a
	# canonical layer (ground=1, grass/decor=2, trees/walls=3) that
	# overrides — paints land where they should regardless of which
	# toolbar button is active.
	var canonical_layer: int = _canonical_layer_for_path(brush_tex_path)
	var effective_layer: int = canonical_layer if canonical_layer > 0 else current_paint_layer
	s.z_index = effective_layer * 100 + PAINT_BASE_Z + (painted_base[cell].size() if painted_base.has(cell) else 0) + z_offset
	if brush_is_water:
		var mat := ShaderMaterial.new()
		mat.shader = WATER_SHADER
		s.material = mat
	# Tall grass / Flora B-series painted from the editor should sway like
	# the procedurally-spawned tall grass — the procedural generator routes
	# them through main._apply_wind_shader. Detect EITHER the dedicated
	# tall_grass folder OR a "Flora B…" family code (the env-scan paths
	# under environment/ don't include "tall_grass" in the folder string).
	elif main_ref and main_ref.has_method("_apply_wind_shader") and (
			"tall_grass" in brush_tex_path
			or "/Flora B" in brush_tex_path):
		main_ref._apply_wind_shader(s, cell)
	# Painted tiles are siblings of generator-spawned tiles inside main.world
	# so they share the identical y-sort / z-index / canvas pipeline. Tagging
	# them with a group lets us toggle / save / list them later.
	s.add_to_group("editor_paints")
	_paint_parent().add_child(s)
	# Spike tiles fade in over 0.5 s when first placed so they read as
	# a trap arming, not a pop-in. Texture path detection so the same
	# behaviour applies whether painted live or restored from save.
	if "spikes_tile" in brush_tex_path:
		s.modulate = Color(1, 1, 1, 0.0)
		var fade_tw := create_tween()
		fade_tw.tween_property(s, "modulate:a", 1.0, 0.5)
	if not painted_base.has(cell):
		painted_base[cell] = []
	# Auto-chain slope tiles: if this is an elevation tile and the south
	# (or south-east, south-west — neighbours that the slope might come up
	# from) cell already has an elevation tile painted, lift this one by
	# the previous slope's max height so the surfaces connect end-to-end
	# instead of every tile starting at ground level.
	var paint_y_lift: int = paint_lift
	if not dungeon_mode and "/elevation/" in brush_tex_path and main_ref:
		var below_max: int = 0
		for off in [Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1),
					Vector2i(1, 0), Vector2i(-1, 0)]:
			var nb: Vector2i = cell + (off as Vector2i)
			if painted_base.has(nb):
				for entry in painted_base[nb]:
					if not entry is Dictionary:
						continue
					if not "/elevation/" in String(entry.get("tex", "")):
						continue
					# Each elevation tile climbs SLOPE_RISE_PER_TILE px from
					# its south edge to its north edge. The chain links the
					# next tile to start at neighbour.y_lift + SLOPE_RISE_PER_TILE.
					var slope_top: int = int(entry.get("y_lift", 0)) + main_ref.SLOPE_RISE_PER_TILE
					if slope_top > below_max:
						below_max = slope_top
		if below_max > 0:
			paint_y_lift = below_max
			s.offset = Vector2(0, main_ref.SPRITE_Y_OFFSET - paint_y_lift)
	painted_base[cell].append({"tex": brush_tex_path, "is_water": brush_is_water, "sprite": s, "y_lift": paint_y_lift, "layer": effective_layer})
	_apply_rules_for_paint(cell, brush_tex_path, true)
	# Force walkable: stones / decor / overlay paints should never block
	# the player, even if a procedural pass had previously marked the cell
	# blocked (e.g. a tree was at this cell before being painted over).
	if effective_layer <= 2 and main_ref:
		main_ref.blocked.erase(cell)
		if main_ref.terrain_lift:
			main_ref.terrain_lift.tile_blocked.erase(cell)
			main_ref.terrain_lift.unregister_tree(cell)
	# Push the effective layer (after canonical override) through to the
	# pixel-collision system so "visible pixel wins" sorts by where this
	# tile actually renders, not what the toolbar said.
	if main_ref and main_ref.terrain_lift:
		main_ref.terrain_lift.set_painted_layer(cell, brush_tex_path, paint_y_lift, effective_layer)
	# Iso-shifted rule cell: a sprite lifted L px vertically lands visually
	# at iso (col - L/64, row - L/64). Writing the lift rule on that cell
	# instead of the painted cell makes the player walk on the floor where
	# they actually SEE it — no more "rule on -22,-15 but visual at -22,-16"
	# offsets.
	var rule_shift: int = paint_y_lift / 64
	var rule_cell: Vector2i = Vector2i(cell.x - rule_shift, cell.y - rule_shift)
	if paint_y_lift > 0 and main_ref and main_ref.has_method("set_tile_paint_lift"):
		main_ref.set_tile_paint_lift(rule_cell, paint_y_lift, true)
	# Register the painted texture for pixel-perfect lift lookup so the
	# player automatically rides the slope of any tile (G17 etc.) without
	# us having to know its shape ahead of time.
	if main_ref and main_ref.has_method("register_painted_pixel_tile"):
		main_ref.register_painted_pixel_tile(rule_cell, brush_tex_path, paint_y_lift)
	# Editor-painted props also become destructibles. Classify by path so
	# trees/rocks take a few hits and grass/flora pop on the first hit.
	if main_ref and main_ref.has_method("register_destructible"):
		var path_l: String = brush_tex_path.to_lower()
		var dkind: String = ""
		if "tree" in path_l or "/oak" in path_l or "/pine" in path_l or "/dead" in path_l:
			dkind = "tree"
		elif "stone" in path_l or "rock" in path_l or "scattered_stones" in path_l:
			dkind = "stone"
		elif "tall_grass" in path_l or "/flora b" in path_l:
			# Only LONG GRASS (tall_grass / Flora B) is a destructible.
			# Short tufts, flowers, small flora and plain grass tiles are
			# decorative — they don't pop on hit.
			dkind = "tall_grass"
		if dkind != "":
			main_ref.register_destructible(cell, s, dkind)
			# Trees and rocks block like walls: the trunk cell PLUS the
			# cell one tile south on screen (c+1, r+1). The south cell
			# is where the tree's visual base / trunk reads, so blocking
			# it stops the player from walking through the front. The
			# north cell stays walkable so you can step BEHIND the tree.
			if dkind == "tree" or dkind == "stone":
				main_ref.blocked[cell] = true
				main_ref.blocked[Vector2i(cell.x + 1, cell.y + 1)] = true

# Generic animated-prop placement (portal idle, future animated decor).
# `folder` is an absolute res:// path containing 000N.png frames. Loops
# the animation at `fps` and stamps it at z = `paint_z`. Tracked under
# painted_ripples so right-click peels it like any other paint.
func _add_animated_prop(cell: Vector2i, folder: String, fps: float, paint_z: int) -> void:
	if folder == "" or main_ref == null:
		return
	var frames: Array[Texture2D] = []
	var d := DirAccess.open(folder)
	if d == null:
		return
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
		var t: Texture2D = load("%s/%s" % [folder, n])
		if t != null:
			frames.append(t)
	if frames.is_empty():
		return
	var sf := SpriteFrames.new()
	sf.add_animation("loop")
	sf.set_animation_loop("loop", true)
	sf.set_animation_speed("loop", fps)
	for t in frames:
		sf.add_frame("loop", t)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	a.animation = "loop"
	a.play("loop")
	a.centered = true
	a.offset = Vector2(0, main_ref.SPRITE_Y_OFFSET)
	a.position = main_ref.grid_to_screen(cell)
	a.z_index = paint_z
	a.add_to_group("editor_paints")
	_paint_parent().add_child(a)
	if not painted_ripples.has(cell):
		painted_ripples[cell] = []
	painted_ripples[cell].append({"sprite": a, "tex": folder, "is_portal": true})
	# Without this the auto-save loop never fires for portal paints — they
	# weren't being persisted and would vanish on the next reload.
	_dirty_since_save = true

func _add_ripple(cell: Vector2i) -> void:
	# Ripples accumulate on top of the base; multiple ripples can sit on one cell.
	var frames: Array[Texture2D] = _load_ripple_frames(brush_ripple_folder)
	if frames.is_empty():
		return
	var sf := SpriteFrames.new()
	sf.add_animation("loop")
	sf.set_animation_loop("loop", true)
	sf.set_animation_speed("loop", 10.0)
	for t in frames:
		sf.add_frame("loop", t)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	a.animation = "loop"
	a.play("loop")
	a.centered = true
	# Per-ripple centroid offset ONLY: places the visible art's centroid at the
	# cell pivot. Don't combine with SPRITE_Y_OFFSET (-82) - that's for tiles
	# whose pivot is at canvas y=210 (the floor diamond), but ripples have art
	# at varying canvas positions and we want each one centered where clicked.
	a.offset = _ripple_centroid_offset(brush_ripple_folder, frames[0])
	a.position = main_ref.grid_to_screen(cell)
	a.z_index = PAINT_RIPPLE_Z
	# Recolor cyan ripple to soft white foam. Alpha is set via the shader's
	# froth_color uniform so it's baked into the fragment output (modulate
	# can interact unreliably with canvas_item shader alpha).
	var froth_mat := ShaderMaterial.new()
	froth_mat.shader = FROTH_SHADER
	froth_mat.set_shader_parameter("froth_color", Color(0.95, 1.0, 1.0, 0.08))
	a.material = froth_mat
	a.modulate = Color(1, 1, 1, 1)
	a.add_to_group("editor_paints")
	_paint_parent().add_child(a)
	if not painted_ripples.has(cell):
		painted_ripples[cell] = []
	painted_ripples[cell].append({
		"tex": brush_tex_path,
		"ripple_folder": brush_ripple_folder,
		"sprite": a,
	})
	_dirty_since_save = true

func _refresh_area_overlay() -> void:
	if overlay and overlay.has_method("set_area"):
		overlay.set_area(area_rect, area_active and area_rect.size.x > 0 and area_rect.size.y > 0)

func _area_fill() -> void:
	# Stamp the current brush at every cell in the selected rect. Honours all
	# brush behaviours (water, ripple, hill auto, overlay) by routing through
	# _paint_cell, so e.g. the Hill (auto-fit) brush correctly resolves
	# corners across the whole filled region after one pass.
	if not area_active:
		return
	for cy in range(area_rect.position.y, area_rect.position.y + area_rect.size.y):
		for cx in range(area_rect.position.x, area_rect.position.x + area_rect.size.x):
			_paint_cell(Vector2i(cx, cy))
	_update_status()

func _area_delete() -> void:
	# Wipes every layer at every cell in the selected rect: editor paints,
	# editor ripples, AND the chunk-generated world sprites underneath. The
	# cell becomes truly empty so a subsequent area-fill draws onto bare
	# ground.
	if not area_active:
		return
	for cy in range(area_rect.position.y, area_rect.position.y + area_rect.size.y):
		for cx in range(area_rect.position.x, area_rect.position.x + area_rect.size.x):
			var c := Vector2i(cx, cy)
			if painted_base.has(c):
				for entry in painted_base[c]:
					if is_instance_valid(entry.sprite):
						entry.sprite.queue_free()
				painted_base.erase(c)
			if painted_ripples.has(c):
				for entry in painted_ripples[c]:
					if is_instance_valid(entry.sprite):
						entry.sprite.queue_free()
				painted_ripples.erase(c)
			hill_cells.erase(c)
			if main_ref and main_ref.has_method("erase_world_cell"):
				main_ref.erase_world_cell(c)
	_update_status()

func _set_paint_layer(layer: int) -> void:
	current_paint_layer = clampi(layer, 1, MAX_PAINT_LAYERS)
	for i in range(1, MAX_PAINT_LAYERS + 1):
		var btn: Button = get_node_or_null("UILayer/Panel/Scroll/VBox/LayerRow/L%dBtn" % i)
		if btn:
			btn.button_pressed = (i == current_paint_layer)
			var a: float = 1.0 if i == current_paint_layer else 0.45
			btn.modulate = Color(1, 1, 1, a)
	# Refresh the Category dropdown so it shows only categories that fit
	# this layer (ground on L1, grass / overlay decor on L2, trees / big
	# props on L3, etc.).
	_init_dropdowns()
	_update_status()

# Returns true if a category dict should appear in the dropdown for the
# given paint layer. Pattern: each layer has a target slice of the world's
# vertical stack, and the dropdown narrows to whatever fits there. "Ground"
# tiles match category labels Water / Edges / Ground. "Grass" is anything
# scanned with the words tall_grass / Flora B / decor. "Trees / props" is
# Tree, Wall, Stone, Roof, Misc, etc.
# Returns the canonical layer for a given texture path, or 0 if no rule.
# Drives auto-layering so groups always land where they belong (ground=1,
# grass+decor=2, trees+walls=3) regardless of which layer button is active.
func _canonical_layer_for_path(tex_path: String) -> int:
	var l := tex_path.to_lower()
	# Layer 1: ground / floor / water / edges.
	if "/ground/" in l or "/water" in l or "/edges/" in l or "/elevation/" in l:
		return 1
	# Layer 2: tall grass, decor, flora, hills, ripples, wall-mounted
	# flora, scatter stones (loose ground stones lie on the floor).
	if "tall_grass" in l or "/decor/" in l or "/flora b" in l \
			or "/wallflora" in l or "/ripple" in l or "/stone " in l:
		return 2
	# Layer 3: structural / props — trees, walls, roofs, doors, chests,
	# torches, fireplaces, misc.
	if "/props/trees/" in l or "/tree " in l or "/treetrunk" in l \
			or "/wall " in l or "/roof " in l \
			or "/door " in l or "/chest " in l or "/torch" in l \
			or "/fireplace" in l or "/misc " in l:
		return 3
	return 0   # unknown → fall back to current_paint_layer

func _category_fits_layer(cat_label: String, layer: int) -> bool:
	var l := cat_label.to_lower()
	match layer:
		1:   # Ground: water, edges, base ground tiles
			return ("water" in l) or ("edges" in l) or l.begins_with("ground") or l == "ripples (animated)"
		2:   # Grass / overlay decor / hills / wall flora / loose stones / paths.
			return ("grass" in l) or l.begins_with("hill") or l.begins_with("decor") \
					or l.begins_with("flora") or l.begins_with("wallflora") \
					or l.begins_with("stone") or l == "path"
		3:   # Trees / Walls / Roofs / Misc / Doors / Chests / Torches.
			return l.begins_with("tree") or l.begins_with("wall") or l.begins_with("roof") \
					or l.begins_with("misc") or l.begins_with("door") \
					or l.begins_with("chest") or l.begins_with("torch") or l.begins_with("fireplace")
		_:
			# Layers 4-6: show everything (free overlay layers).
			return true

func _set_tool_mode(mode: int) -> void:
	tool_mode = mode
	# Toggle button states reflect the active mode.
	if paint_mode_btn:
		paint_mode_btn.button_pressed = (mode == ToolMode.PAINT)
	if select_mode_btn:
		select_mode_btn.button_pressed = (mode == ToolMode.SELECT)
	if _path_mode_btn:
		_path_mode_btn.button_pressed = (mode == ToolMode.PATH)
	# Ghost preview only makes sense while painting; hide it in SELECT so
	# the cursor cell highlight reads as the selection cursor.
	if ghost_sprite:
		ghost_sprite.visible = false
	# Drop any in-progress paint drag if you switch out of paint mid-drag.
	if mode == ToolMode.SELECT:
		paint_drag_button = 0
	_update_status()

func _set_lift_preset(storey: int) -> void:
	# Quick-select the lift used by future paints + Mark Floor / Slope. Each
	# preset matches one of the storey constants in tile_rules.
	y_lift = storey * LIFT_STEP
	_update_status()

func _area_clear_selection() -> void:
	area_active = false
	area_dragging = false
	_refresh_area_overlay()
	_update_status()

func _area_mark_floor() -> void:
	# Stamp the current y_lift across every cell in the selection as a
	# terrain rule (no new sprite). Player walks ON TOP at this height.
	if not area_active or main_ref == null or not main_ref.has_method("set_tile_paint_lift"):
		return
	for cy in range(area_rect.position.y, area_rect.position.y + area_rect.size.y):
		for cx in range(area_rect.position.x, area_rect.position.x + area_rect.size.x):
			main_ref.set_tile_paint_lift(Vector2i(cx, cy), y_lift, true)
	_dirty_since_save = true
	_update_status()

func _area_mark_slope() -> void:
	# Linear ramp from 0 at the south-east corner of the selection up to the
	# current y_lift at the north-west corner. South-east is the "low" side
	# matching the procedural hill ramp convention. Used to mark hand-drawn
	# slopes between ground and a Floor area.
	if not area_active or main_ref == null or not main_ref.has_method("set_tile_paint_lift"):
		return
	if y_lift <= 0:
		return
	var w: int = area_rect.size.x
	var h: int = area_rect.size.y
	var max_axis: float = max(float(w + h - 2), 1.0)
	for cy in range(area_rect.position.y, area_rect.position.y + area_rect.size.y):
		for cx in range(area_rect.position.x, area_rect.position.x + area_rect.size.x):
			# Distance from SE corner along (-x, -y) axis, normalized.
			var dx: int = (area_rect.position.x + w - 1) - cx
			var dy: int = (area_rect.position.y + h - 1) - cy
			var t: float = float(dx + dy) / max_axis
			var lift: int = int(round(float(y_lift) * t))
			if lift > 0:
				main_ref.set_tile_paint_lift(Vector2i(cx, cy), lift, true)
	_dirty_since_save = true
	_update_status()

func _area_mark_block() -> void:
	# Make every cell in the selection impassable to the player (cave wall
	# behaviour, no painted sprite required). Refcounted via tile_blocked.
	if not area_active or main_ref == null:
		return
	for cy in range(area_rect.position.y, area_rect.position.y + area_rect.size.y):
		for cx in range(area_rect.position.x, area_rect.position.x + area_rect.size.x):
			var c := Vector2i(cx, cy)
			main_ref.tile_blocked[c] = int(main_ref.tile_blocked.get(c, 0)) + 1
			main_ref.blocked[c] = true
	_dirty_since_save = true
	_update_status()

func _area_mark_step(step: int) -> void:
	# Stamp the selection at a discrete stair height. Step N → lift =
	# N * STAIR_RISE. Combined with the discrete-with-edge-blend in
	# main.cell_lift_at, the player snaps to the step height inside each
	# cell and ramps smoothly across the cell boundary to the next step.
	if not area_active or main_ref == null or not main_ref.has_method("set_tile_paint_lift"):
		return
	var lift: int = step * STAIR_RISE
	var n: int = 0
	for cy in range(area_rect.position.y, area_rect.position.y + area_rect.size.y):
		for cx in range(area_rect.position.x, area_rect.position.x + area_rect.size.x):
			var c := Vector2i(cx, cy)
			# Stair tool is a *physics rule* only — write the per-cell lift
			# and leave painted sprites exactly where the user placed them.
			# The player's walk height tracks the rule; visuals are not
			# touched.
			main_ref.tile_paint_lift.erase(c)
			main_ref.set_tile_paint_lift(c, lift, true)
			n += 1
	_dirty_since_save = true
	if status_label:
		status_label.text = "Marked %d cells as step %d (%d px)\n(rule only — sprites unchanged)" % [n, step, lift]

func _area_clear_rules() -> void:
	if not area_active or main_ref == null:
		return
	for cy in range(area_rect.position.y, area_rect.position.y + area_rect.size.y):
		for cx in range(area_rect.position.x, area_rect.position.x + area_rect.size.x):
			var c := Vector2i(cx, cy)
			main_ref.tile_storey.erase(c)
			main_ref.tile_paint_lift.erase(c)
			main_ref.tile_blocked.erase(c)
			main_ref.blocked.erase(c)
	_dirty_since_save = true
	_update_status()

func _shift_z(cell: Vector2i, delta: int) -> void:
	# If the topmost paint at this cell exists, shift its z by delta. Otherwise
	# just adjust the next-placement offset so the next click lands at the new
	# z. Status updates so user can see the value.
	if painted_base.has(cell) and painted_base[cell].size() > 0:
		var top: Sprite2D = painted_base[cell].back().sprite
		if is_instance_valid(top):
			top.z_index += delta
	else:
		z_offset = clampi(z_offset + delta, -32, 32)
	_update_status()

func _erase_cell(cell: Vector2i) -> void:
	# Right-click peels the topmost layer at this cell. Order:
	#   1) editor path stamp
	#   2) editor base paints (painted tiles — these always come before
	#      generated tiles so the user can delete their paint without
	#      first eating through the dungeon's generated tile)
	#   3) ripples
	#   4) DUNGEON generated cell (when in_dungeon)
	#   5) world tiles
	if main_ref and main_ref.has_method("erase_path_at") \
			and main_ref.erase_path_at(cell):
		_update_status()
		return
	if painted_base.has(cell) and painted_base[cell].size() > 0:
		var b = painted_base[cell].pop_back()
		_apply_rules_for_paint(cell, String(b.get("tex", "")), false)
		var blift: int = int(b.get("y_lift", 0))
		if blift > 0 and main_ref and main_ref.has_method("set_tile_paint_lift"):
			main_ref.set_tile_paint_lift(cell, blift, false)
		if main_ref and main_ref.has_method("unregister_painted_pixel_tile"):
			main_ref.unregister_painted_pixel_tile(cell, String(b.get("tex", "")), blift)
		if is_instance_valid(b.sprite):
			b.sprite.queue_free()
		if painted_base[cell].size() == 0:
			painted_base.erase(cell)
		_update_status()
		return
	# Dungeon-generated sprites (floor / wall / props) live on
	# `main_ref.dungeon`. Route delete there so the editor's right-click
	# can peel them off the dungeon directly.
	if main_ref and "in_dungeon" in main_ref and main_ref.in_dungeon \
			and "dungeon" in main_ref and main_ref.dungeon \
			and main_ref.dungeon.has_method("delete_cell"):
		if main_ref.dungeon.delete_cell(cell):
			_update_status()
			return
	if painted_ripples.has(cell) and painted_ripples[cell].size() > 0:
		var entry = painted_ripples[cell].pop_back()
		var s = entry.sprite
		if is_instance_valid(s):
			s.queue_free()
		if painted_ripples[cell].size() == 0:
			painted_ripples.erase(cell)
	elif painted_base.has(cell) and painted_base[cell].size() > 0:
		var b = painted_base[cell].pop_back()
		_apply_rules_for_paint(cell, String(b.get("tex", "")), false)
		var blift: int = int(b.get("y_lift", 0))
		if blift > 0 and main_ref and main_ref.has_method("set_tile_paint_lift"):
			main_ref.set_tile_paint_lift(cell, blift, false)
		if main_ref and main_ref.has_method("unregister_painted_pixel_tile"):
			main_ref.unregister_painted_pixel_tile(cell, String(b.get("tex", "")), blift)
		if is_instance_valid(b.sprite):
			b.sprite.queue_free()
		if painted_base[cell].size() == 0:
			painted_base.erase(cell)
	elif main_ref and main_ref.has_method("erase_world_cell"):
		main_ref.erase_world_cell(cell)
	_update_status()

func _clear_painted() -> void:
	for cell in painted_base.keys():
		for entry in painted_base[cell]:
			if is_instance_valid(entry.sprite):
				entry.sprite.queue_free()
	for cell in painted_ripples.keys():
		for entry in painted_ripples[cell]:
			if is_instance_valid(entry.sprite):
				entry.sprite.queue_free()
	painted_base.clear()
	painted_ripples.clear()
	_update_status()

# -------------------------------------------------------------- Save/Load ---

func _rechain_slopes() -> void:
	# Walk every painted-elevation cell south-to-north, lifting each one's
	# y_lift by the highest slope_top among its already-processed south /
	# south-east / south-west / east / west neighbours. Updates the sprite
	# offset, the painted_base entry's y_lift, and the registered pixel
	# tile entry so the player physics + visuals all match.
	if main_ref == null:
		return
	var elev_cells: Array = []
	for cell in painted_base.keys():
		for entry in painted_base[cell]:
			if entry is Dictionary and "/elevation/" in String(entry.get("tex", "")):
				elev_cells.append(cell)
				break
	# Sort south-first: bigger iso y = further south, processed first.
	elev_cells.sort_custom(func(a, b): return a.y > b.y)
	var sprite_y_off: int = main_ref.SPRITE_Y_OFFSET
	for cell in elev_cells:
		var below_max: int = 0
		for off in [Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1),
				Vector2i(1, 0), Vector2i(-1, 0)]:
			var nb: Vector2i = cell + (off as Vector2i)
			if not painted_base.has(nb):
				continue
			for nentry in painted_base[nb]:
				if not nentry is Dictionary:
					continue
				if not "/elevation/" in String(nentry.get("tex", "")):
					continue
				# 3-step rise (96 px) per cell, matching the visual G17 art.
				var slope_top: int = int(nentry.get("y_lift", 0)) + main_ref.SLOPE_RISE_PER_TILE
				if slope_top > below_max:
					below_max = slope_top
		# Wipe the per-cell pixel-tile registration entirely so the rebuild
		# below isn't fighting stale y_lift=0 entries from the original load.
		main_ref._painted_pixels.erase(cell)
		# Apply the chained lift to every elevation entry at this cell so
		# stacked layers (e.g. G17 + a corner accent) all rise together.
		for entry in painted_base[cell]:
			if not entry is Dictionary:
				continue
			var tex_path: String = String(entry.get("tex", ""))
			if not "/elevation/" in tex_path:
				continue
			entry["y_lift"] = below_max
			if is_instance_valid(entry.get("sprite")):
				var spr: Sprite2D = entry.sprite
				spr.offset = Vector2(0, sprite_y_off - below_max)
			if main_ref.has_method("register_painted_pixel_tile"):
				main_ref.register_painted_pixel_tile(cell, tex_path, below_max)
		if main_ref.has_method("set_tile_paint_lift"):
			main_ref.tile_paint_lift.erase(cell)
			if below_max > 0:
				main_ref.set_tile_paint_lift(cell, below_max, true)

func _save_arena() -> void:
	# Persistent arena snapshot — overwrites a single file (no draft_N.json
	# numbering) so the bounded test world has one canonical save.
	var bases: Array = []
	for cell in painted_base.keys():
		for entry in painted_base[cell]:
			if not entry is Dictionary:
				continue
			bases.append({
				"x": cell.x, "y": cell.y,
				"tex": entry.get("tex", ""),
				"is_water": bool(entry.get("is_water", false)),
				"y_lift": int(entry.get("y_lift", 0)),
				"layer": int(entry.get("layer", 1)),
			})
	var ripples: Array = []
	for cell in painted_ripples.keys():
		for entry in painted_ripples[cell]:
			if not entry is Dictionary:
				continue
			ripples.append({
				"x": cell.x, "y": cell.y,
				"tex": entry.get("tex", ""),
				"ripple_folder": entry.get("ripple_folder", ""),
				"is_portal": bool(entry.get("is_portal", false)),
			})
	# Per-cell terrain rules (lift / blocking / storey) painted via the
	# toolbar — these aren't sprite paints so the bases array misses them.
	var rules: Array = []
	if main_ref:
		var lift_d: Dictionary = main_ref.get("tile_paint_lift") if main_ref.get("tile_paint_lift") else {}
		var storey_d: Dictionary = main_ref.get("tile_storey") if main_ref.get("tile_storey") else {}
		var block_d: Dictionary = main_ref.get("tile_blocked") if main_ref.get("tile_blocked") else {}
		var keys: Dictionary = {}
		for k in lift_d.keys(): keys[k] = true
		for k in storey_d.keys(): keys[k] = true
		for k in block_d.keys(): keys[k] = true
		for k in keys.keys():
			rules.append({
				"x": k.x, "y": k.y,
				"lift": int(lift_d.get(k, 0)),
				"storey": int(storey_d.get(k, 0)),
				"block": int(block_d.get(k, 0)),
			})
	# Player position so reopening the arena drops them where they left off.
	var player_pos: Dictionary = {}
	if main_ref and main_ref.player:
		player_pos = {"x": main_ref.player.position.x, "y": main_ref.player.position.y}
	var f := FileAccess.open(ARENA_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"bases": bases,
		"ripples": ripples,
		"rules": rules,
		"player": player_pos,
	}, "  "))
	f.close()
	_dirty_since_save = false
	if status_label:
		status_label.text = "[auto-saved arena: %d bases, %d ripples]" % [bases.size(), ripples.size()]
	print("[editor] auto-saved arena (%d bases, %d ripples) to %s" % [bases.size(), ripples.size(), ProjectSettings.globalize_path(ARENA_PATH)])

func _load_arena() -> void:
	if not FileAccess.file_exists(ARENA_PATH):
		return
	var f := FileAccess.open(ARENA_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not data is Dictionary:
		return
	_clear_painted()
	if data.has("bases"):
		var saved_layer: int = current_paint_layer
		for entry in data.bases:
			brush_tex_path = entry.tex
			brush_is_water = bool(entry.get("is_water", false))
			brush_is_ripple = false
			brush_ripple_folder = ""
			y_lift = int(entry.get("y_lift", 0))
			# Restore the saved layer for each paint so render order +
			# pixel-collision pick the right priority on reload.
			current_paint_layer = clampi(int(entry.get("layer", 1)), 1, MAX_PAINT_LAYERS)
			_set_base(Vector2i(int(entry.x), int(entry.y)))
		y_lift = 0
		current_paint_layer = saved_layer
	if data.has("ripples"):
		for entry in data.ripples:
			var c2 := Vector2i(int(entry.x), int(entry.y))
			# Portal entries (is_portal=true) re-spawn via the animated-prop
			# helper using `tex` as the absolute folder path; ripples take
			# the original ripple-folder path.
			if bool(entry.get("is_portal", false)):
				_add_animated_prop(c2, String(entry.get("tex", "")), 12.0,
						PAINT_BASE_Z + 4 * 100)
				continue
			brush_tex_path = entry.tex
			brush_is_water = false
			brush_is_ripple = true
			brush_ripple_folder = String(entry.get("ripple_folder", ""))
			_add_ripple(c2)
	if data.has("rules") and main_ref:
		for entry in data.rules:
			var c := Vector2i(int(entry.x), int(entry.y))
			var lift: int = int(entry.get("lift", 0))
			var storey: int = int(entry.get("storey", 0))
			var block: int = int(entry.get("block", 0))
			if lift > 0: main_ref.tile_paint_lift[c] = lift
			if storey > 0: main_ref.tile_storey[c] = storey
			if block > 0:
				main_ref.tile_blocked[c] = block
				main_ref.blocked[c] = true
	# Re-chain elevation tile y_lifts after a load — sprites saved with
	# y_lift=0 won't have picked up the auto-chain on paint, but we can
	# recompute here so a saved 3-cell ramp climbs continuously.
	_rechain_slopes()
	if data.has("player") and main_ref and main_ref.player and data.player is Dictionary:
		# Restore last saved player position so combat / physics tests
		# resume where you left off instead of warping to spawn.
		var px: float = float(data.player.get("x", main_ref.player.position.x))
		var py: float = float(data.player.get("y", main_ref.player.position.y))
		main_ref.player.position = Vector2(px, py)
	_refresh_brush()
	_dirty_since_save = false
	_update_status()

func _save_draft() -> void:
	DirAccess.make_dir_recursive_absolute("user://drafts")
	var idx := 1
	while FileAccess.file_exists("user://drafts/draft_%d.json" % idx):
		idx += 1
	var fpath := "user://drafts/draft_%d.json" % idx
	# Resilient to both legacy single-dict cells and new list cells so an
	# in-memory mix from a hot-reloaded session still serializes correctly.
	var bases: Array = []
	for cell in painted_base.keys():
		var raw = painted_base[cell]
		var entries: Array = raw if raw is Array else [raw]
		for entry in entries:
			if not entry is Dictionary:
				continue
			bases.append({
				"x": cell.x, "y": cell.y,
				"tex": entry.get("tex", ""),
				"is_water": bool(entry.get("is_water", false)),
				"y_lift": int(entry.get("y_lift", 0)),
				"layer": int(entry.get("layer", 1)),
			})
	var ripples: Array = []
	for cell in painted_ripples.keys():
		var raw_r = painted_ripples[cell]
		var rentries: Array = raw_r if raw_r is Array else [raw_r]
		for entry in rentries:
			if not entry is Dictionary:
				continue
			ripples.append({
				"x": cell.x, "y": cell.y,
				"tex": entry.get("tex", ""),
				"ripple_folder": entry.get("ripple_folder", ""),
				"is_portal": bool(entry.get("is_portal", false)),
			})
	# Snapshot procedurally-generated sprites in the currently-loaded chunks so
	# we can analyse what the generator chose for any cell, alongside paints.
	var generated: Array = []
	if main_ref and "loaded_chunks" in main_ref:
		for cv in main_ref.loaded_chunks.keys():
			for s in main_ref.loaded_chunks[cv]:
				if not is_instance_valid(s):
					continue
				var tex_path := ""
				if s is Sprite2D and s.texture != null:
					tex_path = s.texture.resource_path
				var cell: Vector2i = main_ref._screen_to_grid(s.position)
				generated.append({
					"x": cell.x, "y": cell.y,
					"tex": tex_path,
					"z": int(s.z_index),
				})
	var f := FileAccess.open(fpath, FileAccess.WRITE)
	f.store_string(JSON.stringify({"bases": bases, "ripples": ripples, "generated": generated}, "  "))
	f.close()
	var abs_path := ProjectSettings.globalize_path(fpath)
	var total := bases.size() + ripples.size() + generated.size()
	status_label.text = "Saved %d entries (paint=%d gen=%d)\n%s" % [total, bases.size() + ripples.size(), generated.size(), abs_path]
	print("[editor] saved %d (bases=%d ripples=%d generated=%d) to %s" % [total, bases.size(), ripples.size(), generated.size(), abs_path])

func _load_latest_draft() -> void:
	var idx := 1
	while FileAccess.file_exists("user://drafts/draft_%d.json" % (idx + 1)):
		idx += 1
	var fpath := "user://drafts/draft_%d.json" % idx
	if not FileAccess.file_exists(fpath):
		status_label.text = "No drafts to load."
		return
	var f := FileAccess.open(fpath, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not data is Dictionary:
		return
	_clear_painted()
	var n_loaded := 0
	if data.has("bases"):
		for entry in data.bases:
			var cell := Vector2i(int(entry.x), int(entry.y))
			brush_tex_path = entry.tex
			brush_is_water = bool(entry.get("is_water", false))
			brush_is_ripple = false
			brush_ripple_folder = ""
			_set_base(cell)   # paint append: stacks correctly on reload
			n_loaded += 1
	if data.has("ripples"):
		for entry in data.ripples:
			var cell := Vector2i(int(entry.x), int(entry.y))
			brush_tex_path = entry.tex
			brush_is_water = false
			brush_is_ripple = true
			brush_ripple_folder = String(entry.get("ripple_folder", ""))
			_add_ripple(cell)
			n_loaded += 1
	# Backwards-compat with the older single-list draft format.
	if data.has("cells"):
		for entry in data.cells:
			var cell := Vector2i(int(entry.x), int(entry.y))
			brush_tex_path = entry.tex
			brush_is_water = bool(entry.get("is_water", false))
			brush_is_ripple = bool(entry.get("is_ripple", false))
			brush_ripple_folder = String(entry.get("ripple_folder", ""))
			_paint_cell(cell)
			n_loaded += 1
	_refresh_brush()
	status_label.text = "Loaded %d entries from %s" % [n_loaded, fpath]

# -------------------------------------------------------------- Status -----

func _update_status() -> void:
	if not is_inside_tree():
		return
	var brush := brush_tex_path.get_file() if brush_tex_path else "(none)"
	var base_count := 0
	for cell in painted_base.keys():
		base_count += int(painted_base[cell].size())
	var ripple_count := 0
	for cell in painted_ripples.keys():
		ripple_count += int(painted_ripples[cell].size())
	var hover_str: String = "(%d, %d)" % [hover_cell.x, hover_cell.y] if hover_visible else "—"
	var player_str: String = "—"
	var hover_lift_str: String = ""
	var player_lift_str: String = ""
	if main_ref and main_ref.player and main_ref.has_method("_screen_to_grid"):
		var pcell: Vector2i = main_ref._screen_to_grid(main_ref.player.position)
		player_str = "(%d, %d)" % [pcell.x, pcell.y]
		# Show actual stored lift (in px) at hover + player so you can see
		# what the stair / floor tools have written.
		if "tile_paint_lift" in main_ref:
			var hl: int = int(main_ref.tile_paint_lift.get(hover_cell, 0))
			var pl: int = int(main_ref.tile_paint_lift.get(pcell, 0))
			hover_lift_str = "  lift:%d" % hl
			player_lift_str = "  lift:%d" % pl
	var area_str: String = "—"
	if area_active and area_rect.size.x > 0 and area_rect.size.y > 0:
		area_str = "%dx%d @ (%d,%d)" % [area_rect.size.x, area_rect.size.y, area_rect.position.x, area_rect.position.y]
	var mode_str: String = "PAINT" if tool_mode == ToolMode.PAINT else "SELECT"
	status_label.text = "[%s mode]  Brush: %s\nBases: %d   Ripples: %d\nBrush lift: %dpx ([/] adjust, \\ reset)   Z-off: %d\nHover: %s%s   Player: %s%s\nArea: %s   (Shift-drag or Select-mode-drag)" % [mode_str, brush, base_count, ripple_count, y_lift, z_offset, hover_str, hover_lift_str, player_str, player_lift_str, area_str]
