extends RefCounted
class_name CompositeBaker

# Bakes a layered character (kit + slot picks + per-slot colors) into a single
# spritesheet PNG. Layers are blended sequentially so peak memory stays around
# (canvas + one source layer), instead of holding all 9 layers in VRAM at once.
#
# Output goes to user://composite_cache/<hash>.png and is referenced by
# the player's profile so it loads as a single texture.

const PIECES_ROOT := "res://assets/character_pieces"
const CACHE_DIR := "user://composite_cache"
const SLOT_ORDER := ["Shadow", "Base", "Bottom", "Top", "Head", "Hair", "FacialHair", "Accessories", "Weapons"]
const SLOT_ORDER_BACKER := ["Shadow", "Base", "Bottom", "Top", "Hair", "Head", "FacialHair", "Accessories", "Weapons"]

static func composite_path_for(profile: Dictionary) -> String:
	var key := JSON.stringify(profile)
	return "%s/%s.png" % [CACHE_DIR, str(key.hash())]

static func ensure_baked(profile: Dictionary) -> String:
	# Returns the absolute file path of the baked composite, baking it if it
	# doesn't already exist. Empty string = nothing to bake.
	var rel := composite_path_for(profile)
	var abs := ProjectSettings.globalize_path(rel)
	if FileAccess.file_exists(rel):
		return rel
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	return _bake(profile, rel)

static func _bake(profile: Dictionary, dst_path: String) -> String:
	var kit: String = String(profile.get("kit", "female"))
	var slots: Dictionary = profile.get("slots", {})
	var colors: Dictionary = profile.get("colors", {})
	var order: Array = SLOT_ORDER_BACKER if kit.begins_with("backer_") else SLOT_ORDER
	var canvas: Image = null
	for slot in order:
		var variant: String = String(slots.get(slot, ""))
		if variant == "":
			continue
		var src := _layer_path(kit, slot, variant)
		var img := _load_image(src)
		if img == null:
			push_warning("composite_baker: missing %s" % src)
			continue
		if canvas == null:
			canvas = Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		# Apply per-slot color tint by multiplying the layer's RGB.
		if colors.has(slot):
			var c := Color(String(colors[slot]))
			if c != Color.WHITE:
				_tint_in_place(img, c)
		canvas.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(0, 0))
		# Free the layer image promptly.
		img = null
	if canvas == null:
		push_warning("composite_baker: nothing to composite for profile")
		return ""
	canvas.save_png(dst_path)
	return dst_path

static func _layer_path(kit: String, slot: String, variant: String) -> String:
	if slot == "Shadow" or variant == "":
		return "%s/%s/%s/Spritesheet.png" % [PIECES_ROOT, kit, slot]
	return "%s/%s/%s/%s/Spritesheet.png" % [PIECES_ROOT, kit, slot, variant]

static func _load_image(path: String) -> Image:
	var img := Image.new()
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path)
		if t:
			return t.get_image()
	var fs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(fs_path):
		var err := img.load(path if FileAccess.file_exists(path) else fs_path)
		if err == OK:
			return img
	return null

static func _tint_in_place(img: Image, c: Color) -> void:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var p := img.get_pixel(x, y)
			if p.a <= 0.001:
				continue
			img.set_pixel(x, y, Color(p.r * c.r, p.g * c.g, p.b * c.b, p.a))
