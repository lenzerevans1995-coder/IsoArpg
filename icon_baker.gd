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
const ItemMetadataScript := preload("res://item_metadata.gd")
const LayeredCharacterScript := preload("res://layered_character.gd")

const ICON_DIR := "res://assets/generated/icons"
const GROUND_DIR := "res://assets/generated/ground"
const OUT_SIZE := Vector2i(128, 128)
const ANCHOR := Vector2(64, 96)         # center the rig in the 128x128 frame
# Slot id -> LayeredCharacter layer (mirrors item_editor's table).
const SLOT_TO_LAYER := {
	ItemsDB.Slot.HEAD: "head", ItemsDB.Slot.HANDS: "hands",
	ItemsDB.Slot.CHEST: "chest", ItemsDB.Slot.LEGS: "legs",
	ItemsDB.Slot.SHOES: "shoes", ItemsDB.Slot.BELT: "belt",
	ItemsDB.Slot.BAG: "bag", ItemsDB.Slot.MAINHAND: "mainhand",
	ItemsDB.Slot.OFFHAND: "offhand", ItemsDB.Slot.SHIELD: "offhand",
	ItemsDB.Slot.MOUNT: "mount",
}
# Slots whose preview reads better with a body underneath. Mounts get
# a body too (rendering on top, so it reads as ridden).
const NEEDS_BODY := {
	ItemsDB.Slot.HEAD: true, ItemsDB.Slot.HANDS: true,
	ItemsDB.Slot.CHEST: true, ItemsDB.Slot.LEGS: true,
	ItemsDB.Slot.SHOES: true, ItemsDB.Slot.BELT: true,
	ItemsDB.Slot.BAG: true, ItemsDB.Slot.MOUNT: true,
	ItemsDB.Slot.MAINHAND: true, ItemsDB.Slot.OFFHAND: true,
	ItemsDB.Slot.SHIELD: true,
}

# Bake every catalog entry. host_node is any Node already in the scene
# tree — the SubViewport must be a child of a tree-attached node so it
# actually renders before we read back its texture.
static func bake_all(host_node: Node, force: bool = false) -> Dictionary:
	var summary := {"icons": 0, "ground": 0, "skipped": 0}
	_ensure_dir(ICON_DIR)
	_ensure_dir(GROUND_DIR)
	var vp := SubViewport.new()
	vp.size = OUT_SIZE
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
	rig.call("set_direction", 2)
	# Die anim, last frame — looks like the item dropped on the ground.
	# Looping false so play_anim parks on the final frame; fps very low
	# so the texture readback catches it.
	rig.call("play_anim", "Die", 0.001, false, Callable())

static func _clear(rig: Node2D) -> void:
	for layer in ["body", "head", "hands", "chest", "legs", "shoes",
			"belt", "bag", "mainhand", "offhand", "mount"]:
		rig.call("clear_layer", layer)
		rig.call("set_tint", layer, Color.WHITE)

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
	var img: Image = tex.get_image()
	if img == null: return
	# Strip the OS path prefix from res:// for save_png.
	var sys_path: String = ProjectSettings.globalize_path(path)
	img.save_png(sys_path)

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
