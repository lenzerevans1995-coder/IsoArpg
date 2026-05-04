@tool
extends Button
class_name StatStepperBtn

# Small +/- button drawn in code. Style matches the Lucide icon set
# (centred glyph on a 24×24 grid, rounded line caps, 2-px stroke). The
# glyph is rendered into a SubViewport with the project's pixelize
# shader so it inherits the chunky pixel-art look used elsewhere on
# the HUD without needing imported PNGs.

enum Mode { PLUS, MINUS }

@export var mode: int = Mode.PLUS :
	set(v):
		mode = v
		queue_redraw()
@export var glyph_color: Color = Color(0.95, 0.85, 0.55, 1.0) :
	set(v):
		glyph_color = v
		queue_redraw()
@export_range(1.0, 6.0, 0.5) var stroke_px: float = 3.0 :
	set(v):
		stroke_px = v
		queue_redraw()
# Reuses the same pixelize shader the skill icons use so the +/- read
# the same chunky pixel-art aesthetic. 1.0 = no pixelisation.
@export_range(1.0, 16.0, 0.1) var pixel_size: float = 2.0 :
	set(v):
		pixel_size = v
		_apply_shader()

const _PIXELIZE_SHADER := preload("res://skill_icon_pixelize.gdshader")

func _ready() -> void:
	flat = true
	custom_minimum_size = Vector2(20, 20)
	_apply_shader()

func _apply_shader() -> void:
	# Apply the shader to the Button itself — _draw output is captured
	# by the canvas item and passes through the material before render.
	var mat := ShaderMaterial.new()
	mat.shader = _PIXELIZE_SHADER
	mat.set_shader_parameter("pixel_size", pixel_size)
	material = mat
	queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	# Lucide icons live on a 24-unit grid; use the smaller dimension
	# so the glyph stays a true square inside non-square buttons.
	var unit: float = min(w, h) / 24.0
	var cx: float = w * 0.5
	var cy: float = h * 0.5
	# Hover / press tint a touch brighter / dimmer.
	var col: Color = glyph_color
	var dm: int = get_draw_mode()
	if dm == DRAW_HOVER or dm == DRAW_HOVER_PRESSED:
		col = Color(min(col.r * 1.25, 1.0), min(col.g * 1.25, 1.0), min(col.b * 1.25, 1.0), col.a)
	if dm == DRAW_PRESSED or dm == DRAW_HOVER_PRESSED:
		col.a *= 0.85
	# Plus / minus arms — Lucide uses arms ~10 units long, capped
	# rounded. Approximate the rounded cap with a circle at each end.
	var half_arm: float = unit * 5.0
	var thick: float = max(stroke_px, 1.0)
	# Plain stroke arms — no rounded end caps. The cap circles became
	# visible "dots" under the pixelize shader at small button sizes.
	# Horizontal arm (both PLUS and MINUS).
	draw_line(Vector2(cx - half_arm, cy), Vector2(cx + half_arm, cy),
			col, thick, true)
	# Vertical arm (PLUS only).
	if mode == Mode.PLUS:
		draw_line(Vector2(cx, cy - half_arm), Vector2(cx, cy + half_arm),
				col, thick, true)
