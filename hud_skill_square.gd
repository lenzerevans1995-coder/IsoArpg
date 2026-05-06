extends Control
class_name HUDSkillSquare

# D2-style large LMB / RMB main-skill square. Big chunky frame, deep
# cavity, optional skill icon and keybind chip. Pure pixel-art draws.

@export var sz: int = 64 :
	set(v):
		sz = max(16, v)
		queue_redraw()

@export var hover: bool = false :
	set(v):
		hover = v
		queue_redraw()

# Skill registry id ("warrior_basic", "warrior_cleave"…) — when set, the
# square renders that skill's icon inside the cavity. Leave empty for an
# unbound slot.
@export var skill_id: String = "" :
	set(v):
		skill_id = v
		_apply_icon()
# Direct texture override — wins over `skill_id` when set. Useful for
# slots showing inventory items / passives that don't live in SkillDB.
@export var icon_texture: Texture2D = null :
	set(v):
		icon_texture = v
		_apply_icon()
# Renders the icon at reduced alpha for locked / unequipped slots.
@export var icon_greyed: bool = false :
	set(v):
		icon_greyed = v
		queue_redraw()
# Pixelize shader strength applied to the icon. 9 hits the sweet spot
# for the warrior icon set (chunky pixel-art read without losing
# silhouette detail). Editable in inspector if a different set wants
# a different value.
@export_range(1.0, 32.0, 0.1) var icon_pixel_size: float = 9.0 :
	set(v):
		icon_pixel_size = v
		_apply_icon()

# Cooldown state — driven externally by trigger_cooldown(seconds) when a
# skill fires. While > 0 the slot dims, a sweeping fill animates from
# the top down, and a press-flash brightens for the first 0.15 s.
var _cd_total: float = 0.0
var _cd_left: float = 0.0
var _cd_flash: float = 0.0

func trigger_cooldown(seconds: float, flash: float = 0.15) -> void:
	_cd_total = max(seconds, 0.001)
	_cd_left = _cd_total
	_cd_flash = max(flash, 0.0)
	set_process(true)
	queue_redraw()

func is_on_cooldown() -> bool:
	return _cd_left > 0.0

func _process(delta: float) -> void:
	if _cd_left <= 0.0 and _cd_flash <= 0.0:
		set_process(false)
		return
	_cd_left = max(0.0, _cd_left - delta)
	_cd_flash = max(0.0, _cd_flash - delta)
	queue_redraw()
	if _cd_overlay and is_instance_valid(_cd_overlay):
		_cd_overlay.queue_redraw()

const _SkillDB := preload("res://skill_db.gd")
const _PIXELIZE_SHADER := preload("res://shaders/skill_icon_pixelize.gdshader")
var _icon_node: TextureRect
# Cooldown overlay drawn ON TOP of the icon. Lives as the last child
# so it renders after the TextureRect (children paint after the
# parent's _draw, in sibling order).
var _cd_overlay: Control = null

func _ready() -> void:
	_apply_icon()

# Builds / updates the icon child. The cavity is (w-12, h-12) starting
# at (6, 6); the icon fills the cavity with a ~4 px margin and runs
# through the pixelize shader at 1.2 strength.
func _apply_icon() -> void:
	var tex: Texture2D = icon_texture
	if tex == null and skill_id != "":
		tex = _SkillDB.icon_for(skill_id)
	# Reject textures whose RID never finished initialising — attaching
	# them to the TextureRect would trigger draw-time RID errors.
	if tex == null or not is_instance_valid(tex) or tex.get_width() <= 0:
		if _icon_node and is_instance_valid(_icon_node):
			_icon_node.queue_free()
		_icon_node = null
		queue_redraw()
		return
	if _icon_node == null or not is_instance_valid(_icon_node):
		_icon_node = TextureRect.new()
		_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon_node.stretch_mode = TextureRect.STRETCH_SCALE
		_icon_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_icon_node)
	# Ensure the cooldown overlay exists AND is the last child so it
	# renders on top of the icon. Children paint after the parent's
	# _draw, in sibling order — last sibling wins.
	if _cd_overlay == null or not is_instance_valid(_cd_overlay):
		_cd_overlay = _CooldownOverlay.new()
		_cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cd_overlay.set("host", self)
		add_child(_cd_overlay)
	move_child(_cd_overlay, get_child_count() - 1)
	# (Re)assign the shader material every call so hot-reloads pick up
	# changes to the .gdshader file and shader parameter tweaks above
	# actually take effect (a previous run could have left a different
	# material on the node).
	var mat := ShaderMaterial.new()
	mat.shader = _PIXELIZE_SHADER
	mat.set_shader_parameter("pixel_size", icon_pixel_size)
	_icon_node.material = mat
	_icon_node.texture = tex
	_layout_icon()
	_icon_node.modulate = Color(0.55, 0.55, 0.55, 0.85) if icon_greyed else Color(1, 1, 1, 1)

func _layout_icon() -> void:
	if _icon_node == null or not is_instance_valid(_icon_node):
		return
	var w: int = int(size.x)
	var h: int = int(size.y)
	# Fill the cavity edge-to-edge — right up to the gold pinstripe.
	# Cavity rect is (5, 5) to (w-5, h-5) in _draw, so icon spans that
	# exact area with no inner margin.
	_icon_node.position = Vector2(5, 5)
	_icon_node.size = Vector2(w - 10, h - 10)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_icon()

const COL_STONE_DARK   := Color(0.10, 0.11, 0.12)
const COL_BRONZE_DARK  := Color(0.18, 0.20, 0.22)
const COL_BRONZE_MID   := Color(0.32, 0.34, 0.36)
const COL_GOLD         := Color(0.55, 0.55, 0.52)
const COL_GOLD_HI      := Color(0.78, 0.76, 0.70)
const COL_VOID         := Color(0.05, 0.06, 0.07)

func _draw() -> void:
	var w: int = int(size.x)
	var h: int = int(size.y)
	# Drop shadow.
	draw_rect(Rect2(2, 4, w, h), Color(0, 0, 0, 0.55), true)
	# Outer dark stone frame.
	draw_rect(Rect2(0, 0, w, h), COL_STONE_DARK, true)
	# Bronze rim (chunky 3 px).
	draw_rect(Rect2(2, 2, w - 4, h - 4), COL_BRONZE_DARK, true)
	draw_rect(Rect2(3, 3, w - 6, h - 6), COL_BRONZE_MID, true)
	# Gold pinstripe.
	var rim_col: Color = COL_GOLD_HI if hover else COL_GOLD
	draw_rect(Rect2(4, 4, w - 8, h - 8), rim_col, true)
	# Inner dark.
	draw_rect(Rect2(5, 5, w - 10, h - 10), COL_STONE_DARK, true)
	# Cavity.
	draw_rect(Rect2(6, 6, w - 12, h - 12), COL_VOID, true)
	# Inner top sheen.
	draw_rect(Rect2(6, 6, w - 12, max(2, (h - 12) / 6)), Color(1, 1, 1, 0.07), true)
	# Inner bottom shadow.
	draw_rect(Rect2(6, h - 8, w - 12, 2), Color(0, 0, 0, 0.4), true)
	# Gold corner studs (4 small dots).
	var ts: int = 4
	_corner_tri(4, 4, ts, 0)
	_corner_tri(w - 4, 4, ts, 1)
	_corner_tri(4, h - 4, ts, 2)
	_corner_tri(w - 4, h - 4, ts, 3)
	# Cooldown sweep + press flash live in _CooldownOverlay (the last
	# child) so they render ON TOP of the icon TextureRect. Drawing
	# them here in the parent's _draw left them hidden behind the
	# child icon.

func _corner_tri(x: int, y: int, ts: int, corner: int) -> void:
	var pts := PackedVector2Array()
	match corner:
		0:  pts = PackedVector2Array([Vector2(x, y), Vector2(x + ts, y), Vector2(x, y + ts)])
		1:  pts = PackedVector2Array([Vector2(x, y), Vector2(x - ts, y), Vector2(x, y + ts)])
		2:  pts = PackedVector2Array([Vector2(x, y), Vector2(x + ts, y), Vector2(x, y - ts)])
		_:  pts = PackedVector2Array([Vector2(x, y), Vector2(x - ts, y), Vector2(x, y - ts)])
	draw_colored_polygon(pts, COL_GOLD)

# Inline child Control that draws the cooldown sweep + press flash on
# top of the icon. Reads timer state from its `host` HUDSkillSquare.
class _CooldownOverlay extends Control:
	var host: Control = null
	func _ready() -> void:
		# Cover the entire parent so we can draw within the cavity area.
		anchor_right = 1.0
		anchor_bottom = 1.0
	func _draw() -> void:
		if host == null:
			return
		var w: int = int(size.x)
		var h: int = int(size.y)
		var cd_left: float = float(host.get("_cd_left"))
		var cd_total: float = float(host.get("_cd_total"))
		var cd_flash: float = float(host.get("_cd_flash"))
		if cd_left > 0.0 and cd_total > 0.0:
			var t: float = clamp(cd_left / cd_total, 0.0, 1.0)
			var cav_y: int = 5
			var cav_h: int = h - 10
			var fill_h: int = int(round(float(cav_h) * t))
			draw_rect(Rect2(5, cav_y, w - 10, fill_h), Color(0, 0, 0, 0.55), true)
		if cd_flash > 0.0:
			var fa: float = cd_flash / 0.15
			draw_rect(Rect2(5, 5, w - 10, h - 10), Color(1, 1, 0.7, 0.35 * fa), true)
