extends Node2D
class_name HitFX

# Cartoon-style hit pop, repurposed from JMO's CFXR4 Hit Pow Cartoon prefab.
# We can't load the .prefab itself but we mimic the look using its textures
# (debris, star, ember) plus a bouncy "POW!" label and a quick light flash.
# Spawn one per impact: HitFX.spawn(world_root, world_pos, "POW!").

# Runtime-loaded so adding the PNGs after this script was last compiled
# doesn't trip a "no resource loader" parse error. The first call to
# spawn() warms the cache.
const TEX_DEBRIS_PATH := "res://assets/effects/cfxr/cfxr debris flat unlit 3x3.png"
const TEX_STAR_PATH := "res://assets/effects/cfxr/cfxr magic star.png"
const TEX_EMBER_PATH := "res://assets/effects/cfxr/cfxr ember blur.png"
static var TEX_DEBRIS: Texture2D = null
static var TEX_STAR: Texture2D = null
static var TEX_EMBER: Texture2D = null

static func _load_textures() -> void:
	if TEX_DEBRIS == null and ResourceLoader.exists(TEX_DEBRIS_PATH):
		TEX_DEBRIS = load(TEX_DEBRIS_PATH)
	if TEX_STAR == null and ResourceLoader.exists(TEX_STAR_PATH):
		TEX_STAR = load(TEX_STAR_PATH)
	if TEX_EMBER == null and ResourceLoader.exists(TEX_EMBER_PATH):
		TEX_EMBER = load(TEX_EMBER_PATH)

const COLOR_HOT := Color(1.0, 0.85, 0.25, 1.0)
const COLOR_WARM := Color(1.0, 0.55, 0.18, 1.0)

@export var pow_text: String = "POW!"
@export var pow_color: Color = COLOR_HOT

static func spawn(parent: Node, world_pos: Vector2, text: String = "POW!", color: Color = COLOR_HOT) -> void:
	if parent == null:
		return
	_load_textures()
	var fx := HitFX.new()
	fx.pow_text = text
	fx.pow_color = color
	parent.add_child(fx)
	fx.global_position = world_pos
	fx._kick()

func _kick() -> void:
	z_index = 950
	# Just the popup text — no debris/stars/flash. The flash ring was
	# rendering as a black square when the ember texture wasn't imported,
	# and the particle bursts were piling on without adding much.
	_pow_label()
	get_tree().create_timer(0.9).timeout.connect(queue_free)

func _burst_debris() -> void:
	var p := CPUParticles2D.new()
	p.texture = TEX_DEBRIS
	p.amount = 24
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 320.0
	p.gravity = Vector2(0, 380)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.color = pow_color
	p.angular_velocity_min = -380.0
	p.angular_velocity_max = 380.0
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.emitting = true
	add_child(p)

func _burst_stars() -> void:
	var p := CPUParticles2D.new()
	p.texture = TEX_STAR
	p.amount = 8
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.spread = 180.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 160.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.color = COLOR_WARM
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.emitting = true
	add_child(p)

func _flash_ring() -> void:
	# Quick scale-up + fade ring using the ember texture for a soft flash.
	var s := Sprite2D.new()
	s.texture = TEX_EMBER
	s.modulate = pow_color
	s.scale = Vector2(0.2, 0.2)
	s.z_index = -1   # behind label/particles within the FX node
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(s)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector2(1.6, 1.6), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, 0.35)

# CFXR cartoon-font atlas. Unity stores rects with origin at the BOTTOM
# of the image, so we flip Y to match Godot's top-origin region_rect.
const CFXR_FONT_PATH := "res://assets/effects/cfxr/cfxr_font_AmazGoDaBold.png"
const CFXR_FONT_GLYPHS_PATH := "res://cfxr_font_glyphs.json"
const CFXR_FONT_TEX_HEIGHT := 72
static var _font_tex: Texture2D = null
static var _font_glyphs: Dictionary = {}    # char -> Rect2 (already y-flipped)

static var _pix_shader: Shader = null
static func _pixelize_shader() -> Shader:
	if _pix_shader == null and ResourceLoader.exists("res://pixelize.gdshader"):
		_pix_shader = load("res://pixelize.gdshader")
	return _pix_shader

static func _load_font() -> void:
	if _font_tex == null and ResourceLoader.exists(CFXR_FONT_PATH):
		_font_tex = load(CFXR_FONT_PATH)
	if _font_glyphs.is_empty() and FileAccess.file_exists(CFXR_FONT_GLYPHS_PATH):
		var f := FileAccess.open(CFXR_FONT_GLYPHS_PATH, FileAccess.READ)
		var raw = JSON.parse_string(f.get_as_text())
		f.close()
		if raw is Dictionary:
			for c in raw.keys():
				var r: Array = raw[c]
				if r.size() == 4:
					var ux: int = int(r[0]); var uy: int = int(r[1])
					var uw: int = int(r[2]); var uh: int = int(r[3])
					# Flip Y from Unity (bottom-origin) to Godot (top-origin).
					_font_glyphs[c] = Rect2(ux, CFXR_FONT_TEX_HEIGHT - uy - uh, uw, uh)

func _pow_label() -> void:
	# Build the text out of glyph sprites from the CFXR cartoon font, then
	# animate the whole group with a 3-part pop curve (overshoot, settle,
	# fade-up). All glyphs share one parent Node2D so they animate in sync.
	HitFX._load_font()
	if HitFX._font_tex == null or HitFX._font_glyphs.is_empty():
		return
	var holder := Node2D.new()
	add_child(holder)
	var x_cursor: float = 0.0
	const KERN := 2.0
	# Render the text small (≈18 px tall), then a pixelise shader on each
	# glyph quantises UVs to coarser blocks for a chunky pixel-art feel.
	const SCALE_BASE := 0.32
	const PIXEL_BLOCK := 3.0   # bigger = more chunky pixels per glyph
	var glyph_nodes: Array[Sprite2D] = []
	for c in pow_text.to_upper():
		if not HitFX._font_glyphs.has(c):
			x_cursor += 18.0   # space-ish gap for unknown chars
			continue
		var rect: Rect2 = HitFX._font_glyphs[c]
		var s := Sprite2D.new()
		s.texture = HitFX._font_tex
		s.region_enabled = true
		s.region_rect = rect
		s.centered = true
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Per-glyph pixelise shader: quantises UVs into PIXEL_BLOCK-sized
		# squares within the glyph's region so each character renders as
		# coarse pixel chunks instead of a smooth bitmap.
		var mat := ShaderMaterial.new()
		mat.shader = _pixelize_shader()
		mat.set_shader_parameter("pixel_block", PIXEL_BLOCK)
		mat.set_shader_parameter("region_size", rect.size)
		s.material = mat
		s.modulate = pow_color
		s.position = Vector2(x_cursor + rect.size.x * 0.5 * SCALE_BASE, 0.0)
		s.scale = Vector2(SCALE_BASE, SCALE_BASE)
		holder.add_child(s)
		glyph_nodes.append(s)
		x_cursor += (rect.size.x + KERN) * SCALE_BASE
	# Centre horizontally above the spawn point.
	holder.position = Vector2(-x_cursor * 0.5, -36.0)
	holder.scale = Vector2(0.0, 0.0)
	holder.modulate.a = 0.0
	# 3-part popout curve:
	#   1) scale 0 → 1.2 with overshoot, alpha fades in (180ms)
	#   2) settle 1.2 → 1.0 (120ms)
	#   3) drift up + fade out (450ms)
	var tw := create_tween()
	tw.tween_property(holder, "scale", Vector2(1.2, 1.2), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holder, "modulate:a", 1.0, 0.12)
	tw.tween_property(holder, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(holder, "position:y", holder.position.y - 28.0, 0.45)
	tw.parallel().tween_property(holder, "modulate:a", 0.0, 0.45).set_delay(0.05)
