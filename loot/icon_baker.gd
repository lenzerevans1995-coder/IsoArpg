@tool
extends Node
class_name IconBaker

# Bakes per-item PNGs from the LayeredCharacter into:
#   res://assets/generated/icons/<item_id>.png        — S-facing Idle frame
#   res://assets/generated/ground/<item_id>.png       — death pose (loot drop)
#
# Driven by the "Bake all icons" button in item_editor.gd. Bakes only
# the items that have can_drop = true (and aren't pure cosmetic stubs)
# unless force=true.
#
# Output is the *neutral* sprite — no tint, no glow. Material tint and
# rarity glow are applied at display time by the inventory UI / loot
# drop code so a single bake covers every rolled instance.

const ItemsDB := preload("res://items_db.gd")
const ItemMetadataScript := preload("res://loot/item_metadata.gd")
const LayeredCharacterScript := preload("res://layered_character.gd")
const LoadoutScript := preload("res://loadout.gd")

const ICON_DIR := "res://assets/generated/icons"
const GROUND_DIR := "res://assets/generated/ground"
const OUT_SIZE := Vector2i(128, 128)
# Render at a much larger viewport so the LayeredCharacter's content
# (which only fills ~10-20 px of a naive 128x128 frame because the rig
# sits at native scale) gives us enough resolution to crop tightly.
const RENDER_SIZE := Vector2i(384, 384)
# Anchor the rig roughly at the bottom-center so feet land in-frame.
const ANCHOR := Vector2(192, 320)
# Fraction of the cropped content edge length to leave as breathing room
# inside the OUT_SIZE canvas. 0.85 = content fills 85% of the icon.
const CONTENT_FILL_FRACTION := 0.82
# Slot id -> LayeredCharacter layer (mirrors item_editor's table).
const SLOT_TO_LAYER := {
	ItemsDB.Slot.HEAD: "head", ItemsDB.Slot.HANDS: "hands",
	ItemsDB.Slot.CHEST: "chest", ItemsDB.Slot.LEGS: "legs",
	ItemsDB.Slot.SHOES: "shoes", ItemsDB.Slot.BELT: "belt",
	ItemsDB.Slot.BAG: "bag", ItemsDB.Slot.MAINHAND: "mainhand",
	ItemsDB.Slot.OFFHAND: "offhand", ItemsDB.Slot.SHIELD: "offhand",
	ItemsDB.Slot.MOUNT: "mount",
}
# Empty by design: every item bakes alone, no body underneath. Armor
# sheets are authored over a body silhouette but the cloth covers the
# torso enough to read as the item. If a particular slot bakes badly
# without context, add it back here.
const NEEDS_BODY := {}

# Bake every catalog entry. host_node is any Node already in the scene
# tree — the SubViewport must be a child of a tree-attached node so it
# actually renders before we read back its texture.
static func bake_all(host_node: Node, force: bool = false) -> Dictionary:
	var summary := {"icons": 0, "ground": 0, "skipped": 0}
	_ensure_dir(ICON_DIR)
	_ensure_dir(GROUND_DIR)
	var vp := SubViewport.new()
	vp.size = RENDER_SIZE
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host_node.add_child(vp)
	var rig: Node2D = LayeredCharacterScript.new()
	rig.position = ANCHOR
	vp.add_child(rig)
	# Wait one frame so the rig's _ready runs and creates layer Sprite2Ds.
	await host_node.get_tree().process_frame
	for entry in ItemsDB.build_catalog():
		var iid: String = String(entry["id"])
		var meta: Resource = _load_meta(iid, int(entry["slot"]))
		if not force and meta != null and not bool(meta.can_drop):
			summary.skipped += 1
			continue
		var icon_path: String = "%s/%s.png" % [ICON_DIR, iid]
		var ground_path: String = "%s/%s.png" % [GROUND_DIR, iid]
		# S-facing Idle frame 0 — the canonical inventory icon.
		_pose_for_icon(rig, entry)
		await _flush(host_node, vp)
		_save_image(vp, icon_path)
		summary.icons += 1
		# Death pose for the ground drop sprite. Falls back to Idle if
		# the slot's sheets don't have Die (rare).
		_pose_for_ground(rig, entry)
		await _flush(host_node, vp)
		_save_image(vp, ground_path)
		summary.ground += 1
	rig.queue_free()
	vp.queue_free()
	return summary

# --- pose helpers ---------------------------------------------------

static func _pose_for_icon(rig: Node2D, entry: Dictionary) -> void:
	_clear(rig)
	var slot_id: int = int(entry["slot"])
	if NEEDS_BODY.get(slot_id, false):
		rig.call("equip", "body", "NakedBody")
	var layer: String = String(SLOT_TO_LAYER.get(slot_id, ""))
	if layer != "":
		rig.call("equip", layer, String(entry["folder"]))
		rig.call("set_tint", layer, _tint_for_item(layer, String(entry["id"])))
	# Direction 2 = S (front-facing). Frame 0 of Idle is the canonical
	# icon pose; for mounts we need RideIdle so the mount actually
	# renders.
	rig.call("set_direction", 2)
	var anim: String = "Idle"
	if slot_id == ItemsDB.Slot.MOUNT:
		anim = "RideIdle"
	rig.call("play_anim", anim, 0.001, true, Callable())

static func _pose_for_ground(rig: Node2D, entry: Dictionary) -> void:
	_clear(rig)
	var slot_id: int = int(entry["slot"])
	if NEEDS_BODY.get(slot_id, false):
		rig.call("equip", "body", "NakedBody")
	var layer: String = String(SLOT_TO_LAYER.get(slot_id, ""))
	if layer != "":
		rig.call("equip", layer, String(entry["folder"]))
		rig.call("set_tint", layer, _tint_for_item(layer, String(entry["id"])))
	rig.call("set_direction", 2)
	# Die anim, last frame — looks like the item dropped on the ground.
	# Looping false so play_anim parks on the final frame; fps very low
	# so the texture readback catches it.
	rig.call("play_anim", "Die", 0.001, false, Callable())

static func _clear(rig: Node2D) -> void:
	for layer in ["body", "head", "hands", "chest", "legs", "shoes",
			"belt", "bag", "mainhand", "offhand", "mount"]:
		rig.call("clear_layer", layer)

# Per-item layer tint chosen by hashing item_id against the per-slot
# palette in loadout.gd. Two chest items (chest_3, chest_7) end up in
# different palette swatches so the loot pile reads as varied colors
# instead of all-grey. Stable: chest_3 always picks the same swatch.
static func _tint_for_item(layer: String, item_id: String) -> Color:
	var palette: Array = LoadoutScript.palette_for(layer)
	if palette.is_empty():
		return Color.WHITE
	var idx: int = abs(item_id.hash()) % palette.size()
	return palette[idx]

# Wait until the SubViewport has rendered the new pose. Two frames is
# enough: one for _process to update sheet/region, one for the renderer
# to actually flush.
static func _flush(host: Node, vp: SubViewport) -> void:
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await host.get_tree().process_frame
	await host.get_tree().process_frame

static func _save_image(vp: SubViewport, path: String) -> void:
	var tex: Texture2D = vp.get_texture()
	if tex == null: return
	var src: Image = tex.get_image()
	if src == null: return
	# Find the alpha bounding box of the rendered content.
	var bbox: Rect2i = _content_bbox(src)
	if bbox.size.x <= 0 or bbox.size.y <= 0:
		# Fully transparent — write an empty OUT_SIZE png so the file
		# exists; runtime fallback paths still work.
		var blank := Image.create(OUT_SIZE.x, OUT_SIZE.y, false, Image.FORMAT_RGBA8)
		blank.save_png(ProjectSettings.globalize_path(path))
		return
	# Crop to bbox.
	var cropped := src.get_region(bbox)
	# Compose into the OUT_SIZE canvas with content filling
	# CONTENT_FILL_FRACTION of the longest edge, centered.
	var target_long: int = int(OUT_SIZE.x * CONTENT_FILL_FRACTION)
	var src_long: int = max(bbox.size.x, bbox.size.y)
	var scale: float = float(target_long) / float(src_long)
	var dst_w: int = max(1, int(round(bbox.size.x * scale)))
	var dst_h: int = max(1, int(round(bbox.size.y * scale)))
	cropped.resize(dst_w, dst_h, Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create(OUT_SIZE.x, OUT_SIZE.y, false, Image.FORMAT_RGBA8)
	var dst_x: int = (OUT_SIZE.x - dst_w) / 2
	var dst_y: int = (OUT_SIZE.y - dst_h) / 2
	canvas.blit_rect(cropped, Rect2i(0, 0, dst_w, dst_h), Vector2i(dst_x, dst_y))
	canvas.save_png(ProjectSettings.globalize_path(path))

# Find the smallest rect containing all non-transparent pixels.
static func _content_bbox(img: Image) -> Rect2i:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var min_x: int = w; var min_y: int = h
	var max_x: int = -1; var max_y: int = -1
	# Threshold 0.25 (was 0.05). Item sheets have faint anti-alias /
	# shadow wisps that make the alpha bbox larger than the visible
	# content; head sheets in particular had hair/shading pixels that
	# pushed the bbox 30-40% bigger than the helmet itself, leaving the
	# rendered icon too small after the resize.
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.25:
				if x < min_x: min_x = x
				if y < min_y: min_y = y
				if x > max_x: max_x = x
				if y > max_y: max_y = y
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

static func _load_meta(item_id: String, slot_id: int) -> Resource:
	var slot_name: String = ItemsDB.Slot.keys()[slot_id].to_lower()
	var path: String = "res://data/items/%s/%s.tres" % [slot_name, item_id]
	if FileAccess.file_exists(path):
		var r: Resource = load(path)
		if r is ItemMetadataScript: return r
	return null

static func _ensure_dir(p: String) -> void:
	if not DirAccess.dir_exists_absolute(p):
		DirAccess.make_dir_recursive_absolute(p)
