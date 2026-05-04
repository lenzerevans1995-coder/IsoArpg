extends RefCounted
class_name ArcherShotFX

# Spawns Effekseer effects via a SubViewport-hosted 3D layer rendered
# above the 2D world. EffekseerEmitter3D is the renderer the .efkefc
# files were authored against — the 2D variant is finicky with Godot's
# y-sort + camera zoom and was failing intermittently. The 3D pipeline
# uses a depth buffer and is what these effects expect.
#
# Architecture:
#   SceneTreeRoot
#   └─ FxOverlay3DRunner (Node)        ← caches refs, syncs the camera
#      └─ FxOverlay3DLayer (CanvasLayer, layer=35)
#         └─ SubViewportContainer (full-rect, stretch=true)
#            └─ SubViewport (3D-enabled, transparent bg)
#               ├─ Camera3D (orthographic, top-down, follows the 2D cam)
#               └─ FxRoot (Node3D, parent for all spawned emitters)
#
# Coordinate mapping: 2D world (x, y) → 3D world (x, 0, y). The 3D
# camera sits at Y=500 looking straight down with up = −Z, so positive
# 3D Z appears lower on screen — same as positive 2D Y.

const FX_RUNNER_NAME := "FxOverlay3DRunner"
const FX_LAYER_ORDER: int = 35
const CAM_HEIGHT: float = 500.0
const DEFAULT_PIXEL_SIZE := 1.1
const DEBUG_FX := true

# Optional facing-mask target. When set, the FX overlay shader hides any
# particles spawned BEHIND this node along its facing direction so they
# only appear once the projectile crosses to the front.
static var _mask_target: Node2D = null
static var _mask_strength: float = 1.0
# Pixel offset added to the mask target's global_position so the cut
# line lands on the visible body instead of the feet (which is the
# actual Node2D position).
static var _mask_body_offset: Vector2 = Vector2(0, -90)
# Continuous (un-snapped) facing direction used for the half-plane cut.
# Updated by player_longbow.gd at fire-time with the actual cursor-aim
# vector — that's more reliable than the 8-way snapped player.direction
# which can mismatch the trajectory at off-axis angles.
static var _mask_facing: Vector2 = Vector2.RIGHT

# ---- Per-frame camera sync (inner script) -------------------------------

class _Runner extends Node:
	var viewport: SubViewport = null
	var camera_3d: Camera3D = null
	var fx_root: Node3D = null
	var container: SubViewportContainer = null

	func _ready() -> void:
		set_process(true)

	func _process(_dt: float) -> void:
		if viewport == null or camera_3d == null:
			return
		var root_vp: Viewport = get_tree().root
		var screen_size: Vector2 = root_vp.get_visible_rect().size
		if viewport.size != Vector2i(screen_size):
			viewport.size = Vector2i(screen_size)
		var cam2d: Camera2D = root_vp.get_camera_2d()
		if cam2d == null:
			return
		var cam_pos: Vector2 = cam2d.global_position
		var cam_zoom: float = max(cam2d.zoom.y, 0.0001)
		camera_3d.position = Vector3(cam_pos.x, CAM_HEIGHT, cam_pos.y)
		# Top-down orthographic. Vertical extent of the 3D view in world
		# units = pixel height / 2D zoom — matches the 2D camera 1:1.
		camera_3d.size = screen_size.y / cam_zoom
		# Update tracking emitters — those with a `track_node` meta keep
		# their target_location pinned to that Node2D's current world
		# position so the effect homes on a moving enemy.
		if fx_root and is_instance_valid(fx_root):
			for em in fx_root.get_children():
				if not em.has_meta("track_node"):
					continue
				var track: Variant = em.get_meta("track_node")
				if track == null or not is_instance_valid(track):
					continue
				if not (track is Node2D):
					continue
				var t2d: Vector2 = (track as Node2D).global_position
				var off: Vector2 = em.get_meta("track_offset") if em.has_meta("track_offset") else Vector2.ZERO
				var t3d: Vector3 = Vector3(t2d.x + off.x, 0.0, t2d.y + off.y)
				em.set("target_location", t3d - (em as Node3D).global_position)
		# Update the half-plane facing mask shader uniforms so FX hidden
		# behind the player only appear when they cross to the front.
		if container != null and container.material is ShaderMaterial:
			var mat: ShaderMaterial = container.material
			var mask_target: Node2D = ArcherShotFX._mask_target
			if mask_target != null and is_instance_valid(mask_target):
				# Apply the body-centre offset so the cut line lands on
				# the player's visible torso instead of the feet.
				var p_pos: Vector2 = mask_target.global_position + ArcherShotFX._mask_body_offset
				var screen_offset: Vector2 = (p_pos - cam_pos) * cam2d.zoom
				var screen_pos: Vector2 = screen_size * 0.5 + screen_offset
				var uv_pos: Vector2 = Vector2(
					screen_pos.x / max(screen_size.x, 1.0),
					screen_pos.y / max(screen_size.y, 1.0)
				)
				# Body radius (pixels) → UV radius. We normalise by screen
				# height so the shader can undo the X-stretch via aspect.
				var body_r_px: float = 26.0
				if "body_radius" in mask_target:
					body_r_px = float(mask_target.get("body_radius"))
				var radius_uv: float = body_r_px * cam2d.zoom.y / max(screen_size.y, 1.0)
				var aspect: float = screen_size.x / max(screen_size.y, 1.0)
				mat.set_shader_parameter("mask_center_uv", uv_pos)
				mat.set_shader_parameter("mask_radius_uv", radius_uv)
				mat.set_shader_parameter("mask_aspect", aspect)
				mat.set_shader_parameter("mask_facing", ArcherShotFX._mask_facing)
				mat.set_shader_parameter("mask_strength", ArcherShotFX._mask_strength)
			else:
				mat.set_shader_parameter("mask_strength", 0.0)

# ---- Lazy overlay setup --------------------------------------------------

static func _get_fx_root(any_node: Node) -> Node3D:
	if any_node == null:
		return null
	var root: Node = any_node.get_tree().root
	var existing: Node = root.find_child(FX_RUNNER_NAME, false, false)
	if existing and existing is _Runner:
		return (existing as _Runner).fx_root
	var runner := _Runner.new()
	runner.name = FX_RUNNER_NAME
	root.add_child(runner)
	var canvas := CanvasLayer.new()
	canvas.layer = FX_LAYER_ORDER
	runner.add_child(canvas)
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Pixelize shader on the container so we can dial chunkiness up/down
	# at runtime via `set_pixel_size()`. pixel_size=1 means no effect.
	if ResourceLoader.exists("res://pixelize_ui.gdshader"):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://pixelize_ui.gdshader")
		mat.set_shader_parameter("pixel_size", DEFAULT_PIXEL_SIZE)
		mat.set_shader_parameter("saturation", 1.0)
		mat.set_shader_parameter("brightness", 1.0)
		container.material = mat
	canvas.add_child(container)
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.disable_3d = false
	viewport.size = root.get_visible_rect().size
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var cam3d := Camera3D.new()
	cam3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam3d.size = 720.0
	cam3d.position = Vector3(0.0, CAM_HEIGHT, 0.0)
	# Rotate -90° around X so camera-forward points -Y (straight down)
	# and camera-up points -Z, which means positive 3D Z renders lower
	# on screen — matching the 2D y-axis convention.
	cam3d.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	cam3d.current = true
	viewport.add_child(cam3d)
	var fx_root := Node3D.new()
	fx_root.name = "FxRoot"
	viewport.add_child(fx_root)
	runner.viewport = viewport
	runner.camera_3d = cam3d
	runner.fx_root = fx_root
	runner.container = container
	if DEBUG_FX:
		print("[ArcherShotFX] built 3D overlay  vp_size=", viewport.size,
			"  cam=", cam3d.position, "  size=", cam3d.size)
	return fx_root

# ---- Public API ----------------------------------------------------------

# Register the player (or any Node2D) as the source for the FX
# half-plane mask. The FX overlay then hides particles spawned behind
# this node's facing direction. Pass `null` to disable.
# `facing_property` is the name of the property on `target` that holds
# its 8-way facing direction int (0=E, 1=SE, 2=S, … as in player_longbow).
static func set_mask_target(target: Node2D, strength: float = 1.0,
		body_offset: Vector2 = Vector2(0, -90)) -> void:
	_mask_target = target
	_mask_strength = clamp(strength, 0.0, 1.0)
	_mask_body_offset = body_offset

# Set the half-plane facing direction explicitly (continuous, not snapped).
# Called from player_longbow.gd at fire-time with the cursor-aim vector
# so the mask aligns precisely with the shot's trajectory.
static func set_mask_facing(facing: Vector2) -> void:
	if facing.length_squared() > 0.0001:
		_mask_facing = facing.normalized()

# Update the runtime pixel size of the FX overlay's pixelize shader.
# Call with 1.0 for no pixelation, higher values for more chunkiness.
static func set_pixel_size(any_node: Node, pixel_size: float) -> void:
	if any_node == null:
		return
	var root: Node = any_node.get_tree().root
	var runner: Node = root.find_child(FX_RUNNER_NAME, false, false)
	if runner == null or not (runner is _Runner):
		return
	var c: SubViewportContainer = (runner as _Runner).container
	if c == null or c.material == null:
		return
	(c.material as ShaderMaterial).set_shader_parameter("pixel_size", max(1.0, pixel_size))

static func spawn(parent: Node, source_pos: Vector2, target_pos: Vector2,
		efkefc_path: String, fx_scale: float = 4.0,
		tracking_node: Node2D = null, tracking_offset: Vector2 = Vector2.ZERO,
		fx_speed: float = 1.5) -> Node:
	if parent == null or efkefc_path == "":
		if DEBUG_FX: print("[ArcherShotFX] abort: parent=", parent, " path=", efkefc_path)
		return null
	if not ClassDB.class_exists("EffekseerEmitter3D"):
		if DEBUG_FX: print("[ArcherShotFX] abort: EffekseerEmitter3D class not registered (plugin not loaded)")
		return null
	if not ResourceLoader.exists(efkefc_path):
		if DEBUG_FX: print("[ArcherShotFX] abort: efkefc not found at ", efkefc_path)
		return null
	var effect: Resource = load(efkefc_path)
	if effect == null:
		if DEBUG_FX: print("[ArcherShotFX] abort: load failed ", efkefc_path)
		return null
	var fx_root: Node3D = _get_fx_root(parent)
	if fx_root == null:
		if DEBUG_FX: print("[ArcherShotFX] abort: could not create FX root")
		return null
	var em: Node = ClassDB.instantiate("EffekseerEmitter3D")
	if em == null:
		if DEBUG_FX: print("[ArcherShotFX] abort: ClassDB.instantiate(EffekseerEmitter3D) returned null")
		return null
	em.set("effect", effect)
	em.set("autoplay", false)
	em.set("autofree", true)
	em.set("scale", Vector3(fx_scale, fx_scale, fx_scale))
	em.set("speed", max(0.1, fx_speed))
	fx_root.add_child(em)
	# Position in 3D using the 2D world coords (x, y) → (x, 0, y).
	var src3: Vector3 = Vector3(source_pos.x, 0.0, source_pos.y)
	var dst3: Vector3 = Vector3(target_pos.x, 0.0, target_pos.y)
	(em as Node3D).global_position = src3
	# Orient the emitter so its authored forward direction points toward
	# the target on the XZ plane.
	if target_pos != Vector2.ZERO and target_pos != source_pos:
		var dx: float = dst3.x - src3.x
		var dz: float = dst3.z - src3.z
		var yaw: float = atan2(-dz, dx)
		(em as Node3D).rotation = Vector3(0.0, yaw, 0.0)
		em.set("target_location", dst3 - src3)
	# Optional tracking — the runner's _process loop re-points
	# target_location at this Node2D's position each frame.
	if tracking_node != null and is_instance_valid(tracking_node):
		em.set_meta("track_node", tracking_node)
		em.set_meta("track_offset", tracking_offset)
	if em.has_method("play"):
		em.call("play")
	if DEBUG_FX:
		print("[ArcherShotFX] spawned3D ", efkefc_path.get_file(),
			"  src2d=", source_pos, "  dst2d=", target_pos,
			"  emitter3D=", (em as Node3D).global_position,
			"  scale=", fx_scale)
	return em
