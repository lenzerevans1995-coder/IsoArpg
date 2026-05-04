@tool
extends Button
class_name HUDStoneButton

# Stone-rim button matching HUDSkillSquare / HUDCenterBar palette. Hover
# brightens the gold pinstripe, pressed sinks the cavity. Custom-drawn
# under the default Button label so hover/click states still propagate
# through Godot's signal system.

const COL_OUT_DARK   := Color(0.06, 0.07, 0.08)
const COL_BRONZE_LO  := Color(0.18, 0.20, 0.22)
const COL_BRONZE_MID := Color(0.32, 0.34, 0.36)
const COL_GOLD       := Color(0.55, 0.55, 0.52)
const COL_GOLD_HI    := Color(0.78, 0.76, 0.70)
const COL_VOID       := Color(0.05, 0.06, 0.07)
const COL_VOID_HOT   := Color(0.10, 0.11, 0.13)

const _IconAtlas := preload("res://icon_atlas.gd")

# Inspector knobs for the icon rendered inside the stone cavity.
# Pick a cell from the 64×64 icon sheet by grid coords or by linear
# index (linear takes precedence when ≥ 0). Setting any of these
# triggers an immediate redraw in the editor.
@export var icon_col: int = -1 :
	set(v):
		icon_col = v
		queue_redraw()
@export var icon_row: int = 0 :
	set(v):
		icon_row = v
		queue_redraw()
@export var icon_linear_index: int = -1 :
	set(v):
		icon_linear_index = v
		queue_redraw()
# How much of the cavity the icon fills (1.0 = exact size, ≤0.95 leaves
# a small margin so the gold rim still reads).
@export_range(0.4, 1.0, 0.05) var icon_fill: float = 0.85 :
	set(v):
		icon_fill = v
		queue_redraw()
# Renders the icon as a desaturated grey silhouette. Useful for HP / MP
# slot indicators and locked / unequipped skill slots.
@export var icon_greyed: bool = false :
	set(v):
		icon_greyed = v
		queue_redraw()

func _ready() -> void:
	flat = true
	add_theme_color_override("font_color", COL_GOLD_HI)
	add_theme_color_override("font_color_hover", Color(1, 0.96, 0.85))
	add_theme_color_override("font_color_pressed", COL_GOLD)
	add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.9))
	add_theme_constant_override("outline_size", 3)

func _draw() -> void:
	var w: int = int(size.x)
	var h: int = int(size.y)
	var mode: int = get_draw_mode()
	var rim: Color = COL_GOLD_HI if mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED else COL_GOLD
	var cavity: Color = COL_VOID_HOT if mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED else COL_VOID

	# Outer dark.
	draw_rect(Rect2(0, 0, w, h), COL_OUT_DARK, true)
	# Bronze rim.
	draw_rect(Rect2(1, 1, w - 2, h - 2), COL_BRONZE_LO, true)
	draw_rect(Rect2(2, 2, w - 4, h - 4), COL_BRONZE_MID, true)
	# Gold pinstripe.
	draw_rect(Rect2(3, 3, w - 6, h - 6), rim, true)
	# Inner dark.
	draw_rect(Rect2(4, 4, w - 8, h - 8), COL_OUT_DARK, true)
	# Cavity (changes when pressed).
	draw_rect(Rect2(5, 5, w - 10, h - 10), cavity, true)
	# Top sheen (1 px highlight).
	if mode != DRAW_PRESSED:
		draw_rect(Rect2(5, 5, w - 10, 1), Color(1, 1, 1, 0.10), true)
	# Icon, drawn on top of the cavity. Resolved from the shared atlas
	# (col/row, or linear_index when ≥ 0). Sized by icon_fill so a small
	# margin still shows the gold pinstripe around the icon.
	var icon_tex: Texture2D = null
	if icon_linear_index >= 0:
		icon_tex = _IconAtlas.at_index(icon_linear_index)
	elif icon_col >= 0:
		icon_tex = _IconAtlas.at(icon_col, icon_row)
	# Guard against textures whose underlying RID never made it to the
	# GPU (atlas slice failed, or a hot-reload left a stale ImageTexture
	# with an uninitialised rd_texture). draw_texture_rect on those
	# spams "Parameter tex is null" / RID errors every frame.
	if icon_tex != null and is_instance_valid(icon_tex) and icon_tex.get_width() > 0:
		var cav_w: float = float(w - 10)
		var cav_h: float = float(h - 10)
		var ic_w: float = cav_w * icon_fill
		var ic_h: float = cav_h * icon_fill
		var ic_x: float = 5.0 + (cav_w - ic_w) * 0.5
		var ic_y: float = 5.0 + (cav_h - ic_h) * 0.5
		# Pressed sinks 1px so the icon "presses in" with the button.
		if mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED:
			ic_y += 1.0
		var tint: Color = Color(0.55, 0.55, 0.55, 0.85) if icon_greyed else Color(1, 1, 1, 1)
		draw_texture_rect(icon_tex, Rect2(ic_x, ic_y, ic_w, ic_h), false, tint)

# Trigger redraws on state changes so hover/press visuals update immediately.
func _on_state_changed() -> void:
	queue_redraw()
