@tool
extends EditorScript

# Run via Godot's File → Run menu while item_catalog_dump.gd is open.
# Prints the item count per slot the editor's TreeView will display.

const ItemsDB := preload("res://items_db.gd")

func _run() -> void:
	var cat: Array = ItemsDB.build_catalog()
	var by_slot: Dictionary = {}
	for entry in cat:
		var slot_id: int = int(entry["slot"])
		var slot_name: String = ItemsDB.Slot.keys()[slot_id]
		var key: String = slot_name
		if int(entry["weapon_class"]) != ItemsDB.WeaponClass.NONE:
			key = "%s (%s)" % [slot_name, ItemsDB.WeaponClass.keys()[int(entry["weapon_class"])]]
		var arr: Array = by_slot.get(key, [])
		arr.append(entry["id"])
		by_slot[key] = arr
	var keys: Array = by_slot.keys()
	keys.sort()
	var total: int = 0
	for k in keys:
		var ids: Array = by_slot[k]
		print("%s: %d  -> %s" % [k, ids.size(), ", ".join(ids.slice(0, 3)) + ("…" if ids.size() > 3 else "")])
		total += ids.size()
	print("---")
	print("total items: %d" % total)
