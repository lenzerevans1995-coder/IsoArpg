extends Node
class_name ProjectileRuntime

# Plays a single projectile flipbook with one of four motion modes.
# Driven by SkillDef.projectile_* fields and the data/projectiles.json
# registry.

const REGISTRY_PATH := "res://data/projectiles.json"
static var _registry_cache: Dictionary = {}

static func registry() -> Dictionary:
	if not _registry_cache.is_empty():
		return _registry_cache
	if not FileAccess.file_exists(REGISTRY_PATH):
		return {}
	var f := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_registry_cache = parsed
	return _registry_cache

# Look up a projectile entry. Returns the dict from the registry or {} if
# nothing matches. Pack + category + name come straight off SkillDef.
static func lookup(pack: String, category: String, name: String) -> Dictionary:
	if pack == "" or category == "" or name == "":
		return {}
	var reg := registry()
	var p: Variant = reg.get(pack, null)
	if not (p is Dictionary): return {}
	var c: Variant = p.get(category, null)
	if not (c is Dictionary): return {}
	var e: Variant = c.get(name, null)
	if e is Dictionary: return e
	return {}

# Build a Sprite2D flipbook node from frame paths. The node animates in
# _process and queue_frees itself when finished.
class _Flipbook extends Sprite2D:
	var frames: Array = []
	var frame_idx: int = 0
	var fps: float = 24.0
	var t: float = 0.0
	var on_finished: Callable = Callable()
	func _process(delta: float) -> void:
		t += delta
		var step: float = 1.0 / max(fps, 1.0)
		while t >= step and frame_idx < frames.size() - 1:
			t -= step
			frame_idx += 1
			texture = frames[frame_idx]
		if frame_idx >= frames.size() - 1 and t >= step:
			if on_finished.is_valid(): on_finished.call()
			queue_free()

static func _resolve_frames(entry: Dictionary, start: int, end: int) -> Array:
	# Build the frame list at runtime by scanning the entry's folder via
	# DirAccess — same approach explosion_anim uses for fantasy effects,
	# which works reliably across all packs. The JSON's `frames` array is
	# only used as a hint for frame count; the actual textures come from
	# the live directory listing.
	var src: Array = []
	var folder: String = String(entry.get("path", ""))
	if folder != "":
		var d := DirAccess.open(folder)
		if d != null:
			var names: Array = []
			d.list_dir_begin()
			var fn := d.get_next()
			while fn != "":
				if fn.ends_with(".png") and not fn.ends_with(".import"):
					names.append(fn)
				fn = d.get_next()
			d.list_dir_end()
			names.sort()
			for n in names:
				src.append("%s/%s" % [folder, n])
	# Fallback to the JSON paths if DirAccess didn't find anything (eg
	# folder field missing on an older registry).
	if src.is_empty():
		src = entry.get("frames", [])
	if src.is_empty():
		push_warning("ProjectileRuntime: entry has no frames")
		return []
	var s: int = clamp(start, 0, src.size() - 1)
	var e: int = src.size() - 1 if end < 0 else clamp(end, s, src.size() - 1)
	var out: Array = []
	for i in range(s, e + 1):
		var p: String = String(src[i])
		var t: Texture2D = load(p)
		if t != null:
			out.append(t)
	if out.is_empty():
		push_warning("ProjectileRuntime: 0 frames loaded. First path: %s" % src[s])
	return out

static func _make_flipbook(frames: Array, fps: float, color: Color, scale: float = 1.0) -> _Flipbook:
	var fb := _Flipbook.new()
	fb.frames = frames
	fb.fps = fps
	fb.texture = frames[0] if frames.size() > 0 else null
	fb.modulate = color
	fb.centered = true
	fb.scale = Vector2(scale, scale)
	# Force NEAREST so fantasy / hd1 / pack1 / pack2 projectiles all
	# look pixel-aligned with the rest of the world. Some packs default
	# to LINEAR via their .import settings; this overrides per-node.
	fb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return fb

# Spawn the projectile in the world. `parent` should be a node in the
# game world (player.get_parent() is the typical caller). origin/target
# are global world coordinates.
static func play(def: Resource, parent: Node, origin: Vector2, target: Vector2) -> void:
	if def == null: return
	var entry := lookup(def.get("projectile_pack"), def.get("projectile_category"), def.get("projectile_name"))
	if entry.is_empty(): return
	var frames: Array = _resolve_frames(entry,
		int(def.get("projectile_start_frame")),
		int(def.get("projectile_end_frame")))
	if frames.is_empty(): return
	var fps: float = float(def.get("projectile_fps"))
	var color: Color = def.get("projectile_color")
	var motion: String = def.get("projectile_motion")
	# Apply the saved spawn / impact offsets so the projectile fires from
	# the rig's hand / staff / etc. and lands at chest height instead of
	# the foot. Editor surfaces these as the blue / red drag markers.
	# Resource.get() in 4.6 only takes one arg, so read the property
	# directly via `in` checks instead of `.get(name, default)`.
	# Cast to the typed SkillDef so the new fields read cleanly. Older
	# saved skills loaded via load() are auto-upgraded by Godot to the
	# current script schema; missing fields take the @export defaults.
	var sd: Resource = def
	var origin_off: Vector2 = Vector2.ZERO
	var target_off: Vector2 = Vector2.ZERO
	var p_scale: float = 1.0
	if sd.has_method("get") and ("projectile_origin_offset" in sd):
		origin_off = sd.projectile_origin_offset
	if sd.has_method("get") and ("projectile_target_offset" in sd):
		target_off = sd.projectile_target_offset
	if sd.has_method("get") and ("projectile_scale" in sd):
		p_scale = float(sd.projectile_scale)
	origin = origin + origin_off
	target = target + target_off
	# Important: add to the parent FIRST, then set global_position.
	# Setting `position` before parenting puts the flipbook at parent-
	# local coords equal to the global value, which double-offsets when
	# the parent itself has a non-zero global_position (typical when
	# parent = a TileMapLayer inside the painted-world tree).
	match motion:
		"at_player":
			var fb := _make_flipbook(frames, fps, color, p_scale)
			fb.z_index = 10; fb.z_as_relative = true
			parent.add_child(fb)
			fb.global_position = origin
		"at_target":
			var fb2 := _make_flipbook(frames, fps, color, p_scale)
			fb2.z_index = 10; fb2.z_as_relative = true
			parent.add_child(fb2)
			fb2.global_position = target
		"travel":
			var fb3 := _make_flipbook(frames, fps, color, p_scale)
			fb3.z_index = 10; fb3.z_as_relative = true
			parent.add_child(fb3)
			fb3.global_position = origin
			fb3.rotation = (target - origin).angle()
			var dist: float = origin.distance_to(target)
			var speed: float = max(50.0, float(def.get("projectile_speed")))
			var tw := fb3.create_tween()
			tw.tween_property(fb3, "global_position", target, dist / speed)
			tw.tween_callback(func(): if is_instance_valid(fb3): fb3.queue_free())
		"arc_rain":
			var count: int = max(1, int(def.get("projectile_arc_count")))
			var radius: float = max(0.0, float(def.get("projectile_arc_radius")))
			for i in count:
				var ang: float = randf() * TAU
				var r: float = sqrt(randf()) * radius
				var spot: Vector2 = target + Vector2(cos(ang), sin(ang)) * r
				var drop_frames: Array = frames.duplicate()
				var fb4 := _make_flipbook(drop_frames, fps, color, p_scale)
				fb4.z_index = 10; fb4.z_as_relative = true
				parent.add_child(fb4)
				fb4.global_position = spot + Vector2(0, -200)
				var tw2 := fb4.create_tween()
				tw2.tween_interval(float(i) * 0.05)
				tw2.tween_property(fb4, "global_position", spot, 0.35)
